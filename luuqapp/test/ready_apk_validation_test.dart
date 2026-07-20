import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:luuqapp/licensing/license_storage.dart';
import 'package:luuqapp/licensing/update_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temporaryDirectory;
  late File apkFile;
  late List<int> apkBytes;
  late String apkHash;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    LicenseStorage.setStorageForTesting(null);
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'luuq-ready-apk-test-',
    );
    apkBytes = utf8.encode('verified-apk-payload');
    apkHash = sha256.convert(apkBytes).toString();
    apkFile = File('${temporaryDirectory.path}${Platform.pathSeparator}app.apk');
    await apkFile.writeAsBytes(apkBytes);
    await LicenseStorage.saveDownloadedApkInfo(
      path: apkFile.path,
      version: 'v1.2.0+14',
      sha256: apkHash,
      fileSize: apkBytes.length,
    );
  });

  tearDown(() async {
    LicenseStorage.setStorageForTesting(null);
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('accepts an existing APK with matching version, size and SHA-256', () async {
    expect(
      await UpdateService.isDownloadedApkValid(
        expectedVersion: 'v1.2.0+14',
        expectedSha256: apkHash,
        expectedSize: apkBytes.length,
      ),
      isTrue,
    );
  });

  test('rejects a ready APK that was deleted after initial validation', () async {
    await apkFile.delete();

    expect(
      await UpdateService.isDownloadedApkValid(
        expectedVersion: 'v1.2.0+14',
        expectedSha256: apkHash,
        expectedSize: apkBytes.length,
      ),
      isFalse,
    );
  });

  test('rejects a ready APK whose contents changed', () async {
    await apkFile.writeAsString('tampered-apk-payload');

    expect(
      await UpdateService.isDownloadedApkValid(
        expectedVersion: 'v1.2.0+14',
        expectedSha256: apkHash,
      ),
      isFalse,
    );
  });

  test('rejects a ready APK with an unexpected size', () async {
    expect(
      await UpdateService.isDownloadedApkValid(
        expectedVersion: 'v1.2.0+14',
        expectedSha256: apkHash,
        expectedSize: apkBytes.length + 1,
      ),
      isFalse,
    );
  });

  test('rejects ready APK metadata for another target version', () async {
    expect(
      await UpdateService.isDownloadedApkValid(
        expectedVersion: 'v1.3.0+15',
        expectedSha256: apkHash,
        expectedSize: apkBytes.length,
      ),
      isFalse,
    );
  });

  test('rejects metadata whose recorded SHA-256 differs from target', () async {
    await LicenseStorage.saveDownloadedApkInfo(
      path: apkFile.path,
      version: 'v1.2.0+14',
      sha256: List.filled(64, '0').join(),
      fileSize: apkBytes.length,
    );

    expect(
      await UpdateService.isDownloadedApkValid(
        expectedVersion: 'v1.2.0+14',
        expectedSha256: apkHash,
        expectedSize: apkBytes.length,
      ),
      isFalse,
    );
  });
}
