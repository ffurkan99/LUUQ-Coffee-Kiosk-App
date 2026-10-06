part of '../../main.dart';

// ===== ANALİZLER ADMİN DİYALOGU =====

class _AnalyticsAdminDialog extends StatefulWidget {
  const _AnalyticsAdminDialog();

  @override
  State<_AnalyticsAdminDialog> createState() => _AnalyticsAdminDialogState();
}

class _AnalyticsAdminDialogState extends State<_AnalyticsAdminDialog> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    await _LuuqAnalytics.instance.load();
    if (mounted) {
      setState(() {
        _loading = false;
      });
    }
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
          border: Border.all(color: _gold.withValues(alpha: 0.24)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.7),
              blurRadius: 64,
            ),
          ],
        ),
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: _gold))
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header
                  Row(
                    children: [
                      const Icon(
                        Icons.analytics_rounded,
                        color: _gold,
                        size: 28,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          tr('Kullanım Analizleri', 'Usage Analytics'),
                          style: const TextStyle(
                            color: _cream,
                            fontSize: 26,
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
                  const SizedBox(height: 24),

                  // Cards Grid
                  Row(
                    children: [
                      Expanded(
                        child: _buildStatCard(
                          icon: Icons.menu_book_rounded,
                          title: tr('Menü Tıklama', 'Menu Clicks'),
                          value: _LuuqAnalytics.instance.menuClicks,
                          color: _mint,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildStatCard(
                          icon: Icons.casino_rounded,
                          title: tr('Çark Çevirme', 'Wheel Spins'),
                          value: _LuuqAnalytics.instance.wheelSpins,
                          color: _gold,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildStatCard(
                          icon: Icons.payments_rounded,
                          title: tr('Hesap Kimde', 'Who Pays'),
                          value: _LuuqAnalytics.instance.whoPaysPlays,
                          color: const Color(0xFF74B9FF),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),

                  // Footer Actions
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Reset Button
                      TextButton.icon(
                        onPressed: _showResetConfirmDialog,
                        icon: const Icon(
                          Icons.refresh_rounded,
                          color: Colors.redAccent,
                          size: 20,
                        ),
                        label: Text(
                          tr('Verileri Sıfırla', 'Reset Data'),
                          style: const TextStyle(
                            color: Colors.redAccent,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(
                              color: Colors.redAccent.withValues(alpha: 0.3),
                            ),
                          ),
                        ),
                      ),

                      // Close Button
                      ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _gold,
                          foregroundColor: _bgDark,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 32,
                            vertical: 16,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 8,
                          shadowColor: _gold.withValues(alpha: 0.3),
                        ),
                        child: Text(
                          tr('Kapat', 'Close'),
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String title,
    required int value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withValues(alpha: 0.15), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              color: _mutedText,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$value',
            style: TextStyle(
              color: _cream,
              fontSize: 36,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showResetConfirmDialog() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1C1724),
        title: Text(
          tr('Verileri Sıfırla', 'Reset Data'),
          style: const TextStyle(color: _cream),
        ),
        content: Text(
          tr(
            'Tüm analiz verilerini sıfırlamak istediğinize emin misiniz? Bu işlem geri alınamaz.',
            'Are you sure you want to reset all analytics data? This action cannot be undone.',
          ),
          style: const TextStyle(color: _mutedText),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              tr('Hayır', 'No'),
              style: const TextStyle(color: _mutedText),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              tr('Evet, Sıfırla', 'Yes, Reset'),
              style: const TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _LuuqAnalytics.instance.reset();
      setState(() {});
    }
  }
}
