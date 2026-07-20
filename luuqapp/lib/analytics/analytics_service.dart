import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../licensing/device_identity_service.dart';
import '../licensing/license_service.dart';
import '../licensing/license_status.dart';
import 'analytics_config.dart';
import 'analytics_event.dart';

class AnalyticsService {
  static final AnalyticsService instance = AnalyticsService._();
  AnalyticsService._();

  final Map<String, DateTime> _lastSentEvents = {};

  /// Debounce check helper: avoids spamming duplicate event parameters within 1 second
  bool _shouldDebounce(AnalyticsEvent event) {
    final now = DateTime.now();
    final String key;
    
    if (event.eventType == 'category_click') {
      key = 'category_click_${event.categoryName}';
    } else if (event.eventType == 'product_click' || event.eventType == 'product_detail_open') {
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
        debugPrint('Analytics: debounced event: ${event.eventType} (param-specific)');
      }
      return;
    }

    // Run asynchronously without blocking the caller
    unawaited(_sendEventAsync(event));
  }

  Future<void> _sendEventAsync(AnalyticsEvent event) async {
    try {
      final status = LicenseService.instance.currentStatus;
      final deviceId = await DeviceIdentityService.getDeviceId();
      final fingerprint = await DeviceIdentityService.getDeviceFingerprintHash();
      final deviceModel = await DeviceIdentityService.getDeviceModel();
      final appVersion = await DeviceIdentityService.getAppVersion();
      if (kDebugMode) {
        debugPrint('track-event app_version: $appVersion');
      }
      final platformName = Platform.operatingSystem.toLowerCase();

      final String licenseMode = status.mode == LicenseMode.licensed
          ? 'licensed'
          : status.mode == LicenseMode.trial
              ? 'trial'
              : 'none';

      final Map<String, dynamic> body = {
        'device_id': deviceId,
        'device_fingerprint_hash': fingerprint,
        'device_model': deviceModel,
        'device_name': deviceModel,
        'license_mode': licenseMode,
        'customer_name': status.customerName ?? '',
        'branch_name': status.branchName ?? '',
        'plan': status.plan ?? '',
        'app_version': appVersion,
        'platform': platformName,
        ...event.toJson(),
      };

      if (kDebugMode) {
        debugPrint('Analytics tracking: event_type=${event.eventType}, screen=${event.screen}');
      }

      final response = await http
          .post(
            Uri.parse(AnalyticsConfig.trackEventUrl),
            headers: {'Content-Type': 'application/json'},
            body: json.encode(body),
          )
          .timeout(AnalyticsConfig.apiTimeout);

      if (kDebugMode) {
        debugPrint('Analytics response code: ${response.statusCode}, body: ${response.body}');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Analytics error sending event: $e');
      }
    }
  }

  // Helper track methods:
  void trackAppStarted() {
    trackEvent(AnalyticsEvent(eventType: 'app_started', screen: 'loading'));
  }

  void trackMenuOpen() {
    trackEvent(AnalyticsEvent(eventType: 'menu_open', screen: 'menu'));
  }

  void trackCategoryClick(String categoryName) {
    trackEvent(AnalyticsEvent(
      eventType: 'category_click',
      screen: 'menu',
      categoryName: categoryName,
    ));
  }

  void trackProductClick(String productId, String productName, String categoryName) {
    trackEvent(AnalyticsEvent(
      eventType: 'product_click',
      screen: 'menu',
      productId: productId,
      productName: productName,
      categoryName: categoryName,
    ));
  }

  void trackProductDetailOpen(String productId, String productName, String categoryName) {
    trackEvent(AnalyticsEvent(
      eventType: 'product_detail_open',
      screen: 'product_detail',
      productId: productId,
      productName: productName,
      categoryName: categoryName,
    ));
  }

  void trackWheelSpinStart() {
    trackEvent(AnalyticsEvent(eventType: 'wheel_spin_start', screen: 'home'));
  }

  void trackWheelSpinResult(String productId, String productName, String categoryName) {
    trackEvent(AnalyticsEvent(
      eventType: 'wheel_spin_result',
      screen: 'home',
      productId: productId,
      productName: productName,
      categoryName: categoryName,
    ));
  }

  void trackWhoPaysClick() {
    trackEvent(AnalyticsEvent(eventType: 'who_pays_click', screen: 'home'));
  }

  void trackLockedFeatureClick(String feature, String featureLabel, String screen) {
    trackEvent(AnalyticsEvent(
      eventType: 'locked_feature_click',
      screen: screen,
      metadata: {'feature': feature, 'feature_label': featureLabel},
    ));
  }

  void trackLinksClick() {
    trackEvent(AnalyticsEvent(eventType: 'links_click', screen: 'home'));
  }

  void trackQrClick(String linkType) {
    trackEvent(AnalyticsEvent(
      eventType: 'qr_click',
      screen: 'home',
      metadata: {'link_type': linkType},
    ));
  }

  void trackAdminOpenSuccess() {
    trackEvent(AnalyticsEvent(eventType: 'admin_open_success', screen: 'admin'));
  }

  void trackAdminLockedAttempt() {
    trackEvent(AnalyticsEvent(eventType: 'admin_locked_attempt', screen: 'admin'));
  }

  void trackAdminPinVerifySuccess() {
    trackEvent(AnalyticsEvent(eventType: 'admin_pin_verify_success', screen: 'admin'));
  }

  void trackAdminPinVerifyFailed(String reason) {
    if (reason == 'rate_limited') {
      trackEvent(AnalyticsEvent(eventType: 'admin_pin_rate_limited', screen: 'admin', metadata: {'reason': reason}));
    } else {
      trackEvent(AnalyticsEvent(eventType: 'admin_pin_verify_failed', screen: 'admin', metadata: {'reason': reason}));
    }
  }

  void trackThemeChanged(String oldTheme, String newTheme) {
    trackEvent(AnalyticsEvent(
      eventType: 'theme_changed',
      screen: 'admin_menu',
      metadata: {'old_theme': oldTheme, 'new_theme': newTheme},
    ));
  }

  void trackLanguageChanged(String language) {
    trackEvent(AnalyticsEvent(
      eventType: 'language_changed',
      screen: 'home',
      metadata: {'language': language},
    ));
  }

  void trackCleaningModeStarted({String screen = 'home'}) {
    trackEvent(AnalyticsEvent(
      eventType: 'cleaning_mode_started',
      screen: screen,
      metadata: {'source': screen},
    ));
  }

  void trackAdminMenuOpened() {
    trackEvent(AnalyticsEvent(
      eventType: 'admin_menu_opened',
      screen: 'home',
      metadata: {'source': 'settings_button'},
    ));
  }

  void trackVolumeChanged(int oldVolume, int newVolume) {
    trackEvent(AnalyticsEvent(
      eventType: 'volume_changed',
      screen: 'admin_menu',
      metadata: {'old_volume': oldVolume, 'new_volume': newVolume},
    ));
  }

  void trackBaristaRecommendationUpdated(String recommendationTitle, String recommendationType) {
    trackEvent(AnalyticsEvent(
      eventType: 'barista_recommendation_updated',
      screen: 'admin_menu',
      metadata: {
        'recommendation_title': recommendationTitle,
        'recommendation_type': recommendationType,
      },
    ));
  }

  void trackWheelContentUpdated(int selectedCount, List<String> selectedItems) {
    trackEvent(AnalyticsEvent(
      eventType: 'wheel_content_updated',
      screen: 'admin_menu',
      metadata: {
        'selected_count': selectedCount,
        'selected_items': selectedItems,
      },
    ));
  }

  void trackAnalyticsOpened() {
    trackEvent(AnalyticsEvent(
      eventType: 'analytics_opened',
      screen: 'admin_menu',
      metadata: {'source': 'admin_menu'},
    ));
  }

  void trackAppInfoOpened() {
    trackEvent(AnalyticsEvent(
      eventType: 'app_info_opened',
      screen: 'admin_menu',
      metadata: {'source': 'admin_menu'},
    ));
  }

  void trackManualExitClicked() {
    trackEvent(AnalyticsEvent(
      eventType: 'manual_exit_clicked',
      screen: 'admin_menu',
      metadata: {'source': 'admin_menu'},
    ));
  }
}
