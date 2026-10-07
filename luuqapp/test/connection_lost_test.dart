import 'package:flutter_test/flutter_test.dart';

import 'package:luuqapp/licensing/feature_sync_service.dart';
import 'package:luuqapp/licensing/license_status.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final service = FeatureSyncService.instance;
  late DateTime clock;

  const active = LicenseStatus(active: true, mode: LicenseMode.licensed);
  const offline = LicenseStatus(
    active: false,
    mode: LicenseMode.licensed,
    reason: 'network_error',
  );
  const serverDown = LicenseStatus(
    active: false,
    mode: LicenseMode.licensed,
    reason: 'server_error',
  );

  setUp(() {
    clock = DateTime(2026, 10, 7, 12);
    service.now = () => clock;
    service.start();
  });

  tearDown(() {
    service.stop();
    service.now = DateTime.now;
  });

  test('one failed check (30 s) keeps the kiosk open', () {
    clock = clock.add(const Duration(seconds: 30));
    expect(service.recordCheckResult(offline), isFalse);
    expect(service.connectionLost.value, isFalse);
  });

  test('two failed checks in a row (60 s) cover the kiosk', () {
    clock = clock.add(const Duration(seconds: 30));
    service.recordCheckResult(offline);
    expect(service.connectionLost.value, isFalse);
    clock = clock.add(const Duration(seconds: 30));
    service.recordCheckResult(serverDown);
    expect(service.connectionLost.value, isTrue);
  });

  test('the first successful check lifts the cover', () {
    clock = clock.add(const Duration(minutes: 2));
    service.recordCheckResult(offline);
    expect(service.connectionLost.value, isTrue);

    expect(service.recordCheckResult(active), isTrue);
    expect(service.connectionLost.value, isFalse);

    // The grace period restarts from that success.
    clock = clock.add(const Duration(seconds: 30));
    service.recordCheckResult(offline);
    expect(service.connectionLost.value, isFalse);
  });

  test('an old screen stopping late keeps the new screen syncing', () {
    final oldScreen = Object();
    final newScreen = Object();
    service.start(oldScreen);
    service.start(newScreen);
    service.stopIfOwner(oldScreen);
    expect(service.isRunning, isTrue);
    service.stopIfOwner(newScreen);
    expect(service.isRunning, isFalse);
  });

  test('a real license problem is not treated as a lost connection', () {
    clock = clock.add(const Duration(minutes: 10));
    const revoked = LicenseStatus(
      active: false,
      mode: LicenseMode.licensed,
      reason: 'device_revoked',
    );
    expect(service.recordCheckResult(revoked), isTrue);
    expect(service.connectionLost.value, isFalse);
  });
}
