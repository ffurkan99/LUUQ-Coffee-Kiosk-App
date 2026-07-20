// ignore_for_file: avoid_relative_lib_imports
import 'package:flutter_test/flutter_test.dart';
import 'package:luuqapp/licensing/version_info.dart';
import 'package:luuqapp/licensing/update_service.dart' show UpdateService;

void main() {
  // ─────────────────────────────────────────────────────────────────────────
  // VersionInfo.parse
  // ─────────────────────────────────────────────────────────────────────────
  group('VersionInfo.parse', () {
    test('parses canonical format v1.1.1+2', () {
      final v = VersionInfo.parse('v1.1.1+2')!;
      expect(v.versionName, '1.1.1');
      expect(v.versionCode, 2);
      expect(v.toString(), 'v1.1.1+2');
    });

    test('parses pubspec format 1.1.0+9 (no leading v)', () {
      final v = VersionInfo.parse('1.1.0+9')!;
      expect(v.versionName, '1.1.0');
      expect(v.versionCode, 9);
    });

    test('handles upper-case V prefix', () {
      final v = VersionInfo.parse('V2.0.0+1')!;
      expect(v.versionName, '2.0.0');
      expect(v.versionCode, 1);
    });

    test('parses version without build number', () {
      final v = VersionInfo.parse('v1.1.1')!;
      expect(v.versionName, '1.1.1');
      expect(v.versionCode, 0);
      expect(v.toString(), 'v1.1.1');
    });

    test('pads 2-segment version to 3 segments', () {
      final v = VersionInfo.parse('v1.2')!;
      expect(v.versionName, '1.2.0');
    });

    test('pads 1-segment version to 3 segments', () {
      final v = VersionInfo.parse('v2')!;
      expect(v.versionName, '2.0.0');
    });

    test('strips leading and trailing whitespace', () {
      final v = VersionInfo.parse('  v1.0.0+3  ')!;
      expect(v.versionName, '1.0.0');
      expect(v.versionCode, 3);
    });

    test('returns null for empty string', () {
      expect(VersionInfo.parse(''), isNull);
    });

    test('returns null for blank string', () {
      expect(VersionInfo.parse('   '), isNull);
    });

    test('large build number is preserved', () {
      final v = VersionInfo.parse('v10.20.30+9999')!;
      expect(v.versionCode, 9999);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // VersionInfo.compareVersionNames
  // ─────────────────────────────────────────────────────────────────────────
  group('VersionInfo.compareVersionNames', () {
    test('equal versions return 0', () {
      expect(VersionInfo.compareVersionNames('1.1.1', '1.1.1'), 0);
    });

    test('higher patch returns positive', () {
      expect(VersionInfo.compareVersionNames('1.1.2', '1.1.1'), isPositive);
    });

    test('lower patch returns negative', () {
      expect(VersionInfo.compareVersionNames('1.1.0', '1.1.1'), isNegative);
    });

    test('higher minor returns positive', () {
      expect(VersionInfo.compareVersionNames('1.2.0', '1.1.9'), isPositive);
    });

    test('higher major returns positive', () {
      expect(VersionInfo.compareVersionNames('2.0.0', '1.9.9'), isPositive);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // VersionInfo.isNewerThan / isEqualOrNewerThan
  // ─────────────────────────────────────────────────────────────────────────
  group('VersionInfo comparison methods', () {
    const old = VersionInfo('1.1.0', 9);
    const latest = VersionInfo('1.1.1', 2);
    const sameName = VersionInfo('1.1.0', 10); // higher build number

    test('isNewerThan: higher version name → true', () {
      expect(latest.isNewerThan(old), isTrue);
    });

    test('isNewerThan: same version, higher build number → true', () {
      expect(sameName.isNewerThan(old), isTrue);
    });

    test('isNewerThan: equal → false', () {
      expect(old.isNewerThan(old), isFalse);
    });

    test('isNewerThan: older → false', () {
      expect(old.isNewerThan(latest), isFalse);
    });

    test('isEqualOrNewerThan: equal → true', () {
      expect(old.isEqualOrNewerThan(old), isTrue);
    });

    test('isEqualOrNewerThan: newer → true', () {
      expect(latest.isEqualOrNewerThan(old), isTrue);
    });

    test('isEqualOrNewerThan: older → false', () {
      expect(old.isEqualOrNewerThan(latest), isFalse);
    });

    // Key post-install scenario: freshly installed v1.1.1+2 vs expected v1.1.1+2
    test('post-install success: same version and build number', () {
      final current = VersionInfo.parse('v1.1.1+2')!;
      final expected = VersionInfo.parse('v1.1.1+2')!;
      expect(current.isEqualOrNewerThan(expected), isTrue);
    });

    // Key post-install failure: old version still installed after cancel
    test('post-install failure: old version still installed', () {
      final current = VersionInfo.parse('v1.1.0+9')!;
      final expected = VersionInfo.parse('v1.1.1+2')!;
      expect(current.isEqualOrNewerThan(expected), isFalse);
    });

    // Scenario: backend sends v1.1.1 (no +BUILD) – versionCode == 0
    // isEqualOrNewerThan should still work because versionCode 0 >= 0
    test('backend without build number: same version name passes', () {
      final current = VersionInfo.parse('v1.1.1+5')!;
      final expected = VersionInfo.parse('v1.1.1')!; // versionCode == 0
      expect(current.isEqualOrNewerThan(expected), isTrue);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // UpdateService.normalizeVersionName
  // ─────────────────────────────────────────────────────────────────────────
  group('UpdateService.normalizeVersionName', () {
    test('3-segment name is returned as-is', () {
      expect(UpdateService.normalizeVersionName('1.1.1'), '1.1.1');
    });

    test('2-segment name is padded to 3', () {
      expect(UpdateService.normalizeVersionName('1.1'), '1.1.0');
    });

    test('1-segment name is padded to 3', () {
      expect(UpdateService.normalizeVersionName('1'), '1.0.0');
    });

    test('strips leading v', () {
      expect(UpdateService.normalizeVersionName('v1.1.1'), '1.1.1');
    });

    test('strips leading V', () {
      expect(UpdateService.normalizeVersionName('V2.0.0'), '2.0.0');
    });

    test('whitespace is trimmed', () {
      expect(UpdateService.normalizeVersionName('  1.0.0  '), '1.0.0');
    });
  });
}
