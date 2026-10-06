part of '../../main.dart';

String _generateSlug(String name) {
  return name
      .toLowerCase()
      .replaceAll(RegExp(r'[ıİ]'), 'i')
      .replaceAll(RegExp(r'[şŞ]'), 's')
      .replaceAll(RegExp(r'[ğĞ]'), 'g')
      .replaceAll(RegExp(r'[üÜ]'), 'u')
      .replaceAll(RegExp(r'[öÖ]'), 'o')
      .replaceAll(RegExp(r'[çÇ]'), 'c')
      .replaceAll(RegExp(r'[^a-z0-9\s-]'), '')
      .replaceAll(RegExp(r'\s+'), '_')
      .replaceAll(RegExp(r'-+'), '_');
}

void showFeatureLockedDialog(
  BuildContext context,
  String featureName, {
  String? customMessage,
  String? screen,
  String? featureKey,
}) {
  final status = LicenseService.instance.currentStatus;
  if (kDebugMode) {
    debugPrint('UI FEATURE LOCK CONTROL:');
    debugPrint('  featureName: $featureName');
    debugPrint('  featureValue: false');
    debugPrint('  currentMode: ${status.mode.name}');
    debugPrint('  currentPlan: ${status.plan ?? 'null'}');
  }
  AnalyticsService.instance.trackLockedFeatureClick(
    featureKey ?? _generateSlug(featureName),
    featureName,
    screen ?? 'home',
  );
  showDialog(
    context: context,
    builder: (context) {
      final isLicensedMode = status.mode == LicenseMode.licensed;

      final title = isLicensedMode
          ? tr('Özellik Devre Dışı', 'Feature Disabled')
          : tr('Lisanslı Sürüm Özelliği', 'Premium Feature');

      final description = isLicensedMode
          ? tr(
              '“$featureName” özelliği yöneticiniz tarafından devre dışı bırakılmıştır. Bu özelliği kullanmak için lütfen yöneticinizle iletişime geçin.',
              '“$featureName” feature has been disabled by your administrator. Please contact your administrator to use this feature.',
            )
          : (customMessage ??
                tr(
                  '“$featureName” özelliği deneme sürümünde kilitlidir. Devam etmek için lütfen lisans edinin.',
                  '“$featureName” feature is locked in the trial version. Please obtain a license to continue.',
                ));

      return Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 420,
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: const Color(0xFF1C1724),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: _gold.withValues(alpha: 0.24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.65),
                blurRadius: 24,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _gold.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.lock_outline_rounded,
                  color: _gold,
                  size: 48,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                title,
                style: const TextStyle(
                  color: _cream,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                description,
                style: const TextStyle(
                  color: _mutedText,
                  fontSize: 14,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              if (isLicensedMode)
                BouncyButton(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: _gold,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      tr('Kapat', 'Close'),
                      style: const TextStyle(
                        color: _bgDark,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                  ),
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: BouncyButton(
                        onTap: () => Navigator.of(context).pop(),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            color: _surface.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.1),
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            tr('Kapat', 'Close'),
                            style: const TextStyle(
                              color: _cream,
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: BouncyButton(
                        onTap: () {
                          Navigator.of(context).pop();
                          _openLicenseUpgradeDialog(context);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            color: _gold,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            tr('Lisans Gir', 'Enter License'),
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
            ],
          ),
        ),
      );
    },
  );
}

void _openLicenseUpgradeDialog(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (context) => LicenseActivationScreen(
        upgradeMode: true,
        onActivated: () {
          Navigator.of(context).pop();
        },
      ),
    ),
  );
}

String getTrialRemainingText() {
  final status = LicenseService.instance.currentStatus;
  if (status.mode != LicenseMode.trial) return '';
  if (status.trialExpiresAt == null) return '';
  try {
    final expiry = DateTime.parse(status.trialExpiresAt!);
    final diff = expiry.difference(DateTime.now());
    if (diff.isNegative) {
      return tr('Süre doldu', 'Expired');
    }
    if (diff.inDays >= 1) {
      return tr('Kalan: ${diff.inDays} Gün', 'Remaining: ${diff.inDays} Days');
    } else if (diff.inHours >= 1) {
      return tr(
        'Kalan: ${diff.inHours} Saat',
        'Remaining: ${diff.inHours} Hours',
      );
    } else {
      return tr('Kalan: < 1 Saat', 'Remaining: < 1 Hour');
    }
  } catch (_) {
    return '';
  }
}
