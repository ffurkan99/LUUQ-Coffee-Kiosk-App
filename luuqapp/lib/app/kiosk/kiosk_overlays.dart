part of '../../main.dart';

/// Update badge, maintenance/update-required cover, loading screen and the idle (AFK) overlay.
extension _KioskOverlays on _CafeKioskScreenState {
  Widget _buildUpdateBadge(BuildContext context, LicenseStatus status) {
    if (!_hasTrackedUpdateSeen) {
      _hasTrackedUpdateSeen = true;
      AnalyticsService.instance.trackEvent(
        AnalyticsEvent(eventType: 'update_available_seen', screen: 'home'),
      );
    }
    return InkWell(
      onTap: () {
        AnalyticsService.instance.trackEvent(
          AnalyticsEvent(eventType: 'update_prompt_opened', screen: 'home'),
        );
        _showUpdateDialog(context, status);
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF9AB3E).withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: const Color(0xFFF9AB3E).withValues(alpha: 0.5),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Color(0xFFF9AB3E),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              tr('Yeni Sürüm Mevcut', 'New Version Available'),
              style: const TextStyle(
                color: Color(0xFFFFF7EC),
                fontSize: 14,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServiceBlockOverlay(({String title, String body}) message) {
    return AbsorbPointer(
      child: Container(
        color: const Color(0xF216131D),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 48),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.construction_rounded,
                color: Color(0xFFF9AB3E),
                size: 64,
              ),
              const SizedBox(height: 24),
              Text(
                message.title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _cream,
                  fontSize: 34,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                message.body,
                textAlign: TextAlign.center,
                style: const TextStyle(color: _mutedText, fontSize: 22),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingScreen() {
    return Container(
      decoration: const BoxDecoration(
        color: _bgDark,
        gradient: RadialGradient(
          colors: [Color(0xFF282136), _bgDark],
          radius: 1.2,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Pulsing Logo (own layer: the idle screen is not redrawn per
            // frame).
            RepaintBoundary(
              child: AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  final scale = 0.96 + (_pulseController.value * 0.08);
                  return Transform.scale(scale: scale, child: child);
                },
                child: Image.asset(
                  'assets/logo.png',
                  width: 250,
                  height: 250,
                  cacheWidth: _logoCacheWidth,
                  fit: BoxFit.contain,
                  errorBuilder: (c, e, s) => const Icon(
                    Icons.restaurant_menu_rounded,
                    color: _gold,
                    size: 100,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 48),
            // Brand Subtitle
            Text(
              tr('LUUQ COFFEE ROASTERY', 'LUUQ COFFEE ROASTERY'),
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: 8,
                color: _gold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              tr('LEZZET DENEYİMİ YÜKLENİYOR', 'LOADING FLAVOR EXPERIENCE'),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                letterSpacing: 4,
                color: _cream.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 60),
            // Progress Bar Container
            Container(
              width: 500,
              height: 8,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withValues(alpha: 0.03)),
              ),
              child: Stack(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 100),
                    width: 500 * _loadingProgress,
                    height: 8,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [_gold, _caramel]),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: _gold.withValues(alpha: 0.4),
                          blurRadius: 12,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // Status Text
            Text(
              _loadingStatus,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: _cream.withValues(alpha: 0.7),
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAfkOverlayContent(BoxConstraints constraints) {
    final isCompact = constraints.maxWidth < 700;
    final horizontalPadding = isCompact ? 16.0 : 32.0;
    final contentWidth = min(
      constraints.maxWidth - (horizontalPadding * 2),
      isCompact ? 520.0 : 720.0,
    );

    return Stack(
      children: [
        if (appThemeNotifier.value == AppTheme.feast)
          const _FeastThemeCandyRain(count: 15),
        Align(
          alignment: Alignment(0, isCompact ? 0.70 : 0.78),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: SizedBox(
                width: contentWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RepaintBoundary(
                      child: AnimatedBuilder(
                        animation: _pulseController,
                        builder: (context, child) {
                          final offset = -1.4 + (_pulseController.value * 2.8);
                          return ShaderMask(
                            blendMode: BlendMode.srcIn,
                            shaderCallback: (bounds) {
                              return LinearGradient(
                                colors: const [
                                  Colors.white,
                                  Colors.white,
                                  _gold,
                                  _caramel,
                                  Colors.white,
                                  Colors.white,
                                ],
                                stops: const [0.0, 0.30, 0.45, 0.52, 0.68, 1.0],
                                begin: Alignment(offset - 1.0, 0),
                                end: Alignment(offset + 1.0, 0),
                              ).createShader(bounds);
                            },
                            child: child,
                          );
                        },
                        child: Text(
                          appThemeNotifier.value == AppTheme.feast
                              ? tr('BAYRAMINIZ KUTLU OLSUN', 'HAPPY EID')
                              : tr('HOŞGELDİNİZ', 'WELCOME'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: isCompact
                                ? (appThemeNotifier.value == AppTheme.feast
                                      ? 28
                                      : 38)
                                : (appThemeNotifier.value == AppTheme.feast
                                      ? 46
                                      : 56),
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: isCompact ? 2 : 4,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: isCompact ? 16 : 22),
                    _buildAfkConnections(isCompact: isCompact),
                    SizedBox(height: isCompact ? 20 : 28),
                    FadeTransition(
                      opacity: _pulseController.drive(
                        Tween<double>(begin: 0.3, end: 1.0),
                      ),
                      child: Text(
                        tr(
                          'Başlamak için ekrana dokunun',
                          'Tap the screen to start',
                        ),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: isCompact ? 16 : 24,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withValues(alpha: 0.9),
                          letterSpacing: isCompact ? 1.5 : 3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAfkConnections({required bool isCompact}) {
    final qrSize = isCompact ? 62.0 : 88.0;
    final cardWidth = isCompact ? double.infinity : 560.0;
    final slideDistance = isCompact ? 0.08 : 0.12;

    return TweenAnimationBuilder<Offset>(
      key: ValueKey(_isIdle),
      tween: Tween<Offset>(
        begin: _isIdle ? Offset(-slideDistance, 0) : Offset.zero,
        end: _isIdle ? Offset.zero : Offset(slideDistance, 0),
      ),
      duration: const Duration(milliseconds: 1400),
      curve: Curves.easeInOutQuint,
      builder: (context, offset, child) {
        return FractionalTranslation(translation: offset, child: child);
      },
      child: Container(
        width: cardWidth,
        padding: EdgeInsets.symmetric(
          horizontal: isCompact ? 14 : 22,
          vertical: isCompact ? 14 : 18,
        ),
        decoration: BoxDecoration(
          color: _surface.withValues(alpha: 0.34),
          borderRadius: BorderRadius.circular(isCompact ? 24 : 30),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.22),
              blurRadius: 28,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              tr('BAĞLANTILARIMIZ', 'OUR CONNECTIONS'),
              style: TextStyle(
                color: _gold,
                fontSize: _fsCaption,
                fontWeight: FontWeight.w900,
                letterSpacing: 3,
              ),
            ),
            SizedBox(height: isCompact ? 12 : 14),
            Row(
              children: [
                Expanded(
                  child: _buildAfkQrItem(
                    assetPath: 'assets/instagramqr.png',
                    title: 'INSTAGRAM',
                    size: qrSize,
                  ),
                ),
                _buildAfkDivider(isCompact),
                Expanded(
                  child: _buildAfkQrItem(
                    assetPath: 'assets/mapsqr.png',
                    title: 'GOOGLE MAPS',
                    size: qrSize,
                  ),
                ),
                _buildAfkDivider(isCompact),
                Expanded(
                  child: _buildAfkQrItem(
                    assetPath: 'assets/wifiqr.png',
                    title: 'LUUQ WI-FI',
                    size: qrSize,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAfkDivider(bool isCompact) {
    return Container(
      width: 1,
      height: isCompact ? 58 : 78,
      margin: EdgeInsets.symmetric(horizontal: isCompact ? 6 : 10),
      color: Colors.white.withValues(alpha: 0.13),
    );
  }

  Widget _buildAfkQrItem({
    required String assetPath,
    required String title,
    required double size,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.asset(
            assetPath,
            width: size,
            height: size,
            cacheWidth: _qrCacheWidth,
            fit: BoxFit.cover,
          ),
        ),
        const SizedBox(height: 8),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            title,
            maxLines: 1,
            style: const TextStyle(
              color: _cream,
              fontSize: _fsBadge,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
            ),
          ),
        ),
      ],
    );
  }
}
