import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'license_status.dart';

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
  // resetOnError false: the plugin's default wipes everything on a read error
  // (e.g. a Keystore hiccup after boot), and the kiosk then re-enrolled as a
  // new device. Now the error reaches the gate, which shows the storage
  // failure screen with "Tekrar Dene" and an explicit, confirmed reset.
  static const AndroidOptions _androidOptions = AndroidOptions(
    resetOnError: false,
  );
  static const _defaultStorage = FlutterSecureStorage(aOptions: _androidOptions);
  static FlutterSecureStorage _storage = _defaultStorage;

  @visibleForTesting
  static AndroidOptions get androidOptionsForTesting => _androidOptions;

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

  /// A status save is a dozen separate writes. When a newer save or a clear
  /// starts meanwhile (30 s sync, menu 401 retry, update flow), the older one
  /// stops at its next step instead of writing stale values over the new
  /// ones. Nothing waits on anything, so a stuck call cannot block the rest.
  static int _stateGeneration = 0;

  static Future<void> saveLicenseStatus(
    LicenseStatus status, {
    String? licenseKey,
  }) async {
    final generation = ++_stateGeneration;
    bool superseded() => generation != _stateGeneration;

    final previousLicenseKey = await _read(_keyLicenseKey);
    final previousProfileId = await _read(_keyMenuProfileId);
    final previousGeneration = await _read(_keyMenuProfileGeneration);
    if (superseded()) return;
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
      // Drop the old digest first: if the writes below stop halfway, the next
      // save sees no matching digest and rewrites every field.
      await _delete(_keyStatusDigest);
      for (final entry in values.entries) {
        if (superseded()) return;
        final value = entry.value;
        if (value == null) {
          await _delete(entry.key);
        } else {
          await _write(entry.key, value);
        }
      }
      if (superseded()) return;
      await _write(_keyStatusDigest, digest);
    }
    if (superseded()) return;
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

  static Future<void> clearLicense() async {
    final generation = ++_stateGeneration;
    for (final key in const [
      _keyStatusDigest,
      _keyLicenseMode,
      _keyLicenseKey,
      _keyBranchName,
      _keyCustomerName,
      _keyPlan,
      _keyExpiresAt,
      _keyTrialExpiresAt,
      _keyFeatures,
      _keyMenuAccessToken,
      _keyMenuProfileId,
      _keyMenuProfileGeneration,
      _keyAdminSessionToken,
      _keyLastSuccessfulCheckAt,
    ]) {
      // A save that started after this clear owns the state now.
      if (generation != _stateGeneration) return;
      await _delete(key);
    }
  }

  static Future<void> resetForReactivation() {
    ++_stateGeneration;
    return _runStorageOperation(
      kind: LicenseStorageFailureKind.delete,
      key: 'all_secure_storage',
      operation: _storage.deleteAll,
    );
  }

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
