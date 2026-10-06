import 'dart:io';

/// `lib/main.dart` kütüphanesinin tüm kaynağı: main.dart ve `part` dosyaları
/// (`lib/app/**`). Kaynak tarayan testler kod hangi part dosyasına taşınırsa
/// taşınsın tamamını görmeli; yalnız main.dart'ı okumak kontrolü sessizce
/// boşa düşürür.
String readMainLibrarySource() {
  final buffer = StringBuffer(File('lib/main.dart').readAsStringSync());
  final partsDir = Directory('lib/app');
  if (partsDir.existsSync()) {
    final parts =
        partsDir
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    for (final part in parts) {
      buffer
        ..writeln()
        ..write(part.readAsStringSync());
    }
  }
  return buffer.toString();
}
