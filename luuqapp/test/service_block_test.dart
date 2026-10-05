import 'package:flutter_test/flutter_test.dart';

import 'package:luuqapp/licensing/license_status.dart';
import 'package:luuqapp/licensing/version_info.dart';

void main() {
  group('VersionInfo.isBelowMinimum', () {
    test('older version name is below', () {
      expect(VersionInfo.isBelowMinimum('v1.0.9+30', '1.1.0'), isTrue);
    });

    test('same name passes when the minimum has no build number', () {
      expect(VersionInfo.isBelowMinimum('v1.1.0+5', '1.1.0'), isFalse);
    });

    test('build number counts when the minimum has one', () {
      expect(VersionInfo.isBelowMinimum('v1.1.0+21', '1.1.0+22'), isTrue);
      expect(VersionInfo.isBelowMinimum('v1.1.0+22', '1.1.0+22'), isFalse);
      expect(VersionInfo.isBelowMinimum('v1.2.0+1', '1.1.0+22'), isFalse);
    });

    test('empty or unparseable values never block', () {
      expect(VersionInfo.isBelowMinimum('v1.0.0+1', null), isFalse);
      expect(VersionInfo.isBelowMinimum('v1.0.0+1', ''), isFalse);
      expect(VersionInfo.isBelowMinimum('unknown', '1.1.0'), isFalse);
    });
  });

  group('LicenseStatus maintenance fields', () {
    test('parses maintenance and minimum version', () {
      final status = LicenseStatus.fromJson({
        'active': true,
        'mode': 'licensed',
        'maintenance': {'enabled': true, 'message': 'Bakımdayız'},
        'minimum_app_version': '1.1.0',
      }, LicenseMode.licensed);
      expect(status.maintenanceEnabled, isTrue);
      expect(status.maintenanceMessage, 'Bakımdayız');
      expect(status.minimumAppVersion, '1.1.0');
    });

    test('an inactive license never reports maintenance', () {
      final status = LicenseStatus.fromJson({
        'active': false,
        'maintenance': {'enabled': true},
      }, LicenseMode.licensed);
      expect(status.maintenanceEnabled, isFalse);
    });

    test('missing fields keep the kiosk open', () {
      final status = LicenseStatus.fromJson({
        'active': true,
        'mode': 'licensed',
      }, LicenseMode.licensed);
      expect(status.maintenanceEnabled, isFalse);
      expect(status.minimumAppVersion, isNull);
    });
  });
}
