import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('main.dart honours the kiosk type scale and muted-text rules', () {
    final source = File('lib/main.dart').readAsStringSync();

    // Kiosk tip ölçeği (docs/ui-audit-2026-07-21.md D1/D2): rozet tabanı
    // _fsBadge (12), ikincil metin tabanı _fsCaption (14). 10-13px serbest
    // literaller ölçek dışıdır ve kiosk izleme mesafesinde okunmaz.
    expect(
      source.contains('fontSize: 10,'),
      isFalse,
      reason: 'Rozetler _fsBadge (12) kullanmalı, 10px değil.',
    );
    expect(source.contains('fontSize: 11,'), isFalse);
    expect(
      source.contains('fontSize: 12,'),
      isFalse,
      reason: 'Rozetler _fsBadge sabitini kullanmalı, 12 literalini değil.',
    );
    expect(
      source.contains('fontSize: 13,'),
      isFalse,
      reason: 'Caption metinler _fsCaption (14) kullanmalı, 13px değil.',
    );

    expect(source.contains('const double _fsBadge = 12'), isTrue);
    expect(source.contains('const double _fsCaption = 14'), isTrue);

    // Soluk METİN _mutedText kullanır (koyu zeminde ~6:1 kontrast);
    // _muted yalnız ikon/çizgi soldurma için kalır.
    expect(source.contains('const _mutedText = Color(0xFFA29DB0)'), isTrue);
  });
}
