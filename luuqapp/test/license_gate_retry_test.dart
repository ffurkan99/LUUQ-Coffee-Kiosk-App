import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:luuqapp/licensing/feature_flags.dart';
import 'package:luuqapp/licensing/license_activation_screen.dart';
import 'package:luuqapp/licensing/license_gate.dart';
import 'package:luuqapp/licensing/license_service.dart';
import 'package:luuqapp/licensing/license_status.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      'license_mode': 'trial',
      'license_key': 'LUUQ-TEST-TEST-TEST-TEST',
      'device_id': 'test-device-id',
      'device_fingerprint_hash': 'test-device-fingerprint',
      'features': jsonEncode(FeatureFlags.proDefault.toJson()),
    });
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

  test('auto retry backs off from 5 s to 60 s', () {
    expect(
      [for (var i = 0; i < 7; i++) LicenseGate.autoRetryDelay(i).inSeconds],
      [5, 10, 20, 40, 60, 60, 60],
    );
  });

  testWidgets('an unreachable license server is retried automatically', (
    tester,
  ) async {
    var calls = 0;
    await http.runWithClient(
      () async {
        await tester.pumpWidget(const MaterialApp(home: LicenseGate()));
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(calls, 1);
        expect(find.text('Tekrar Dene'), findsOneWidget);

        // First automatic retry after 5 s, without any tap.
        await tester.pump(const Duration(seconds: 5));
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(calls, 2);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
      () => MockClient((request) async {
        calls++;
        return http.Response('unavailable', 503);
      }),
    );
  });

  testWidgets('upgrade mode opens the key form and never auto-closes', (
    tester,
  ) async {
    LicenseService.instance.statusNotifier.value = const LicenseStatus(
      active: true,
      mode: LicenseMode.trial,
      features: FeatureFlags.proDefault,
    );
    var activated = false;
    var requests = 0;
    await http.runWithClient(
      () async {
        await tester.pumpWidget(
          MaterialApp(
            home: LicenseActivationScreen(
              upgradeMode: true,
              onActivated: () => activated = true,
            ),
          ),
        );
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(find.byType(TextField), findsOneWidget);
        expect(activated, isFalse);
        expect(requests, 0, reason: 'the trial status is not re-checked');
      },
      () => MockClient((request) async {
        requests++;
        return http.Response('{}', 500);
      }),
    );
  });
}
