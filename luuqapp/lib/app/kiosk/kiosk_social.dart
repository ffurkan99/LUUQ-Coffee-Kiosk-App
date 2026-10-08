part of '../../main.dart';

/// Who-pays card, menu button, QR codes and social links.
extension _KioskSocial on _CafeKioskScreenState {
  Widget _buildBillGameCard() {
    final isCompact = MediaQuery.sizeOf(context).width < 700;

    Widget content = Container(
      width: double.infinity,
      padding: EdgeInsets.all(isCompact ? 16 : 22),
      decoration: BoxDecoration(
        color: _surface.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 20),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.groups_rounded,
                color: _mint,
                size: isCompact ? 24 : 32,
              ),
              const SizedBox(width: 12),
              Text(
                tr('HESAP KİMDE?', 'WHO PAYS?'),
                style: TextStyle(
                  fontSize: isCompact ? 20 : 28,
                  fontWeight: FontWeight.w900,
                  color: _mint,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            tr(
              'Hesabı kimin ödeyeceğini heyecanlı bir şekilde belirle!',
              'Determine who pays the bill in an exciting way!',
            ),
            style: TextStyle(
              fontSize: isCompact ? 15 : 18,
              color: _mutedText,
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: isCompact ? 16 : 14),
          BouncyButton(
            onTap: () async {
              if (!currentFeatureFlags.whoPays) {
                showFeatureLockedDialog(context, tr('Hesap Kimde', 'Who Pays'));
                return;
              }
              await _showCustomerDialog(
                const _HesapKimdeDialog(),
                'HesapKimde',
                barrierDismissible: false,
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: _bgDark,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _mint.withValues(alpha: 0.4)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.casino_rounded, color: _mint, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    tr('Mini Çarkı Aç', 'Open Mini Wheel'),
                    style: const TextStyle(
                      color: _mint,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    if (!currentFeatureFlags.whoPays) {
      return BouncyButton(
        onTap: () =>
            showFeatureLockedDialog(context, tr('Hesap Kimde', 'Who Pays')),
        child: Stack(
          children: [
            Opacity(opacity: 0.4, child: content),
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(32),
                ),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1C1724).withValues(alpha: 0.8),
                      shape: BoxShape.circle,
                      border: Border.all(color: _gold.withValues(alpha: 0.5)),
                    ),
                    child: const Icon(
                      Icons.lock_rounded,
                      color: _gold,
                      size: 28,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return content;
  }

  Widget _buildMenuButton() {
    final isCompact = MediaQuery.sizeOf(context).width < 700;
    return BouncyButton(
      onTap: () async {
        if (!currentFeatureFlags.menu) {
          showFeatureLockedDialog(context, tr('Ürün Menüsü', 'Product Menu'));
          return;
        }
        unawaited(_LuuqAnalytics.instance.incrementMenuClicks());
        await _showCustomerDialog(const _MenuDialog(), 'Menu');
      },
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(vertical: isCompact ? 20 : 32),
        decoration: BoxDecoration(
          color: _gold,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: _gold.withValues(alpha: 0.3),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.menu_book_rounded,
              color: _bgDark,
              size: isCompact ? 38 : 56,
            ),
            SizedBox(height: isCompact ? 10 : 16),
            Text(
              tr('TÜM MENÜYÜ İNCELE', 'BROWSE FULL MENU'),
              style: TextStyle(
                fontSize: isCompact ? 16 : 22,
                fontWeight: FontWeight.w900,
                color: _bgDark,
                letterSpacing: isCompact ? 0.8 : 2,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  /// Opens a customer dialog (menu, who pays). The idle timer keeps running
  /// with a longer timeout, so a dialog left open still returns the kiosk to
  /// its idle screen; the timeout closes open dialogs.
  Future<void> _showCustomerDialog(
    Widget dialog,
    String name, {
    bool barrierDismissible = true,
  }) async {
    GlobalDialogTracker.isCustomerDialogOpen = true;
    _resetIdleTimer();
    try {
      await _showAnimatedDialog(
        dialog,
        name,
        barrierDismissible: barrierDismissible,
      );
    } finally {
      GlobalDialogTracker.isCustomerDialogOpen = false;
    }
    if (mounted) _resetIdleTimer();
  }

  Future<void> _showAnimatedDialog(
    Widget dialogWidget,
    String label, {
    bool barrierDismissible = true,
  }) {
    return _showKioskDialog<void>(
      context,
      dialogWidget,
      label: label,
      barrierDismissible: barrierDismissible,
    );
  }

  void _showLargeQR(String assetPath, String title) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'LargeQR',
      barrierColor: Colors.black.withValues(alpha: 0.40),
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (context, anim1, anim2) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5.0, sigmaY: 5.0),
          child: GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Scaffold(
              backgroundColor: Colors.transparent,
              body: _VirtualCanvasDialogWrapper(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      tr('KAPATMAK İÇİN DOKUNUN', 'TAP TO CLOSE'),
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 4,
                      ),
                    ),
                    const SizedBox(height: 40),
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(40),
                        boxShadow: [
                          BoxShadow(
                            color: _gold.withValues(alpha: 0.3),
                            blurRadius: 100,
                            spreadRadius: 20,
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: Image.asset(
                          assetPath,
                          width: 500,
                          height: 500,
                          cacheWidth: _qrCacheWidth,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    const SizedBox(height: 40),
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 54,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 6,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, anim1, anim2, child) {
        return FadeTransition(
          opacity: anim1,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.9, end: 1.0).animate(
              CurvedAnimation(
                parent: anim1,
                curve: Curves.easeOutCubic,
                reverseCurve: Curves.easeIn,
              ),
            ),
            child: child,
          ),
        );
      },
    );
  }

  Widget _buildSocialArea() {
    final isCompact = MediaQuery.sizeOf(context).width < 700;
    final qrSize = isCompact ? 82.0 : 102.0;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 16 : 18,
        vertical: isCompact ? 16 : 14,
      ),
      decoration: BoxDecoration(
        color: _surface.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 20),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          RepaintBoundary(
            child: AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                // Pulse controller goes 0 -> 1 -> 0. We'll map this to a sweeping offset.
                final offset = -1.0 + (_pulseController.value * 2.0);
                return ShaderMask(
                  blendMode: BlendMode.srcIn,
                  shaderCallback: (bounds) {
                    return LinearGradient(
                      colors: [_gold, _gold, Colors.white, _gold, _gold],
                      stops: const [0.0, 0.35, 0.5, 0.65, 1.0],
                      begin: Alignment(offset - 1.5, 0.0),
                      end: Alignment(offset + 1.5, 0.0),
                    ).createShader(bounds);
                  },
                  child: Text(
                    tr('BAĞLANTILARIMIZ', 'OUR CONNECTIONS'),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 3,
                      color: Colors.white,
                    ),
                  ),
                );
              },
            ),
          ),
          SizedBox(height: isCompact ? 16 : 10),
          if (isCompact)
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 14,
              runSpacing: 18,
              children: [
                _buildSocialQrItem(
                  assetPath: 'assets/instagramqr.png',
                  linkType: 'instagram',
                  title: 'INSTAGRAM',
                  size: qrSize,
                ),
                _buildSocialQrItem(
                  assetPath: 'assets/mapsqr.png',
                  linkType: 'maps',
                  title: 'GOOGLE MAPS',
                  size: qrSize,
                ),
                _buildSocialQrItem(
                  assetPath: 'assets/wifiqr.png',
                  linkType: 'wifi',
                  title: 'LUUQ WI-FI',
                  size: qrSize,
                ),
              ],
            )
          else
            Row(
              children: [
                Expanded(
                  child: _buildSocialQrItem(
                    assetPath: 'assets/instagramqr.png',
                    linkType: 'instagram',
                    title: 'INSTAGRAM',
                    size: qrSize,
                  ),
                ),
                _buildSocialDivider(),
                Expanded(
                  child: _buildSocialQrItem(
                    assetPath: 'assets/mapsqr.png',
                    linkType: 'maps',
                    title: 'GOOGLE MAPS',
                    size: qrSize,
                  ),
                ),
                _buildSocialDivider(),
                Expanded(
                  child: _buildSocialQrItem(
                    assetPath: 'assets/wifiqr.png',
                    linkType: 'wifi',
                    title: 'LUUQ WI-FI',
                    size: qrSize,
                  ),
                ),
              ],
            ),
          const SizedBox(height: 16),
          FadeTransition(
            opacity: _pulseController.drive(
              Tween<double>(begin: 0.35, end: 0.8),
            ),
            child: Text(
              tr('BÜYÜTMEK İÇİN DOKUNUN', 'TAP TO ENLARGE'),
              style: const TextStyle(
                color: _cream,
                fontSize: _fsCaption,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSocialDivider() {
    return Container(
      width: 1,
      height: 92,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: Colors.white.withValues(alpha: 0.13),
    );
  }

  Widget _buildSocialQrItem({
    required String assetPath,
    required String title,
    required String linkType,
    required double size,
  }) {
    return BouncyButton(
      onTap: () {
        // Explicit type: guessing from the title counted Wi-Fi taps as
        // "other" ("LUUQ WI-FI" never contains "wifi").
        AnalyticsService.instance.trackQrClick(linkType);
        AnalyticsService.instance.trackLinksClick();
        _showLargeQR(assetPath, title);
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
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
                fontSize: _fsCaption,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
