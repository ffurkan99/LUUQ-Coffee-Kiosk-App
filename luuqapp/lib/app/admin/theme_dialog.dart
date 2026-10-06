part of '../../main.dart';

// ===== UYGULAMA TEMASI SEÇİM DİYALOGU =====

class _ThemeSelectionDialog extends StatefulWidget {
  const _ThemeSelectionDialog();

  @override
  State<_ThemeSelectionDialog> createState() => _ThemeSelectionDialogState();
}

class _ThemeSelectionDialogState extends State<_ThemeSelectionDialog> {
  AppTheme _selectedTheme = AppTheme.summer;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _selectedTheme = appThemeNotifier.value;
  }

  Future<void> _onThemeSelected(AppTheme theme) async {
    if (_isSaving || theme == _selectedTheme) return;

    final previousTheme = _selectedTheme;
    final oldThemeName = appThemeNotifier.value.name;
    setState(() {
      _isSaving = true;
      _selectedTheme = theme;
    });

    final saved = await _saveAppTheme(theme);
    if (!mounted) return;

    setState(() {
      _isSaving = false;
      if (!saved) {
        _selectedTheme = previousTheme;
      }
    });

    if (!saved) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(
              'Tema kaydedilemedi. Önceki tema kullanılmaya devam edecek.',
              'Theme could not be saved. The previous theme will remain active.',
            ),
            style: const TextStyle(color: _cream, fontWeight: FontWeight.bold),
          ),
          backgroundColor: const Color(0xFF231E2D),
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    AnalyticsService.instance.trackThemeChanged(oldThemeName, theme.name);

    final String themeName = theme == AppTheme.summer
        ? tr('Yaz Modu', 'Summer Mode')
        : theme == AppTheme.winter
        ? tr('Kış Modu', 'Winter Mode')
        : theme == AppTheme.feast
        ? tr('Bayram Modu', 'Bayram Mode')
        : theme == AppTheme.newYear
        ? tr('Yılbaşı Modu', 'New Year Mode')
        : tr('Normal Mod', 'Normal Mode');

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          tr('$themeName aktif edildi!', '$themeName has been activated!'),
          style: const TextStyle(color: _cream, fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF231E2D),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 680,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1724),
          borderRadius: BorderRadius.circular(36),
          border: Border.all(
            color: Colors.purpleAccent.withValues(alpha: 0.24),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.7),
              blurRadius: 64,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.purpleAccent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.palette_rounded,
                    color: Colors.purpleAccent,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr('UYGULAMA TEMASI', 'APPLICATION THEME'),
                        style: const TextStyle(
                          color: _cream,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        tr(
                          'Kiosk Görünüm Modunu Değiştirin',
                          'Change Kiosk Visual Mode',
                        ),
                        style: const TextStyle(
                          color: _mutedText,
                          fontSize: _fsCaption,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                  color: _muted,
                ),
              ],
            ),
            const SizedBox(height: 28),

            // Grid of Themes
            GridView.count(
              shrinkWrap: true,
              crossAxisCount: 2,
              crossAxisSpacing: 20,
              mainAxisSpacing: 20,
              childAspectRatio: 1.6,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildThemeCard(
                  theme: AppTheme.normal,
                  title: tr('Normal Mod', 'Normal Mode'),
                  subtitle: tr(
                    'Sade görünüm, içecek önerileriyle',
                    'Simple appearance with drink suggestions',
                  ),
                  icon: Icons.coffee_rounded,
                  color: Colors.tealAccent,
                ),
                _buildThemeCard(
                  theme: AppTheme.summer,
                  title: tr('Yaz Modu', 'Summer Mode'),
                  subtitle: tr(
                    'Canlı sarı ve sıcak koyu tonlar',
                    'Vibrant gold & warm dark tones',
                  ),
                  icon: Icons.wb_sunny_rounded,
                  color: _gold,
                ),
                _buildThemeCard(
                  theme: AppTheme.winter,
                  title: tr('Kış Modu', 'Winter Mode'),
                  subtitle: tr(
                    'Soğuk mavi tonlar ve kar animasyonları',
                    'Cool blue tones & snow animations',
                  ),
                  icon: Icons.ac_unit_rounded,
                  color: Colors.lightBlueAccent,
                ),
                _buildThemeCard(
                  theme: AppTheme.feast,
                  title: tr('Bayram Modu', 'Holiday Mode'),
                  subtitle: tr(
                    'Geleneksel motifler ve kutlama detayları',
                    'Traditional motifs & celebration details',
                  ),
                  icon: Icons.celebration_rounded,
                  color: Colors.greenAccent,
                ),
                _buildThemeCard(
                  theme: AppTheme.newYear,
                  title: tr('Yılbaşı Modu', 'New Year Mode'),
                  subtitle: tr(
                    'Kırmızı, yeşil tonlar ve yeni yıl coşkusu',
                    'Red, green tones & new year spirit',
                  ),
                  icon: Icons.forest_rounded,
                  color: Colors.redAccent,
                ),
              ],
            ),
            const SizedBox(height: 32),

            // Footer close button
            Align(
              alignment: Alignment.centerRight,
              child: BouncyButton(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 36,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.purpleAccent,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.purpleAccent.withValues(alpha: 0.25),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Text(
                    tr('Kapat', 'Close'),
                    style: const TextStyle(
                      color: _bgDark,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThemeCard({
    required AppTheme theme,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    bool isDevelopment = false,
  }) {
    final isSelected = _selectedTheme == theme;
    final isLocked = !currentFeatureFlags.themes && !isSelected;

    return BouncyButton(
      onTap: _isSaving
          ? null
          : () {
              if (isLocked) {
                showFeatureLockedDialog(
                  context,
                  tr('Tema Seçimi', 'Theme Selection'),
                );
                return;
              }
              _onThemeSelected(theme);
            },
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.08)
              : _surface.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isSelected ? color : Colors.white.withValues(alpha: 0.08),
            width: isSelected ? 2.5 : 1.5,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.15),
                    blurRadius: 12,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                if (isSelected)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      tr('Aktif', 'Active'),
                      style: const TextStyle(
                        color: _bgDark,
                        fontSize: _fsBadge,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  )
                else if (isLocked)
                  const Icon(Icons.lock_rounded, color: _gold, size: 18)
                else if (isDevelopment)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.1),
                      ),
                    ),
                    child: Text(
                      tr('Yakında', 'Soon'),
                      style: TextStyle(
                        color: _mutedText.withValues(alpha: 0.8),
                        fontSize: _fsBadge,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            const Spacer(),
            Text(
              title,
              style: TextStyle(
                color: isSelected ? _cream : _cream.withValues(alpha: 0.9),
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _mutedText,
                fontSize: _fsCaption,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
