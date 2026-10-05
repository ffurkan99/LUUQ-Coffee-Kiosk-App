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

  factory LicenseStatus.fromJson(
    Map<String, dynamic> json,
    LicenseMode defaultMode, {
    DateTime? lastCheckedAt,
  }) {
    final active = json['active'] ?? false;
    final updateJson = json['update'] as Map<String, dynamic>?;
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
    LicenseMode resolvedMode = defaultMode;
    if (trialValues.contains(modeLower) ||
        trialValues.contains(planLower) ||
        trialValues.any((v) => modeLower.contains(v) || planLower.contains(v))) {
      resolvedMode = LicenseMode.trial;
    } else if (licensedValues.contains(modeLower) ||
        licensedValues.contains(planLower) ||
        licensedValues.any((v) => modeLower.contains(v) || planLower.contains(v))) {
      resolvedMode = LicenseMode.licensed;
    } else if (modeLower == 'none' || planLower == 'none') {
      resolvedMode = LicenseMode.none;
    } else if (defaultMode != LicenseMode.none) {
      resolvedMode = defaultMode;
    } else if (active) {
      resolvedMode = LicenseMode.licensed;
    }

    final fallbackFlags = resolvedMode == LicenseMode.trial
        ? FeatureFlags.trialDefault
        : (resolvedMode == LicenseMode.licensed
              ? FeatureFlags.proDefault
              : FeatureFlags.lockedAll);
    final featuresJson = json['features'] as Map<String, dynamic>?;
    String featureSource = 'none';
    FeatureFlags parsedFeatures;
    if (!active) {
      parsedFeatures = FeatureFlags.lockedAll;
      featureSource = 'inactive_locked_all';
    } else if (featuresJson != null && featuresJson.isNotEmpty) {
      parsedFeatures = FeatureFlags.fromJson(featuresJson, fallback: fallbackFlags);
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
      branchName: json['branch_name'] as String?,
      customerName: json['customer_name'] as String?,
      plan: json['plan'] as String?,
      expiresAt: json['expires_at'] as String?,
      trialExpiresAt: json['trial_expires_at'] as String?,
      features: parsedFeatures,
      reason: json['reason'] as String?,
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
