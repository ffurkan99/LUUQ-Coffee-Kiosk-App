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

  test('mode and plan are matched exactly, mode first', () {
    LicenseMode modeOf(Map<String, dynamic> json) => LicenseStatus.fromJson({
      'active': true,
      ...json,
    }, LicenseMode.none).mode;
    // A paid plan whose name contains "Deneme" stays licensed.
    expect(
      modeOf({'mode': 'licensed', 'plan': 'Pro Deneme'}),
      LicenseMode.licensed,
    );
    expect(modeOf({'mode': 'trial', 'plan': 'Deneme'}), LicenseMode.trial);
    expect(modeOf({'plan': 'Deneme'}), LicenseMode.trial);
    expect(modeOf({'mode': '', 'plan': 'pro'}), LicenseMode.licensed);
    // "inactive" contains "active" but is not a licensed mode.
    expect(
      LicenseStatus.fromJson({
        'active': false,
        'mode': 'inactive',
      }, LicenseMode.none).mode,
      LicenseMode.none,
    );
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
