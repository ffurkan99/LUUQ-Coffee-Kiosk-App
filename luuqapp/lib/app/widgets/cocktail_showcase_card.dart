part of '../../main.dart';

class _CocktailShowcaseCard extends StatefulWidget {
  final List<_MenuItem> cocktails;
  final ValueChanged<_MenuItem> onTap;
  final bool isSpinning;

  const _CocktailShowcaseCard({
    required this.cocktails,
    required this.onTap,
    required this.isSpinning,
  });

  @override
  State<_CocktailShowcaseCard> createState() => _CocktailShowcaseCardState();
}

class _CocktailShowcaseCardState extends State<_CocktailShowcaseCard>
    with WidgetsBindingObserver {
  int _currentIndex = 0;
  bool _reduceMotion = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startTimer();
  }

  @override
  void didUpdateWidget(covariant _CocktailShowcaseCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldNames = oldWidget.cocktails.map((item) => item.name).toList();
    final newNames = widget.cocktails.map((item) => item.name).toList();
    final listChanged = !listEquals(oldNames, newNames);
    if (listChanged) {
      final previousName = _currentIndex < oldNames.length
          ? oldNames[_currentIndex]
          : null;
      final retainedIndex = previousName == null
          ? -1
          : newNames.indexOf(previousName);
      _currentIndex = retainedIndex < 0 ? 0 : retainedIndex;
    }
    if (listChanged || widget.isSpinning != oldWidget.isSpinning) {
      if (widget.isSpinning) {
        _stopTimer();
      } else {
        _startTimer();
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _startTimer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopTimer();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !widget.isSpinning) {
      _startTimer();
    } else {
      _stopTimer();
    }
  }

  void _startTimer() {
    _stopTimer();
    final lifecycleState = WidgetsBinding.instance.lifecycleState;
    if (_reduceMotion ||
        widget.isSpinning ||
        widget.cocktails.isEmpty ||
        (lifecycleState != null &&
            lifecycleState != AppLifecycleState.resumed)) {
      return;
    }
    _timer = Timer.periodic(const Duration(milliseconds: 4500), (timer) {
      if (mounted) {
        setState(() {
          _currentIndex = (_currentIndex + 1) % widget.cocktails.length;
        });
      }
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.cocktails.isEmpty) return const SizedBox.shrink();

    final isCompact = MediaQuery.sizeOf(context).width < 700;
    final item = widget.cocktails[_currentIndex];

    // Vibrant gradient lists for fallback cocktail placeholder
    final gradients = [
      [
        const Color(0xFFF9AB3E),
        const Color(0xFFE879A8),
      ], // sunset orange to pink
      [
        const Color(0xFF4ECDC4),
        const Color(0xFF45AAF2),
      ], // turquoise to ocean blue
      [
        const Color(0xFFFF7675),
        const Color(0xFFFDA7DF),
      ], // soft red to lavender
      [const Color(0xFF74B9FF), const Color(0xFFA29BFE)], // blue to violet
      [const Color(0xFF55EFC4), const Color(0xFF4ECDC4)], // mint to teal
    ];
    final activeGradient = gradients[_currentIndex % gradients.length];

    final theme = appThemeNotifier.value;
    final Color themeColor;
    final IconData themeIcon;
    final String themeTitle;
    final Color badgeColor;
    final String badgeText;

    if (theme == AppTheme.winter) {
      themeColor = Colors.lightBlueAccent;
      themeIcon = Icons.ac_unit_rounded;
      themeTitle = tr('KIŞIN NE GİDER ?', 'WINTER FAVS ?');
      badgeColor = const Color(0xFF74B9FF);
      badgeText = tr('SICAK KAHVE', 'HOT DRINK');
    } else if (theme == AppTheme.normal) {
      themeColor = Colors.tealAccent;
      themeIcon = Icons.coffee_rounded;
      themeTitle = tr('BUGÜN NE İÇSEK?', 'WHAT TO DRINK TODAY?');
      badgeColor = Colors.tealAccent;
      badgeText = tr('İÇECEK', 'DRINK');
    } else if (theme == AppTheme.newYear) {
      themeColor = Colors.redAccent;
      themeIcon = Icons.forest_rounded;
      themeTitle = tr('YENİ YILDA NE GİDER ?', 'NEW YEAR FAVS ?');
      badgeColor = Colors.redAccent;
      badgeText = tr('YENİ YIL', 'NEW YEAR');
    } else if (theme == AppTheme.feast) {
      themeColor = Colors.greenAccent;
      themeIcon = Icons.celebration_rounded;
      themeTitle = tr('BAYRAM ŞEKERLERİ', 'BAYRAM SWEETS');
      badgeColor = Colors.greenAccent;
      badgeText = tr('TATLI', 'SWEET');
    } else {
      // Default / Summer
      themeColor = _gold;
      themeIcon = Icons.wb_sunny_rounded;
      themeTitle = tr('YAZIN NE GİDER ?', 'SUMMER FAVS ?');
      badgeColor = const Color(0xFF4ECDC4);
      badgeText = tr('KOKTEYL', 'COCKTAIL');
    }

    return BouncyButton(
      onTap: () => widget.onTap(item),
      child: Container(
        width: double.infinity,
        height: double.infinity,
        padding: EdgeInsets.all(isCompact ? 16 : 22),
        decoration: BoxDecoration(
          color: _surface.withValues(alpha: 0.27),
          borderRadius: BorderRadius.circular(isCompact ? 24 : 32),
          border: Border.all(
            color: themeColor.withValues(alpha: 0.25),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 24,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Slot (Summer/Winter dynamic)
            Row(
              children: [
                _RotatingIcon(icon: themeIcon, color: themeColor, size: 26),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    themeTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: themeColor,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                // Glowing badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: badgeColor.withValues(alpha: 0.5),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    badgeText,
                    style: TextStyle(
                      color: badgeColor,
                      fontSize: _fsBadge,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Carousel Showcase
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 600),
                switchInCurve: Curves.easeInOutCubic,
                switchOutCurve: Curves.easeInOutCubic,
                transitionBuilder: (Widget child, Animation<double> animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position:
                          Tween<Offset>(
                            begin: child.key == ValueKey(_currentIndex)
                                ? const Offset(0.18, 0.0)
                                : const Offset(-0.18, 0.0),
                            end: Offset.zero,
                          ).animate(
                            CurvedAnimation(
                              parent: animation,
                              curve: Curves.easeInOutCubic,
                            ),
                          ),
                      child: child,
                    ),
                  );
                },
                child: KeyedSubtree(
                  key: ValueKey(_currentIndex),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Showcase Image
                      Expanded(
                        child: Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.08),
                              width: 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.2),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              // Vibrant background summer gradient pool
                              Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: activeGradient,
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                ),
                              ),

                              if (item.imagePath != null ||
                                  item.remoteImageUrl != null ||
                                  item.transparentImagePath != null ||
                                  item.remoteTransparentImageUrl != null)
                                Padding(
                                  padding: const EdgeInsets.all(12.0),
                                  child: _buildMenuImage(
                                    fallbackIcon: Icons.local_bar_rounded,
                                    assetPath: item.imagePath,
                                    remoteImageUrl: item.remoteImageUrl,
                                    transparentAssetPath:
                                        item.transparentImagePath,
                                    transparentRemoteImageUrl:
                                        item.remoteTransparentImageUrl,
                                    preferTransparent: true,
                                    // Vitrin 4,5 sn'de bir ürün değiştirir;
                                    // tam çözünürlük decode önbelleği şişirir.
                                    cacheWidth: 640,
                                    fit: BoxFit.contain,
                                  ),
                                )
                              else
                                const Center(
                                  child: Icon(
                                    Icons.local_bar_rounded,
                                    color: Colors.white70,
                                    size: 64,
                                  ),
                                ),

                              // Dark vignette overlay at bottom of image
                              Positioned.fill(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        Colors.black.withValues(alpha: 0.0),
                                        Colors.black.withValues(alpha: 0.35),
                                      ],
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Details Area
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Cocktail Name
                                ShaderMask(
                                  shaderCallback: (bounds) => LinearGradient(
                                    colors: [_cream, activeGradient.first],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ).createShader(bounds),
                                  child: Text(
                                    _menuItemName(item),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.white,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                // Description
                                Text(
                                  _menuItemDescription(item),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: _fsCaption,
                                    color: _cream.withValues(alpha: 0.7),
                                    height: 1.3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Price Badge
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: _gold.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: _gold.withValues(alpha: 0.35),
                                width: 1.2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: _gold.withValues(alpha: 0.05),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  item.price,
                                  style: const TextStyle(
                                    color: _gold,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(
                                  Icons.arrow_forward_ios_rounded,
                                  color: _gold,
                                  size: 10,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      // Secondary details: Tag pills row
                      if (item.tags.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: item.tags.map((tag) {
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
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
