part of '../../main.dart';

enum _AdminSection {
  barista,
  wheel,
  clean,
  analytics,
  theme,
  volume,
  info,
  exit,
}

class _AdminHubDialog extends StatelessWidget {
  const _AdminHubDialog();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<LicenseStatus>(
      valueListenable: LicenseService.instance.statusNotifier,
      builder: (context, status, _) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            width: 520,
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: const Color(0xFF1C1724),
              borderRadius: BorderRadius.circular(34),
              border: Border.all(color: _gold.withValues(alpha: 0.24)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.65),
                  blurRadius: 56,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.admin_panel_settings_rounded,
                      color: _gold,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        tr('Admin Menüsü', 'Admin Menu'),
                        style: const TextStyle(
                          color: _cream,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                      color: _muted,
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _AdminSectionButton(
                  icon: Icons.auto_awesome_rounded,
                  title: tr('Barista Önerisi', "Barista's Pick"),
                  subtitle: tr(
                    'Ana ekrandaki tavsiye içecek ve tatlıyı değiştir.',
                    'Change the recommended drink and dessert on the main screen.',
                  ),
                  isLocked: !status.features.baristaRecommendation,
                  onTap: () {
                    if (!status.features.baristaRecommendation) {
                      showFeatureLockedDialog(
                        context,
                        tr('Barista Önerisi', "Barista's Pick"),
                        customMessage: tr(
                          'Bu özellik lisansınızda aktif değil.',
                          'This feature is not active in your license.',
                        ),
                        screen: 'admin_menu',
                        featureKey: 'barista_recommendation_updated',
                      );
                      return;
                    }
                    Navigator.of(context).pop(_AdminSection.barista);
                  },
                ),
                const SizedBox(height: 14),
                _AdminSectionButton(
                  icon: Icons.casino_rounded,
                  title: tr('Çark İçeriği', 'Wheel Items'),
                  subtitle: tr(
                    'Ana çarktaki 8 menü ürününü seç.',
                    'Select the 8 menu items on the wheel.',
                  ),
                  isLocked: !status.features.wheelContent,
                  onTap: () {
                    if (!status.features.wheelContent) {
                      showFeatureLockedDialog(
                        context,
                        tr('Çark İçeriği', 'Wheel Items'),
                        customMessage: tr(
                          'Bu özellik lisansınızda aktif değil.',
                          'This feature is not active in your license.',
                        ),
                        screen: 'admin_menu',
                        featureKey: 'wheel_content_updated',
                      );
                      return;
                    }
                    Navigator.of(context).pop(_AdminSection.wheel);
                  },
                ),
                const SizedBox(height: 14),
                _AdminSectionButton(
                  icon: Icons.cleaning_services_rounded,
                  title: tr('Ekran Temizleme Modu', 'Screen Cleaning Mode'),
                  subtitle: tr(
                    'Ekranı 30 saniyeliğine karartır ve dokunmatiği kilitler.',
                    'Dims screen for 30 seconds and locks touch.',
                  ),
                  customColor: Colors.lightBlueAccent,
                  isLocked: !status.features.cleaningMode,
                  onTap: () {
                    if (!status.features.cleaningMode) {
                      showFeatureLockedDialog(
                        context,
                        tr('Ekran Temizleme Modu', 'Screen Cleaning Mode'),
                        customMessage: tr(
                          'Bu özellik lisansınızda aktif değil.',
                          'This feature is not active in your license.',
                        ),
                        screen: 'admin_menu',
                        featureKey: 'cleaning_mode_started',
                      );
                      return;
                    }
                    Navigator.of(context).pop(_AdminSection.clean);
                  },
                ),
                const SizedBox(height: 14),
                _AdminSectionButton(
                  icon: Icons.bar_chart_rounded,
                  title: tr('Analizler', 'Analytics'),
                  subtitle: tr(
                    'Menü tıklamaları, çark çevrimleri ve hesap kimde istatistikleri.',
                    'Menu clicks, wheel spins, and who pays game statistics.',
                  ),
                  customColor: Colors.amberAccent,
                  isLocked: !status.features.analytics,
                  onTap: () {
                    if (!status.features.analytics) {
                      showFeatureLockedDialog(
                        context,
                        tr('Analizler', 'Analytics'),
                        customMessage: tr(
                          'Bu özellik lisansınızda aktif değil.',
                          'This feature is not active in your license.',
                        ),
                        screen: 'admin_menu',
                        featureKey: 'analytics_opened',
                      );
                      return;
                    }
                    Navigator.of(context).pop(_AdminSection.analytics);
                  },
                ),
                const SizedBox(height: 14),
                _AdminSectionButton(
                  icon: Icons.palette_rounded,
                  title: tr('Uygulama Teması', 'App Theme'),
                  subtitle: tr(
                    'Yaz, Kış, Bayram ve Yılbaşı temaları arasında geçiş yap.',
                    'Switch between Summer, Winter, Holiday, and New Year themes.',
                  ),
                  customColor: Colors.purpleAccent,
                  isLocked: !status.features.themes,
                  onTap: () {
                    if (!status.features.themes) {
                      showFeatureLockedDialog(
                        context,
                        tr('Uygulama Teması', 'App Theme'),
                        customMessage: tr(
                          'Bu özellik lisansınızda aktif değil.',
                          'This feature is not active in your license.',
                        ),
                        screen: 'admin_menu',
                        featureKey: 'theme_changed',
                      );
                      return;
                    }
                    Navigator.of(context).pop(_AdminSection.theme);
                  },
                ),
                const SizedBox(height: 14),
                _AdminSectionButton(
                  icon: Icons.volume_up_rounded,
                  title: tr('Ses Seviyesi', 'Volume Level'),
                  subtitle: tr(
                    'Kiosk ses seviyesini ayarla (%0, %25, %50, %75, %100).',
                    'Adjust kiosk volume level (0%, 25%, 50%, 75%, 100%).',
                  ),
                  customColor: Colors.pinkAccent,
                  isLocked: !status.features.volumeControl,
                  onTap: () {
                    if (!status.features.volumeControl) {
                      showFeatureLockedDialog(
                        context,
                        tr('Ses Seviyesi', 'Volume Level'),
                        customMessage: tr(
                          'Bu özellik lisansınızda aktif değil.',
                          'This feature is not active in your license.',
                        ),
                        screen: 'admin_menu',
                        featureKey: 'volume_changed',
                      );
                      return;
                    }
                    Navigator.of(context).pop(_AdminSection.volume);
                  },
                ),
                const SizedBox(height: 14),
                _AdminSectionButton(
                  icon: Icons.info_outline_rounded,
                  title: tr('Uygulama Bilgileri', 'App Information'),
                  subtitle: tr('Geliştirici Sekmesi', 'Developer Tab'),
                  customColor: Colors.tealAccent,
                  onTap: () => Navigator.of(context).pop(_AdminSection.info),
                ),
                const SizedBox(height: 14),
                _AdminSectionButton(
                  icon: Icons.power_settings_new_rounded,
                  title: tr('Uygulamadan Çık', 'Exit App'),
                  subtitle: tr(
                    'Kiosk modunu kapatır ve masaüstüne döner.',
                    'Close kiosk mode and return to desktop.',
                  ),
                  customColor: Colors.redAccent,
                  isLocked: !status.features.manualExit,
                  onTap: () {
                    if (!status.features.manualExit) {
                      showFeatureLockedDialog(
                        context,
                        tr('Uygulamadan Çık', 'Exit App'),
                        customMessage: tr(
                          'Bu özellik lisansınızda aktif değil.',
                          'This feature is not active in your license.',
                        ),
                        screen: 'admin_menu',
                        featureKey: 'manual_exit_clicked',
                      );
                      return;
                    }
                    Navigator.of(context).pop(_AdminSection.exit);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AdminSectionButton extends StatelessWidget {
  const _AdminSectionButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.customColor,
    this.isLocked = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color? customColor;
  final bool isLocked;

  @override
  Widget build(BuildContext context) {
    return BouncyButton(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: isLocked
              ? _bgDark.withValues(alpha: 0.3)
              : _bgDark.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: isLocked
                ? _gold.withValues(alpha: 0.15)
                : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Row(
          children: [
            Opacity(
              opacity: isLocked ? 0.5 : 1.0,
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: (customColor ?? _gold).withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: customColor ?? _gold),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Opacity(
                opacity: isLocked ? 0.5 : 1.0,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: customColor ?? _cream,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: _mutedText,
                        fontSize: _fsCaption,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Icon(
              isLocked ? Icons.lock_rounded : Icons.chevron_right_rounded,
              color: isLocked ? _gold : _muted,
            ),
          ],
        ),
      ),
    );
  }
}
