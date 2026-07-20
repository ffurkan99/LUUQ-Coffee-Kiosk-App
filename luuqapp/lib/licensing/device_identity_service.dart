import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:uuid/uuid.dart';
import 'license_storage.dart';

class DeviceIdentityService {
  static final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();
  
  static String? _cachedDeviceId;
  static String? _cachedFingerprint;
  static String? _cachedDeviceModel;
  static String? _cachedAppVersion;

  /// Get or generate unique persistent device UUID
  static Future<String> getDeviceId() async {
    if (_cachedDeviceId != null) return _cachedDeviceId!;

    // Check secure storage
    String? storedId = await LicenseStorage.getDeviceId();
    if (storedId == null || storedId.trim().isEmpty) {
      // Generate new UUID
      storedId = const Uuid().v4();
      await LicenseStorage.saveDeviceId(storedId);
    }
    
    _cachedDeviceId = storedId;
    return storedId;
  }

  /// Get or calculate device fingerprint hash (SHA-256)
  static Future<String> getDeviceFingerprintHash() async {
    if (_cachedFingerprint != null) return _cachedFingerprint!;

    // Check secure storage
    String? storedHash = await LicenseStorage.getDeviceFingerprintHash();
    if (storedHash != null && storedHash.trim().isNotEmpty) {
      _cachedFingerprint = storedHash;
      return storedHash;
    }

    // Otherwise, generate new fingerprint
    String fingerprintData = '';
    try {
      if (Platform.isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo;
        fingerprintData = [
          androidInfo.manufacturer,
          androidInfo.model,
          androidInfo.brand,
          androidInfo.device,
          androidInfo.hardware,
          androidInfo.id,
        ].join('|');
      } else if (Platform.isWindows) {
        final windowsInfo = await _deviceInfo.windowsInfo;
        fingerprintData = [
          windowsInfo.computerName,
          windowsInfo.numberOfCores.toString(),
          windowsInfo.systemMemoryInMegabytes.toString(),
        ].join('|');
      } else if (Platform.isIOS) {
        final iosInfo = await _deviceInfo.iosInfo;
        fingerprintData = [
          iosInfo.name,
          iosInfo.model,
          iosInfo.systemName,
          iosInfo.systemVersion,
          iosInfo.identifierForVendor ?? '',
        ].join('|');
      } else {
        fingerprintData = 'generic-platform-${Platform.operatingSystem}';
      }
    } catch (_) {
      fingerprintData = 'fallback-fingerprint-${DateTime.now().millisecondsSinceEpoch}';
    }

    // SHA-256 hash
    final bytes = utf8.encode(fingerprintData);
    final hash = sha256.convert(bytes).toString();

    await LicenseStorage.saveDeviceFingerprintHash(hash);
    _cachedFingerprint = hash;
    return hash;
  }

  /// Get device model name for analytics and registration
  static Future<String> getDeviceModel() async {
    if (_cachedDeviceModel != null) return _cachedDeviceModel!;

    String modelStr = 'Cihaz';
    try {
      if (Platform.isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo;
        final manufacturer = androidInfo.manufacturer;
        final model = androidInfo.model;
        if (manufacturer.isEmpty) {
          modelStr = model.isEmpty ? 'Android Cihaz' : model;
        } else if (model.toLowerCase().contains(manufacturer.toLowerCase())) {
          modelStr = model;
        } else {
          modelStr = '$manufacturer $model';
        }
      } else if (Platform.isWindows) {
        modelStr = 'Windows';
      } else if (Platform.isIOS) {
        final iosInfo = await _deviceInfo.iosInfo;
        modelStr = iosInfo.model;
      } else {
        modelStr = Platform.operatingSystem;
      }
    } catch (_) {}

    if (modelStr.trim().isEmpty) {
      modelStr = 'Cihaz';
    }

    _cachedDeviceModel = modelStr;
    return modelStr;
  }

  /// Get formatted application version (e.g. v1.0.3+12 or v1.0.3 or unknown)
  static Future<String> getAppVersion({bool bypassCache = false}) async {
    if (bypassCache) {
      _cachedAppVersion = null;
    }
    if (_cachedAppVersion != null) return _cachedAppVersion!;

    String versionStr = 'unknown';
    try {
      final info = await PackageInfo.fromPlatform();
      final version = info.version;
      final buildNumber = info.buildNumber;
      if (version.isNotEmpty) {
        String normalizedVersion = version;
        final segments = version.split('.');
        if (segments.length == 1 && segments[0].isNotEmpty) {
          normalizedVersion = '${segments[0]}.0.0';
        } else if (segments.length == 2) {
          normalizedVersion = '${segments[0]}.${segments[1]}.0';
        }
        if (buildNumber.isNotEmpty) {
          versionStr = 'v$normalizedVersion+$buildNumber';
        } else {
          versionStr = 'v$normalizedVersion';
        }
      }
    } catch (_) {}

    _cachedAppVersion = versionStr;
    
    if (kDebugMode) {
      debugPrint('AppVersion resolved: $versionStr');
    }
    
    return versionStr;
  }
}
