import 'dart:convert';

import 'package:flutter/foundation.dart';

String menuTextForLanguage({
  required String turkish,
  required String? english,
  required bool useEnglish,
}) => useEnglish && english != null && english.isNotEmpty ? english : turkish;

final RegExp _sha256Pattern = RegExp(r'^[a-f0-9]{64}$');
final RegExp _bundledMenuAssetPattern = RegExp(
  r'^assets/menu/(png/)?[A-Za-z0-9_.-]+\.(jpe?g|png|webp)$',
  caseSensitive: false,
);

/// Stable, server-owned menu item. Names and descriptions are editable; ids
/// are not, so wheel and barista selections survive copy changes.
class RemoteMenuItem {
  const RemoteMenuItem({
    required this.id,
    required this.categoryId,
    required this.nameTr,
    required this.nameEn,
    this.descriptionTr = '',
    this.descriptionEn = '',
    this.priceText = '',
    this.tags = const <String>[],
    this.tagsEn = const <String>[],
    this.iconKey = 'local_cafe_rounded',
    this.imageUrl,
    this.imageSha256,
    this.imageMime,
    this.localImagePath,
    this.imageAsset,
    this.transparentImageUrl,
    this.transparentImageSha256,
    this.transparentImageMime,
    this.localTransparentImagePath,
  });

  final String id;
  final String categoryId;
  final String nameTr;
  final String nameEn;
  final String descriptionTr;
  final String descriptionEn;
  final String priceText;
  final List<String> tags;
  final List<String> tagsEn;
  final String iconKey;
  final String? imageUrl;
  final String? imageSha256;
  final String? imageMime;
  final String? localImagePath;

  /// APK-bundled photo (`assets/menu/...`) used when no cached remote image
  /// is available, e.g. offline after the signed image URL expired.
  final String? imageAsset;
  final String? transparentImageUrl;
  final String? transparentImageSha256;
  final String? transparentImageMime;
  final String? localTransparentImagePath;

  /// [clearLocalImagePath]/[clearLocalTransparentImagePath] drop a cached path
  /// that no longer verifies, instead of carrying it forward.
  RemoteMenuItem copyWith({
    String? localImagePath,
    String? localTransparentImagePath,
    bool clearLocalImagePath = false,
    bool clearLocalTransparentImagePath = false,
  }) => RemoteMenuItem(
    id: id,
    categoryId: categoryId,
    nameTr: nameTr,
    nameEn: nameEn,
    descriptionTr: descriptionTr,
    descriptionEn: descriptionEn,
    priceText: priceText,
    tags: tags,
    tagsEn: tagsEn,
    iconKey: iconKey,
    imageUrl: imageUrl,
    imageSha256: imageSha256,
    imageMime: imageMime,
    localImagePath: clearLocalImagePath
        ? null
        : localImagePath ?? this.localImagePath,
    imageAsset: imageAsset,
    transparentImageUrl: transparentImageUrl,
    transparentImageSha256: transparentImageSha256,
    transparentImageMime: transparentImageMime,
    localTransparentImagePath: clearLocalTransparentImagePath
        ? null
        : localTransparentImagePath ?? this.localTransparentImagePath,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'category_id': categoryId,
    'name_tr': nameTr,
    'name_en': nameEn,
    'description_tr': descriptionTr,
    'description_en': descriptionEn,
    'price_text': priceText,
    'tags': tags,
    'tags_en': tagsEn,
    'icon_key': iconKey,
    if (imageUrl != null) 'image_url': imageUrl,
    if (imageSha256 != null) 'image_sha256': imageSha256,
    if (imageMime != null) 'image_mime': imageMime,
    if (localImagePath != null) 'local_image_path': localImagePath,
    if (imageAsset != null) 'image_asset': imageAsset,
    if (transparentImageUrl != null)
      'transparent_image_url': transparentImageUrl,
    if (transparentImageSha256 != null)
      'transparent_image_sha256': transparentImageSha256,
    if (transparentImageMime != null)
      'transparent_image_mime': transparentImageMime,
    if (localTransparentImagePath != null)
      'local_transparent_image_path': localTransparentImagePath,
  };

  /// [allowLocalPaths] is true only when reading this app's own cache file.
  /// A server response must never choose which local file the renderer opens.
  factory RemoteMenuItem.fromJson(
    Map<String, dynamic> json, {
    bool allowLocalPaths = false,
  }) {
    List<String> strings(Object? value) => value is List
        ? value
              .map((item) => item.toString())
              .where((item) => item.isNotEmpty)
              .toList(growable: false)
        : const <String>[];
    final id = json['id']?.toString() ?? json['public_id']?.toString() ?? '';
    final categoryId = json['category_id']?.toString() ?? '';
    if (id.isEmpty || categoryId.isEmpty) {
      throw const FormatException('Remote menu item has no stable id.');
    }
    String? digest(Object? value) {
      final text = value?.toString().trim().toLowerCase();
      if (text == null || text.isEmpty) return null;
      return _sha256Pattern.hasMatch(text) ? text : '';
    }

    // A malformed hash makes that image unverifiable: drop the image (the
    // item still renders with its bundled photo or icon) rather than the item.
    final imageHash = digest(json['image_sha256']);
    final transparentHash = digest(json['transparent_image_sha256']);
    final imageUsable = imageHash != '';
    final transparentUsable = transparentHash != '';
    final asset = json['image_asset']?.toString().trim();

    return RemoteMenuItem(
      id: id,
      categoryId: categoryId,
      nameTr: json['name_tr']?.toString() ?? '',
      nameEn: json['name_en']?.toString() ?? json['name_tr']?.toString() ?? '',
      descriptionTr: json['description_tr']?.toString() ?? '',
      descriptionEn:
          json['description_en']?.toString() ??
          json['description_tr']?.toString() ??
          '',
      priceText: json['price_text']?.toString() ?? '',
      tags: strings(json['tags']),
      tagsEn: strings(json['tags_en']),
      iconKey: json['icon_key']?.toString() ?? 'local_cafe_rounded',
      imageUrl: imageUsable ? json['image_url']?.toString() : null,
      imageSha256: imageUsable ? imageHash : null,
      imageMime: imageUsable ? json['image_mime']?.toString() : null,
      localImagePath: allowLocalPaths && imageUsable
          ? json['local_image_path']?.toString()
          : null,
      imageAsset: asset != null && _bundledMenuAssetPattern.hasMatch(asset)
          ? asset
          : null,
      transparentImageUrl: transparentUsable
          ? json['transparent_image_url']?.toString()
          : null,
      transparentImageSha256: transparentUsable ? transparentHash : null,
      transparentImageMime: transparentUsable
          ? json['transparent_image_mime']?.toString()
          : null,
      localTransparentImagePath: allowLocalPaths && transparentUsable
          ? json['local_transparent_image_path']?.toString()
          : null,
    );
  }
}

class RemoteMenuCategory {
  const RemoteMenuCategory({
    required this.id,
    required this.nameTr,
    required this.nameEn,
    this.descriptionTr = '',
    this.descriptionEn = '',
    this.iconKey = 'local_cafe_rounded',
    this.items = const <RemoteMenuItem>[],
  });

  final String id;
  final String nameTr;
  final String nameEn;
  final String descriptionTr;
  final String descriptionEn;
  final String iconKey;
  final List<RemoteMenuItem> items;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name_tr': nameTr,
    'name_en': nameEn,
    'description_tr': descriptionTr,
    'description_en': descriptionEn,
    'icon_key': iconKey,
    'items': items.map((item) => item.toJson()).toList(growable: false),
  };

  factory RemoteMenuCategory.fromJson(
    Map<String, dynamic> json, {
    bool allowLocalPaths = false,
  }) {
    final id = json['id']?.toString() ?? json['public_id']?.toString() ?? '';
    if (id.isEmpty) {
      throw const FormatException('Remote menu category has no id.');
    }
    final rawItems = json['items'] is List ? json['items'] as List : const [];
    final items = <RemoteMenuItem>[];
    for (final raw in rawItems.whereType<Map>()) {
      try {
        items.add(
          RemoteMenuItem.fromJson(
            Map<String, dynamic>.from(raw),
            allowLocalPaths: allowLocalPaths,
          ),
        );
      } on FormatException catch (error) {
        // One malformed item must not take the whole menu down.
        debugPrint('[MENU] skipped item in category $id: ${error.message}');
      }
    }
    return RemoteMenuCategory(
      id: id,
      nameTr: json['name_tr']?.toString() ?? '',
      nameEn: json['name_en']?.toString() ?? json['name_tr']?.toString() ?? '',
      descriptionTr: json['description_tr']?.toString() ?? '',
      descriptionEn:
          json['description_en']?.toString() ??
          json['description_tr']?.toString() ??
          '',
      iconKey: json['icon_key']?.toString() ?? 'local_cafe_rounded',
      items: List.unmodifiable(items),
    );
  }
}

class MenuCatalog {
  const MenuCatalog({
    required this.schemaVersion,
    required this.menuVersion,
    required this.catalogRevision,
    required this.wheelRevision,
    required this.baristaRevision,
    required this.categories,
    this.wheelItemIds = const <String>[],
    this.baristaDrinkId,
    this.baristaDessertId,
    this.updatedAt,
    this.effectiveRevision,
    this.menuProfileId,
    this.themeKey,
  });

  /// Theme names the server may send (the app's AppTheme values).
  static const Set<String> themeKeys = {
    'normal',
    'summer',
    'winter',
    'feast',
    'newYear',
  };

  final int schemaVersion;
  final int menuVersion;
  final int catalogRevision;
  final int wheelRevision;
  final int baristaRevision;
  final List<RemoteMenuCategory> categories;
  final List<String> wheelItemIds;
  final String? baristaDrinkId;
  final String? baristaDessertId;
  final String? updatedAt;
  final String? effectiveRevision;
  final String? menuProfileId;

  /// The theme set on the panel for this kiosk (device, license or global);
  /// null when the panel leaves the theme to the kiosk.
  final String? themeKey;

  Iterable<RemoteMenuItem> get items =>
      categories.expand((category) => category.items);

  MenuCatalog copyWithCategories(List<RemoteMenuCategory> categories) =>
      MenuCatalog(
        schemaVersion: schemaVersion,
        menuVersion: menuVersion,
        catalogRevision: catalogRevision,
        wheelRevision: wheelRevision,
        baristaRevision: baristaRevision,
        categories: categories,
        wheelItemIds: wheelItemIds,
        baristaDrinkId: baristaDrinkId,
        baristaDessertId: baristaDessertId,
        updatedAt: updatedAt,
        effectiveRevision: effectiveRevision,
        menuProfileId: menuProfileId,
        themeKey: themeKey,
      );

  Map<String, dynamic> toJson() => {
    'schema_version': schemaVersion,
    'menu_version': menuVersion,
    'catalog_revision': catalogRevision,
    'wheel_revision': wheelRevision,
    'barista_revision': baristaRevision,
    if (effectiveRevision != null) 'effective_revision': effectiveRevision,
    if (menuProfileId != null) 'menu_profile_id': menuProfileId,
    'catalog': {
      'categories': categories
          .map((category) => category.toJson())
          .toList(growable: false),
    },
    'wheel_item_ids': wheelItemIds,
    'barista_drink_id': baristaDrinkId,
    'barista_dessert_id': baristaDessertId,
    'theme': themeKey,
    if (updatedAt != null) 'updated_at': updatedAt,
  };

  String encode() => jsonEncode(toJson());

  /// Parses a server response. Local file paths in it are ignored.
  factory MenuCatalog.fromApiJson(Map<String, dynamic> json) =>
      MenuCatalog._parse(json, allowLocalPaths: false);

  /// Parses this app's own cache file, which may carry cached image paths.
  factory MenuCatalog.fromCacheJson(Map<String, dynamic> json) =>
      MenuCatalog._parse(json, allowLocalPaths: true);

  factory MenuCatalog._parse(
    Map<String, dynamic> json, {
    required bool allowLocalPaths,
  }) {
    final rawCatalog = json['catalog'] is Map
        ? Map<String, dynamic>.from(json['catalog'] as Map)
        : json;
    final rawCategories = rawCatalog['categories'] is List
        ? rawCatalog['categories'] as List
        : const [];
    final categories = <RemoteMenuCategory>[];
    for (final raw in rawCategories.whereType<Map>()) {
      try {
        categories.add(
          RemoteMenuCategory.fromJson(
            Map<String, dynamic>.from(raw),
            allowLocalPaths: allowLocalPaths,
          ),
        );
      } on FormatException catch (error) {
        debugPrint('[MENU] skipped category: ${error.message}');
      }
    }
    if (categories.isEmpty) {
      throw const FormatException('Remote menu has no categories.');
    }

    List<String> ids(Object? value) => value is List
        ? value
              .map((item) => item.toString())
              .where((item) => item.isNotEmpty)
              .toList(growable: false)
        : const <String>[];
    int number(String key, [String? fallback]) =>
        int.tryParse(
          (json[key] ?? (fallback == null ? null : rawCatalog[fallback]))
                  ?.toString() ??
              '',
        ) ??
        0;

    return MenuCatalog(
      schemaVersion: number('schema_version'),
      menuVersion: number('menu_version'),
      catalogRevision: number('catalog_revision', 'revision'),
      wheelRevision: number('wheel_revision'),
      baristaRevision: number('barista_revision'),
      categories: List.unmodifiable(categories),
      wheelItemIds: ids(json['wheel_item_ids']),
      baristaDrinkId: json['barista_drink_id']?.toString(),
      baristaDessertId: json['barista_dessert_id']?.toString(),
      updatedAt: json['updated_at']?.toString(),
      effectiveRevision: json['effective_revision']?.toString(),
      menuProfileId: json['menu_profile_id']?.toString(),
      // An unknown name (a newer server) is treated as "not set".
      themeKey: themeKeys.contains(json['theme'])
          ? json['theme'] as String
          : null,
    );
  }
}
