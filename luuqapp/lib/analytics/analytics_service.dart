import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../licensing/device_identity_service.dart';
import '../licensing/license_service.dart';
import '../licensing/license_storage.dart';
import '../licensing/license_status.dart';
import 'analytics_config.dart';
import 'analytics_event.dart';
import 'analytics_queue.dart';

/// Sends kiosk events to track-event.php. Events that cannot be delivered
/// (no connection, server error, rate limit) wait in an offline queue and
/// are sent later with their original id and age, so the panel counts them
/// once and at the right time.
class AnalyticsService {
  static final AnalyticsService instance = AnalyticsService._();
  AnalyticsService._() {
    // The key only changes with the license status (activation, revoke).
    LicenseService.instance.statusNotifier.addListener(() {
      _licenseKeyLoaded = false;
      _licenseKey = null;
    });
  }

  final Map<String, DateTime> _lastSentEvents = {};

  /// Queued events are sent one by one at most this often, so draining a full
  /// queue stays under the server's per-device and per-shop limits.
  @visibleForTesting
  Duration drainSpacing = const Duration(seconds: 2);

  /// Server errors one queued event may get before it is given up.
  static const int maxServerAttempts = 20;

  @visibleForTesting
  DateTime Function() now = DateTime.now;

  /// Tests: replaces the device/license fields added to every event.
  @visibleForTesting
  Future<Map<String, dynamic>> Function()? envelopeOverride;

  @visibleForTesting
  String Function() newEventId = () => const Uuid().v4();

  AnalyticsQueueStore? _queueStore;

  AnalyticsQueueStore get _queue => _queueStore ??= AnalyticsQueueStore(
    file: () async {
      try {
        final dir = await getApplicationSupportDirectory();
        return File('${dir.path}${Platform.pathSeparator}analytics_queue.json');
      } catch (_) {
        return null; // no storage (tests): memory only
      }
    },
    now: () => now(),
  );

  /// Tests: use [store] (null: a fresh default store).
  @visibleForTesting
  set queueStoreForTesting(AnalyticsQueueStore? store) => _queueStore = store;

  @visibleForTesting
  List<String> get queuedIds => _queue.events.map((e) => e.id).toList();

  /// Tests: completes when the queue file is written (Windows cannot delete
  /// a file that is still open).
  @visibleForTesting
  Future<void> get queueSaveIdle => _queue.saveIdle;

  String? _licenseKey;
  bool _licenseKeyLoaded = false;
  bool _flushing = false;

  /// Debounce check helper: avoids spamming duplicate event parameters within 1 second
  bool _shouldDebounce(AnalyticsEvent event) {
    final now = DateTime.now();
    final String key;

    if (event.eventType == 'category_click') {
      key = 'category_click_${event.categoryName}';
    } else if (event.eventType == 'product_click' ||
        event.eventType == 'product_detail_open') {
      key = '${event.eventType}_${event.productId}';
    } else if (event.eventType == 'qr_click') {
      key = 'qr_click_${event.metadata?['link_type']}';
    } else {
      key = event.eventType;
    }

    final lastSent = _lastSentEvents[key];
    if (lastSent != null && now.difference(lastSent).inSeconds < 1) {
      return true;
    }
    _lastSentEvents[key] = now;
    return false;
  }

  /// Send event to backend safely in a fire-and-forget manner
  void trackEvent(AnalyticsEvent event) {
    if (_shouldDebounce(event)) {
      if (kDebugMode) {
        debugPrint(
          'Analytics: debounced event: ${event.eventType} (param-specific)',
        );
      }
      return;
    }

    // Run asynchronously without blocking the caller
    unawaited(sendNow(event));
  }

  /// Sends one event now; queues it when it cannot be delivered.
  @visibleForTesting
  Future<void> sendNow(AnalyticsEvent event) async {
    final entry = QueuedAnalyticsEvent(
      id: newEventId(),
      createdAt: now(),
      payload: event.toJson(),
    );
    final outcome = await _send(entry, queued: false);
    switch (outcome) {
      case TrackOutcome.delivered:
        // The connection works: send what waited meanwhile.
        if (!_queue.isEmpty) unawaited(flushQueue());
      case TrackOutcome.drop:
        break;
      case TrackOutcome.keepCounted:
        entry.attempts++;
        await _queue.add(entry);
      case TrackOutcome.keep:
        await _queue.add(entry);
    }
  }

  /// Loads events saved by a previous run (no network).
  Future<void> loadQueue() => _queue.load();

  /// Sends queued events, oldest first, [drainSpacing] apart. Stops at the
  /// first one that cannot be delivered; a later trigger (next delivered
  /// event, next successful license check) continues.
  Future<void> flushQueue() async {
    if (_flushing) return;
    _flushing = true;
    try {
      await _queue.load();
      _queue.dropExpired();
      while (!_queue.isEmpty) {
        final entry = _queue.events.first;
        final outcome = await _send(entry, queued: true);
        if (outcome == TrackOutcome.delivered || outcome == TrackOutcome.drop) {
          await _queue.remove(entry.id);
        } else {
          if (outcome == TrackOutcome.keepCounted) {
            entry.attempts++;
            if (entry.attempts >= maxServerAttempts) {
              await _queue.remove(entry.id);
            } else {
              _queue.touch();
            }
          }
          break;
        }
        if (!_queue.isEmpty) await Future<void>.delayed(drainSpacing);
      }
    } finally {
      _flushing = false;
    }
  }

  Future<TrackOutcome> _send(
    QueuedAnalyticsEvent entry, {
    required bool queued,
  }) async {
    try {
      final envelope = await (envelopeOverride ?? _envelope)();
      final body = <String, dynamic>{
        ...envelope,
        ...entry.payload,
        'client_event_id': entry.id,
        if (queued)
          'queued_seconds': max(0, now().difference(entry.createdAt).inSeconds),
      };
      if (kDebugMode) {
        debugPrint(
          'Analytics tracking: event_type=${entry.payload['event_type']}, '
          'screen=${entry.payload['screen']}, queued=$queued',
        );
      }
      final response = await http
          .post(
            Uri.parse(AnalyticsConfig.trackEventUrl),
            headers: {'Content-Type': 'application/json'},
            body: json.encode(body),
          )
          .timeout(AnalyticsConfig.apiTimeout);
      if (kDebugMode) {
        debugPrint('Analytics response code: ${response.statusCode}');
      }
      return classifyTrackResponse(response.statusCode, response.body);
    } catch (e) {
      // No connection, timeout, TLS, storage: try again later.
      if (kDebugMode) {
        debugPrint('Analytics error sending event: $e');
      }
      return TrackOutcome.keep;
    }
  }

  Future<Map<String, dynamic>> _envelope() async {
    final status = LicenseService.instance.currentStatus;
    final deviceId = await DeviceIdentityService.getDeviceId();
    final fingerprint = await DeviceIdentityService.getDeviceFingerprintHash();
    final deviceModel = await DeviceIdentityService.getDeviceModel();
    final appVersion = await DeviceIdentityService.getAppVersion();
    // Proof that this is the enrolled kiosk, not just someone who knows its
    // device ID (the server checks it against the device's license). Read
    // once from secure storage, not for every tap.
    if (!_licenseKeyLoaded) {
      _licenseKey = await LicenseStorage.getLicenseKey();
      _licenseKeyLoaded = true;
    }
    final licenseKey = _licenseKey;
    final String licenseMode = status.mode == LicenseMode.licensed
        ? 'licensed'
        : status.mode == LicenseMode.trial
        ? 'trial'
        : 'none';
    return {
      'device_id': deviceId,
      'device_fingerprint_hash': fingerprint,
      'license_key': ?licenseKey,
      'device_model': deviceModel,
      'device_name': deviceModel,
      'license_mode': licenseMode,
      'customer_name': status.customerName ?? '',
      'branch_name': status.branchName ?? '',
      'plan': status.plan ?? '',
      'app_version': appVersion,
      'platform': Platform.operatingSystem.toLowerCase(),
    };
  }

  // Helper track methods:
  void trackAppStarted() {
    trackEvent(AnalyticsEvent(eventType: 'app_started', screen: 'loading'));
  }

  void trackMenuOpen() {
    trackEvent(AnalyticsEvent(eventType: 'menu_open', screen: 'menu'));
  }

  void trackCategoryClick(String categoryName) {
    trackEvent(
      AnalyticsEvent(
        eventType: 'category_click',
        screen: 'menu',
        categoryName: categoryName,
      ),
    );
  }

  void trackProductClick(
    String productId,
    String productName,
    String categoryName,
  ) {
    trackEvent(
      AnalyticsEvent(
        eventType: 'product_click',
        screen: 'menu',
        productId: productId,
        productName: productName,
        categoryName: categoryName,
      ),
    );
  }

  void trackProductDetailOpen(
    String productId,
    String productName,
    String categoryName,
  ) {
    trackEvent(
      AnalyticsEvent(
        eventType: 'product_detail_open',
        screen: 'product_detail',
        productId: productId,
        productName: productName,
        categoryName: categoryName,
      ),
    );
  }

  void trackWheelSpinStart() {
    trackEvent(AnalyticsEvent(eventType: 'wheel_spin_start', screen: 'home'));
  }

  void trackWheelSpinResult(
    String productId,
    String productName,
    String categoryName,
  ) {
    trackEvent(
      AnalyticsEvent(
        eventType: 'wheel_spin_result',
        screen: 'home',
        productId: productId,
        productName: productName,
        categoryName: categoryName,
      ),
    );
  }

  void trackWhoPaysClick() {
    trackEvent(AnalyticsEvent(eventType: 'who_pays_click', screen: 'home'));
  }

  void trackLockedFeatureClick(
    String feature,
    String featureLabel,
    String screen,
  ) {
    trackEvent(
      AnalyticsEvent(
        eventType: 'locked_feature_click',
        screen: screen,
        metadata: {'feature': feature, 'feature_label': featureLabel},
      ),
    );
  }

  void trackLinksClick() {
    trackEvent(AnalyticsEvent(eventType: 'links_click', screen: 'home'));
  }

  void trackQrClick(String linkType) {
    trackEvent(
      AnalyticsEvent(
        eventType: 'qr_click',
        screen: 'home',
        metadata: {'link_type': linkType},
      ),
    );
  }

  void trackAdminOpenSuccess() {
    trackEvent(
      AnalyticsEvent(eventType: 'admin_open_success', screen: 'admin'),
    );
  }

  void trackAdminPinVerifySuccess() {
    trackEvent(
      AnalyticsEvent(eventType: 'admin_pin_verify_success', screen: 'admin'),
    );
  }

  void trackAdminPinVerifyFailed(String reason) {
    if (reason == 'rate_limited') {
      trackEvent(
        AnalyticsEvent(
          eventType: 'admin_pin_rate_limited',
          screen: 'admin',
          metadata: {'reason': reason},
        ),
      );
    } else {
      trackEvent(
        AnalyticsEvent(
          eventType: 'admin_pin_verify_failed',
          screen: 'admin',
          metadata: {'reason': reason},
        ),
      );
    }
  }

  void trackThemeChanged(String oldTheme, String newTheme) {
    trackEvent(
      AnalyticsEvent(
        eventType: 'theme_changed',
        screen: 'admin_menu',
        metadata: {'old_theme': oldTheme, 'new_theme': newTheme},
      ),
    );
  }

  void trackLanguageChanged(String language) {
    trackEvent(
      AnalyticsEvent(
        eventType: 'language_changed',
        screen: 'home',
        metadata: {'language': language},
      ),
    );
  }

  void trackCleaningModeStarted({String screen = 'home'}) {
    trackEvent(
      AnalyticsEvent(
        eventType: 'cleaning_mode_started',
        screen: screen,
        metadata: {'source': screen},
      ),
    );
  }

  void trackAdminMenuOpened() {
    trackEvent(
      AnalyticsEvent(
        eventType: 'admin_menu_opened',
        screen: 'home',
        metadata: {'source': 'settings_button'},
      ),
    );
  }

  void trackVolumeChanged(int oldVolume, int newVolume) {
    trackEvent(
      AnalyticsEvent(
        eventType: 'volume_changed',
        screen: 'admin_menu',
        metadata: {'old_volume': oldVolume, 'new_volume': newVolume},
      ),
    );
  }

  void trackBaristaRecommendationUpdated(
    String recommendationTitle,
    String recommendationType,
  ) {
    trackEvent(
      AnalyticsEvent(
        eventType: 'barista_recommendation_updated',
        screen: 'admin_menu',
        metadata: {
          'recommendation_title': recommendationTitle,
          'recommendation_type': recommendationType,
        },
      ),
    );
  }

  void trackWheelContentUpdated(int selectedCount, List<String> selectedItems) {
    trackEvent(
      AnalyticsEvent(
        eventType: 'wheel_content_updated',
        screen: 'admin_menu',
        metadata: {
          'selected_count': selectedCount,
          'selected_items': selectedItems,
        },
      ),
    );
  }

  void trackAnalyticsOpened() {
    trackEvent(
      AnalyticsEvent(
        eventType: 'analytics_opened',
        screen: 'admin_menu',
        metadata: {'source': 'admin_menu'},
      ),
    );
  }

  void trackAppInfoOpened() {
    trackEvent(
      AnalyticsEvent(
        eventType: 'app_info_opened',
        screen: 'admin_menu',
        metadata: {'source': 'admin_menu'},
      ),
    );
  }

  void trackManualExitClicked() {
    trackEvent(
      AnalyticsEvent(
        eventType: 'manual_exit_clicked',
        screen: 'admin_menu',
        metadata: {'source': 'admin_menu'},
      ),
    );
  }
}
