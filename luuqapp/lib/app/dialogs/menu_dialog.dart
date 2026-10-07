part of '../../main.dart';

class _MenuDialog extends StatefulWidget {
  const _MenuDialog();

  @override
  State<_MenuDialog> createState() => _MenuDialogState();
}

class _MenuDialogState extends State<_MenuDialog> {
  String _selectedCategory = 'Espresso Kahveler';
  String _searchQuery = '';
  final ScrollController _categoryScrollController = ScrollController();
  final ScrollController _itemsScrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (!_currentMenuCategories.containsKey(_selectedCategory) &&
        _currentMenuCategories.isNotEmpty) {
      _selectedCategory = _currentMenuCategories.keys.first;
    }
    AnalyticsService.instance.trackMenuOpen();
  }

  @override
  void dispose() {
    _categoryScrollController.dispose();
    _itemsScrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  List<_MenuItem> get _filteredItems {
    final items = _currentMenuCategories[_selectedCategory] ?? [];
    if (_searchQuery.isEmpty) return items;
    final q = searchFold(_searchQuery);
    // Search across ALL categories
    final allItems = <_MenuItem>[];
    for (final entry in _currentMenuCategories.entries) {
      for (final item in entry.value) {
        if (searchFold(_menuItemName(item)).contains(q) ||
            searchFold(_menuItemDescription(item)).contains(q)) {
          allItems.add(item);
        }
      }
    }
    return allItems;
  }

  // Parse M/L pricing: "185₺ / 205₺" → two prices, "220₺" → single
  bool _hasDualPrice(String price) => price.contains('/');

  String _mPrice(String price) {
    final parts = price.split('/');
    return parts[0].trim();
  }

  String _lPrice(String price) {
    final parts = price.split('/');
    return parts.length > 1 ? parts[1].trim() : '';
  }

  @override
  Widget build(BuildContext context) {
    // Safety net: if the selected category no longer exists in the menu,
    // show the first one instead of an empty panel.
    if (!_currentMenuCategories.containsKey(_selectedCategory) &&
        _currentMenuCategories.isNotEmpty) {
      _selectedCategory = _currentMenuCategories.keys.first;
    }
    final screenW = MediaQuery.of(context).size.width;
    final screenH = MediaQuery.of(context).size.height;
    final items = _filteredItems;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(
        horizontal: screenW * 0.10,
        vertical: screenH * 0.06,
      ),
      child: Container(
        width: screenW * 0.80,
        height: screenH * 0.88,
        decoration: BoxDecoration(
          color: const Color(0xFF1C1724), // Solid dark plum/charcoal
          borderRadius: BorderRadius.circular(40),
          border: Border.all(color: _gold.withValues(alpha: 0.2), width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.9),
              blurRadius: 80,
              spreadRadius: 20,
            ),
            BoxShadow(color: _gold.withValues(alpha: 0.08), blurRadius: 40),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(38),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset('assets/menuphoto1.jpg', fit: BoxFit.cover),
              // Premium Dark Overlay for Readability
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF14101A).withValues(alpha: 0.65),
                      const Color(0xFF1C1724).withValues(alpha: 0.80),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
              Column(
                children: [
                  // ─── TOP HEADER BAR ───
                  _buildMenuHeader(),
                  // ─── BODY: Sidebar + Items ───
                  Expanded(
                    child: Row(
                      children: [
                        // Left Sidebar
                        _buildCategorySidebar(),
                        // Vertical divider
                        Container(
                          width: 1,
                          color: Colors.white.withValues(alpha: 0.06),
                        ),
                        // Right Content
                        Expanded(child: _buildItemsPanel(items)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══ HEADER ═══
  Widget _buildMenuHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(40, 28, 28, 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1A1520).withValues(alpha: 0.5),
            const Color(0xFF241E2E).withValues(alpha: 0.5),
          ],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        border: Border(
          bottom: BorderSide(color: _gold.withValues(alpha: 0.12)),
        ),
      ),
      child: Row(
        children: [
          // Logo icon
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _gold.withValues(alpha: 0.25),
                  _caramel.withValues(alpha: 0.15),
                ],
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.restaurant_menu_rounded,
              color: _gold,
              size: 30,
            ),
          ),
          const SizedBox(width: 20),
          // Title + subtitle
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr('LUUQ MENÜ', 'LUUQ MENU'),
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 6,
                    foreground: Paint()
                      ..shader = const LinearGradient(colors: [_cream, _gold])
                          .createShader(const Rect.fromLTWH(0, 0, 250, 40)),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  tr(
                    'Kategoriyi seç, lezzetleri keşfet.',
                    'Choose a category, explore the flavors.',
                  ),
                  style: TextStyle(
                    fontSize: 15,
                    color: _mutedText,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
          const _KioskCloseButton(),
        ],
      ),
    );
  }

  // ═══ CATEGORY SIDEBAR ═══
  Widget _buildCategorySidebar() {
    final categories = _currentMenuCategories.keys.toList();
    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: const Color(0xFF14101A).withValues(alpha: 0.5),
        border: Border(
          right: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
        ),
      ),
      child: ScrollbarTheme(
        data: ScrollbarThemeData(
          thumbColor: WidgetStateProperty.all(_gold.withValues(alpha: 0.3)),
          thickness: WidgetStateProperty.all(3),
          radius: const Radius.circular(10),
        ),
        child: Scrollbar(
          controller: _categoryScrollController,
          child: ListView.builder(
            controller: _categoryScrollController,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            itemCount: categories.length,
            itemBuilder: (context, index) {
              final category = categories[index];
              final isSelected =
                  category == _selectedCategory && _searchQuery.isEmpty;
              final icon =
                  (_activeMenuCategoryIcons.isNotEmpty
                      ? _activeMenuCategoryIcons[category]
                      : _categoryIcons[category]) ??
                  Icons.circle;
              final itemCount = _currentMenuCategories[category]?.length ?? 0;

              return Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: BouncyButton(
                  onTap: () => _selectCategory(category),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutQuint,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? _caramel.withValues(alpha: 0.15)
                          : const Color(0xFF1C1724).withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSelected
                            ? _gold.withValues(alpha: 0.5)
                            : Colors.white.withValues(alpha: 0.03),
                        width: 1.5,
                      ),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: _gold.withValues(alpha: 0.1),
                                blurRadius: 15,
                                offset: const Offset(0, 4),
                              ),
                            ]
                          : [],
                    ),
                    child: Row(
                      children: [
                        // Icon
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? _gold
                                : Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            icon,
                            color: isSelected
                                ? _bgDark
                                : Colors.white.withValues(alpha: 0.8),
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Text & Badge
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                _menuCategoryName(category),
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: isSelected
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                  color: isSelected
                                      ? _cream
                                      : Colors.white.withValues(alpha: 0.85),
                                  letterSpacing: 0.5,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? _gold.withValues(alpha: 0.2)
                                      : Colors.white.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  tr('$itemCount Ürün', '$itemCount Items'),
                                  style: TextStyle(
                                    fontSize: _fsBadge,
                                    color: isSelected
                                        ? _gold
                                        : Colors.white.withValues(alpha: 0.7),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (isSelected)
                          const Icon(
                            Icons.chevron_right_rounded,
                            color: _gold,
                            size: 20,
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  // ═══ ITEMS PANEL ═══
  Widget _buildItemsPanel(List<_MenuItem> items) {
    return Column(
      children: [
        // ─── SEARCH & HERO AREA ───
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 24, 32, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Search bar
              Container(
                height: 54,
                decoration: BoxDecoration(
                  color: const Color(0xFF14101A).withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: TextField(
                  controller: _searchController,
                  onChanged: (v) => setState(() => _searchQuery = v),
                  style: const TextStyle(color: _cream, fontSize: 16),
                  decoration: InputDecoration(
                    hintText: tr(
                      'Menüde lezzet veya kategori ara...',
                      'Search for a flavor or category...',
                    ),
                    hintStyle: TextStyle(
                      color: Colors.white.withValues(alpha: 0.3),
                      fontSize: 15,
                    ),
                    prefixIcon: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Icon(
                        Icons.search_rounded,
                        color: _gold.withValues(alpha: 0.8),
                        size: 24,
                      ),
                    ),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? BouncyButton(
                            onTap: () => setState(() {
                              _searchQuery = '';
                              _searchController.clear();
                            }),
                            child: const Padding(
                              padding: EdgeInsets.all(12),
                              child: Icon(
                                Icons.close_rounded,
                                color: Colors.white54,
                                size: 22,
                              ),
                            ),
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              // Category Hero
              if (_searchQuery.isEmpty)
                _buildCategoryHero(items)
              else
                _buildSearchHero(items),
            ],
          ),
        ),

        // ─── ITEMS GRID ───
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            switchInCurve: Curves.easeOutQuad,
            switchOutCurve: Curves.easeInQuad,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.05),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: items.isEmpty && _searchQuery.isNotEmpty
                ? _buildNoResults()
                : GridView.builder(
                    key: ValueKey(
                      _searchQuery.isNotEmpty
                          ? 'search_$_searchQuery'
                          : _selectedCategory,
                    ),
                    controller: _itemsScrollController,
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                          childAspectRatio:
                              3.5, // More compact cards as requested
                        ),
                    itemCount: items.length,
                    itemBuilder: (context, index) =>
                        _buildMenuItemCard(items[index]),
                  ), // end of GridView.builder
          ), // end of AnimatedSwitcher
        ), // end of Expanded
      ],
    );
  }

  // ═══ CATEGORY HERO ═══
  Widget _buildCategoryHero(List<_MenuItem> items) {
    final remoteDescription = _menuCategoryDescription(_selectedCategory);
    final configuredDescription = remoteDescription.isNotEmpty
        ? remoteDescription
        : _categoryDescriptions[_selectedCategory];
    final description = remoteDescription.isNotEmpty
        ? remoteDescription
        : trMenu(
            configuredDescription ??
                tr(
                  'Bu kategoride ${items.length} ürün bulunuyor.',
                  'There are ${items.length} products in this category.',
                ),
          );
    final populars = items
        .where((i) => i.tags.contains('Popüler'))
        .take(3)
        .map(_menuItemName)
        .join(', ');

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF231E2D).withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _gold.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _gold.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  (_activeMenuCategoryIcons.isNotEmpty
                          ? _activeMenuCategoryIcons[_selectedCategory]
                          : _categoryIcons[_selectedCategory]) ??
                      Icons.circle,
                  color: _gold,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  displayUpper(_menuCategoryName(_selectedCategory)),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: _gold,
                    letterSpacing: 2,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.05),
                  ),
                ),
                child: Text(
                  tr('${items.length} Ürün', '${items.length} Items'),
                  style: const TextStyle(
                    fontSize: _fsCaption,
                    fontWeight: FontWeight.w700,
                    color: Colors.white70,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            description,
            style: const TextStyle(
              fontSize: 15,
              color: Colors.white70,
              height: 1.4,
            ),
          ),
          if (populars.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _gold.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _gold.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.star_rounded, color: _gold, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    tr('Popüler Favoriler: ', 'Popular Favorites: '),
                    style: TextStyle(
                      fontSize: _fsCaption,
                      fontWeight: FontWeight.w900,
                      color: _gold,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      populars,
                      style: const TextStyle(
                        fontSize: _fsCaption,
                        fontWeight: FontWeight.w800,
                        color: _cream,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSearchHero(List<_MenuItem> items) {
    return Row(
      children: [
        const Icon(Icons.search_rounded, color: _gold, size: 24),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            tr('"$_searchQuery" için sonuçlar', 'Results for "$_searchQuery"'),
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: _gold,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: _gold.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            tr('${items.length} Bulundu', '${items.length} Found'),
            style: const TextStyle(
              fontSize: _fsCaption,
              fontWeight: FontWeight.w700,
              color: _gold,
            ),
          ),
        ),
      ],
    );
  }

  void _selectCategory(String category) {
    setState(() {
      _selectedCategory = category;
      _searchQuery = '';
      _searchController.clear();
    });
    if (_itemsScrollController.hasClients) {
      _itemsScrollController.jumpTo(0);
    }
    AnalyticsService.instance.trackCategoryClick(category);
  }

  // ═══ NO SEARCH RESULTS ═══
  /// Instead of an empty grid: popular products and the categories, one tap
  /// away.
  Widget _buildNoResults() {
    final popular = <_MenuItem>[
      for (final list in _currentMenuCategories.values)
        for (final item in list)
          if (item.tags.contains('Popüler')) item,
    ].take(6);
    return SingleChildScrollView(
      key: ValueKey('no_results_$_searchQuery'),
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(32, 32, 32, 32),
      child: Column(
        children: [
          Icon(
            Icons.search_off_rounded,
            size: 56,
            color: _gold.withValues(alpha: 0.7),
          ),
          const SizedBox(height: 16),
          Text(
            tr('Sonuç bulunamadı', 'No results'),
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: _cream,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            tr('Şunlara göz atabilirsiniz:', 'You can browse these:'),
            style: const TextStyle(fontSize: 16, color: _mutedText),
          ),
          const SizedBox(height: 24),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final item in popular)
                _buildSuggestionChip(
                  icon: Icons.star_rounded,
                  label: _menuItemName(item),
                  onTap: () => _showProductDetailDialog(item),
                ),
              for (final category in _currentMenuCategories.keys.take(6))
                _buildSuggestionChip(
                  icon:
                      (_activeMenuCategoryIcons.isNotEmpty
                          ? _activeMenuCategoryIcons[category]
                          : _categoryIcons[category]) ??
                      Icons.circle,
                  label: _menuCategoryName(category),
                  onTap: () => _selectCategory(category),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestionChip({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return BouncyButton(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: _gold),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: _cream,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══ PRODUCT DETAIL DIALOG ═══
  void _showProductDetailDialog(_MenuItem item, {Object? heroTag}) {
    if (!currentFeatureFlags.menu) {
      showFeatureLockedDialog(context, tr('Ürün Detayı', 'Product Detail'));
      return;
    }
    AnalyticsService.instance.trackProductDetailOpen(
      _generateSlug(item.name),
      item.name,
      _selectedCategory,
    );
    _showKioskDialog<void>(
      context,
      _ProductDetailDialog(item: item, heroTag: heroTag),
      label: _menuItemName(item),
    );
  }

  // ═══ MENU ITEM CARD ═══
  Widget _buildMenuItemCard(_MenuItem item) {
    final hasTags = item.tags.isNotEmpty;
    final isPopular = item.tags.contains('Popüler');
    final isSpecial = item.tags.contains('Special');
    final dual = _hasDualPrice(item.price);
    // The grid key is part of the tag: while one grid fades into the next,
    // the same product is on screen twice.
    final heroTag = _productHeroTag(
      'menu:${_searchQuery.isNotEmpty ? 'search:$_searchQuery' : _selectedCategory}',
      item,
    );

    return BouncyButton(
      onTap: () {
        AnalyticsService.instance.trackProductClick(
          _generateSlug(item.name),
          item.name,
          _selectedCategory,
        );
        _showProductDetailDialog(item, heroTag: heroTag);
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF282136).withValues(alpha: 0.85),
              const Color(0xFF1B1624).withValues(alpha: 0.85),
            ],
          ),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: isSpecial
                ? _gold.withValues(alpha: 0.4)
                : Colors.white.withValues(alpha: 0.08),
            width: 1.5,
          ),
          boxShadow: [
            if (isSpecial)
              BoxShadow(
                color: _gold.withValues(alpha: 0.12),
                blurRadius: 18,
                spreadRadius: 1,
              ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // ─── THUMBNAIL AREA ───
            _productHero(
              heroTag,
              Container(
                width: 88,
                height: 88,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: const Color(0xFF16131D).withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                ),
                child: _buildMenuImage(
                  fallbackIcon: item.icon,
                  fallbackColor: _gold.withValues(alpha: 0.75),
                  assetPath: item.imagePath,
                  remoteImageUrl: item.remoteImageUrl,
                  cacheWidth: 176,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(width: 16),
            // ─── INFO AREA ───
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Name + Badges
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      Text(
                        _menuItemName(item),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: _gold,
                          height: 1.2,
                          letterSpacing: 0.3,
                        ),
                      ),
                      if (isPopular || isSpecial)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: (isSpecial ? const Color(0xFFE879A8) : _gold)
                                .withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color:
                                  (isSpecial ? const Color(0xFFE879A8) : _gold)
                                      .withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isSpecial
                                    ? Icons.star_rounded
                                    : Icons.star_rounded,
                                size: 14,
                                color: isSpecial
                                    ? const Color(0xFFE879A8)
                                    : _gold,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                isSpecial ? 'Special' : trMenu('Popüler'),
                                style: TextStyle(
                                  fontSize: _fsBadge,
                                  fontWeight: FontWeight.w900,
                                  color: isSpecial
                                      ? const Color(0xFFE879A8)
                                      : _gold,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  // Description
                  if (_menuItemDescription(item).isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      _menuItemDescription(item),
                      style: TextStyle(
                        fontSize: _fsCaption,
                        color: Colors.white.withValues(alpha: 0.75),
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  // Tags (filtered to avoid redundancy)
                  if (hasTags) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: item.tags
                          .where((tag) => tag != 'Popüler' && tag != 'Special')
                          .map((tag) {
                            final color =
                                _tagStyles[tag] ?? const Color(0xFFB2BEC3);
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: color.withValues(alpha: 0.4),
                                ),
                              ),
                              child: Text(
                                _menuItemTag(item, tag),
                                style: TextStyle(
                                  fontSize: _fsBadge,
                                  fontWeight: FontWeight.w800,
                                  color: color,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            );
                          })
                          .toList(),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            // ─── PRICE AREA ───
            dual
                ? _buildDualPriceBadge(item.price)
                : _buildSinglePrice(item.price),
          ],
        ),
      ),
    );
  }

  // ═══ SINGLE PRICE ═══
  Widget _buildSinglePrice(String price) {
    return Container(
      width: 90,
      height: 46,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _gold.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _gold.withValues(alpha: 0.4)),
      ),
      child: Text(
        price,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w900,
          color: _gold,
        ),
      ),
    );
  }

  // ═══ DUAL PRICE BADGES (M / L) ═══
  Widget _buildDualPriceBadge(String price) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _priceBadge('M', _mPrice(price)),
        const SizedBox(height: 6),
        _priceBadge('L', _lPrice(price)),
      ],
    );
  }

  Widget _priceBadge(String label, String price) {
    return Container(
      padding: const EdgeInsets.only(right: 6),
      decoration: BoxDecoration(
        color: _gold.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _gold.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 32,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(vertical: 5),
            decoration: BoxDecoration(
              color: _gold.withValues(alpha: 0.2),
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(9),
                right: Radius.circular(4),
              ),
            ),
            child: Text(
              label,
              style: const TextStyle(
                fontSize: _fsBadge,
                fontWeight: FontWeight.w900,
                color: _gold,
              ),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 44,
            child: Text(
              price,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: _cream,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}
