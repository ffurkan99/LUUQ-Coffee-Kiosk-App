import 'package:flutter_test/flutter_test.dart';
import 'package:luuqapp/main.dart' show AppLanguage, displayUpper;

void main() {
  test('Turkish mode uses the Turkish i rule', () {
    expect(displayUpper('Bitki Çayı', language: AppLanguage.tr), 'BİTKİ ÇAYI');
    expect(
      displayUpper('Sıcak Çikolata', language: AppLanguage.tr),
      'SICAK ÇİKOLATA',
    );
    expect(
      displayUpper('Filtre Kahve', language: AppLanguage.tr),
      'FİLTRE KAHVE',
    );
  });

  test('English mode keeps the English rule', () {
    expect(displayUpper('Bitki Çayı', language: AppLanguage.en), 'BITKI ÇAYI');
    expect(
      displayUpper('White Mocha', language: AppLanguage.en),
      'WHITE MOCHA',
    );
  });
}
