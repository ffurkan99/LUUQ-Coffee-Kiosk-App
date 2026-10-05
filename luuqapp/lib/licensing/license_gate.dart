import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../main.dart'; // To launch CafeKioskScreen
import 'feature_flags.dart';
import 'license_activation_screen.dart';
import 'license_service.dart';
import 'license_status.dart';
import 'license_storage.dart';

class LicenseGate extends StatefulWidget {
  const LicenseGate({super.key, this.showRevokedNotice = false});

  /// The running kiosk was revoked: explain why the activation form is shown.
  final bool showRevokedNotice;

  /// Wait before the n-th automatic retry while the license server is
  /// unreachable: 5 s, 10 s, 20 s, 40 s, then every 60 s.
  @visibleForTesting
  static Duration autoRetryDelay(int attempt) =>
      Duration(seconds: math.min(60, 5 * (1 << math.min(attempt, 4))));

  @override
  State<LicenseGate> createState() => _LicenseGateState();
}

class _LicenseGateState extends State<LicenseGate> {
  bool _isChecking = true;
  bool _isLicenseServerUnavailable = false;
  bool _isLicenseStorageUnavailable = false;
  bool _isResettingStorage = false;
  String? _gateError;
  String? _storageResetError;

  /// While the license server is unreachable the check is retried on its own
  /// (5 s, 10 s, ... up to 60 s), so a kiosk that started without network
  /// opens by itself once the connection returns. Not an offline grace: the
  /// customer screen still opens only after a successful server check.
  Timer? _autoRetryTimer;
  int _autoRetryAttempt = 0;

  void _scheduleAutoRetry() {
    _autoRetryTimer?.cancel();
    final delay = LicenseGate.autoRetryDelay(_autoRetryAttempt);
    _autoRetryAttempt++;
    _autoRetryTimer = Timer(delay, () {
      if (mounted && _isLicenseServerUnavailable) _checkLicenseFlow();
    });
  }

  void _stopAutoRetry() {
    _autoRetryTimer?.cancel();
    _autoRetryTimer = null;
    _autoRetryAttempt = 0;
  }

  @override
  void dispose() {
    _autoRetryTimer?.cancel();
    super.dispose();
  }

  static const _bgDark = Color(0xFF16131D);
  static const _gold = Color(0xFFF9AB3E);
  static const _cream = Color(0xFFFFF7EC);

  @override
  void initState() {
    super.initState();
    _checkLicenseFlow();
    if (widget.showRevokedNotice) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showRevokedDialog();
      });
    }
  }

  Future<void> _checkLicenseFlow() async {
    if (!mounted) return;
    _autoRetryTimer?.cancel();
    setState(() {
      _isChecking = true;
      _isLicenseServerUnavailable = false;
      _isLicenseStorageUnavailable = false;
      _gateError = null;
      _storageResetError = null;
    });

    // Startup is fail-closed. Cached status may provide stored metadata, but it
    // is never an authorization source for opening the customer UI.
    LicenseService.instance.statusNotifier.value = const LicenseStatus(
      active: false,
      mode: LicenseMode.none,
      features: FeatureFlags.lockedAll,
    );

    try {
      final licenseKey = await LicenseStorage.getLicenseKey();
      if (!mounted) return;

      final hasLicenseKey = licenseKey != null && licenseKey.trim().isNotEmpty;
      if (!hasLicenseKey) {
        setState(() {
          _isChecking = false;
        });
        return;
      }

      // The real LUUQ license endpoint is the only startup reachability and
      // authorization check. There is deliberately no third-party DNS probe.
      final status = await LicenseService.instance.checkStatus();
      if (!mounted) return;

      if (status.active) {
        _stopAutoRetry();
        _navigateToHome();
        return;
      }

      if (status.reason == 'device_revoked') {
        _showRevokedDialog();
        return;
      }

      if (status.reason == 'network_error' || status.reason == 'server_error') {
        setState(() {
          _isChecking = false;
          _isLicenseServerUnavailable = true;
        });
        _scheduleAutoRetry();
        return;
      }
      _stopAutoRetry();

      setState(() {
        _isChecking = false;
        _gateError = LicenseService.getLocalizedError(status.reason);
      });
    } on LicenseStorageException catch (error, stackTrace) {
      debugPrint(
        '[LICENSE][STORAGE] Startup blocked by secure storage failure: '
        '$error\n$stackTrace',
      );
      _showStorageFailure();
    } catch (error, stackTrace) {
      debugPrint(
        '[LICENSE][STARTUP] Controlled startup validation failure: '
        '$error\n$stackTrace',
      );
      if (!mounted) return;
      setState(() {
        _isChecking = false;
        _isLicenseServerUnavailable = true;
      });
      _scheduleAutoRetry();
    }
  }

  void _showStorageFailure() {
    if (!mounted) return;
    LicenseService.instance.statusNotifier.value = const LicenseStatus(
      active: false,
      mode: LicenseMode.none,
      features: FeatureFlags.lockedAll,
    );
    setState(() {
      _isChecking = false;
      _isLicenseServerUnavailable = false;
      _isLicenseStorageUnavailable = true;
      _isResettingStorage = false;
    });
  }

  Future<void> _confirmStorageReset() async {
    if (_isResettingStorage) return;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF231E2D),
        title: const Text(
          'Lisansı Yeniden Etkinleştir',
          style: TextStyle(color: _cream, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'Bu işlem yalnız güvenli cihaz/lisans verisini sıfırlar. Mevcut lisans anahtarını yeniden girmeniz gerekir. İşlem otomatik olarak yapılmaz.',
          style: TextStyle(color: Color(0xFF8A8694)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text(
              'Sıfırla ve Etkinleştir',
              style: TextStyle(color: _gold, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _isResettingStorage = true;
      _storageResetError = null;
    });
    try {
      await LicenseStorage.resetForReactivation();
      if (!mounted) return;
      LicenseService.instance.statusNotifier.value = const LicenseStatus(
        active: false,
        mode: LicenseMode.none,
        features: FeatureFlags.lockedAll,
      );
      setState(() {
        _isResettingStorage = false;
        _isLicenseStorageUnavailable = false;
        _gateError = LicenseService.getLocalizedError('storage_error');
      });
    } on LicenseStorageException catch (error, stackTrace) {
      debugPrint(
        '[LICENSE][STORAGE] Explicit reactivation reset failed: '
        '$error\n$stackTrace',
      );
      if (!mounted) return;
      setState(() {
        _isResettingStorage = false;
        _storageResetError =
            'Güvenli lisans verisi sıfırlanamadı. Lütfen yönetici desteğine başvurun.';
      });
    }
  }

  void _showRevokedDialog() {
    if (kDebugMode) {
      debugPrint('redirectedToActivation: true');
    }
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF231E2D),
          title: const Text(
            'Lisans Bağlantısı Kaldırıldı',
            style: TextStyle(
              color: Color(0xFFFFF7EC),
              fontWeight: FontWeight.bold,
            ),
          ),
          content: const Text(
            'Bu cihazın lisans bağlantısı yönetici tarafından kaldırıldı. Devam etmek için yeniden lisans anahtarı girmeniz gerekir.',
            style: TextStyle(color: Color(0xFF8A8694)),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                if (mounted) {
                  setState(() {
                    _isChecking = false;
                    _gateError = null;
                  });
                }
              },
              child: const Text(
                'Tamam',
                style: TextStyle(
                  color: Color(0xFFF9AB3E),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _navigateToHome() {
    // Navigate replacing this screen to avoid backing into the gate
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const CafeKioskScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isChecking) {
      return const Scaffold(
        backgroundColor: _bgDark,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(_gold),
              ),
              SizedBox(height: 24),
              Text(
                'Lisans ve deneme süresi kontrol ediliyor...',
                style: TextStyle(
                  color: _cream,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_isLicenseServerUnavailable) {
      return _LicenseServerUnavailableScreen(onRetry: _checkLicenseFlow);
    }

    if (_isLicenseStorageUnavailable) {
      return _LicenseStorageUnavailableScreen(
        onRetry: _checkLicenseFlow,
        onReset: _confirmStorageReset,
        isResetting: _isResettingStorage,
        resetError: _storageResetError,
      );
    }

    // Direct registration screen or screen with past error validation
    return LicenseActivationScreen(
      errorMessage: _gateError,
      onStorageFailure: _showStorageFailure,
      onActivated: () {
        _navigateToHome();
      },
    );
  }
}

class _LicenseStorageUnavailableScreen extends StatelessWidget {
  final VoidCallback onRetry;
  final VoidCallback onReset;
  final bool isResetting;
  final String? resetError;

  const _LicenseStorageUnavailableScreen({
    required this.onRetry,
    required this.onReset,
    required this.isResetting,
    required this.resetError,
  });

  static const _bgDark = Color(0xFF16131D);
  static const _surface = Color(0xFF231E2D);
  static const _gold = Color(0xFFF9AB3E);
  static const _cream = Color(0xFFFFF7EC);
  static const _muted = Color(0xFF8A8694);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgDark,
      body: Center(
        child: SingleChildScrollView(
          child: Container(
            width: 460,
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 48),
            decoration: BoxDecoration(
              color: _surface.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(36),
              border: Border.all(
                color: _gold.withValues(alpha: 0.25),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 40,
                  offset: const Offset(0, 20),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.redAccent.withValues(alpha: 0.1),
                    border: Border.all(
                      color: Colors.redAccent.withValues(alpha: 0.3),
                      width: 2,
                    ),
                  ),
                  child: const Icon(
                    Icons.lock_reset_rounded,
                    color: Colors.redAccent,
                    size: 40,
                  ),
                ),
                const SizedBox(height: 28),
                const Text(
                  'Lisans Verisine Erişilemiyor',
                  style: TextStyle(
                    color: _cream,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 14),
                const Text(
                  'Güvenli lisans verisi okunamadı. Müşteri ekranı güvenlik nedeniyle kapalı tutuluyor. Veriler otomatik silinmedi; tekrar deneyebilir veya cihazı açıkça yeniden etkinleştirebilirsiniz.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _muted, fontSize: 14, height: 1.5),
                ),
                if (resetError != null) ...[
                  const SizedBox(height: 18),
                  Text(
                    resetError!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 32),
                if (isResetting)
                  const CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(_gold),
                  )
                else ...[
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: onRetry,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _gold,
                        foregroundColor: _bgDark,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      child: const Text(
                        'Tekrar Dene',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: OutlinedButton(
                      onPressed: onReset,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _gold,
                        side: const BorderSide(color: _gold, width: 1.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      child: const Text(
                        'Lisansı Yeniden Etkinleştir',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LicenseServerUnavailableScreen extends StatelessWidget {
  final VoidCallback onRetry;

  const _LicenseServerUnavailableScreen({required this.onRetry});

  static const _bgDark = Color(0xFF16131D);
  static const _surface = Color(0xFF231E2D);
  static const _gold = Color(0xFFF9AB3E);
  static const _cream = Color(0xFFFFF7EC);
  static const _muted = Color(0xFF8A8694);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgDark,
      body: Center(
        child: Container(
          width: 460,
          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 48),
          decoration: BoxDecoration(
            color: _surface.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(36),
            border: Border.all(
              color: _gold.withValues(alpha: 0.25),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 40,
                offset: const Offset(0, 20),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.redAccent.withValues(alpha: 0.1),
                  border: Border.all(
                    color: Colors.redAccent.withValues(alpha: 0.3),
                    width: 2,
                  ),
                ),
                child: const Icon(
                  Icons.cloud_off_rounded,
                  color: Colors.redAccent,
                  size: 40,
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                'Lisans Sunucusuna Ulaşılamıyor',
                style: TextStyle(
                  color: _cream,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              const Text(
                'Lisans doğrulaması tamamlanamadı. İnternet bağlantısını ve lisans sunucusu erişimini kontrol edip tekrar deneyin.',
                textAlign: TextAlign.center,
                style: TextStyle(color: _muted, fontSize: 14, height: 1.5),
              ),
              const SizedBox(height: 36),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: onRetry,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _gold,
                    foregroundColor: _bgDark,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: const Text(
                    'Tekrar Dene',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
