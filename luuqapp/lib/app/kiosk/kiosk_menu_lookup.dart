part of '../../main.dart';

/// Menu item lookups and the option lists behind the barista recommendation.
extension _KioskMenuLookup on _CafeKioskScreenState {
  _MenuItem? _findMenuItemByName(String name) {
    for (final list in _currentMenuCategories.values) {
      for (final item in list) {
        if (item.name == name) {
          return item;
        }
      }
    }
    return null;
  }

  _MenuItem? _findMenuItemById(String id) {
    for (final list in _currentMenuCategories.values) {
      for (final item in list) {
        if (item.id == id) return item;
      }
    }
    return null;
  }

  // Desserts and drinks are told apart by category icon, for the server menu
  // and the bundled one alike: cakes, cookies and ice creams (outlined) are
  // desserts; Milkshake (rounded ice cream) is a drink. Extras, merchandise
  // and sandwiches are neither.
  static final _dessertIcons = <IconData>{
    Icons.cake_rounded,
    Icons.cookie_rounded,
    Icons.icecream_outlined,
  };
  static final _notRecommendedIcons = <IconData>{
    Icons.add_circle_outline_rounded,
    Icons.coffee_rounded,
    Icons.lunch_dining_rounded,
  };

  Map<String, IconData> get _recommendationIconMap =>
      _activeMenuCategoryIcons.isNotEmpty
      ? _activeMenuCategoryIcons
      : _categoryIcons;

  List<_MenuItem> get _recommendationDrinkOptions {
    final icons = _recommendationIconMap;
    return _currentMenuCategories.entries
        .where((entry) {
          final icon = icons[entry.key];
          return !_dessertIcons.contains(icon) &&
              !_notRecommendedIcons.contains(icon);
        })
        .expand((entry) => entry.value)
        .toList(growable: false);
  }

  List<_MenuItem> get _recommendationDessertOptions {
    final icons = _recommendationIconMap;
    return _currentMenuCategories.entries
        .where((entry) => _dessertIcons.contains(icons[entry.key]))
        .expand((entry) => entry.value)
        .toList(growable: false);
  }

  List<_MenuItem> get _iceCoffeeOptions => _itemsForCategoryIcons([
    Icons.ac_unit_rounded,
    Icons.severe_cold_rounded,
    Icons.sports_bar_rounded,
    Icons.bubble_chart_rounded,
    Icons.icecream_rounded,
  ]);

  List<_MenuItem> get _hotCoffeeOptions => _itemsForCategoryIcons([
    Icons.local_cafe_rounded,
    Icons.coffee_maker_rounded,
    Icons.whatshot_rounded,
  ]);

  List<_MenuItem> get _cocktailOptions =>
      _itemsForCategoryIcons([Icons.local_bar_rounded]);

  List<_MenuItem> get _herbalTeaOptions =>
      _itemsForCategoryIcons([Icons.eco_rounded]);

  // Ice creams only; Milkshake is a drink (same rule as the default wheel).
  List<_MenuItem> get _iceCreamOptions =>
      _itemsForCategoryIcons([Icons.icecream_outlined]);

  List<_MenuItem> _itemsForCategoryIcons(List<IconData> icons) {
    final items = <_MenuItem>[];
    final iconMap = _activeMenuCategoryIcons.isNotEmpty
        ? _activeMenuCategoryIcons
        : _categoryIcons;
    for (final entry in iconMap.entries) {
      if (icons.contains(entry.value)) {
        items.addAll(_currentMenuCategories[entry.key] ?? const []);
      }
    }
    return items;
  }

  // Varsayılan öneri: admin hiç seçim yapmadıysa fotoğrafı olan ilk ürün.
  // (Fotoğrafsız varsayılan, en görünür karta boş ikon kutusu koyuyordu.)
  // Null when the menu has nothing to recommend (e.g. no dessert category):
  // the card then leaves that box out instead of failing to build.
  _MenuItem? get _currentBaristaDrink =>
      _baristaDrink ?? _defaultRecommendation(_recommendationDrinkOptions);

  _MenuItem? get _currentBaristaDessert =>
      _baristaDessert ?? _defaultRecommendation(_recommendationDessertOptions);

  _MenuItem? _defaultRecommendation(List<_MenuItem> options) {
    for (final item in options) {
      if (item.imagePath != null) return item;
    }
    return options.isEmpty ? null : options.first;
  }

  _MenuItem? _menuItemForDrink(Drink drink) {
    final preferredNames =
        _preferredMenuNames[drink.fullName] ??
        _preferredMenuNames[drink.shortName] ??
        [drink.fullName, drink.shortName];
    final allItems = _currentMenuCategories.values
        .expand((items) => items)
        .toList();
    _MenuItem? fallbackMatch;

    for (final preferredName in preferredNames) {
      final match = _firstMenuMatch(
        allItems,
        (item) =>
            _normalizeMenuName(_menuItemName(item)) ==
            _normalizeMenuName(preferredName),
      );
      if (match?.imagePath != null || match?.remoteImageUrl != null) {
        return match;
      }
      fallbackMatch ??= match;
    }
    if (fallbackMatch != null) return fallbackMatch;

    for (final preferredName in preferredNames) {
      final normalized = _normalizeMenuName(preferredName);
      final match = _firstMenuMatch(
        allItems,
        (item) => _normalizeMenuName(_menuItemName(item)).contains(normalized),
      );
      if (match?.imagePath != null || match?.remoteImageUrl != null) {
        return match;
      }
      fallbackMatch ??= match;
    }
    if (fallbackMatch != null) return fallbackMatch;

    final fullName = _normalizeMenuName(drink.fullName);
    return _firstMenuMatch(
      allItems,
      (item) => fullName.contains(_normalizeMenuName(_menuItemName(item))),
    );
  }

  _MenuItem? _firstMenuMatch(
    Iterable<_MenuItem> items,
    bool Function(_MenuItem item) test,
  ) {
    for (final item in items) {
      if (test(item)) return item;
    }
    return null;
  }

  String _normalizeMenuName(String value) {
    return value
        .toLowerCase()
        .replaceAll('ice ', 'iced ')
        .replaceAll('caffe ', '')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '');
  }
}
