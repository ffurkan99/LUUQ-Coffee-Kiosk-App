import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luuqapp/licensing/update_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('luuqapp/apk_install');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final methodCalls = <MethodCall>[];

  setUp(() {
    methodCalls.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      methodCalls.add(call);
      throw TestFailure('APK channel must not be called on non-Android.');
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test(
    'non-Android updater operations never invoke the APK MethodChannel',
    () async {
      expect(await UpdateService.checkInstallPermission(), isFalse);
      expect(await UpdateService.openInstallSettings(), isFalse);
      expect(await UpdateService.isLockTaskActive(), isFalse);
      expect(await UpdateService.waitForLockTaskRelease(), isTrue);
      expect(await UpdateService.readApkPackageInfo('ignored.apk'), isNull);

      await UpdateService.enableKioskMode();
      await UpdateService.disableKioskMode();
      await UpdateService.restoreKioskModeAfterUpdateCancel();

      await expectLater(
        UpdateService.downloadApk(
          'https://updates.example.test/app.apk',
          (_) {},
        ),
        throwsA(isA<UnsupportedError>()),
      );
      await expectLater(
        UpdateService.installApk('ignored.apk'),
        throwsA(isA<UnsupportedError>()),
      );
      await expectLater(
        UpdateService.stopLockTaskForUpdate(),
        throwsA(isA<UnsupportedError>()),
      );

      expect(methodCalls, isEmpty);
    },
    skip: Platform.isAndroid
        ? 'This guard test must run on a non-Android Flutter host.'
        : false,
  );
}
