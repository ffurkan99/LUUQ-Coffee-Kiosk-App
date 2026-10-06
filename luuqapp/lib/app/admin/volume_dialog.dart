part of '../../main.dart';

// ===== SES SEVİYESİ SEÇİM DİYALOGU =====

class _VolumeSelectionDialog extends StatefulWidget {
  const _VolumeSelectionDialog();

  @override
  State<_VolumeSelectionDialog> createState() => _VolumeSelectionDialogState();
}

class _VolumeSelectionDialogState extends State<_VolumeSelectionDialog> {
  double _selectedVolume = 1.0;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _selectedVolume = appVolumeNotifier.value;
  }

  Future<void> _onVolumeSelected(double vol) async {
    if (_isSaving || (_selectedVolume - vol).abs() < 0.001) return;

    final previousVolume = _selectedVolume;
    final int oldVolume = (appVolumeNotifier.value * 100).round();
    final int newVolume = (vol * 100).round();
    setState(() {
      _isSaving = true;
      _selectedVolume = vol;
    });

    final saved = await _saveAppVolume(vol);
    if (!mounted) return;

    setState(() {
      _isSaving = false;
      if (!saved) {
        _selectedVolume = previousVolume;
      }
    });

    if (!saved) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(
              'Ses seviyesi kaydedilemedi. Önceki değer kullanılmaya devam edecek.',
              'Volume could not be saved. The previous value will remain active.',
            ),
            style: const TextStyle(color: _cream, fontWeight: FontWeight.bold),
          ),
          backgroundColor: const Color(0xFF231E2D),
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    AnalyticsService.instance.trackVolumeChanged(oldVolume, newVolume);

    // Play a preview tick sound so user can hear the new volume
    _SpinTickSound().playTick();

    final int percentage = (vol * 100).round();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          tr(
            'Ses seviyesi %$percentage olarak ayarlandı!',
            'Volume level set to $percentage%!',
          ),
          style: const TextStyle(color: _cream, fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF231E2D),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double virtualWidth = 540.0;

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: virtualWidth,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1724),
          borderRadius: BorderRadius.circular(34),
          border: Border.all(color: Colors.pinkAccent.withValues(alpha: 0.24)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.75),
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
                    color: Colors.pinkAccent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.volume_up_rounded,
                    color: Colors.pinkAccent,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr('SES SEVİYESİ', 'VOLUME LEVEL'),
                        style: const TextStyle(
                          color: _cream,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        tr(
                          'Kiosk Ses Seviyesini Değiştirin',
                          'Change Kiosk Volume Level',
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

            // Horizontal Row of 5 Volume options
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildVolumeCard(0.0, '0%', Icons.volume_off_rounded),
                _buildVolumeCard(0.25, '25%', Icons.volume_mute_rounded),
                _buildVolumeCard(0.50, '50%', Icons.volume_down_rounded),
                _buildVolumeCard(0.75, '75%', Icons.volume_down_rounded),
                _buildVolumeCard(1.00, '100%', Icons.volume_up_rounded),
              ],
            ),
            const SizedBox(height: 28),

            // Footer Close Button
            Align(
              alignment: Alignment.centerRight,
              child: BouncyButton(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.pinkAccent,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.pinkAccent.withValues(alpha: 0.25),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Text(
                    tr('Kapat', 'Close'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
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

  Widget _buildVolumeCard(double value, String label, IconData icon) {
    final bool isSelected = (_selectedVolume - value).abs() < 0.05;

    return BouncyButton(
      onTap: _isSaving ? null : () => _onVolumeSelected(value),
      child: Container(
        width: 82,
        height: 104,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.pinkAccent.withValues(alpha: 0.12)
              : Colors.white.withValues(alpha: 0.02),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected
                ? Colors.pinkAccent
                : Colors.white.withValues(alpha: 0.08),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.pinkAccent.withValues(alpha: 0.15),
                    blurRadius: 12,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.pinkAccent : _muted,
              size: 28,
            ),
            const SizedBox(height: 10),
            Text(
              label,
              style: TextStyle(
                color: isSelected
                    ? Colors.white
                    : _cream.withValues(alpha: 0.7),
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
