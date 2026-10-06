part of '../../main.dart';

const _preferredMenuNames = <String, List<String>>{
  'Double Espresso': ['Espresso Double'],
  'Espresso': ['Espresso Double'],
  'Iced Americano': ['Ice Americano', 'Americano'],
  'Americano': ['Ice Americano', 'Americano'],
  'Caffe Latte': ['Latte'],
  'Latte': ['Latte'],
  'Caramel Macchiato': ['Caramel Macchiato'],
  'Mocha': ['Mocha', 'Ice Mocha'],
  'Caffe Mocha': ['Mocha'],
  'Cold Brew': ['Cold Brew'],
  'Caramel Frappe': ['Ice Caramel Latte', 'Caramel Latte'],
  'Frappe': ['Ice Caramel Latte', 'Caramel Latte'],
  'Matcha Latte': ['Ice Matcha Latte', 'Matcha Mix'],
  'Matcha': ['Ice Matcha Latte', 'Matcha Mix'],
  'Peach Iced Tea': ['Çay'],
  'Iced Tea': ['Çay'],
  'Hot Chocolate': ['Sıcak Çikolata'],
  'Hot Choco': ['Sıcak Çikolata'],
};

final Map<String, IconData> _activeMenuCategoryIcons = <String, IconData>{};
final Map<String, String> _activeMenuCategoryDescriptions = <String, String>{};
final Map<String, String> _activeMenuCategoryDescriptionsEn =
    <String, String>{};
final Map<String, String> _activeMenuCategoryNamesEn = <String, String>{};

// ===== MENÜ DIALOG (Veri Tabanlı) =====

class _MenuItem {
  const _MenuItem(
    this.name,
    this.price,
    this.icon, {
    this.desc = '',
    this.tags = const [],
    this.imagePath,
    this.id,
    this.nameEn,
    this.descEn,
    this.tagsEn = const [],
    this.remoteImageUrl,
    this.transparentImagePath,
    this.remoteTransparentImageUrl,
    this.categoryId,
  });
  final String? id;
  final String? categoryId;
  final String name;
  final String? nameEn;
  final String price;
  final IconData icon;
  final String desc;
  final String? descEn;
  final List<String> tags;
  final List<String> tagsEn;
  final String? imagePath;
  final String? remoteImageUrl;
  final String? transparentImagePath;
  final String? remoteTransparentImageUrl;
}

Widget _buildMenuImage({
  required IconData fallbackIcon,
  String? assetPath,
  String? remoteImageUrl,
  String? transparentAssetPath,
  String? transparentRemoteImageUrl,
  bool preferTransparent = false,
  int? cacheWidth,
  BoxFit fit = BoxFit.cover,
  Color? fallbackColor,
}) => MenuImageView(
  fallbackIcon: fallbackIcon,
  fallbackColor: fallbackColor ?? _cream,
  assetPath: assetPath,
  remoteImageUrl: remoteImageUrl,
  transparentAssetPath: transparentAssetPath,
  transparentRemoteImageUrl: transparentRemoteImageUrl,
  preferTransparent: preferTransparent,
  cacheWidth: cacheWidth,
  fit: fit,
);

Map<String, List<_MenuItem>> _activeMenuCategories =
    <String, List<_MenuItem>>{};
final Map<String, String> _activeMenuCategoryNamesById = <String, String>{};

Map<String, List<_MenuItem>> get _currentMenuCategories =>
    _activeMenuCategories.isEmpty ? _menuCategories : _activeMenuCategories;

IconData _menuIconForKey(
  String key, {
  IconData fallback = Icons.local_cafe_rounded,
}) {
  const icons = <String, IconData>{
    'local_cafe_rounded': Icons.local_cafe_rounded,
    'coffee_maker_rounded': Icons.coffee_maker_rounded,
    'whatshot_rounded': Icons.whatshot_rounded,
    'ac_unit_rounded': Icons.ac_unit_rounded,
    'local_bar_rounded': Icons.local_bar_rounded,
    'eco_rounded': Icons.eco_rounded,
    'severe_cold_rounded': Icons.severe_cold_rounded,
    'bubble_chart_rounded': Icons.bubble_chart_rounded,
    'icecream_rounded': Icons.icecream_rounded,
    'icecream_outlined': Icons.icecream_outlined,
    'sports_bar_rounded': Icons.sports_bar_rounded,
    'cake_rounded': Icons.cake_rounded,
    'cookie_rounded': Icons.cookie_rounded,
    'lunch_dining_rounded': Icons.lunch_dining_rounded,
    'coffee_rounded': Icons.coffee_rounded,
    'add_circle_outline_rounded': Icons.add_circle_outline_rounded,
    'emoji_food_beverage_rounded': Icons.emoji_food_beverage_rounded,
  };
  return icons[key] ?? fallback;
}

void _applyRemoteMenuCatalog(MenuCatalog catalog) {
  final categories = <String, List<_MenuItem>>{};
  _activeMenuCategoryIcons.clear();
  _activeMenuCategoryDescriptions.clear();
  _activeMenuCategoryDescriptionsEn.clear();
  _activeMenuCategoryNamesEn.clear();
  _activeMenuCategoryNamesById.clear();
  for (final category in catalog.categories) {
    // Keep the display label for the existing UI, but never let duplicate
    // labels collapse two server-owned category IDs into one map entry.
    var categoryKey = category.nameTr;
    if (categories.containsKey(categoryKey)) {
      final suffix = category.id.length >= 8
          ? category.id.substring(0, 8)
          : category.id;
      categoryKey = '${category.nameTr} · $suffix';
    }
    _activeMenuCategoryNamesById[category.id] = categoryKey;
    _activeMenuCategoryDescriptions[categoryKey] = category.descriptionTr;
    _activeMenuCategoryNamesEn[categoryKey] = category.nameEn;
    _activeMenuCategoryDescriptionsEn[categoryKey] = category.descriptionEn;
    _activeMenuCategoryIcons[categoryKey] = _menuIconForKey(category.iconKey);
    final items = <_MenuItem>[];
    for (final remote in category.items) {
      items.add(
        _MenuItem(
          remote.nameTr,
          remote.priceText,
          _menuIconForKey(remote.iconKey),
          id: remote.id,
          categoryId: category.id,
          nameEn: remote.nameEn,
          desc: remote.descriptionTr,
          descEn: remote.descriptionEn,
          tags: remote.tags,
          tagsEn: remote.tagsEn,
          // Cached file first; otherwise the APK-bundled photo, so an offline
          // kiosk whose signed image URL expired still shows a picture.
          imagePath: remote.localImagePath ?? remote.imageAsset,
          remoteImageUrl: remote.imageUrl,
          transparentImagePath: remote.localTransparentImagePath,
          remoteTransparentImageUrl: remote.transparentImageUrl,
        ),
      );
    }
    categories[categoryKey] = items;
  }
  if (categories.isNotEmpty) _activeMenuCategories = categories;
}
