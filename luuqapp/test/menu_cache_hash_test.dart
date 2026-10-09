import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luuqapp/menu/menu_cache.dart';

void main() {
  test('background hashing gives the same digest as the UI-thread one', () async {
    final random = Random(7);
    final bytes = List<int>.generate(300 * 1024, (_) => random.nextInt(256));
    final expected = sha256.convert(bytes).toString();

    expect(await MenuCache.bytesSha256ForTesting(bytes), expected);

    final dir = await Directory.systemTemp.createTemp('menu_hash_');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}${Platform.pathSeparator}photo.jpg');
    await file.writeAsBytes(bytes, flush: true);
    expect(await MenuCache.pathSha256ForTesting(file.path), expected);
  });
}
