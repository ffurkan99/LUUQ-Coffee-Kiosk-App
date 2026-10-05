/// Version format standard:
///
///   pubspec.yaml  → version: X.Y.Z+BUILD   (no leading 'v')
///   API / display → vX.Y.Z+BUILD            (with leading 'v')
///   BUILD         → Android versionCode; must increment with every APK release.
///
/// Examples:
///   version: 1.1.1+2   (pubspec)
///   v1.1.1+2           (API / admin panel)
library;

/// Parsed representation of a LUUQ version string.
class VersionInfo {
  /// Three-segment version name, e.g. '1.1.1' (never starts with 'v').
  final String versionName;

  /// Android versionCode / build number, e.g. 2 (from the '+2' part).
  /// Zero means no build number was provided.
  final int versionCode;

  const VersionInfo(this.versionName, this.versionCode);

  // ---------------------------------------------------------------------------
  // Parsing
  // ---------------------------------------------------------------------------

  /// Parse a version string such as `'v1.1.1+2'`, `'1.1.0'`, or `'1.1'` into
  /// a [VersionInfo].  Returns `null` when [versionStr] is blank or has no
  /// recognisable version segment.
  static VersionInfo? parse(String versionStr) {
    var clean = versionStr.trim();
    if (clean.isEmpty) return null;

    // Strip optional leading 'v' or 'V'
    if (clean.startsWith('v') || clean.startsWith('V')) {
      clean = clean.substring(1);
    }

    // Split on '+' to separate versionName from versionCode
    final plusParts = clean.split('+');
    if (plusParts.isEmpty || plusParts[0].trim().isEmpty) return null;

    var versionName = plusParts[0].trim();
    final versionCode = plusParts.length > 1
        ? (int.tryParse(plusParts[1].trim()) ?? 0)
        : 0;

    // Normalise to three segments: '1' → '1.0.0', '1.1' → '1.1.0'
    final segments = versionName.split('.');
    if (segments.length == 1 && segments[0].isNotEmpty) {
      versionName = '${segments[0]}.0.0';
    } else if (segments.length == 2) {
      versionName = '${segments[0]}.${segments[1]}.0';
    }

    return VersionInfo(versionName, versionCode);
  }

  // ---------------------------------------------------------------------------
  // Comparison helpers
  // ---------------------------------------------------------------------------

  /// Compare two normalised version-name strings (e.g. `'1.2.0'` vs `'1.1.3'`).
  ///
  /// Returns a positive integer if [v1] > [v2], a negative integer if [v1] <
  /// [v2], and 0 if they are equal.
  static int compareVersionNames(String v1, String v2) {
    final parts1 = v1.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final parts2 = v2.split('.').map((s) => int.tryParse(s) ?? 0).toList();

    for (var i = 0; i < 3; i++) {
      final a = parts1.length > i ? parts1[i] : 0;
      final b = parts2.length > i ? parts2[i] : 0;
      if (a > b) return 1;
      if (a < b) return -1;
    }
    return 0;
  }

  /// Returns `true` when this version is strictly newer than [other].
  ///
  /// A higher [versionCode] wins when the [versionName] strings are equal.
  bool isNewerThan(VersionInfo other) {
    final cmp = compareVersionNames(versionName, other.versionName);
    if (cmp != 0) return cmp > 0;
    return versionCode > other.versionCode;
  }

  /// Whether [current] is older than the panel's [minimum]. A minimum without
  /// a build number compares version names only. Unparseable values never
  /// block: a typo in the panel must not lock every kiosk.
  static bool isBelowMinimum(String current, String? minimum) {
    final min = VersionInfo.parse(minimum ?? '');
    final cur = VersionInfo.parse(current);
    final numeric = RegExp(r'^\d+\.\d+\.\d+$');
    if (min == null ||
        cur == null ||
        !numeric.hasMatch(min.versionName) ||
        !numeric.hasMatch(cur.versionName)) {
      return false;
    }
    if (min.versionCode <= 0) {
      return compareVersionNames(cur.versionName, min.versionName) < 0;
    }
    return !cur.isEqualOrNewerThan(min);
  }

  /// Returns `true` when this version is the same as or newer than [other].
  bool isEqualOrNewerThan(VersionInfo other) {
    final cmp = compareVersionNames(versionName, other.versionName);
    if (cmp != 0) return cmp > 0;
    return versionCode >= other.versionCode;
  }

  // ---------------------------------------------------------------------------
  // Diagnostics
  // ---------------------------------------------------------------------------

  @override
  String toString() =>
      versionCode > 0 ? 'v$versionName+$versionCode' : 'v$versionName';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VersionInfo &&
          versionName == other.versionName &&
          versionCode == other.versionCode;

  @override
  int get hashCode => versionName.hashCode ^ versionCode.hashCode;
}
