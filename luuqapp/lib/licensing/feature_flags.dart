class FeatureFlags {
  final bool whoPays;
  final bool menu;
  final bool wheel;
  final bool english;
  final bool cleaningMode;
  final bool manualExit;
  final bool baristaRecommendation;
  final bool wheelContent;
  final bool themes;
  final bool volumeControl;
  final bool analytics;

  const FeatureFlags({
    this.whoPays = false,
    this.menu = true,
    this.wheel = true,
    this.english = true,
    this.cleaningMode = true,
    this.manualExit = false,
    this.baristaRecommendation = false,
    this.wheelContent = false,
    this.themes = false,
    this.volumeControl = false,
    this.analytics = false,
  });

  static bool _parseBool(dynamic val, bool fallback) {
    if (val == null) return fallback;
    if (val is bool) return val;
    if (val is num) return val.toInt() == 1;
    if (val is String) {
      final s = val.trim().toLowerCase();
      return s == '1' || s == 'true';
    }
    return fallback;
  }

  factory FeatureFlags.fromJson(Map<String, dynamic> json, {FeatureFlags fallback = const FeatureFlags()}) {
    return FeatureFlags(
      whoPays: _parseBool(json['who_pays'], fallback.whoPays),
      menu: _parseBool(json['menu'], fallback.menu),
      wheel: _parseBool(json['wheel'], fallback.wheel),
      english: _parseBool(json['english'], fallback.english),
      cleaningMode: _parseBool(json['cleaning_mode'], fallback.cleaningMode),
      manualExit: _parseBool(json['manual_exit'], fallback.manualExit),
      baristaRecommendation: _parseBool(json['barista_recommendation'], fallback.baristaRecommendation),
      wheelContent: _parseBool(json['wheel_content'], fallback.wheelContent),
      themes: _parseBool(json['themes'], fallback.themes),
      volumeControl: _parseBool(json['volume_control'], fallback.volumeControl),
      analytics: _parseBool(json['analytics'], fallback.analytics),
    );
  }

  Map<String, bool> toJson() {
    return {
      'who_pays': whoPays,
      'menu': menu,
      'wheel': wheel,
      'english': english,
      'cleaning_mode': cleaningMode,
      'manual_exit': manualExit,
      'barista_recommendation': baristaRecommendation,
      'wheel_content': wheelContent,
      'themes': themes,
      'volume_control': volumeControl,
      'analytics': analytics,
    };
  }

  /// Default flags used when no license or trial is active
  static const FeatureFlags lockedAll = FeatureFlags(
    whoPays: false,
    menu: false,
    wheel: false,
    english: false,
    cleaningMode: false,
    manualExit: false,
    baristaRecommendation: false,
    wheelContent: false,
    themes: false,
    volumeControl: false,
    analytics: false,
  );

  /// Default flags for a trial plan
  static const FeatureFlags trialDefault = FeatureFlags(
    whoPays: false,
    menu: true,
    wheel: true,
    english: true,
    cleaningMode: true,
    manualExit: false,
    baristaRecommendation: false,
    wheelContent: false,
    themes: false,
    volumeControl: false,
    analytics: false,
  );

  /// Default flags for a pro/licensed plan
  static const FeatureFlags proDefault = FeatureFlags(
    whoPays: true,
    menu: true,
    wheel: true,
    english: true,
    cleaningMode: true,
    manualExit: true,
    baristaRecommendation: true,
    wheelContent: true,
    themes: true,
    volumeControl: true,
    analytics: true,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FeatureFlags &&
          runtimeType == other.runtimeType &&
          whoPays == other.whoPays &&
          menu == other.menu &&
          wheel == other.wheel &&
          english == other.english &&
          cleaningMode == other.cleaningMode &&
          manualExit == other.manualExit &&
          baristaRecommendation == other.baristaRecommendation &&
          wheelContent == other.wheelContent &&
          themes == other.themes &&
          volumeControl == other.volumeControl &&
          analytics == other.analytics;

  @override
  int get hashCode =>
      whoPays.hashCode ^
      menu.hashCode ^
      wheel.hashCode ^
      english.hashCode ^
      cleaningMode.hashCode ^
      manualExit.hashCode ^
      baristaRecommendation.hashCode ^
      wheelContent.hashCode ^
      themes.hashCode ^
      volumeControl.hashCode ^
      analytics.hashCode;
}
