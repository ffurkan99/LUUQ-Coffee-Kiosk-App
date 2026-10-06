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

  List<_MenuItem> get _recommendationDrinkOptions {
    if (_activeMenuCategoryIcons.isNotEmpty) {
      final excluded = <IconData>{
        Icons.cake_rounded,
        Icons.cookie_rounded,
        Icons.icecream_rounded,
        Icons.icecream_outlined,
        Icons.add_circle_outline_rounded,
        Icons.coffee_rounded,
        Icons.lunch_dining_rounded,
      };
      return _currentMenuCategories.entries
          .where(
            (entry) => !excluded.contains(_activeMenuCategoryIcons[entry.key]),
          )
          .expand((entry) => entry.value)
          .toList(growable: false);
    }
    const dessertCategories = {'Pasta & Tatlı', 'LUUQ Chocolate'};
    const hiddenCategories = {'Ekstralar', 'Termos & Seramik', 'Sandviç'};
    return _currentMenuCategories.entries
        .where(
          (entry) =>
              !dessertCategories.contains(entry.key) &&
              !hiddenCategories.contains(entry.key),
        )
        .expand((entry) => entry.value)
        .toList(growable: false);
  }

  List<_MenuItem> get _recommendationDessertOptions {
    if (_activeMenuCategoryIcons.isNotEmpty) {
      final dessertIcons = <IconData>{
        Icons.cake_rounded,
        Icons.cookie_rounded,
        Icons.icecream_rounded,
        Icons.icecream_outlined,
      };
      return _currentMenuCategories.entries
          .where(
            (entry) =>
                dessertIcons.contains(_activeMenuCategoryIcons[entry.key]),
          )
          .expand((entry) => entry.value)
          .toList(growable: false);
    }
    return [
      ...?_currentMenuCategories['Pasta & Tatlı'],
      ...?_currentMenuCategories['LUUQ Chocolate'],
    ];
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

  List<_MenuItem> get _iceCreamOptions => _activeMenuCategoryIcons.isNotEmpty
      ? _itemsForCategoryIcons([
          Icons.icecream_outlined,
          Icons.icecream_rounded,
        ])
      : (_currentMenuCategories['Dondurmalar'] ?? const []);

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
  _MenuItem get _currentBaristaDrink {
    final options = _recommendationDrinkOptions;
    return _baristaDrink ??
        options.firstWhere(
          (item) => item.imagePath != null,
          orElse: () => options.first,
        );
  }

  _MenuItem get _currentBaristaDessert {
    final options = _recommendationDessertOptions;
    return _baristaDessert ??
        options.firstWhere(
          (item) => item.imagePath != null,
          orElse: () => options.first,
        );
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
