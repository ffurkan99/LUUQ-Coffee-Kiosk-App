import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luuqapp/src/menu/name_fit.dart';

// The test font draws every character as a square as wide as the font size:
// at size 10, a 100 px line holds 10 characters.
const _style = TextStyle(fontSize: 10, fontFamily: 'FlutterTest');

/// The lines [text] takes at [_style] in [width].
List<LineMetrics> _lines(String text, double width) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: _style),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: width);
  final lines = painter.computeLineMetrics();
  painter.dispose();
  return lines;
}

void main() {
  test('a short name is returned unchanged', () {
    expect(
      fitNameBeforeBadge(
        name: 'Latte',
        style: _style,
        maxWidth: 100,
        badgeWidth: 30,
      ),
      'Latte',
    );
  });

  test('a long name is cut to two lines ending in an ellipsis', () {
    const name = 'Beyaz Çikolatalı Karamelli Buzlu Latte';
    final fitted = fitNameBeforeBadge(name: name, style: _style, maxWidth: 100);
    expect(fitted, endsWith('…'));
    expect(name.startsWith(fitted.substring(0, fitted.length - 1)), isTrue);
    expect(_lines(fitted, 100).length, lessThanOrEqualTo(2));
    // As long as it can be: one more character would not fit.
    final longer = '${name.substring(0, fitted.length)}…';
    expect(_lines(longer, 100).length, greaterThan(2));
  });

  test('the badge width stays free at the end of the last line', () {
    const name = 'Karamel Macchiato Latte';
    final fitted = fitNameBeforeBadge(
      name: name,
      style: _style,
      maxWidth: 100,
      badgeWidth: 40,
    );
    final lines = _lines(fitted, 100);
    expect(lines.length, lessThanOrEqualTo(2));
    expect(lines.last.width + 40, lessThanOrEqualTo(100));
  });

  test('a name that just fits with its badge is kept whole', () {
    // "Mocha Latte" takes two lines ("Mocha " / "Latte", 50 px), leaving
    // 50 px for the badge.
    expect(
      fitNameBeforeBadge(
        name: 'Mocha Latte',
        style: _style,
        maxWidth: 60,
        badgeWidth: 10,
      ),
      'Mocha Latte',
    );
  });

  test('Turkish letters are never split', () {
    const name = 'İğneli Şöğüşçü Çağlayan Ölçülü Ürün';
    final fitted = fitNameBeforeBadge(
      name: name,
      style: _style,
      maxWidth: 80,
      badgeWidth: 20,
    );
    final kept = fitted.substring(0, fitted.length - 1);
    expect(name.startsWith(kept), isTrue);
    expect(kept, isNot(endsWith(' ')));
  });

  test('a zero width or an empty name is returned as is', () {
    expect(
      fitNameBeforeBadge(name: 'Latte', style: _style, maxWidth: 0),
      'Latte',
    );
    expect(fitNameBeforeBadge(name: '', style: _style, maxWidth: 100), '');
  });
}
