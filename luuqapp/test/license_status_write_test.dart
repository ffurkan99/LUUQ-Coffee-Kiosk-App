import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:luuqapp/licensing/feature_flags.dart';
import 'package:luuqapp/licensing/license_status.dart';
import 'package:luuqapp/licensing/license_storage.dart';

/// Counts writes and deletes so the test can see what one status save costs.
class _CountingStorage extends FlutterSecureStorage {
  final values = <String, String>{};
  int writes = 0;
  int deletes = 0;

  /// Yield on every call so concurrent operations could interleave.
  bool slow = false;

  /// Throw on this write number (1-based), simulating a crash mid-save.
  int? failOnWrite;

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (slow) await Future<void>.delayed(Duration.zero);
    return values[key];
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (slow) await Future<void>.delayed(Duration.zero);
    writes++;
    if (failOnWrite != null && writes == failOnWrite) {
      throw Exception('simulated crash');
    }
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (slow) await Future<void>.delayed(Duration.zero);
    deletes++;
    values.remove(key);
  }
}

void main() {
  late _CountingStorage storage;

  const status = LicenseStatus(
    active: true,
    mode: LicenseMode.licensed,
    customerName: 'LUUQ',
    branchName: 'Merkez',
    features: FeatureFlags.proDefault,
    menuAccessToken: 'token-1',
    menuProfileId: 'profile-1',
    menuProfileGeneration: 1,
  );

  setUp(() {
    storage = _CountingStorage();
    LicenseStorage.setStorageForTesting(storage);
  });

  tearDown(() => LicenseStorage.setStorageForTesting(null));

  test('an unchanged status is not written again', () async {
    await LicenseStorage.saveLicenseStatus(status, licenseKey: 'LUUQ-KEY');
    expect(storage.values['customer_name'], 'LUUQ');
    final writesAfterFirst = storage.writes;
    expect(writesAfterFirst, greaterThan(5));

    // A routine 30 s check returns the same status without the key.
    await LicenseStorage.saveLicenseStatus(status);
    expect(storage.writes, writesAfterFirst);
  });

  test('a changed field is written', () async {
    await LicenseStorage.saveLicenseStatus(status, licenseKey: 'LUUQ-KEY');
    final writesAfterFirst = storage.writes;
    const renamed = LicenseStatus(
      active: true,
      mode: LicenseMode.licensed,
      customerName: 'LUUQ',
      branchName: 'Yeni Şube',
      features: FeatureFlags.proDefault,
      menuAccessToken: 'token-1',
      menuProfileId: 'profile-1',
      menuProfileGeneration: 1,
    );
    await LicenseStorage.saveLicenseStatus(renamed);
    expect(storage.writes, greaterThan(writesAfterFirst));
    expect(storage.values['branch_name'], 'Yeni Şube');
  });

  test('after clearLicense the same status is stored again', () async {
    await LicenseStorage.saveLicenseStatus(status, licenseKey: 'LUUQ-KEY');
    await LicenseStorage.clearLicense();
    expect(storage.values['customer_name'], isNull);

    await LicenseStorage.saveLicenseStatus(status, licenseKey: 'LUUQ-KEY');
    expect(storage.values['customer_name'], 'LUUQ');
    expect(storage.values['menu_access_token'], 'token-1');
  });

  test('concurrent save, clear and save end in the last state', () async {
    storage.slow = true;
    const other = LicenseStatus(
      active: true,
      mode: LicenseMode.licensed,
      customerName: 'Başka',
      branchName: 'Şube 2',
      features: FeatureFlags.proDefault,
      menuAccessToken: 'token-2',
      menuProfileId: 'profile-2',
      menuProfileGeneration: 2,
    );
    await Future.wait([
      LicenseStorage.saveLicenseStatus(status, licenseKey: 'LUUQ-KEY'),
      LicenseStorage.clearLicense(),
      LicenseStorage.saveLicenseStatus(other, licenseKey: 'LUUQ-KEY'),
    ]);
    expect(storage.values['customer_name'], 'Başka');
    expect(storage.values['branch_name'], 'Şube 2');
    expect(storage.values['menu_access_token'], 'token-2');
    expect(storage.values['license_key'], 'LUUQ-KEY');
  });

  test('a save cut off halfway is fully rewritten next time', () async {
    await LicenseStorage.saveLicenseStatus(status, licenseKey: 'LUUQ-KEY');
    const renamed = LicenseStatus(
      active: true,
      mode: LicenseMode.licensed,
      customerName: 'LUUQ',
      branchName: 'Yeni Şube',
      features: FeatureFlags.proDefault,
      menuAccessToken: 'token-1',
      menuProfileId: 'profile-1',
      menuProfileGeneration: 1,
    );
    storage.failOnWrite = storage.writes + 3;
    await expectLater(
      LicenseStorage.saveLicenseStatus(renamed),
      throwsA(anything),
    );
    expect(storage.values['license_status_digest'], isNull);
    storage.failOnWrite = null;
    await LicenseStorage.saveLicenseStatus(renamed);
    expect(storage.values['branch_name'], 'Yeni Şube');
    expect(storage.values['license_status_digest'], isNotNull);
  });

  test(
    'the admin session survives routine refreshes of the same profile',
    () async {
      await LicenseStorage.saveLicenseStatus(status, licenseKey: 'LUUQ-KEY');
      await LicenseStorage.saveAdminSessionToken('admin-token');
      await LicenseStorage.saveLicenseStatus(status);
      expect(storage.values['menu_admin_session_token'], 'admin-token');
    },
  );
}
