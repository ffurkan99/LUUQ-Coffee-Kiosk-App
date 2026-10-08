import 'package:flutter/widgets.dart';

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
