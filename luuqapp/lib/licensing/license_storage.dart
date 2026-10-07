import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'license_status.dart';
import 'feature_flags.dart';

enum LicenseStorageFailureKind { read, write, delete, malformedData }

class LicenseStorageException implements Exception {
  final LicenseStorageFailureKind kind;
  final String key;
  final Object cause;

  const LicenseStorageException({required this.kind, required this.key, required this.cause});

  @override
  String toString() =>
      'LicenseStorageException(kind: ${kind.name}, key: $key, cause: ${cause.runtimeType})';
}

class LicenseStorage {
  static const _defaultStorage = FlutterSecureStorage(aOptions: AndroidOptions());
  static FlutterSecureStorage _storage = _defaultStorage;

  static const String _keyLicenseMode = 'license_mode';
  static const String _keyLicenseKey = 'license_key';
  static const String _keyDeviceId = 'device_id';
  static const String _keyDeviceFingerprintHash = 'device_fingerprint_hash';
  static const String _keyBranchName = 'branch_name';
  static const String _keyCustomerName = 'customer_name';
  static const String _keyPlan = 'plan';
  static const String _keyExpiresAt = 'expires_at';
  static const String _keyTrialExpiresAt = 'trial_expires_at';
  static const String _keyFeatures = 'features';
  // Written by older versions and never read; only cleared on reset now.
  static const String _keyLastSuccessfulCheckAt = 'last_successful_check_at';
  static const String _keyMenuAccessToken = 'menu_access_token';
  // Hash of the last saved status fields: a 30 s status check that changed
  // nothing must not rewrite ~10 encrypted keys (keystore work, flash wear).
  static const String _keyStatusDigest = 'license_status_digest';
  static const String _keyMenuProfileId = 'menu_profile_id';
  static const String _keyMenuProfileGeneration = 'menu_profile_generation';
  static const String _keyAdminSessionToken = 'menu_admin_session_token';

  static final RegExp _licenseKeyPattern = RegExp(
    r'^LUUQ-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$',
  );

  @visibleForTesting
  static void setStorageForTesting(FlutterSecureStorage? storage) {
    _storage = storage ?? _defaultStorage;
  }

  static Future<T> _runStorageOperation<T>({
    required LicenseStorageFailureKind kind,
    required String key,
    required Future<T> Function() operation,
  }) async {
    try {
      return await operation();
    } on LicenseStorageException {
      rethrow;
    } catch (error, stackTrace) {
      debugPrint('[LICENSE][STORAGE] ${kind.name} failed for key=$key: ${error.runtimeType}\n$stackTrace');
      throw LicenseStorageException(kind: kind, key: key, cause: error);
    }
  }

  static Future<String?> _read(String key) => _runStorageOperation(
    kind: LicenseStorageFailureKind.read,
    key: key,
    operation: () => _storage.read(key: key),
  );

  static Future<void> _write(String key, String value) => _runStorageOperation(
    kind: LicenseStorageFailureKind.write,
    key: key,
    operation: () => _storage.write(key: key, value: value),
  );

  static Future<void> _delete(String key) => _runStorageOperation(
    kind: LicenseStorageFailureKind.delete,
    key: key,
    operation: () => _storage.delete(key: key),
  );

  static Never _malformed(String key, Object cause) {
    debugPrint('[LICENSE][STORAGE] malformed local value for key=$key: ${cause.runtimeType}');
    throw LicenseStorageException(
      kind: LicenseStorageFailureKind.malformedData,
      key: key,
      cause: cause,
    );
  }

  static Future<void> saveDeviceId(String deviceId) async => _write(_keyDeviceId, deviceId);
  static Future<String?> getDeviceId() async => _read(_keyDeviceId);
  static Future<void> saveDeviceFingerprintHash(String hash) async => _write(_keyDeviceFingerprintHash, hash);
  static Future<String?> getDeviceFingerprintHash() async => _read(_keyDeviceFingerprintHash);

  static Future<void> saveLicenseStatus(
    LicenseStatus status, {
    String? licenseKey,
  }) async {
    final previousLicenseKey = await _read(_keyLicenseKey);
    final previousProfileId = await _read(_keyMenuProfileId);
    final previousGeneration = await _read(_keyMenuProfileGeneration);
    final menuOn = status.active && status.features.menu;
    // Field -> value to store; null deletes the field. Order is the write order.
    final values = <String, String?>{
      _keyLicenseMode: status.mode.name,
      _keyLicenseKey: ?licenseKey,
      _keyBranchName: status.branchName ?? '',
      _keyCustomerName: status.customerName ?? '',
      _keyPlan: status.plan ?? '',
      _keyExpiresAt: status.expiresAt ?? '',
      _keyTrialExpiresAt: status.trialExpiresAt ?? '',
      _keyFeatures: json.encode(status.features.toJson()),
      _keyMenuAccessToken:
          menuOn &&
              status.menuAccessToken != null &&
              status.menuAccessToken!.isNotEmpty
          ? status.menuAccessToken
          : null,
      _keyMenuProfileId:
          menuOn &&
              status.menuProfileId != null &&
              status.menuProfileId!.isNotEmpty
          ? status.menuProfileId
          : null,
      _keyMenuProfileGeneration: menuOn && status.menuProfileGeneration != null
          ? status.menuProfileGeneration.toString()
          : null,
    };
    // Sorted keys: the license key is only in [values] when it was passed in.
    final digestFields = {
      ...values,
      _keyLicenseKey: licenseKey ?? previousLicenseKey,
    };
    final digest = sha256
        .convert(
          utf8.encode(
            json.encode({
              for (final key in digestFields.keys.toList()..sort())
                key: digestFields[key],
            }),
          ),
        )
        .toString();
    if (await _read(_keyStatusDigest) != digest) {
      for (final entry in values.entries) {
        final value = entry.value;
        if (value == null) {
          await _delete(entry.key);
        } else {
          await _write(entry.key, value);
        }
      }
      await _write(_keyStatusDigest, digest);
    }
    // A license or enrollment change invalidates any prior local admin session.
    // Routine periodic status refreshes for the same profile must keep it, or
    // an admin editing the wheel/barista loses their token every sync cycle.
    final scopeUnchanged = status.active &&
        status.features.menu &&
        (licenseKey == null || licenseKey == previousLicenseKey) &&
        previousProfileId != null &&
        previousProfileId == status.menuProfileId &&
        previousGeneration == status.menuProfileGeneration?.toString();
    if (!scopeUnchanged) await _delete(_keyAdminSessionToken);
  }

  static Future<String?> getMenuAccessToken() => _read(_keyMenuAccessToken);
  static Future<String?> getMenuProfileId() => _read(_keyMenuProfileId);
  static Future<int?> getMenuProfileGeneration() async {
    final value = await _read(_keyMenuProfileGeneration);
    return value == null ? null : int.tryParse(value);
  }
  static Future<String?> getAdminSessionToken() => _read(_keyAdminSessionToken);
  static Future<void> saveAdminSessionToken(String token) async {
    if (token.trim().isNotEmpty) await _write(_keyAdminSessionToken, token.trim());
  }
  static Future<void> clearAdminSessionToken() => _delete(_keyAdminSessionToken);

  static Future<String?> getLicenseKey() async {
    final value = await _read(_keyLicenseKey);
    if (value == null || value.isEmpty) return value;
    if (!_licenseKeyPattern.hasMatch(value)) {
      _malformed(_keyLicenseKey, const FormatException('Stored license key has an invalid format.'));
    }
    return value;
  }

  static Future<LicenseMode> getLicenseMode() async {
    final modeStr = await _read(_keyLicenseMode);
    if (modeStr == null || modeStr.isEmpty || modeStr == 'none') return LicenseMode.none;
    if (modeStr == 'licensed') return LicenseMode.licensed;
    if (modeStr == 'trial') return LicenseMode.trial;
    _malformed(_keyLicenseMode, const FormatException('Stored license mode is invalid.'));
  }

  static Future<LicenseStatus> getCachedLicenseStatus() async {
    final licenseKey = await getLicenseKey();
    final mode = await getLicenseMode();
    if (licenseKey == null || licenseKey.isEmpty || mode == LicenseMode.none) {
      return const LicenseStatus(active: false, mode: LicenseMode.none, features: FeatureFlags.lockedAll);
    }

    final branchName = await _read(_keyBranchName);
    final customerName = await _read(_keyCustomerName);
    final plan = await _read(_keyPlan);
    final expiresAt = await _read(_keyExpiresAt);
    final trialExpiresAt = await _read(_keyTrialExpiresAt);
    final menuAccessToken = await _read(_keyMenuAccessToken);
    final menuProfileId = await _read(_keyMenuProfileId);
    final menuProfileGeneration = await getMenuProfileGeneration();

    final fallbackFlags = mode == LicenseMode.trial
        ? FeatureFlags.trialDefault
        : (mode == LicenseMode.licensed ? FeatureFlags.proDefault : FeatureFlags.lockedAll);
    FeatureFlags features = fallbackFlags;
    final featuresJsonStr = await _read(_keyFeatures);
    if (featuresJsonStr != null && featuresJsonStr.isNotEmpty) {
      try {
        final decodedValue = json.decode(featuresJsonStr);
        if (decodedValue is! Map<String, dynamic>) {
          throw const FormatException('Stored features must be a JSON object.');
        }
        features = FeatureFlags.fromJson(decodedValue, fallback: fallbackFlags);
      } catch (error) {
        _malformed(_keyFeatures, error);
      }
    }

    bool isActive = true;
    String? reason;
    if (mode == LicenseMode.trial && trialExpiresAt != null && trialExpiresAt.isNotEmpty) {
      try {
        if (DateTime.parse(trialExpiresAt).difference(DateTime.now()).isNegative) {
          isActive = false;
          reason = 'trial_expired';
        }
      } catch (error) {
        _malformed(_keyTrialExpiresAt, error);
      }
    }
    if (mode == LicenseMode.licensed && expiresAt != null && expiresAt.isNotEmpty) {
      try {
        if (DateTime.parse(expiresAt).difference(DateTime.now()).isNegative) {
          isActive = false;
          reason = 'license_expired';
        }
      } catch (error) {
        _malformed(_keyExpiresAt, error);
      }
    }

    return LicenseStatus(
      active: isActive,
      mode: mode,
      branchName: branchName,
      customerName: customerName,
      plan: plan,
      expiresAt: expiresAt,
      trialExpiresAt: trialExpiresAt,
      features: isActive ? features : FeatureFlags.lockedAll,
      reason: reason,
      menuAccessToken: menuAccessToken,
      menuProfileId: menuProfileId,
      menuProfileGeneration: menuProfileGeneration,
    );
  }

  static Future<void> clearLicense() async {
    await _delete(_keyStatusDigest);
    await _delete(_keyLicenseMode);
    await _delete(_keyLicenseKey);
    await _delete(_keyBranchName);
    await _delete(_keyCustomerName);
    await _delete(_keyPlan);
    await _delete(_keyExpiresAt);
    await _delete(_keyTrialExpiresAt);
    await _delete(_keyFeatures);
    await _delete(_keyMenuAccessToken);
    await _delete(_keyMenuProfileId);
    await _delete(_keyMenuProfileGeneration);
    await _delete(_keyAdminSessionToken);
    await _delete(_keyLastSuccessfulCheckAt);
  }

  static Future<void> resetForReactivation() => _runStorageOperation(
    kind: LicenseStorageFailureKind.delete,
    key: 'all_secure_storage',
    operation: _storage.deleteAll,
  );

  static const String _keyDownloadedApkInfo = 'downloaded_apk_info';

  static Future<void> saveDownloadedApkInfo({
    required String path,
    required String version,
    required String sha256,
    required int fileSize,
  }) async {
    await _write(_keyDownloadedApkInfo, json.encode({
      'apk_path': path,
      'version': version,
      'sha256': sha256,
      'file_size': fileSize,
      'downloaded_at': DateTime.now().toIso8601String(),
    }));
  }

  static Future<Map<String, dynamic>?> getDownloadedApkInfo() async {
    final val = await _read(_keyDownloadedApkInfo);
    if (val == null) return null;
    try {
      return json.decode(val) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static Future<void> clearDownloadedApkInfo() => _delete(_keyDownloadedApkInfo);
}
