import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'device_identity_service.dart';
import 'feature_flags.dart';
import 'license_config.dart';
import 'license_status.dart';
import 'license_storage.dart';

class LicenseService {
  static final LicenseService instance = LicenseService._();
  LicenseService._();

  static const Set<String> _authoritativeInactiveReasons = {
    'device_revoked',
    'invalid_license',
    'license_inactive',
    'license_expired',
    'device_limit_reached',
    'trial_already_used',
    'trial_expired',
  };

  /// Central notifier representing the active license status
  final ValueNotifier<LicenseStatus> statusNotifier =
      ValueNotifier<LicenseStatus>(
        const LicenseStatus(
          active: false,
          mode: LicenseMode.none,
          features: FeatureFlags.lockedAll,
        ),
      );

  LicenseStatus get currentStatus => statusNotifier.value;

  FeatureFlags get currentFeatureFlags => currentStatus.features;

  Map<String, dynamic> _decodeExpectedLicenseResponse(String responseBody) {
    final dynamic decoded = json.decode(responseBody);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('License response must be a JSON object.');
    }

    final isRevoked =
        decoded['reason']?.toString() == 'device_revoked' ||
        decoded['reset_required'] == true ||
        decoded['reset_required']?.toString() == 'true';
    if (!isRevoked && decoded['active'] is! bool) {
      throw const FormatException(
        'License response must contain a boolean active field.',
      );
    }

    if (decoded['active'] == false) {
      final reason = decoded['reason'];
      if (reason is! String || reason.trim().isEmpty) {
        throw const FormatException(
          'Inactive license response must contain a reason.',
        );
      }
    }
    return decoded;
  }

  bool _isAuthoritativeInactiveResponse(Map<String, dynamic> data) {
    final reason = data['reason'];
    if (reason is! String || !_authoritativeInactiveReasons.contains(reason)) {
      return false;
    }

    return data['active'] == false || reason == 'device_revoked';
  }

  Future<LicenseStatus> _transportFailureStatus(String reason) async {
    final localMode = await LicenseStorage.getLicenseMode();
    return LicenseStatus.inactive(reason, localMode);
  }

  /// Initialize and load cached license/trial info on startup
  Future<void> init() async {
    try {
      // Warm up device model and app version cache asynchronously on startup
      DeviceIdentityService.getDeviceModel().catchError((_) => 'Cihaz');
      DeviceIdentityService.getAppVersion().catchError((_) => 'unknown');
      final cached = await LicenseStorage.getCachedLicenseStatus();
      statusNotifier.value = cached;
    } on LicenseStorageException catch (error) {
      statusNotifier.value = const LicenseStatus(
        active: false,
        mode: LicenseMode.none,
        features: FeatureFlags.lockedAll,
      );
      debugPrint('[LICENSE][STORAGE] LicenseService.init failed: $error');
      rethrow;
    }
  }

  /// Validate a license key with the server
  Future<LicenseStatus> validateLicense(String licenseKey) async {
    try {
      final deviceId = await DeviceIdentityService.getDeviceId();
      final fingerprint =
          await DeviceIdentityService.getDeviceFingerprintHash();
      final deviceModel = await DeviceIdentityService.getDeviceModel();
      final appVersion = await DeviceIdentityService.getAppVersion();
      if (kDebugMode) {
        debugPrint('validate-license app_version: $appVersion');
      }
      final platformName = Platform.operatingSystem.toLowerCase();

      final body = {
        'license_key': licenseKey.trim(),
        'device_id': deviceId,
        'device_fingerprint_hash': fingerprint,
        'device_name': deviceModel,
        'device_model': deviceModel,
        'app_version': appVersion,
        'platform': platformName,
      };

      if (kDebugMode) {
        // Obfuscate key and device ID in debug logs
        final maskedKey = licenseKey.length > 5
            ? '${licenseKey.substring(0, 4)}***'
            : '***';
        final maskedDeviceId = deviceId.length > 8
            ? '${deviceId.substring(0, 8)}***'
            : deviceId;
        debugPrint(
          'API validate-license: masked_key=$maskedKey, device_id=$maskedDeviceId',
        );
      }

      final response = await http
          .post(
            Uri.parse(LicenseConfig.validateLicenseUrl),
            headers: {'Content-Type': 'application/json'},
            body: json.encode(body),
          )
          .timeout(LicenseConfig.apiTimeout);

      if (response.statusCode == 200) {
        final data = _decodeExpectedLicenseResponse(response.body);
        final status = LicenseStatus.fromJson(
          data,
          LicenseMode.licensed,
          lastCheckedAt: DateTime.now(),
        );

        if (status.active) {
          await LicenseStorage.saveLicenseStatus(
            status,
            licenseKey: licenseKey.trim(),
          );
          statusNotifier.value = status;
          return statusNotifier.value;
        } else {
          // Failure: do NOT clear existing license/trial state or change statusNotifier
          return LicenseStatus.inactive(
            status.reason ?? 'invalid_license',
            LicenseMode.none,
            lastCheckedAt: DateTime.now(),
          );
        }
      } else {
        return LicenseStatus.inactive('server_error', LicenseMode.none);
      }
    } on LicenseStorageException catch (error) {
      debugPrint('[LICENSE][STORAGE] validateLicense failed: $error');
      rethrow;
    } on TimeoutException catch (_) {
      return LicenseStatus.inactive('network_error', LicenseMode.none);
    } on SocketException catch (_) {
      return LicenseStatus.inactive('network_error', LicenseMode.none);
    } on HandshakeException catch (_) {
      return LicenseStatus.inactive('network_error', LicenseMode.none);
    } on http.ClientException catch (_) {
      return LicenseStatus.inactive('network_error', LicenseMode.none);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('validateLicense error: $e');
      }
      return LicenseStatus.inactive('server_error', LicenseMode.none);
    }
  }

  /// Refresh and verify license or trial status online
  Future<LicenseStatus> checkStatus() async {
    try {
      final licenseKey = await LicenseStorage.getLicenseKey();

      final hasLicenseKey = licenseKey != null && licenseKey.isNotEmpty;

      if (!hasLicenseKey) {
        statusNotifier.value = const LicenseStatus(
          active: false,
          mode: LicenseMode.none,
          features: FeatureFlags.lockedAll,
        );
        return statusNotifier.value;
      }

      final deviceId = await DeviceIdentityService.getDeviceId();
      final fingerprint =
          await DeviceIdentityService.getDeviceFingerprintHash();
      final deviceModel = await DeviceIdentityService.getDeviceModel();
      final appVersion = await DeviceIdentityService.getAppVersion();
      if (kDebugMode) {
        debugPrint('check-status app_version: $appVersion');
      }

      final Map<String, dynamic> body = {
        'mode': LicenseMode.licensed.name,
        'device_id': deviceId,
        'device_fingerprint_hash': fingerprint,
        'device_name': deviceModel,
        'device_model': deviceModel,
        'app_version': appVersion,
        'license_key': licenseKey,
      };

      if (kDebugMode) {
        final maskedDeviceId = deviceId.length > 8
            ? '${deviceId.substring(0, 8)}***'
            : deviceId;
        debugPrint(
          'API check-status: mode=licensed, device_id=$maskedDeviceId',
        );
      }

      final response = await http
          .post(
            Uri.parse(LicenseConfig.checkStatusUrl),
            headers: {'Content-Type': 'application/json'},
            body: json.encode(body),
          )
          .timeout(LicenseConfig.apiTimeout);

      // The current LUUQ backend reports authoritative inactive license
      // states with HTTP 400. Accept only a strict, known inactive payload;
      // malformed/unknown 4xx responses and all 5xx responses remain server
      // failures so they cannot revoke a running session accidentally.
      if (response.statusCode == 200 || response.statusCode == 400) {
        final data = _decodeExpectedLicenseResponse(response.body);
        if (response.statusCode == 400 &&
            !_isAuthoritativeInactiveResponse(data)) {
          return LicenseStatus.inactive('server_error', LicenseMode.licensed);
        }
        final isRevoked =
            data['reason']?.toString() == 'device_revoked' ||
            data['reset_required'] == true ||
            data['reset_required']?.toString() == 'true';

        if (isRevoked) {
          if (kDebugMode) {
            debugPrint('checkStatus reason: device_revoked');
            debugPrint('resetRequired: true');
            debugPrint('clearingLocalLicenseSession: true');
          }
          await LicenseStorage.clearLicense();
          statusNotifier.value = const LicenseStatus(
            active: false,
            mode: LicenseMode.none,
            reason: 'device_revoked',
            features: FeatureFlags.lockedAll,
          );
          return statusNotifier.value;
        }

        final previousStatus = statusNotifier.value;
        final status = LicenseStatus.fromJson(
          data,
          LicenseMode.licensed,
          lastCheckedAt: DateTime.now(),
        );

        if (kDebugMode) {
          final previousMode = previousStatus.mode.name;
          final newMode = status.mode.name;
          final previousPlan = previousStatus.plan ?? 'null';
          final newPlan = status.plan ?? 'null';
          final rawFeatures = data['features'];
          final normalizedFeatures = status.features.toJson();
          final featuresChanged = previousStatus.features != status.features;

          String appliedFeatureSource = 'backend_features';
          final featuresJson = data['features'] as Map<String, dynamic>?;
          if (featuresJson == null || featuresJson.isEmpty) {
            appliedFeatureSource = status.mode == LicenseMode.trial
                ? 'trial_fallback'
                : 'licensed_fallback';
          }

          debugPrint('LICENSE SYNC DEBUG:');
          debugPrint('  previousMode: $previousMode');
          debugPrint('  newMode: $newMode');
          debugPrint('  previousPlan: $previousPlan');
          debugPrint('  newPlan: $newPlan');
          debugPrint('  rawFeaturesFromBackend: $rawFeatures');
          debugPrint('  normalizedFeatureFlags: $normalizedFeatures');
          debugPrint('  featuresChanged: $featuresChanged');
          debugPrint('  appliedFeatureSource: $appliedFeatureSource');
        }

        if (status.active) {
          await LicenseStorage.saveLicenseStatus(status);
          statusNotifier.value = status;
        } else {
          if (status.reason == 'trial_expired' ||
              status.reason == 'trial_already_used') {
            await LicenseStorage.saveLicenseStatus(status);
            statusNotifier.value = status;
          } else {
            final inactiveStatus = LicenseStatus(
              active: false,
              mode: status.mode,
              reason: status.reason ?? 'invalid_license',
              branchName: status.branchName,
              customerName: status.customerName,
              plan: status.plan,
              expiresAt: status.expiresAt,
              trialExpiresAt: status.trialExpiresAt,
              features: FeatureFlags.lockedAll,
              lastCheckedAt: DateTime.now(),
            );
            await LicenseStorage.saveLicenseStatus(inactiveStatus);
            statusNotifier.value = inactiveStatus;
          }
        }
        return statusNotifier.value;
      } else {
        // Return server error state
        return LicenseStatus.inactive('server_error', LicenseMode.licensed);
      }
    } on LicenseStorageException catch (error) {
      debugPrint('[LICENSE][STORAGE] checkStatus failed: $error');
      rethrow;
    } on TimeoutException catch (_) {
      return _transportFailureStatus('network_error');
    } on SocketException catch (_) {
      return _transportFailureStatus('network_error');
    } on HandshakeException catch (_) {
      return _transportFailureStatus('network_error');
    } on http.ClientException catch (_) {
      return _transportFailureStatus('network_error');
    } catch (e) {
      if (kDebugMode) {
        debugPrint('checkStatus error: $e');
      }
      return _transportFailureStatus('server_error');
    }
  }

  /// Get localized description for a reason code
  static String getLocalizedError(String? reason) {
    switch (reason) {
      case 'device_revoked':
        return 'Bu cihazın lisans bağlantısı yönetici tarafından kaldırıldı. Devam etmek için yeniden lisans anahtarı girmeniz gerekir.';
      case 'invalid_license':
        return 'Lisans anahtarı geçersiz.';
      case 'license_inactive':
        return 'Bu lisans pasif durumda.';
      case 'license_expired':
        return 'Lisans süresi dolmuş.';
      case 'device_limit_reached':
        return 'Bu lisans için cihaz limiti dolmuş.';
      case 'trial_already_used':
        return 'Bu cihazda deneme sürümü daha önce kullanılmış.';
      case 'trial_expired':
        return 'Deneme süreniz sona erdi. Devam etmek için lisans anahtarı girin.';
      case 'network_error':
        return 'Lisans sunucusuna ulaşılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.';
      case 'server_error':
        return 'Lisans sunucusuna şu anda ulaşılamıyor. Lütfen daha sonra tekrar deneyin.';
      case 'storage_error':
        return 'Güvenli lisans verisine erişilemiyor. Bu cihazın yeniden etkinleştirilmesi gerekiyor.';
      default:
        return 'Bilinmeyen bir lisans hatası oluştu.';
    }
  }
}
