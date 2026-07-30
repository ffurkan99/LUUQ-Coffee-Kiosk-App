import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// UTF-8 kaynak dosyaları yanlışlıkla Latin-1 olarak yeniden kodlandığında
/// Türkçe karakterler 'Ã¼' (ü), 'Ä±' (ı), 'ÅŸ' (ş), 'ÄŸ' (ğ) gibi çift bayt
/// kalıntılarına dönüşür ve string karşılaştırmaları sessizce başarısız olur
/// (ör. kategori filtreleri, damak modu eşleştirmesi). Türkçe metinde bu
/// karakterlerin meşru bir kullanımı yoktur; varlıkları her zaman bozulmadır.
void main() {
  test('lib sources contain no mojibake artifacts', () {
    final mojibake = RegExp('[ÃÄÅ]|â€');
    final offenders = <String>[];

    final libDir = Directory('lib');
    expect(libDir.existsSync(), isTrue, reason: 'run from the package root');

    final dartFiles = libDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

    for (final file in dartFiles) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (mojibake.hasMatch(lines[i])) {
          offenders.add('${file.path}:${i + 1}: ${lines[i].trim()}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Bozuk kodlanmış Türkçe karakter bulundu; dosyayı UTF-8 olarak '
          'düzeltin:\n${offenders.join('\n')}',
    );
  });
}
