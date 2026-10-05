import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:luuqapp/licensing/feature_flags.dart';
import 'package:luuqapp/licensing/feature_sync_service.dart';
import 'package:luuqapp/licensing/license_activation_screen.dart';
import 'package:luuqapp/licensing/license_config.dart';
import 'package:luuqapp/licensing/license_gate.dart';
import 'package:luuqapp/licensing/license_service.dart';
import 'package:luuqapp/licensing/license_status.dart';
import 'package:luuqapp/main.dart' show CafeKioskScreen, navigatorKey;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues(_storedLicenseCache());
    PackageInfo.setMockInitialValues(
      appName: 'LUUQ',
      packageName: 'com.luuq.kiosk',
      version: '1.1.0',
      buildNumber: '13',
      buildSignature: '',
    );
    LicenseService.instance.statusNotifier.value = const LicenseStatus(
      active: false,
      mode: LicenseMode.none,
      features: FeatureFlags.lockedAll,
    );
  });

  tearDown(() {
    FeatureSyncService.instance.stop();
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('luuqapp/apk_install'),
          null,
        );
  });

  testWidgets('valid API response is the only path that opens customer UI', (
    tester,
  ) async {
    await _runGateScenario(
      tester,
      (_) async => http.Response(
        jsonEncode({
          'active': true,
          'mode': 'licensed',
          'plan': 'pro',
          'features': FeatureFlags.proDefault.toJson(),
        }),
        200,
      ),
      () {
        expect(find.byType(CafeKioskScreen), findsOneWidget);
        expect(LicenseService.instance.currentStatus.active, isTrue);
      },
    );
  });

  testWidgets('timeout keeps the customer UI closed', (tester) async {
    await _runGateScenario(
      tester,
      (_) async => throw TimeoutException('simulated timeout'),
      () => _expectServerUnavailable(tester),
    );
  });

  testWidgets('DNS failure keeps the customer UI closed', (tester) async {
    await _runGateScenario(
      tester,
      (_) async => throw const SocketException('Failed host lookup'),
      () => _expectServerUnavailable(tester),
    );
  });

  testWidgets('TLS failure keeps the customer UI closed', (tester) async {
    await _runGateScenario(
      tester,
      (_) async => throw const HandshakeException('simulated TLS failure'),
      () => _expectServerUnavailable(tester),
    );
  });

  testWidgets('API 5xx keeps the customer UI closed', (tester) async {
    await _runGateScenario(
      tester,
      (_) async => http.Response('temporary failure', 503),
      () => _expectServerUnavailable(tester),
    );
  });

  testWidgets('malformed API response keeps the customer UI closed', (
    tester,
  ) async {
    await _runGateScenario(
      tester,
      (_) async => http.Response('{not-json', 200),
      () => _expectServerUnavailable(tester),
    );
  });

  testWidgets('unexpected response schema keeps the customer UI closed', (
    tester,
  ) async {
    await _runGateScenario(
      tester,
      (_) async => http.Response(jsonEncode({'status': 'ok'}), 200),
      () => _expectServerUnavailable(tester),
    );
  });

  testWidgets('invalid license shows the existing activation UI', (
    tester,
  ) async {
    await _runGateScenario(
      tester,
      (_) async => http.Response(
        jsonEncode({'active': false, 'reason': 'invalid_license'}),
        200,
      ),
      () {
        expect(find.byType(CafeKioskScreen), findsNothing);
        expect(find.byType(LicenseActivationScreen), findsOneWidget);
        expect(LicenseService.instance.currentStatus.active, isFalse);
      },
    );
  });

  testWidgets(
    'HTTP 400 license_inactive is an authoritative inactive response',
    (tester) async {
      await _runGateScenario(
        tester,
        (_) async => http.Response(
          jsonEncode({
            'active': false,
            'reason': 'license_inactive',
            'message': 'Bu lisans pasif durumda.',
          }),
          400,
        ),
        () {
          expect(find.byType(CafeKioskScreen), findsNothing);
          expect(find.byType(LicenseActivationScreen), findsOneWidget);
          expect(LicenseService.instance.currentStatus.active, isFalse);
          expect(
            LicenseService.instance.currentStatus.reason,
            'license_inactive',
          );
        },
      );
    },
  );

  testWidgets('unknown HTTP 400 response remains a server error', (
    tester,
  ) async {
    await _runGateScenario(
      tester,
      (_) async => http.Response(
        jsonEncode({'active': false, 'reason': 'unexpected_backend_error'}),
        400,
      ),
      () => _expectServerUnavailable(tester),
    );
  });

  testWidgets('runtime sync redirects after HTTP 400 license deactivation', (
    tester,
  ) async {
    LicenseService.instance.statusNotifier.value = const LicenseStatus(
      active: true,
      mode: LicenseMode.licensed,
      features: FeatureFlags.proDefault,
    );

    await http.runWithClient(
      () async {
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: navigatorKey,
            home: const _CustomerUiMarker(),
          ),
        );

        await FeatureSyncService.instance.syncNow();
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }

        expect(find.byType(_CustomerUiMarker), findsNothing);
        expect(find.byType(LicenseActivationScreen), findsOneWidget);
        expect(LicenseService.instance.currentStatus.active, isFalse);
        expect(
          LicenseService.instance.currentStatus.reason,
          'license_inactive',
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
      () => MockClient((request) async {
        expect(request.url, Uri.parse(LicenseConfig.checkStatusUrl));
        return http.Response(
          jsonEncode({'active': false, 'reason': 'license_inactive'}),
          400,
        );
      }),
    );
  });

  testWidgets(
    'runtime deactivation keeps Android LockTask active and never disables it',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      const channel = MethodChannel('luuqapp/apk_install');
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            if (call.method == 'isLockTaskActive') return true;
            throw PlatformException(code: 'UNEXPECTED_METHOD');
          });

      LicenseService.instance.statusNotifier.value = const LicenseStatus(
        active: true,
        mode: LicenseMode.licensed,
        features: FeatureFlags.proDefault,
      );

      await http.runWithClient(
        () async {
          await tester.pumpWidget(
            MaterialApp(
              navigatorKey: navigatorKey,
              home: const _CustomerUiMarker(),
            ),
          );

          await FeatureSyncService.instance.syncNow();
          for (var i = 0; i < 20; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }

          expect(find.byType(_CustomerUiMarker), findsNothing);
          expect(find.byType(LicenseActivationScreen), findsOneWidget);
          expect(calls, contains('isLockTaskActive'));
          expect(calls, isNot(contains('disableKioskMode')));
        },
        () => MockClient((_) async => http.Response(
          jsonEncode({'active': false, 'reason': 'license_inactive'}),
          400,
        )),
      );
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'runtime deactivation shows blocking maintenance when LockTask restore fails',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      const channel = MethodChannel('luuqapp/apk_install');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'isLockTaskActive') return false;
            if (call.method == 'restoreKioskModeAfterUpdateCancel') {
              throw PlatformException(code: 'LOCK_TASK_FAILED');
            }
            throw PlatformException(code: 'UNEXPECTED_METHOD');
          });

      LicenseService.instance.statusNotifier.value = const LicenseStatus(
        active: true,
        mode: LicenseMode.licensed,
        features: FeatureFlags.proDefault,
      );

      await http.runWithClient(
        () async {
          await tester.pumpWidget(
            MaterialApp(
              navigatorKey: navigatorKey,
              home: const _CustomerUiMarker(),
            ),
          );

          await FeatureSyncService.instance.syncNow();
          for (var i = 0; i < 20; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }

          expect(find.byType(_CustomerUiMarker), findsNothing);
          expect(find.byType(LicenseActivationScreen), findsNothing);
          expect(find.text('Güvenli Kiosk Modu Geri Açılamadı'), findsOneWidget);
          expect(find.text('Kiosk Modunu Tekrar Aç'), findsOneWidget);
        },
        () => MockClient((_) async => http.Response(
          jsonEncode({'active': false, 'reason': 'license_inactive'}),
          400,
        )),
      );
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('expired license shows the existing activation UI', (
    tester,
  ) async {
    await _runGateScenario(
      tester,
      (_) async => http.Response(
        jsonEncode({'active': false, 'reason': 'license_expired'}),
        200,
      ),
      () {
        expect(find.byType(CafeKioskScreen), findsNothing);
        expect(find.byType(LicenseActivationScreen), findsOneWidget);
        expect(LicenseService.instance.currentStatus.reason, 'license_expired');
      },
    );
  });

  testWidgets('revoked license never opens the customer UI', (tester) async {
    await _runGateScenario(
      tester,
      (_) async => http.Response(
        jsonEncode({
          'active': false,
          'reason': 'device_revoked',
          'reset_required': true,
        }),
        200,
      ),
      () {
        expect(find.byType(CafeKioskScreen), findsNothing);
        expect(find.text('Lisans Bağlantısı Kaldırıldı'), findsOneWidget);
        expect(LicenseService.instance.currentStatus.active, isFalse);
      },
    );
  });

  testWidgets('active cache cannot authorize startup when API is unreachable', (
    tester,
  ) async {
    await LicenseService.instance.init();
    expect(LicenseService.instance.currentStatus.active, isTrue);

    await _runGateScenario(
      tester,
      (_) async => throw const SocketException('API unreachable'),
      () {
        _expectServerUnavailable(tester);
        expect(LicenseService.instance.currentStatus.active, isFalse);
      },
    );
  });

  testWidgets(
    'retry only repeats API validation and never falls back to cache',
    (tester) async {
      var requestCount = 0;
      await _runGateScenario(
        tester,
        (_) async {
          requestCount++;
          throw const SocketException('API unreachable');
        },
        () async {
          expect(requestCount, 1);
          await tester.tap(find.text('Tekrar Dene'));
          for (var i = 0; i < 20; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          expect(requestCount, 2);
          _expectServerUnavailable(tester);
          expect(LicenseService.instance.currentStatus.active, isFalse);
        },
      );
    },
  );
}

Map<String, String> _storedLicenseCache() => {
  'license_mode': 'licensed',
  'license_key': 'LUUQ-TEST-TEST-TEST-TEST',
  'device_id': 'test-device-id',
  'device_fingerprint_hash': 'test-device-fingerprint',
  'branch_name': 'Test Branch',
  'customer_name': 'Test Customer',
  'plan': 'pro',
  'expires_at': '2099-01-01T00:00:00.000Z',
  'trial_expires_at': '',
  'features': jsonEncode(FeatureFlags.proDefault.toJson()),
  'last_successful_check_at': '2026-01-01T00:00:00.000Z',
};

Future<void> _runGateScenario(
  WidgetTester tester,
  Future<http.Response> Function(http.Request request) handler,
  FutureOr<void> Function() verify,
) async {
  await http.runWithClient(
    () async {
      await tester.pumpWidget(const MaterialApp(home: LicenseGate()));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      await verify();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
    () => MockClient((request) async {
      expect(request.url, Uri.parse(LicenseConfig.checkStatusUrl));
      return handler(request);
    }),
  );
}

void _expectServerUnavailable(WidgetTester tester) {
  expect(find.byType(CafeKioskScreen), findsNothing);
  expect(find.text('Lisans Sunucusuna Ulaşılamıyor'), findsOneWidget);
  expect(find.text('Tekrar Dene'), findsOneWidget);
}

class _CustomerUiMarker extends StatelessWidget {
  const _CustomerUiMarker();

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
