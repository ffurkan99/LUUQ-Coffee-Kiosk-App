import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Çark ve vitrin kartı, ürün görsellerini `assets/menu/<ad>.jpg` yolundan
/// `assets/menu/png/<ad>.png` yoluna çevirerek yükler (saydam arka planlı
/// kesip-çıkarılmış sürümler). png karşılığı olmayan bir ürün çarka
/// düştüğünde fotoğraf yerine jenerik ikon görünür. Bu test, yeni ürün
/// görseli eklendiğinde png sürümünün unutulmasını yakalar.
void main() {
  test('every menu image has a wheel png counterpart', () {
    // Bilinen eksikler: png'si üretilmemiş görseller. Yeni bir png
    // eklendiğinde bu listeden çıkarılmalı; test bayatlamayı da denetler.
    const knownMissing = {'sansebastian.png'};

    final menuDir = Directory('assets/menu');
    final pngDir = Directory('assets/menu/png');
    expect(menuDir.existsSync(), isTrue, reason: 'run from the package root');
    expect(pngDir.existsSync(), isTrue);

    final pngNames = pngDir
        .listSync()
        .whereType<File>()
        .map((file) => file.uri.pathSegments.last)
        .toSet();

    final missing = <String>{};
    for (final entity in menuDir.listSync().whereType<File>()) {
      final name = entity.uri.pathSegments.last;
      if (!name.endsWith('.jpg') && !name.endsWith('.jpeg')) continue;
      final pngName =
          '${name.replaceAll(RegExp(r'\.(jpg|jpeg)$'), '')}.png';
      if (!pngNames.contains(pngName)) {
        missing.add(pngName);
      }
    }

    expect(
      missing,
      equals(knownMissing),
      reason:
          'assets/menu/png altında eksik (veya artık gereksiz yere '
          'knownMissing listesinde duran) çark görselleri var.',
    );
  });
}
