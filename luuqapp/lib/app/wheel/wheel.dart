part of '../../main.dart';

class _SpinTickSound {
  static const _channel = MethodChannel('luuqapp/spin_sound');

  DateTime? _lastPlayedAt;

  void playTick() {
    final now = DateTime.now();
    final lastPlayedAt = _lastPlayedAt;
    if (lastPlayedAt != null &&
        now.difference(lastPlayedAt) < const Duration(milliseconds: 28)) {
      return;
    }
    _lastPlayedAt = now;
    unawaited(_playTick());
  }

  void playResult() {
    unawaited(_playResult());
  }

  Future<void> _playTick() async {
    try {
      if (Platform.isAndroid || Platform.isWindows) {
        await _channel.invokeMethod<void>('tick', <String, dynamic>{
          'volume': appVolumeNotifier.value,
        });
      } else {
        await SystemSound.play(SystemSoundType.click);
      }
    } catch (_) {
      await SystemSound.play(SystemSoundType.click);
    }
  }

  Future<void> _playResult() async {
    try {
      if (Platform.isAndroid || Platform.isWindows) {
        await _channel.invokeMethod<void>('result', <String, dynamic>{
          'volume': appVolumeNotifier.value * 0.65,
        });
      } else {
        await SystemSound.play(SystemSoundType.alert);
      }
    } catch (_) {
      await SystemSound.play(SystemSoundType.alert);
    }
  }
}

class _DrinkWheelPainter extends CustomPainter {
  const _DrinkWheelPainter({
    required this.drinks,
    this.selectedDrink,
    this.showResult = false,
  });

  final List<Drink> drinks;
  final Drink? selectedDrink;
  final bool showResult;

  @override
  void paint(Canvas canvas, Size size) {
    if (drinks.isEmpty) return;

    final center = size.center(Offset.zero);
    final radius =
        size.shortestSide / 2 - 8; // Prevent outer stroke from clipping
    final bounds = Rect.fromCircle(center: center, radius: radius);

    final sweep = 2 * pi / drinks.length;

    for (var i = 0; i < drinks.length; i++) {
      final drink = drinks[i];
      final start = -pi / 2 + i * sweep;
      final isSelected = showResult && drink == selectedDrink;

      // Dim non-selected segments slightly when showing result
      final baseColor = (showResult && !isSelected)
          ? drink.color.withValues(alpha: 0.4)
          : drink.color;

      final paint = Paint()
        ..style = PaintingStyle.fill
        ..color = isSelected
            ? Color.lerp(drink.color, Colors.white, 0.25)!
            : baseColor;

      canvas.drawArc(bounds, start, sweep, true, paint);

      if (isSelected) {
        // Bright inner border for selected segment
        final highlightPaint = Paint()
          ..style = PaintingStyle.stroke
          ..color = Colors.white.withValues(alpha: 0.8)
          ..strokeWidth = 6;
        canvas.drawArc(bounds, start, sweep, true, highlightPaint);
      }

      // Separator
      final lineEnd = Offset(
        center.dx + cos(start) * radius,
        center.dy + sin(start) * radius,
      );
      canvas.drawLine(
        center,
        lineEnd,
        Paint()
          ..color = _bgDark.withValues(alpha: 0.8)
          ..strokeWidth = 4,
      );

      // Text and images are now rendered via Flutter Stack in _buildCenterArea
    }

    // Outer border
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12
        ..color = _surface,
    );
    canvas.drawCircle(
      center,
      radius - 6,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = _gold.withValues(alpha: 0.5),
    );
  }

  @override
  bool shouldRepaint(covariant _DrinkWheelPainter oldDelegate) {
    return oldDelegate.drinks != drinks ||
        oldDelegate.selectedDrink != selectedDrink ||
        oldDelegate.showResult != showResult;
  }
}

class _PointerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

    // Rounded triangle path
    final path = Path();
    const double radius = 6.0;

    // Start from top left with rounding
    path.moveTo(radius, 0);
    path.lineTo(size.width - radius, 0);
    path.quadraticBezierTo(size.width, 0, size.width, radius);

    // Point down
    path.lineTo(size.width / 2 + 4, size.height - 4);
    path.quadraticBezierTo(
      size.width / 2,
      size.height,
      size.width / 2 - 4,
      size.height - 4,
    );

    // Back to top
    path.lineTo(0, radius);
    path.quadraticBezierTo(0, 0, radius, 0);
    path.close();

    // Shadow
    canvas.drawPath(path.shift(const Offset(0, 4)), shadowPaint);

    // Main pointer
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

List<_MenuItem> _defaultWheelMenuItems() {
  final iceCoffee = _expensiveItems(
    _menuItemsForCategoryIcons([
      Icons.ac_unit_rounded,
      Icons.severe_cold_rounded,
      Icons.sports_bar_rounded,
      Icons.bubble_chart_rounded,
      Icons.icecream_rounded,
    ]),
  );
  final hotCoffee = _expensiveItems(
    _menuItemsForCategoryIcons([
      Icons.local_cafe_rounded,
      Icons.coffee_maker_rounded,
      Icons.whatshot_rounded,
    ]),
  );
  final desserts = _expensiveItems(
    _menuItemsForCategoryIcons([Icons.cake_rounded, Icons.cookie_rounded]),
  );
  final cocktails = _expensiveItems(
    _menuItemsForCategoryIcons([Icons.local_bar_rounded]),
  );
  final herbalTeas = _expensiveItems(
    _menuItemsForCategoryIcons([Icons.eco_rounded]),
  );
  final iceCreams = _menuItemsForCategoryIcons([Icons.icecream_outlined]);

  if (appThemeNotifier.value == AppTheme.summer) {
    return [
      ...iceCoffee.take(2),
      ...desserts.take(2),
      ...cocktails.take(2),
      ...iceCreams.take(2),
    ];
  }

  return [
    iceCoffee.first,
    hotCoffee.first,
    ...desserts.take(2),
    ...cocktails.take(2),
    ...herbalTeas.take(2),
  ];
}

List<_MenuItem> _menuItemsForCategoryIcons(List<IconData> icons) {
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

List<_MenuItem> _expensiveItems(List<_MenuItem> items) {
  return List<_MenuItem>.from(items)
    ..sort((a, b) => _maxMenuPrice(b.price).compareTo(_maxMenuPrice(a.price)));
}

int _maxMenuPrice(String price) {
  final matches = RegExp(r'\d+').allMatches(price);
  var maxPrice = 0;
  for (final match in matches) {
    maxPrice = max(maxPrice, int.tryParse(match.group(0) ?? '') ?? 0);
  }
  return maxPrice;
}

Drink _drinkFromMenuItem(_MenuItem item) {
  final category = _categoryForMenuItem(item);
  return Drink(
    shortName: _wheelShortName(_menuItemName(item)),
    fullName: _menuItemName(item),
    description: _menuItemDescription(item),
    icon: item.icon,
    color: _wheelColorForMenuItem(item, category),
    moods: _wheelMoodsForMenuItem(item, category),
    imagePath: item.imagePath,
    remoteImageUrl: item.remoteImageUrl,
    transparentImagePath: item.transparentImagePath,
    remoteTransparentImageUrl: item.remoteTransparentImageUrl,
  );
}

String _categoryForMenuItem(_MenuItem item) {
  final stableCategory = item.categoryId == null
      ? null
      : _activeMenuCategoryNamesById[item.categoryId!];
  if (stableCategory != null) return stableCategory;
  for (final entry in _currentMenuCategories.entries) {
    if (entry.value.contains(item)) return entry.key;
  }
  return '';
}

String _wheelShortName(String name) {
  return name
      .replaceAll('Ice ', '')
      .replaceAll('Iced ', '')
      .replaceAll('Luuq ', '')
      .trim();
}

Color _wheelColorForMenuItem(_MenuItem item, String category) {
  final icon = (_activeMenuCategoryIcons.isNotEmpty
      ? _activeMenuCategoryIcons
      : _categoryIcons)[category];
  if (icon == Icons.ac_unit_rounded ||
      icon == Icons.severe_cold_rounded ||
      icon == Icons.sports_bar_rounded) {
    return const Color(0xFF5F7F90);
  }
  if (icon == Icons.local_cafe_rounded ||
      icon == Icons.coffee_maker_rounded ||
      icon == Icons.whatshot_rounded) {
    return const Color(0xFF8A5A37);
  }
  if (icon == Icons.cake_rounded ||
      icon == Icons.cookie_rounded ||
      icon == Icons.bubble_chart_rounded ||
      icon == Icons.icecream_rounded) {
    return const Color(0xFFC97892);
  }
  if (icon == Icons.local_bar_rounded) return const Color(0xFF789D78);
  if (icon == Icons.eco_rounded) return const Color(0xFF5F8E70);
  return Color.lerp(_surface, _gold, 0.35)!;
}

Set<DrinkMood> _wheelMoodsForMenuItem(_MenuItem item, String category) {
  final icon = (_activeMenuCategoryIcons.isNotEmpty
      ? _activeMenuCategoryIcons
      : _categoryIcons)[category];
  final moods = <DrinkMood>{};
  if (icon == Icons.ac_unit_rounded ||
      icon == Icons.local_bar_rounded ||
      icon == Icons.severe_cold_rounded ||
      icon == Icons.bubble_chart_rounded ||
      icon == Icons.icecream_rounded ||
      icon == Icons.sports_bar_rounded) {
    moods.add(DrinkMood.cold);
    moods.add(DrinkMood.fresh);
  }
  if (icon == Icons.local_cafe_rounded ||
      icon == Icons.eco_rounded ||
      icon == Icons.coffee_maker_rounded ||
      icon == Icons.whatshot_rounded) {
    moods.add(DrinkMood.hot);
  }
  if (icon == Icons.cake_rounded ||
      icon == Icons.cookie_rounded ||
      icon == Icons.lunch_dining_rounded ||
      icon == Icons.icecream_rounded ||
      icon == Icons.bubble_chart_rounded) {
    moods.add(DrinkMood.sweet);
  }
  final lowerName = _menuItemName(item).toLowerCase();
  final lowerDesc = _menuItemDescription(item).toLowerCase();
  if (lowerName.contains('latte') ||
      lowerName.contains('mocha') ||
      lowerDesc.contains('süt') ||
      lowerDesc.contains('krem')) {
    moods.add(DrinkMood.milky);
  }
  if (lowerName.contains('espresso') ||
      lowerName.contains('americano') ||
      lowerDesc.contains('yoğun')) {
    moods.add(DrinkMood.strong);
  }
  if (moods.isEmpty) moods.add(DrinkMood.fresh);
  return moods;
}

class Drink {
  const Drink({
    required this.shortName,
    required this.fullName,
    required this.description,
    required this.icon,
    required this.color,
    required this.moods,
    this.imagePath,
    this.remoteImageUrl,
    this.transparentImagePath,
    this.remoteTransparentImageUrl,
  });

  final String shortName;
  final String fullName;
  final String description;
  final IconData icon;
  final Color color;
  final Set<DrinkMood> moods;
  final String? imagePath;
  final String? remoteImageUrl;
  final String? transparentImagePath;
  final String? remoteTransparentImageUrl;

  @override
  bool operator ==(Object other) {
    return other is Drink && other.fullName == fullName;
  }

  @override
  int get hashCode => fullName.hashCode;
}

enum DrinkMood {
  cold('Soğuk', 'Cold', Icons.ac_unit_rounded),
  hot('Sıcak', 'Hot', Icons.local_fire_department_rounded),
  sweet('Tatlı', 'Sweet', Icons.cake_rounded),
  milky('Sütlü', 'Milky', Icons.local_drink_rounded),
  strong('Sert', 'Strong', Icons.bolt_rounded),
  fresh('Ferah', 'Fresh', Icons.spa_rounded);

  const DrinkMood(this.trLabel, this.enLabel, this.icon);
  final String trLabel;
  final String enLabel;
  final IconData icon;

  String get label => tr(trLabel, enLabel);
}
