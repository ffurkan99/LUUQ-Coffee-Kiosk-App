import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:luuqapp/licensing/feature_flags.dart';
import 'package:luuqapp/licensing/license_activation_screen.dart';
import 'package:luuqapp/licensing/license_gate.dart';
import 'package:luuqapp/licensing/license_service.dart';
import 'package:luuqapp/licensing/license_status.dart';
import 'package:luuqapp/licensing/license_storage.dart';
import 'package:luuqapp/main.dart' show CafeKioskScreen;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeSecureStorage storage;

  setUp(() {
    storage = _FakeSecureStorage(<String, String>{
      'license_key': 'LUUQ-TEST-TEST-TEST-TEST',
    });
    LicenseStorage.setStorageForTesting(storage);
    LicenseService.instance.statusNotifier.value = const LicenseStatus(
      active: false,
      mode: LicenseMode.none,
      features: FeatureFlags.lockedAll,
    );
  });

  tearDown(() {
    LicenseStorage.setStorageForTesting(null);
  });

  test('normal license key read returns the stored value', () async {
    expect(await LicenseStorage.getLicenseKey(), 'LUUQ-TEST-TEST-TEST-TEST');
  });

  test('storage read exception is typed and does not reset data', () async {
    storage.onRead = (_) async => throw StateError('simulated read failure');

    await expectLater(
      LicenseStorage.getLicenseKey(),
      throwsA(
        isA<LicenseStorageException>()
            .having(
              (error) => error.kind,
              'kind',
              LicenseStorageFailureKind.read,
            )
            .having((error) => error.key, 'key', 'license_key'),
      ),
    );
    expect(storage.deleteAllCalls, 0);
    expect(storage.values['license_key'], 'LUUQ-TEST-TEST-TEST-TEST');
  });

  test('keystore-like decryption exception remains fail-closed', () async {
    storage.onRead = (_) async => throw PlatformException(
      code: 'Exception encountered',
      message: 'read',
      details: 'java.security.InvalidKeyException: Failed to unwrap key',
    );

    await expectLater(
      LicenseStorage.getLicenseKey(),
      throwsA(
        isA<LicenseStorageException>().having(
          (error) => error.kind,
          'kind',
          LicenseStorageFailureKind.read,
        ),
      ),
    );
    expect(storage.deleteAllCalls, 0);
  });

  test('storage write exception is typed and never triggers reset', () async {
    storage.onWrite = (_, _) async => throw PlatformException(
      code: 'Exception encountered',
      message: 'write',
    );

    await expectLater(
      LicenseStorage.saveLicenseStatus(
        const LicenseStatus(
          active: true,
          mode: LicenseMode.licensed,
          features: FeatureFlags.proDefault,
        ),
        licenseKey: 'LUUQ-NEW1-NEW2-NEW3-NEW4',
      ),
      throwsA(
        isA<LicenseStorageException>().having(
          (error) => error.kind,
          'kind',
          LicenseStorageFailureKind.write,
        ),
      ),
    );
    expect(storage.deleteAllCalls, 0);
    expect(storage.values['license_key'], 'LUUQ-TEST-TEST-TEST-TEST');
  });

  test(
    'LicenseService does not mask a storage read failure as network error',
    () async {
      storage.onRead = (key) async {
        if (key == 'license_key') return storage.values[key];
        throw PlatformException(
          code: 'Exception encountered',
          message: 'device identity read',
        );
      };

      await expectLater(
        LicenseService.instance.checkStatus(),
        throwsA(
          isA<LicenseStorageException>().having(
            (error) => error.kind,
            'kind',
            LicenseStorageFailureKind.read,
          ),
        ),
      );
      expect(LicenseService.instance.currentStatus.active, isFalse);
    },
  );

  testWidgets('activation write failure closes its loader safely', (
    tester,
  ) async {
    storage.values.clear();
    storage.onWrite = (_, _) async => throw PlatformException(
      code: 'Exception encountered',
      message: 'device identity write',
    );
    var storageFailureCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: LicenseActivationScreen(
          onActivated: () {},
          onStorageFailure: () => storageFailureCount++,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'LUUQ-ABCD-EFGH-IJKL-MNOP');
    await tester.tap(find.text('Lisansı Aktifleştir'));
    await tester.pumpAndSettle();

    expect(storageFailureCount, 1);
    expect(find.byType(CafeKioskScreen), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(
      find.textContaining('Güvenli lisans verisine erişilemiyor'),
      findsOneWidget,
    );
    expect(storage.deleteAllCalls, 0);
  });

  testWidgets(
    'malformed local license value closes loader and blocks customer UI',
    (tester) async {
      storage.values['license_key'] = 'restored-ciphertext';

      await tester.pumpWidget(const MaterialApp(home: LicenseGate()));
      await tester.pumpAndSettle();

      _expectStorageFailureScreen(tester);
      expect(storage.deleteAllCalls, 0);
    },
  );

  testWidgets('storage read failure closes loader and blocks customer UI', (
    tester,
  ) async {
    storage.onRead = (_) async =>
        throw PlatformException(code: 'Exception encountered', message: 'read');

    await tester.pumpWidget(const MaterialApp(home: LicenseGate()));
    await tester.pumpAndSettle();

    _expectStorageFailureScreen(tester);
    expect(storage.deleteAllCalls, 0);
  });

  testWidgets('storage failure remains safe across background and resume', (
    tester,
  ) async {
    storage.onRead = (_) async =>
        throw PlatformException(code: 'Exception encountered', message: 'read');

    await tester.pumpWidget(const MaterialApp(home: LicenseGate()));
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    _expectStorageFailureScreen(tester);
    expect(storage.deleteAllCalls, 0);
  });

  testWidgets('late storage failure after dispose does not call setState', (
    tester,
  ) async {
    final readCompleter = Completer<String?>();
    storage.onRead = (_) => readCompleter.future;

    await tester.pumpWidget(const MaterialApp(home: LicenseGate()));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    readCompleter.completeError(
      PlatformException(
        code: 'Exception encountered',
        message: 'late read failure',
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(CafeKioskScreen), findsNothing);
  });

  testWidgets('secure storage is cleared only after explicit confirmation', (
    tester,
  ) async {
    var failReads = true;
    storage.onRead = (key) async {
      if (failReads) {
        throw PlatformException(code: 'Exception encountered', message: 'read');
      }
      return storage.values[key];
    };
    storage.onDeleteAll = () async {
      storage.deleteAllCalls++;
      storage.values.clear();
      failReads = false;
    };

    await tester.pumpWidget(const MaterialApp(home: LicenseGate()));
    await tester.pumpAndSettle();
    expect(storage.deleteAllCalls, 0);

    await tester.tap(find.text('Lisansı Yeniden Etkinleştir'));
    await tester.pumpAndSettle();
    expect(storage.deleteAllCalls, 0);

    await tester.tap(find.text('Sıfırla ve Etkinleştir'));
    await tester.pumpAndSettle();

    expect(storage.deleteAllCalls, 1);
    expect(find.byType(CafeKioskScreen), findsNothing);
    expect(find.byType(LicenseActivationScreen), findsOneWidget);
  });
}

void _expectStorageFailureScreen(WidgetTester tester) {
  expect(find.byType(CafeKioskScreen), findsNothing);
  expect(find.text('Lisans Verisine Erişilemiyor'), findsOneWidget);
  expect(find.text('Tekrar Dene'), findsOneWidget);
  expect(find.text('Lisansı Yeniden Etkinleştir'), findsOneWidget);
  expect(find.byType(CircularProgressIndicator), findsNothing);
}

class _FakeSecureStorage extends FlutterSecureStorage {
  _FakeSecureStorage(this.values);

  final Map<String, String> values;
  Future<String?> Function(String key)? onRead;
  Future<void> Function(String key, String? value)? onWrite;
  Future<void> Function(String key)? onDelete;
  Future<void> Function()? onDeleteAll;
  int deleteAllCalls = 0;

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    final handler = onRead;
    if (handler != null) return handler(key);
    return values[key];
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    final handler = onWrite;
    if (handler != null) return handler(key, value);
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    final handler = onDelete;
    if (handler != null) return handler(key);
    values.remove(key);
  }

  @override
  Future<void> deleteAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    final handler = onDeleteAll;
    if (handler != null) return handler();
    deleteAllCalls++;
    values.clear();
  }
}
