import 'package:flutter_test/flutter_test.dart';

import 'package:luuqapp/licensing/feature_flags.dart';
import 'package:luuqapp/licensing/license_status.dart';

void main() {
  test('a feature missing from the server list is off', () {
    final status = LicenseStatus.fromJson({
      'active': true,
      'mode': 'licensed',
      'features': {'menu': true, 'wheel': true},
    }, LicenseMode.licensed);
    expect(status.features.menu, isTrue);
    expect(status.features.manualExit, isFalse);
    expect(status.features.analytics, isFalse);
  });

  test('a licensed response without any feature list keeps the defaults', () {
    final status = LicenseStatus.fromJson({
      'active': true,
      'mode': 'licensed',
    }, LicenseMode.licensed);
    expect(status.features, FeatureFlags.proDefault);
  });

  test('PHP empty arrays and numbers do not break parsing', () {
    final status = LicenseStatus.fromJson({
      'active': true,
      'mode': 'licensed',
      'update': <dynamic>[],
      'features': <dynamic>[],
      'customer_name': 42,
      'branch_name': null,
      'plan': ['unexpected'],
    }, LicenseMode.licensed);
    expect(status.active, isTrue);
    expect(status.updateAvailable, isFalse);
    expect(status.customerName, '42');
    expect(status.branchName, isNull);
    expect(status.plan, isNull);
  });

  test('only a real true activates', () {
    for (final value in [1, 'true', null]) {
      final status = LicenseStatus.fromJson({
        'active': value,
        'features': {'menu': true},
      }, LicenseMode.licensed);
      expect(status.active, isFalse, reason: '$value');
    }
  });
}
