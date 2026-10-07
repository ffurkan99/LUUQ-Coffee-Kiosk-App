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

  test('a short outage keeps the kiosk open', () {
    clock = clock.add(const Duration(minutes: 4, seconds: 59));
    expect(service.recordCheckResult(offline), isFalse);
    expect(service.connectionLost.value, isFalse);
  });

  test('more than five minutes without the server covers the kiosk', () {
    clock = clock.add(const Duration(minutes: 3));
    service.recordCheckResult(offline);
    clock = clock.add(const Duration(minutes: 2, seconds: 1));
    service.recordCheckResult(serverDown);
    expect(service.connectionLost.value, isTrue);
  });

  test('the first successful check lifts the cover', () {
    clock = clock.add(const Duration(minutes: 6));
    service.recordCheckResult(offline);
    expect(service.connectionLost.value, isTrue);

    expect(service.recordCheckResult(active), isTrue);
    expect(service.connectionLost.value, isFalse);

    // The grace period restarts from that success.
    clock = clock.add(const Duration(minutes: 4));
    service.recordCheckResult(offline);
    expect(service.connectionLost.value, isFalse);
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
