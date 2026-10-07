import 'package:flutter_test/flutter_test.dart';

import 'package:luuqapp/main.dart' show searchFold;

void main() {
  bool matches(String text, String query) =>
      searchFold(text).contains(searchFold(query));

  test('Turkish capital İ is found from a lower-case query', () {
    expect(matches('İtalyan usulü espresso', 'italyan'), isTrue);
    expect(matches('İnce Belli Çay', 'ince'), isTrue);
  });

  test('English names with a capital I still match', () {
    expect(matches('Iced Latte', 'iced'), isTrue);
    expect(matches('Iced Latte', 'ICED'), isTrue);
  });

  test('dotless ı and dotted i are treated alike', () {
    expect(matches('Ilık süt', 'ilik'), isTrue);
    expect(matches('Sıcak çikolata', 'sicak'), isTrue);
  });

  test('other Turkish letters keep their own identity', () {
    expect(matches('Şeker', 'seker'), isFalse);
    expect(matches('Çay', 'çay'), isTrue);
  });
}
