import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luuqapp/main.dart';
import 'package:luuqapp/licensing/license_service.dart';
import 'package:luuqapp/licensing/license_status.dart';
import 'package:luuqapp/licensing/feature_flags.dart';

void main() {
  testWidgets('reduced motion button activates without scaling', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Center(
            child: BouncyButton(
              onTap: () => taps++,
              child: const SizedBox(width: 100, height: 48),
            ),
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(BouncyButton)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    final scale = tester.widget<ScaleTransition>(
      find.descendant(
        of: find.byType(BouncyButton),
        matching: find.byType(ScaleTransition),
      ),
    );
    expect(scale.scale.value, 1);
    await gesture.up();
    expect(taps, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  final originalTheme = appThemeNotifier.value;
  final originalLicense = LicenseService.instance.statusNotifier.value;
  tearDown(() {
    appThemeNotifier.value = originalTheme;
    LicenseService.instance.statusNotifier.value = originalLicense;
  });
  testWidgets('disabled BouncyButton ignores pointer and keyboard', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              const BouncyButton(onTap: null, child: Text('Disabled')),
              BouncyButton(onTap: () => taps++, child: const Text('Enabled')),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.text('Disabled'));
    expect(taps, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(taps, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('theme list shrink preserves a valid showcase and keeps rotating', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    appThemeNotifier.value = AppTheme.normal;
    LicenseService.instance.statusNotifier.value = const LicenseStatus(
      active: true,
      mode: LicenseMode.licensed,
      features: FeatureFlags.proDefault,
    );
    await tester.pumpWidget(const MaterialApp(home: CafeKioskScreen()));
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
    await tester.tapAt(const Offset(20, 20));
    await tester.pump(const Duration(milliseconds: 400));
    final cards = find.byWidgetPredicate(
      (w) => w.runtimeType.toString() == '_CocktailShowcaseCard',
    );
    expect(cards, findsOneWidget);
    final dynamic normal = tester.widget(cards);
    final int longCount = normal.cocktails.length;
    for (var i = 0; i < 20; i++) {
      await tester.tapAt(const Offset(20, 20));
      await tester.pump(const Duration(milliseconds: 4500));
    }
    appThemeNotifier.value = AppTheme.summer;
    await tester.pump();
    final error = tester.takeException();
    final dynamic summer = tester.widget(cards);
    debugPrint(
      'AUDIT theme lists: $longCount -> ${summer.cocktails.length}; error: $error',
    );
    expect(error, isNull);
    expect(summer.cocktails.length, lessThan(longCount));
    await tester.pump(const Duration(milliseconds: 4500));
    expect(tester.takeException(), isNull);
    for (final theme in AppTheme.values) {
      appThemeNotifier.value = theme;
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets('BouncyButton supports Tab Enter Space and pointer activation', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BouncyButton(onTap: () => taps++, child: const Text('Action')),
        ),
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(taps, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(taps, 2);
    await tester.tap(find.text('Action'));
    expect(taps, 3);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
