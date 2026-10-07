import 'package:flutter/foundation.dart';

import 'feature_flags.dart';

enum LicenseMode { licensed, trial, none }

class LicenseStatus {
  final bool active;
  final LicenseMode mode;
  final String? branchName;
  final String? customerName;
  final String? plan;
  final String? expiresAt;
  final String? trialExpiresAt;
  final FeatureFlags features;
  final String? reason;
  final DateTime? lastCheckedAt;
  final bool updateAvailable;
  final String? latestVersion;
  final String? apkUrl;
  final String? apkSha256;
  final int? apkSizeBytes;
  final String? releaseNotes;
  final String? publishedAt;
  final String? menuAccessToken;
  final String? menuProfileId;
  final int? menuProfileGeneration;

  /// Panel "Bakım Modu": the customer screen is closed with [maintenanceMessage].
  final bool maintenanceEnabled;
  final String? maintenanceMessage;

  /// Panel "Minimum Uygulama Sürümü"; older builds show an update-required screen.
  final String? minimumAppVersion;

  const LicenseStatus({
    required this.active,
    required this.mode,
    this.branchName,
    this.customerName,
    this.plan,
    this.expiresAt,
    this.trialExpiresAt,
    this.features = const FeatureFlags(),
    this.reason,
    this.lastCheckedAt,
    this.updateAvailable = false,
    this.latestVersion,
    this.apkUrl,
    this.apkSha256,
    this.apkSizeBytes,
    this.releaseNotes,
    this.publishedAt,
    this.menuAccessToken,
    this.menuProfileId,
    this.menuProfileGeneration,
    this.maintenanceEnabled = false,
    this.maintenanceMessage,
    this.minimumAppVersion,
  });

  static Map<String, dynamic>? _optMap(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : null;

  static String? _optString(Object? value) =>
      value is String ? value : (value is num ? value.toString() : null);

  factory LicenseStatus.fromJson(
    Map<String, dynamic> json,
    LicenseMode defaultMode, {
    DateTime? lastCheckedAt,
  }) {
    // Typed reads: PHP sends [] for an empty object and may send numbers for
    // strings; a bad cast here used to throw and turn into "server error".
    final active = json['active'] == true;
    final updateJson = _optMap(json['update']);
    final bool updateAvailable =
        updateJson != null &&
        (updateJson['available'] == true ||
            updateJson['available']?.toString() == 'true');
    final String? latestVersion = updateJson?['latest_version']?.toString();
    final String? apkUrl = updateJson?['apk_url']?.toString();
    final String? apkSha256 = updateJson?['apk_sha256']?.toString();
    final int? apkSizeBytes = updateJson?['apk_size_bytes'] != null
        ? int.tryParse(updateJson!['apk_size_bytes'].toString())
        : null;
    final String? releaseNotes = updateJson?['release_notes']?.toString();
    final String? publishedAt = updateJson?['published_at']?.toString();
    final String? menuAccessToken = json['menu_access_token']?.toString();
    final String? menuProfileId = json['menu_profile_id']?.toString();
    final int? menuProfileGeneration = json['menu_profile_generation'] != null
        ? int.tryParse(json['menu_profile_generation'].toString())
        : null;
    final maintenanceJson = json['maintenance'];
    final maintenanceEnabled =
        maintenanceJson is Map &&
        (maintenanceJson['enabled'] == true ||
            maintenanceJson['enabled']?.toString() == 'true' ||
            maintenanceJson['enabled']?.toString() == '1');
    final maintenanceMessage = maintenanceJson is Map
        ? maintenanceJson['message']?.toString()
        : null;
    final minimumAppVersion = json['minimum_app_version']?.toString();
    final modeStr = json['mode']?.toString() ?? '';
    final planStr = json['plan']?.toString() ?? '';

    final trialValues = {'trial', 'deneme', 'demo', 'basic_trial'};
    final licensedValues = {
      'licensed', 'active', 'pro', 'premium', 'yearly', 'annual',
      'yillik', 'yıllık',
    };

    final modeLower = modeStr.trim().toLowerCase();
    final planLower = planStr.trim().toLowerCase();
    // Exact values only, mode before plan: substring matching made "inactive"
    // look like "active" and a plan named "Pro Deneme" look like a trial.
    LicenseMode? modeOf(String value) {
      if (trialValues.contains(value)) return LicenseMode.trial;
      if (licensedValues.contains(value)) return LicenseMode.licensed;
      if (value == 'none') return LicenseMode.none;
      return null;
    }

    final LicenseMode resolvedMode =
        modeOf(modeLower) ??
        modeOf(planLower) ??
        (defaultMode != LicenseMode.none
            ? defaultMode
            : (active ? LicenseMode.licensed : defaultMode));

    final fallbackFlags = resolvedMode == LicenseMode.trial
        ? FeatureFlags.trialDefault
        : (resolvedMode == LicenseMode.licensed
              ? FeatureFlags.proDefault
              : FeatureFlags.lockedAll);
    final featuresJson = _optMap(json['features']);
    String featureSource = 'none';
    FeatureFlags parsedFeatures;
    if (!active) {
      parsedFeatures = FeatureFlags.lockedAll;
      featureSource = 'inactive_locked_all';
    } else if (featuresJson != null && featuresJson.isNotEmpty) {
      // A key missing from the server's list is off (fail closed); the
      // server always sends the full list, so this only guards new flags.
      parsedFeatures = FeatureFlags.fromJson(
        featuresJson,
        fallback: FeatureFlags.lockedAll,
      );
      featureSource = 'backend_features';
    } else {
      parsedFeatures = fallbackFlags;
      featureSource = resolvedMode == LicenseMode.trial
          ? 'trial_fallback'
          : (resolvedMode == LicenseMode.licensed
                ? 'licensed_fallback'
                : 'locked_all_fallback');
    }

    if (resolvedMode == LicenseMode.trial) {
      parsedFeatures = FeatureFlags(
        whoPays: false,
        menu: parsedFeatures.menu,
        wheel: parsedFeatures.wheel,
        english: parsedFeatures.english,
        cleaningMode: parsedFeatures.cleaningMode,
        manualExit: false,
        baristaRecommendation: false,
        wheelContent: false,
        themes: false,
        volumeControl: false,
        analytics: false,
      );
      featureSource = '${featureSource}_enforced_trial';
    }

    if (kDebugMode) {
      debugPrint(
        'LicenseStatus.fromJson: mode=$modeStr, plan=$planStr, '
        'resolvedMode=${resolvedMode.name}, featureSource=$featureSource',
      );
    }

    return LicenseStatus(
      active: active,
      mode: resolvedMode,
      branchName: _optString(json['branch_name']),
      customerName: _optString(json['customer_name']),
      plan: _optString(json['plan']),
      expiresAt: _optString(json['expires_at']),
      trialExpiresAt: _optString(json['trial_expires_at']),
      features: parsedFeatures,
      reason: _optString(json['reason']),
      lastCheckedAt: lastCheckedAt,
      updateAvailable: updateAvailable,
      latestVersion: latestVersion,
      apkUrl: apkUrl,
      apkSha256: apkSha256,
      apkSizeBytes: apkSizeBytes,
      releaseNotes: releaseNotes,
      publishedAt: publishedAt,
      menuAccessToken: menuAccessToken,
      menuProfileId: menuProfileId,
      menuProfileGeneration: menuProfileGeneration,
      maintenanceEnabled: active == true && maintenanceEnabled,
      maintenanceMessage: maintenanceMessage,
      minimumAppVersion: minimumAppVersion,
    );
  }

  factory LicenseStatus.inactive(String reason, LicenseMode mode, {DateTime? lastCheckedAt}) {
    return LicenseStatus(
      active: false,
      mode: mode,
      reason: reason,
      features: FeatureFlags.lockedAll,
      lastCheckedAt: lastCheckedAt,
      updateAvailable: false,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LicenseStatus &&
          runtimeType == other.runtimeType &&
          active == other.active &&
          mode == other.mode &&
          branchName == other.branchName &&
          customerName == other.customerName &&
          plan == other.plan &&
          expiresAt == other.expiresAt &&
          trialExpiresAt == other.trialExpiresAt &&
          reason == other.reason &&
          features == other.features &&
          updateAvailable == other.updateAvailable &&
          latestVersion == other.latestVersion &&
          apkUrl == other.apkUrl &&
          apkSha256 == other.apkSha256 &&
          apkSizeBytes == other.apkSizeBytes &&
          releaseNotes == other.releaseNotes &&
          publishedAt == other.publishedAt &&
          menuAccessToken == other.menuAccessToken &&
          menuProfileId == other.menuProfileId &&
          menuProfileGeneration == other.menuProfileGeneration &&
          maintenanceEnabled == other.maintenanceEnabled &&
          maintenanceMessage == other.maintenanceMessage &&
          minimumAppVersion == other.minimumAppVersion;

  @override
  int get hashCode => Object.hashAll([
    active, mode, branchName, customerName, plan, expiresAt, trialExpiresAt,
    reason, features, updateAvailable, latestVersion, apkUrl, apkSha256,
    apkSizeBytes, releaseNotes, publishedAt, menuAccessToken, menuProfileId,
    menuProfileGeneration, maintenanceEnabled, maintenanceMessage,
    minimumAppVersion,
  ]);
}
