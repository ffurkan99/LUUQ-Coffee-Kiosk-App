import 'dart:collection';

import 'package:flutter/widgets.dart';

/// Results of [fitNameBeforeBadge] keyed by every input, newest last. The
/// menu calls it for every card on every rebuild (each typed search letter);
/// a name is measured once per size instead.
final LinkedHashMap<Object, String> _fitCache = LinkedHashMap<Object, String>();
const int _fitCacheSize = 512;
bool _fitCacheListensToFonts = false;

@visibleForTesting
int get fitNameCacheLengthForTesting => _fitCache.length;

/// Shortens [name] so that it fits in [maxLines] lines of [maxWidth] with
/// [badgeWidth] still free at the end of its last line, for a badge drawn
/// inline right after the name.
///
/// A name that fits is returned unchanged; otherwise the longest prefix that
/// fits with a trailing '…'. With a [badgeWidth] of 0 it only caps the lines.
String fitNameBeforeBadge({
  required String name,
  required TextStyle style,
  required double maxWidth,
  double badgeWidth = 0,
  int maxLines = 2,
  TextScaler textScaler = TextScaler.noScaling,
  TextDirection textDirection = TextDirection.ltr,
}) {
  if (maxWidth <= 0 || name.isEmpty) return name;
  if (!_fitCacheListensToFonts) {
    try {
      // New fonts change the measurements: start over.
      PaintingBinding.instance.systemFonts.addListener(_fitCache.clear);
      _fitCacheListensToFonts = true;
    } catch (_) {
      // No binding (plain unit test): nothing to listen to.
    }
  }
  final key = (name, style, maxWidth, badgeWidth, maxLines, textScaler, textDirection);
  final cached = _fitCache.remove(key);
  if (cached != null) {
    _fitCache[key] = cached;
    return cached;
  }
  final fitted = _fitName(
    name: name,
    style: style,
    maxWidth: maxWidth,
    badgeWidth: badgeWidth,
    maxLines: maxLines,
    textScaler: textScaler,
    textDirection: textDirection,
  );
  _fitCache[key] = fitted;
  if (_fitCache.length > _fitCacheSize) _fitCache.remove(_fitCache.keys.first);
  return fitted;
}

String _fitName({
  required String name,
  required TextStyle style,
  required double maxWidth,
  required double badgeWidth,
  required int maxLines,
  required TextScaler textScaler,
  required TextDirection textDirection,
}) {
  final painter = TextPainter(
    textDirection: textDirection,
    textScaler: textScaler,
    // One line more than allowed, to tell "fits" from "cut off".
    maxLines: maxLines + 1,
  );

  bool fits(String text) {
    painter
      ..text = TextSpan(text: text, style: style)
      ..layout(maxWidth: maxWidth);
    final lines = painter.computeLineMetrics();
    if (lines.length > maxLines) return false;
    return lines.isEmpty || lines.last.width + badgeWidth <= maxWidth;
  }

  try {
    if (fits(name)) return name;
    final characters = name.characters.toList();
    var low = 0; // fits (an empty prefix always does)
    var high = characters.length; // does not fit
    while (high - low > 1) {
      final middle = (low + high) ~/ 2;
      if (fits('${characters.take(middle).join().trimRight()}…')) {
        low = middle;
      } else {
        high = middle;
      }
    }
    return '${characters.take(low).join().trimRight()}…';
  } finally {
    painter.dispose();
  }
}
