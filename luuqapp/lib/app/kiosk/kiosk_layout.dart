part of '../../main.dart';

/// Main canvas layout, result panels and barista recommendations.
extension _KioskLayout on _CafeKioskScreenState {
  Widget _buildCanvasMainLayout(
    List<Drink> available,
    bool isSpinning,
    double virtualWidth,
  ) {
    const double sideWidth = 480.0;
    const double columnGap = 28.0;

    // Exact logical sizes for the widgets. FittedBox will gracefully scale them down if needed.
    const double headerSlotHeight = 140.0;
    const double rowGap = 24.0;
    const double filterSlotHeight = 400.0;
    const double billCardHeight =
        240.0; // Increased to 240 to prevent 11px overflow
    const double bottomSlotHeight = 240.0;

    return Stack(
      children: [
        if (appThemeNotifier.value == AppTheme.feast)
          const _FeastThemeCandyRain(),
        if (appThemeNotifier.value == AppTheme.newYear)
          const _NewYearThemeSnowRain(),
        // LEFT COLUMN
        Positioned(
          left: 12.0, // daha da yaklastirildi
          top: 32.0,
          bottom: 64.0, // alt pay birakildi
          width: sideWidth,
          // Each area repaints on its own: the pulse and the effects in one
          // must not redraw the shadowed cards of the others every frame.
          child: RepaintBoundary(
            key: const ValueKey('kiosk_left_column'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: headerSlotHeight),
                const SizedBox(height: rowGap),
                Expanded(
                  flex: filterSlotHeight.toInt(),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.center,
                    child: SizedBox(
                      width: sideWidth,
                      height: filterSlotHeight,
                      child: _buildBaristaRecommendation(),
                    ),
                  ),
                ),
                const SizedBox(height: rowGap),
                Expanded(
                  flex: billCardHeight.toInt(),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.center,
                    child: SizedBox(
                      width: sideWidth,
                      height: billCardHeight,
                      child: _buildBillGameCard(),
                    ),
                  ),
                ),
                const SizedBox(height: rowGap),
                Expanded(
                  flex: bottomSlotHeight.toInt(),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.bottomCenter,
                    child: SizedBox(
                      width: sideWidth,
                      height: bottomSlotHeight,
                      child: _buildSocialArea(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // CENTER AREA
        Positioned(
          left: 12.0 + sideWidth + columnGap,
          right: 12.0 + sideWidth + columnGap,
          top: 32.0,
          bottom: 64.0,
          child: RepaintBoundary(
            key: const ValueKey('kiosk_center_area'),
            child: _buildCenterArea(available, isSpinning),
          ),
        ),

        // RIGHT COLUMN
        Positioned(
          right: 12.0, // daha da yaklastirildi
          top: 32.0,
          bottom: 64.0, // alt pay birakildi
          width: sideWidth,
          child: RepaintBoundary(
            key: const ValueKey('kiosk_right_column'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: headerSlotHeight),
                const SizedBox(height: rowGap),
                Expanded(
                  flex: filterSlotHeight.toInt(),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.center,
                    child: SizedBox(
                      width: sideWidth,
                      height: filterSlotHeight,
                      child: _buildRightTopBlankCard(isSpinning),
                    ),
                  ),
                ),
                const SizedBox(height: rowGap),
                Expanded(
                  flex: billCardHeight.toInt(),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.center,
                    child: SizedBox(
                      width: sideWidth,
                      height: billCardHeight,
                      child: _buildResultSwitcher(),
                    ),
                  ),
                ),
                const SizedBox(height: rowGap),
                Expanded(
                  flex: bottomSlotHeight.toInt(),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.bottomCenter,
                    child: SizedBox(
                      width: sideWidth,
                      height: bottomSlotHeight,
                      child: _buildMenuButton(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildResultSwitcher() {
    // Its scale-and-fade transition repaints only this card.
    return RepaintBoundary(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 800),
        switchInCurve: Curves.easeOutBack,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, animation) {
          return FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.95, end: 1.0).animate(animation),
              child: child,
            ),
          );
        },
        child: _showResult && _selectedDrink != null
            ? _buildResultArea(_selectedDrink!)
            : _buildEmptyResultArea(),
      ),
    );
  }

  Widget _buildBaristaRecommendation() {
    final isCompact = MediaQuery.sizeOf(context).width < 700;
    final drink = _currentBaristaDrink;
    final dessert = _currentBaristaDessert;
    // A menu without drinks or desserts to recommend: show only what exists.
    if (drink == null && dessert == null) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isCompact ? 16 : 22),
      decoration: BoxDecoration(
        color: _surface.withValues(alpha: 0.27),
        borderRadius: BorderRadius.circular(isCompact ? 24 : 32),
        border: Border.all(color: _gold.withValues(alpha: 0.25), width: 1.5),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 24),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.star_rounded, color: _gold, size: isCompact ? 24 : 32),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  tr('BARİSTANIN TAVSİYESİ', 'BARISTA\'S PICK'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _gold,
                    fontSize: isCompact ? 20 : 28,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ),
          Expanded(
            child: Center(
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (drink != null)
                      Expanded(
                        child: _buildRecommendationBox(
                          icon: Icons.local_cafe_rounded,
                          label: tr('İçecek', 'Drink'),
                          value: _menuItemName(drink),
                          imagePath: drink.imagePath,
                          remoteImageUrl: drink.remoteImageUrl,
                          heroTag: _productHeroTag('barista', drink),
                          onTap: () => _showProductDetailDialog(
                            drink,
                            heroTag: _productHeroTag('barista', drink),
                          ),
                        ),
                      ),
                    if (drink != null && dessert != null)
                      SizedBox(width: isCompact ? 12 : 16),
                    if (dessert != null)
                      Expanded(
                        child: _buildRecommendationBox(
                          icon: Icons.cake_rounded,
                          label: tr('Tatlı', 'Dessert'),
                          value: _menuItemName(dessert),
                          imagePath: dessert.imagePath,
                          remoteImageUrl: dessert.remoteImageUrl,
                          heroTag: _productHeroTag('barista', dessert),
                          onTap: () => _showProductDetailDialog(
                            dessert,
                            heroTag: _productHeroTag('barista', dessert),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecommendationBox({
    required IconData icon,
    required String label,
    required String value,
    required String? imagePath,
    required String? remoteImageUrl,
    required VoidCallback onTap,
    Object? heroTag,
  }) {
    final isCompact = MediaQuery.sizeOf(context).width < 700;
    return BouncyButton(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          vertical: isCompact ? 16 : 20,
          horizontal: 8,
        ),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.02),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.15),
            width: 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _productHero(
              heroTag,
              Container(
                width: isCompact ? 72 : 88,
                height: isCompact ? 72 : 88,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                clipBehavior: Clip.antiAlias,
                child: _buildMenuImage(
                  fallbackIcon: icon,
                  assetPath: imagePath,
                  remoteImageUrl: remoteImageUrl,
                  cacheWidth: 176,
                ),
              ),
            ),
            SizedBox(height: isCompact ? 14 : 16),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _mutedText.withValues(alpha: 0.9),
                fontSize: isCompact ? 13 : 14,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _cream,
                fontSize: isCompact ? 14 : 16,
                fontWeight: FontWeight.w600,
                height: 1.2,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyResultArea() {
    final isCompact = MediaQuery.sizeOf(context).width < 700;
    return Container(
      key: const ValueKey('empty'),
      width: double.infinity,
      padding: EdgeInsets.all(isCompact ? 12 : 16),
      decoration: BoxDecoration(
        color: _surface.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Fades as a layer: no rebuild or repaint per frame.
          FadeTransition(
            opacity: _pulseController.drive(Tween(begin: 0.3, end: 0.7)),
            child: Icon(
              Icons.coffee_rounded,
              size: isCompact ? 36 : 48,
              color: _gold,
            ),
          ),
          SizedBox(height: isCompact ? 8 : 12),
          Text(
            tr('Kararsız mısın?', 'Undecided?'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: isCompact ? 18 : 22,
              fontWeight: FontWeight.w700,
              color: _cream,
              letterSpacing: 1,
            ),
          ),
          SizedBox(height: isCompact ? 6 : 8),
          Text(
            tr(
              'Damak modunu seç, çarkı çevir,\niçeceğini LUUQ seçsin.',
              'Choose your mood, spin the wheel,\nlet LUUQ select your drink.',
            ),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: isCompact ? 12 : 13,
              color: _mutedText,
              height: 1.4,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRightTopBlankCard(bool isSpinning) {
    final theme = appThemeNotifier.value;
    _MenuItem showcaseItem(_MenuItem item) {
      return _MenuItem(
        item.name,
        item.price,
        item.icon,
        desc: item.desc,
        tags: item.tags,
        imagePath: item.imagePath,
        id: item.id,
        nameEn: item.nameEn,
        descEn: item.descEn,
        tagsEn: item.tagsEn,
        remoteImageUrl: item.remoteImageUrl,
        transparentImagePath:
            item.transparentImagePath ??
            (item.imagePath?.startsWith('assets/') == true
                ? _wheelImagePath(item.imagePath!)
                : null),
        remoteTransparentImageUrl: item.remoteTransparentImageUrl,
      );
    }

    List<_MenuItem> withImages(Iterable<_MenuItem> items) => items
        .where(
          (item) =>
              item.imagePath != null ||
              item.remoteImageUrl != null ||
              item.transparentImagePath != null ||
              item.remoteTransparentImageUrl != null,
        )
        .map(showcaseItem)
        .toList();

    if (theme == AppTheme.winter) {
      return _CocktailShowcaseCard(
        cocktails: withImages(
          _itemsForCategoryIcons([
            Icons.local_cafe_rounded,
            Icons.coffee_maker_rounded,
            Icons.whatshot_rounded,
          ]),
        ),
        onTap: _showProductDetailDialog,
        isSpinning: isSpinning,
      );
    } else if (theme == AppTheme.normal) {
      final allDrinks = withImages(
        _itemsForCategoryIcons([
          Icons.local_cafe_rounded,
          Icons.coffee_maker_rounded,
          Icons.whatshot_rounded,
          Icons.ac_unit_rounded,
          Icons.local_bar_rounded,
          Icons.eco_rounded,
          Icons.severe_cold_rounded,
          Icons.bubble_chart_rounded,
          Icons.icecream_rounded,
          Icons.sports_bar_rounded,
        ]),
      );
      // Shuffle with a stable seed so it rotates consistently without jumping
      allDrinks.shuffle(Random(42));

      return _CocktailShowcaseCard(
        cocktails: allDrinks,
        onTap: _showProductDetailDialog,
        isSpinning: isSpinning,
      );
    } else if (theme == AppTheme.feast) {
      return _CocktailShowcaseCard(
        cocktails: withImages(
          _itemsForCategoryIcons([Icons.cake_rounded, Icons.cookie_rounded]),
        ),
        onTap: _showProductDetailDialog,
        isSpinning: isSpinning,
      );
    } else {
      return _CocktailShowcaseCard(
        cocktails: withImages(
          _itemsForCategoryIcons([Icons.local_bar_rounded]),
        ),
        onTap: _showProductDetailDialog,
        isSpinning: isSpinning,
      );
    }
  }

  Widget _buildResultVisual({
    required Drink drink,
    required String? imagePath,
    required String? remoteImageUrl,
    required double size,
  }) {
    final iconSize = size * 0.58;

    if ((imagePath == null &&
            (remoteImageUrl == null || remoteImageUrl.isEmpty)) &&
        drink.transparentImagePath == null &&
        (drink.remoteTransparentImageUrl == null ||
            drink.remoteTransparentImageUrl!.isEmpty)) {
      return Icon(drink.icon, size: iconSize, color: _gold);
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _gold.withValues(alpha: 0.35), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
          BoxShadow(color: _gold.withValues(alpha: 0.10), blurRadius: 28),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: _buildMenuImage(
        fallbackIcon: drink.icon,
        assetPath: imagePath,
        remoteImageUrl: remoteImageUrl,
        transparentAssetPath: drink.transparentImagePath,
        transparentRemoteImageUrl: drink.remoteTransparentImageUrl,
        preferTransparent: true,
        cacheWidth: 240,
        fit: BoxFit.cover,
      ),
    );
  }
}
