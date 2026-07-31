import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Menü verisine (ad, açıklama, etiket) Türkçe karakter içeren yeni bir metin
/// eklendiğinde `_menuDict` sözlüğüne İngilizce karşılığı da eklenmeli;
/// aksi halde EN modda metin Türkçe kalır. Bu test main.dart kaynağını
/// tarayarak bu tür eksikleri yakalar ('Yazın İyisi' etiketi ve üç tatlı
/// açıklaması bu şekilde iki denetim turunda elle bulunmuştu).
void main() {
  test('every Turkish menu string has an EN dictionary entry', () {
    final source = File('lib/main.dart').readAsStringSync();

    final dictRegion = _region(
      source,
      RegExp(r'const Map<String, String> _menuDict = \{'),
    );
    final menuRegion = _region(source, RegExp(r'const _menuCategories = \{'));

    final turkish = RegExp('[çğıöşüÇĞİÖŞÜ]');
    final literal = RegExp(r"'([^']+)'");

    final missing = <String>{};
    for (final line in menuRegion.split('\n')) {
      for (final match in literal.allMatches(line)) {
        final value = match.group(1)!;
        if (!turkish.hasMatch(value)) continue;
        if (!dictRegion.contains("'$value'")) {
          missing.add(value);
        }
      }
    }

    expect(
      missing,
      isEmpty,
      reason:
          '_menuDict sözlüğünde İngilizce karşılığı olmayan menü metinleri '
          'var:\n${missing.join('\n')}',
    );
  });
}

String _region(String source, RegExp opener) {
  final start = source.indexOf(opener);
  expect(start, isNot(-1), reason: 'region opener not found: $opener');
  final end = source.indexOf('\n};', start);
  expect(end, isNot(-1), reason: 'region closer not found after $opener');
  return source.substring(start, end);
}
