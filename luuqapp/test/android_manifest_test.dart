import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android manifest disables Impeller with the key the engine reads', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    // The engine (FlutterEngineFlags) only reads the
    // 'io.flutter.embedding.android.' key; the old 'io.flutter.app.android.'
    // prefix is silently ignored, which left Impeller enabled and caused
    // ghost ball-number artifacts on the kiosk device.
    expect(
      manifest,
      contains('io.flutter.embedding.android.EnableImpeller'),
    );
    expect(manifest, isNot(contains('io.flutter.app.android.')));

    final impellerMetaData = RegExp(
      r'android:name="io\.flutter\.embedding\.android\.EnableImpeller"\s*'
      r'android:value="false"',
    );
    expect(manifest, matches(impellerMetaData));
  });

  test('no app data goes to a cloud backup or a new device', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    expect(manifest, contains('android:allowBackup="false"'));
    expect(manifest, contains('android:dataExtractionRules="@xml/data_extraction_rules"'));
    expect(manifest, contains('android:fullBackupContent="@xml/backup_rules"'));

    const domains = [
      'root', 'file', 'database', 'sharedpref', 'external',
      'device_root', 'device_file', 'device_database', 'device_sharedpref',
    ];
    final rules = File(
      'android/app/src/main/res/xml/data_extraction_rules.xml',
    ).readAsStringSync();
    for (final section in ['cloud-backup', 'device-transfer']) {
      final body = RegExp('<$section>(.*?)</$section>', dotAll: true)
          .firstMatch(rules)
          ?.group(1);
      expect(body, isNotNull, reason: section);
      for (final domain in domains) {
        expect(body, contains('<exclude domain="$domain" path="." />'),
            reason: '$section $domain');
      }
      expect(body, isNot(contains('<include')), reason: section);
    }
    final legacy = File(
      'android/app/src/main/res/xml/backup_rules.xml',
    ).readAsStringSync();
    for (final domain in domains) {
      expect(legacy, contains('<exclude domain="$domain" path="." />'),
          reason: 'backup_rules $domain');
    }
  });
}
