import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luuqapp/licensing/feature_flags.dart';
import 'package:luuqapp/licensing/license_service.dart';
import 'package:luuqapp/licensing/license_status.dart';
import 'package:luuqapp/main.dart';
import 'package:luuqapp/menu/menu_models.dart';
import 'package:luuqapp/menu/menu_service.dart';

/// A server catalog with the given categories ({icon_key: item names}).
/// Item ids are their names, so wheel ids can name items directly.
MenuCatalog _catalog(
  Map<String, List<String>> categories, {
  List<String> wheel = const [],
  int revision = 1,
  String? theme,
}) {
  var c = 0;
  return MenuCatalog.fromApiJson({
    'schema_version': 2,
    'menu_version': revision,
    'catalog_revision': revision,
    'effective_revision': 'test-$revision',
    'catalog': {
      'categories': [
        for (final entry in categories.entries)
          {
            'id': 'cat-${c++}',
            'name_tr': 'Kategori $c',
            'icon_key': entry.key,
            'items': [
              for (final name in entry.value)
                {
                  'id': name,
                  'category_id': 'cat-${c - 1}',
                  'name_tr': name,
                  'price_text': '100₺',
                  'icon_key': entry.key,
                },
            ],
          },
      ],
    },
    'wheel_item_ids': wheel,
    'theme': theme,
  });
}

Future<void> _pumpKiosk(WidgetTester tester) async {
  tester.view
    ..physicalSize = const Size(1920, 1080)
    ..devicePixelRatio = 1;
  await tester.pumpWidget(const MaterialApp(home: CafeKioskScreen()));
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Future<void> _setCatalog(WidgetTester tester, MenuCatalog? catalog) async {
  MenuService.instance.catalogNotifier.value = catalog;
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  setUp(() {
    appLanguageNotifier.value = AppLanguage.tr;
    LicenseService.instance.statusNotifier.value = const LicenseStatus(
      active: true,
      mode: LicenseMode.licensed,
      features: FeatureFlags.proDefault,
    );
  });

  tearDown(() {
    MenuService.instance.catalogNotifier.value = null;
    LicenseService.instance.statusNotifier.value = const LicenseStatus(
      active: false,
      mode: LicenseMode.none,
      features: FeatureFlags.lockedAll,
    );
  });

  testWidgets('a menu without a dessert category still builds the kiosk', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    await _pumpKiosk(tester);
    await _setCatalog(
      tester,
      _catalog({
        'local_cafe_rounded': ['Latte', 'Mocha'],
        'ac_unit_rounded': ['Ice Latte'],
      }),
    );
    expect(tester.takeException(), isNull);
    final barista = debugKioskBaristaNames();
    expect(barista.dessert, isNull);
    expect(barista.drink, isNotNull);
    // The wheel never repeats an item, even when the menu is too small.
    final wheel = debugKioskWheelItemNames();
    expect(wheel.toSet().length, wheel.length);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('an item removed from the menu drops off the wheel', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    final names = [
      for (var i = 1; i <= 4; i++) 'Sıcak $i',
      for (var i = 1; i <= 3; i++) 'Soğuk $i',
      for (var i = 1; i <= 3; i++) 'Tatlı $i',
    ];
    final wheel = names.take(8).toList();
    await _pumpKiosk(tester);
    await _setCatalog(
      tester,
      _catalog({
        'local_cafe_rounded': names.sublist(0, 4),
        'ac_unit_rounded': names.sublist(4, 7),
        'cake_rounded': names.sublist(7),
      }, wheel: wheel),
    );
    expect(debugKioskWheelItemNames(), wheel);

    // 'Sıcak 1' is gone, but the server's wheel ids still list it.
    await _setCatalog(
      tester,
      _catalog(
        {
          'local_cafe_rounded': names.sublist(1, 4),
          'ac_unit_rounded': names.sublist(4, 7),
          'cake_rounded': names.sublist(7),
        },
        wheel: wheel,
        revision: 2,
      ),
    );
    expect(tester.takeException(), isNull);
    final after = debugKioskWheelItemNames();
    expect(after, isNot(contains('Sıcak 1')));
    expect(after.length, 8);
    expect(after.toSet().length, 8);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a new menu waits while a customer dialog is open', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    addTearDown(() => GlobalDialogTracker.isCustomerDialogOpen = false);
    await _pumpKiosk(tester);
    await _setCatalog(
      tester,
      _catalog({
        'local_cafe_rounded': ['Latte'],
        'cake_rounded': ['Brownie'],
      }),
    );
    expect(debugKioskBaristaNames().dessert, 'Brownie');

    // The customer is browsing the menu when the panel changes it.
    GlobalDialogTracker.isCustomerDialogOpen = true;
    await _setCatalog(
      tester,
      _catalog({
        'local_cafe_rounded': ['Latte'],
        'cake_rounded': ['Cheesecake'],
      }, revision: 2),
    );
    expect(debugKioskBaristaNames().dessert, 'Brownie');

    // Closing the dialog (any tap resets the idle timer) applies it.
    GlobalDialogTracker.isCustomerDialogOpen = false;
    await tester.tapAt(const Offset(960, 540));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(debugKioskBaristaNames().dessert, 'Cheesecake');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Milkshake is a drink and ice cream is a dessert', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    await _pumpKiosk(tester);
    await _setCatalog(
      tester,
      _catalog({
        'icecream_rounded': ['Çilekli Milkshake'],
        'icecream_outlined': ['Vanilyalı Dondurma'],
      }),
    );
    final barista = debugKioskBaristaNames();
    expect(barista.drink, 'Çilekli Milkshake');
    expect(barista.dessert, 'Vanilyalı Dondurma');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  group('theme set on the panel', () {
    final menu = {
      'local_cafe_rounded': ['Latte'],
      'cake_rounded': ['Brownie'],
    };

    // Each test ends on the summer theme the other tests expect.
    Future<void> backToSummer(WidgetTester tester) async {
      MenuService.instance.debugSetPendingConfig('theme', pending: false);
      GlobalDialogTracker.isCustomerDialogOpen = false;
      await _setCatalog(tester, _catalog(menu, revision: 99, theme: 'summer'));
      expect(appThemeNotifier.value, AppTheme.summer);
      await tester.pumpWidget(const SizedBox.shrink());
    }

    testWidgets('is applied, and no theme keeps the kiosk\'s own', (
      tester,
    ) async {
      addTearDown(tester.view.reset);
      await _pumpKiosk(tester);
      await _setCatalog(tester, _catalog(menu, theme: 'summer'));
      await _setCatalog(tester, _catalog(menu, revision: 2, theme: 'newYear'));
      expect(appThemeNotifier.value, AppTheme.newYear);
      expect(tester.takeException(), isNull);

      // "Kiosk seçsin" on the panel: the kiosk keeps what it shows.
      await _setCatalog(tester, _catalog(menu, revision: 3));
      expect(appThemeNotifier.value, AppTheme.newYear);
      // A name this version does not know is ignored the same way.
      await _setCatalog(tester, _catalog(menu, revision: 4, theme: 'spring'));
      expect(appThemeNotifier.value, AppTheme.newYear);
      await backToSummer(tester);
    });

    testWidgets('waits while a customer dialog is open', (tester) async {
      addTearDown(tester.view.reset);
      addTearDown(() => GlobalDialogTracker.isCustomerDialogOpen = false);
      await _pumpKiosk(tester);
      await _setCatalog(tester, _catalog(menu, theme: 'summer'));

      GlobalDialogTracker.isCustomerDialogOpen = true;
      await _setCatalog(tester, _catalog(menu, revision: 2, theme: 'winter'));
      expect(appThemeNotifier.value, AppTheme.summer);

      GlobalDialogTracker.isCustomerDialogOpen = false;
      await tester.tapAt(const Offset(960, 540));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(appThemeNotifier.value, AppTheme.winter);
      await backToSummer(tester);
    });

    testWidgets('does not replace a kiosk change that is not sent yet', (
      tester,
    ) async {
      addTearDown(tester.view.reset);
      addTearDown(
        () => MenuService.instance.debugSetPendingConfig(
          'theme',
          pending: false,
        ),
      );
      await _pumpKiosk(tester);
      await _setCatalog(tester, _catalog(menu, theme: 'summer'));

      MenuService.instance.debugSetPendingConfig('theme', pending: true);
      await _setCatalog(tester, _catalog(menu, revision: 2, theme: 'feast'));
      expect(appThemeNotifier.value, AppTheme.summer);
      await backToSummer(tester);
    });
  });

  test('the theme survives the menu cache', () {
    final cached = MenuCatalog.fromCacheJson(
      _catalog(const {
        'local_cafe_rounded': ['Latte'],
      }, theme: 'feast').toJson(),
    );
    expect(cached.themeKey, 'feast');
    expect(
      _catalog(const {
        'local_cafe_rounded': ['Latte'],
      }).themeKey,
      isNull,
    );
  });
}
