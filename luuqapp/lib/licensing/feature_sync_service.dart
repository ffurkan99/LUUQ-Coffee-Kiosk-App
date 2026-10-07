import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../main.dart'; // To access navigatorKey
import 'license_gate.dart';
import 'license_service.dart';
import 'license_status.dart';
import 'update_service.dart';
import '../menu/menu_service.dart';

class FeatureSyncService with WidgetsBindingObserver {
  static final FeatureSyncService instance = FeatureSyncService._();
  FeatureSyncService._();

  Timer? _syncTimer;
  bool _isSyncing = false;
  bool _isObserverRegistered = false;
  bool _isRedirectingToGate = false;
  bool _isKioskMaintenanceRouteOpen = false;
  // The revoke notice is shown by the gate itself: a dialog over the kiosk
  // screen could be closed by its idle timer and leave a dead screen behind.
  bool _showRevokedNoticeOnGate = false;

  /// Easy to adjust polling frequency for sync
  static const Duration featureSyncInterval = Duration(seconds: 30);

  /// Internet is required: once the server could not be reached for this
  /// long, [connectionLost] covers the kiosk. The license stays active, so the
  /// cover lifts by itself on the next successful check.
  static const Duration connectionGrace = Duration(minutes: 5);

  /// True while the kiosk has been unable to reach the license server for
  /// longer than [connectionGrace].
  final ValueNotifier<bool> connectionLost = ValueNotifier<bool>(false);

  /// Clock for the grace period (replaced in tests).
  @visibleForTesting
  DateTime Function() now = DateTime.now;

  DateTime? _lastSuccessfulCheck;

  /// Start periodic background checking and register lifecycle observer
  void start() {
    // The gate has just validated online, so the grace period starts now.
    _lastSuccessfulCheck = now();
    connectionLost.value = false;
    if (!_isObserverRegistered) {
      WidgetsBinding.instance.addObserver(this);
      _isObserverRegistered = true;
    }
    _startTimer();
    // İlk sync LicenseGate tarafından yapılıyor; burada tekrar çağırmaya gerek yok.
    // Periyodik sync 30 saniye sonra başlayacak.
  }

  /// Stop periodic checking and unregister observer
  void stop() {
    _syncTimer?.cancel();
    _syncTimer = null;
    _isRedirectingToGate = false;
    _isKioskMaintenanceRouteOpen = false;
    if (_isObserverRegistered) {
      WidgetsBinding.instance.removeObserver(this);
      _isObserverRegistered = false;
    }
  }

  void _startTimer() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(featureSyncInterval, (_) => syncNow());
  }

  /// Trigger checks now with the backend
  Future<void> syncNow() async {
    if (_isSyncing) return;
    _isSyncing = true;

    try {
      final status = await LicenseService.instance.checkStatus();
      if (!recordCheckResult(status)) return;
      if (status.active) {
        // The menu sync runs on its own (MenuService allows one at a time):
        // downloading images on a slow network must not hold this lock and
        // delay license, maintenance and connection checks.
        unawaited(MenuService.instance.syncNow(status: status));
      }
      if (!status.active) {
        // License/Trial is invalid or expired! Stop sync and lock application.
        stop();
        _showRevokedNoticeOnGate = status.reason == 'device_revoked';
        if (kDebugMode && _showRevokedNoticeOnGate) {
          debugPrint('redirectedToActivation: true');
        }
        await _redirectToGate();
      }
    } catch (e) {
      debugPrint('FeatureSyncService: Error checking status: $e');
      recordCheckResult(
        const LicenseStatus(
          active: false,
          mode: LicenseMode.licensed,
          reason: 'network_error',
        ),
      );
    } finally {
      _isSyncing = false;
    }
  }

  /// Updates [connectionLost] from one check. Returns false when the result
  /// was a network/server failure, which never locks the license itself.
  @visibleForTesting
  bool recordCheckResult(LicenseStatus status) {
    final unreachable =
        !status.active &&
        (status.reason == 'network_error' || status.reason == 'server_error');
    if (!unreachable) {
      _lastSuccessfulCheck = now();
      connectionLost.value = false;
      return true;
    }
    final last = _lastSuccessfulCheck ??= now();
    if (now().difference(last) > connectionGrace) {
      connectionLost.value = true;
    }
    return false;
  }

  Future<bool> _ensureRuntimeKioskIsActive() async {
    try {
      await UpdateService.restoreKioskModeAfterUpdateCancel();
      debugPrint(
        '[LICENSE][SECURITY] LockTask verified before runtime license gate.',
      );
      return true;
    } catch (error, stackTrace) {
      debugPrint(
        '[LICENSE][SECURITY][CRITICAL] LockTask could not be restored before '
        'runtime license gate: $error\n$stackTrace',
      );
      return false;
    }
  }

  Future<void> _redirectToGate() async {
    if (_isRedirectingToGate) return;
    _isRedirectingToGate = true;

    final kioskIsActive = await _ensureRuntimeKioskIsActive();
    if (!kioskIsActive) {
      _isRedirectingToGate = false;
      _showKioskMaintenanceScreen();
      return;
    }

    _navigateToGate();
    _isRedirectingToGate = false;
  }

  void _navigateToGate() {
    final showRevokedNotice = _showRevokedNoticeOnGate;
    _showRevokedNoticeOnGate = false;
    navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => LicenseGate(showRevokedNotice: showRevokedNotice),
      ),
      (route) => false,
    );
  }

  void _showKioskMaintenanceScreen() {
    if (_isKioskMaintenanceRouteOpen) return;
    final navigator = navigatorKey.currentState;
    if (navigator == null) {
      debugPrint(
        '[LICENSE][SECURITY][CRITICAL] Kiosk maintenance screen could not be '
        'shown because no navigator exists.',
      );
      return;
    }

    _isKioskMaintenanceRouteOpen = true;
    navigator.pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => _RuntimeLicenseKioskMaintenanceScreen(
          onRetry: () async {
            final restored = await _ensureRuntimeKioskIsActive();
            if (!restored) return false;
            _isKioskMaintenanceRouteOpen = false;
            _navigateToGate();
            return true;
          },
        ),
      ),
      (route) => false,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Immediately run sync when Kiosk resumes from background
      syncNow();
    }
  }
}

class _RuntimeLicenseKioskMaintenanceScreen extends StatefulWidget {
  const _RuntimeLicenseKioskMaintenanceScreen({required this.onRetry});

  final Future<bool> Function() onRetry;

  @override
  State<_RuntimeLicenseKioskMaintenanceScreen> createState() =>
      _RuntimeLicenseKioskMaintenanceScreenState();
}

class _RuntimeLicenseKioskMaintenanceScreenState
    extends State<_RuntimeLicenseKioskMaintenanceScreen> {
  bool _isRetrying = false;
  bool _retryFailed = false;

  Future<void> _retry() async {
    if (_isRetrying) return;
    setState(() {
      _isRetrying = true;
      _retryFailed = false;
    });

    final restored = await widget.onRetry();
    if (!mounted || restored) return;
    setState(() {
      _isRetrying = false;
      _retryFailed = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF16131D),
        body: Center(
          child: Container(
            width: 480,
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 44),
            decoration: BoxDecoration(
              color: const Color(0xFF231E2D),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(
                color: Colors.redAccent.withValues(alpha: 0.35),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.gpp_bad_rounded,
                  color: Colors.redAccent,
                  size: 54,
                ),
                const SizedBox(height: 20),
                Text(
                  tr(
                    'Güvenli Kiosk Modu Geri Açılamadı',
                    'Secure Kiosk Mode Could Not Be Restored',
                  ),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFFFFF7EC),
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  _retryFailed
                      ? tr(
                          'Kiosk modu hâlâ doğrulanamıyor. Uygulamayı kullanmayın; bakım yetkilisine haber verin.',
                          'Kiosk mode still cannot be verified. Do not use the app; contact maintenance.',
                        )
                      : tr(
                          'Lisans devre dışı bırakıldı ancak güvenli kiosk modu doğrulanamadı. Müşteri ekranı kapalı tutuluyor.',
                          'The license was disabled, but secure kiosk mode could not be verified. The customer screen remains closed.',
                        ),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFF8A8694)),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isRetrying ? null : _retry,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF9AB3E),
                      foregroundColor: const Color(0xFF16131D),
                    ),
                    child: _isRetrying
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            tr('Kiosk Modunu Tekrar Aç', 'Restore Kiosk Mode'),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
