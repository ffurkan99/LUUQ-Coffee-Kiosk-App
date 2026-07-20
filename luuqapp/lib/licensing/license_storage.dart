import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'license_status.dart';
import 'feature_flags.dart';

enum LicenseStorageFailureKind { read, write, delete, malformedData }

class LicenseStorageException implements Exception {
  final LicenseStorageFailureKind kind;
  final String key;
  final Object cause;

  const LicenseStorageException({
    required this.kind,
    required this.key,
    required this.cause,
  });

  @override
  String toString() =>
      'LicenseStorageException(kind: ${kind.name}, key: $key, cause: ${cause.runtimeType})';
}

class LicenseStorage {
  static const _defaultStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
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
  static const String _keyLastSuccessfulCheckAt = 'last_successful_check_at';

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
      debugPrint(
        '[LICENSE][STORAGE] ${kind.name} failed for key=$key: '
        '${error.runtimeType}\n$stackTrace',
      );
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
    debugPrint(
      '[LICENSE][STORAGE] malformed local value for key=$key: '
      '${cause.runtimeType}',
    );
    throw LicenseStorageException(
      kind: LicenseStorageFailureKind.malformedData,
      key: key,
      cause: cause,
    );
  }

  /// Save persistent device ID
  static Future<void> saveDeviceId(String deviceId) async {
    await _write(_keyDeviceId, deviceId);
  }

  /// Get persistent device ID
  static Future<String?> getDeviceId() async {
    return _read(_keyDeviceId);
  }

  /// Save persistent device fingerprint hash
  static Future<void> saveDeviceFingerprintHash(String hash) async {
    await _write(_keyDeviceFingerprintHash, hash);
  }

  /// Get persistent device fingerprint hash
  static Future<String?> getDeviceFingerprintHash() async {
    return _read(_keyDeviceFingerprintHash);
  }

  /// Save full license status/result
  static Future<void> saveLicenseStatus(
    LicenseStatus status, {
    String? licenseKey,
  }) async {
    await _write(_keyLicenseMode, status.mode.name);
    if (licenseKey != null) {
      await _write(_keyLicenseKey, licenseKey);
    }
    await _write(_keyBranchName, status.branchName ?? '');
    await _write(_keyCustomerName, status.customerName ?? '');
    await _write(_keyPlan, status.plan ?? '');
    await _write(_keyExpiresAt, status.expiresAt ?? '');
    await _write(_keyTrialExpiresAt, status.trialExpiresAt ?? '');
    await _write(_keyFeatures, json.encode(status.features.toJson()));
    await _write(_keyLastSuccessfulCheckAt, DateTime.now().toIso8601String());
  }

  /// Get stored license key
  static Future<String?> getLicenseKey() async {
    final value = await _read(_keyLicenseKey);
    if (value == null || value.isEmpty) return value;
    if (!_licenseKeyPattern.hasMatch(value)) {
      _malformed(
        _keyLicenseKey,
        const FormatException('Stored license key has an invalid format.'),
      );
    }
    return value;
  }

  /// Get stored license mode
  static Future<LicenseMode> getLicenseMode() async {
    final modeStr = await _read(_keyLicenseMode);
    if (modeStr == null || modeStr.isEmpty || modeStr == 'none') {
      return LicenseMode.none;
    }
    if (modeStr == 'licensed') return LicenseMode.licensed;
    if (modeStr == 'trial') return LicenseMode.trial;
    _malformed(
      _keyLicenseMode,
      const FormatException('Stored license mode is invalid.'),
    );
  }

  /// Load cached license status
  static Future<LicenseStatus> getCachedLicenseStatus() async {
    final licenseKey = await getLicenseKey();
    final mode = await getLicenseMode();
    if (licenseKey == null || licenseKey.isEmpty || mode == LicenseMode.none) {
      return const LicenseStatus(
        active: false,
        mode: LicenseMode.none,
        features: FeatureFlags.lockedAll,
      );
    }

    final branchName = await _read(_keyBranchName);
    final customerName = await _read(_keyCustomerName);
    final plan = await _read(_keyPlan);
    final expiresAt = await _read(_keyExpiresAt);
    final trialExpiresAt = await _read(_keyTrialExpiresAt);

    final fallbackFlags = mode == LicenseMode.trial
        ? FeatureFlags.trialDefault
        : (mode == LicenseMode.licensed
              ? FeatureFlags.proDefault
              : FeatureFlags.lockedAll);

    FeatureFlags features = fallbackFlags;
    final featuresJsonStr = await _read(_keyFeatures);
    if (featuresJsonStr != null && featuresJsonStr.isNotEmpty) {
      try {
        final decodedValue = json.decode(featuresJsonStr);
        if (decodedValue is! Map<String, dynamic>) {
          throw const FormatException('Stored features must be a JSON object.');
        }
        final Map<String, dynamic> decoded = decodedValue;
        features = FeatureFlags.fromJson(decoded, fallback: fallbackFlags);
      } catch (error) {
        _malformed(_keyFeatures, error);
      }
    }

    bool isActive = true;
    String? reason;
    if (mode == LicenseMode.trial &&
        trialExpiresAt != null &&
        trialExpiresAt.isNotEmpty) {
      try {
        final expiry = DateTime.parse(trialExpiresAt);
        if (expiry.difference(DateTime.now()).isNegative) {
          isActive = false;
          reason = 'trial_expired';
        }
      } catch (error) {
        _malformed(_keyTrialExpiresAt, error);
      }
    }
    if (mode == LicenseMode.licensed &&
        expiresAt != null &&
        expiresAt.isNotEmpty) {
      try {
        final expiry = DateTime.parse(expiresAt);
        if (expiry.difference(DateTime.now()).isNegative) {
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
    );
  }

  /// Get last check timestamp
  static Future<String?> getLastSuccessfulCheckAt() async {
    return _read(_keyLastSuccessfulCheckAt);
  }

  /// Reset licensing info (except device ID)
  static Future<void> clearLicense() async {
    await _delete(_keyLicenseMode);
    await _delete(_keyLicenseKey);
    await _delete(_keyBranchName);
    await _delete(_keyCustomerName);
    await _delete(_keyPlan);
    await _delete(_keyExpiresAt);
    await _delete(_keyTrialExpiresAt);
    await _delete(_keyFeatures);
    await _delete(_keyLastSuccessfulCheckAt);
  }

  /// Explicit recovery for an unreadable device-bound secure store. This is
  /// never called automatically; the activation UI requires user confirmation.
  static Future<void> resetForReactivation() => _runStorageOperation(
    kind: LicenseStorageFailureKind.delete,
    key: 'all_secure_storage',
    operation: _storage.deleteAll,
  );

  static const String _keyDownloadedApkInfo = 'downloaded_apk_info';

  /// Save downloaded APK metadata in storage
  static Future<void> saveDownloadedApkInfo({
    required String path,
    required String version,
    required String sha256,
    required int fileSize,
  }) async {
    final Map<String, dynamic> info = {
      'apk_path': path,
      'version': version,
      'sha256': sha256,
      'file_size': fileSize,
      'downloaded_at': DateTime.now().toIso8601String(),
    };
    await _write(_keyDownloadedApkInfo, json.encode(info));
  }

  /// Read downloaded APK metadata
  static Future<Map<String, dynamic>?> getDownloadedApkInfo() async {
    final val = await _read(_keyDownloadedApkInfo);
    if (val == null) return null;
    try {
      return json.decode(val) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Clear downloaded APK metadata
  static Future<void> clearDownloadedApkInfo() async {
    await _delete(_keyDownloadedApkInfo);
  }
}
