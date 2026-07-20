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
}
