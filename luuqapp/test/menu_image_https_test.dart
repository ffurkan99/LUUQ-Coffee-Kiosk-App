import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luuqapp/menu/menu_cache.dart';

void main() {
  late Directory directory;
  late List<Uri> requested;
  late MenuCache cache;
  final jpeg = [0xff, 0xd8, 0xff, ...List<int>.filled(32, 7)];

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('luuq_https_');
    requested = [];
    cache = MenuCache(
      rootDirectory: directory,
      client: MockClient((request) async {
        requested.add(request.url);
        return http.Response.bytes(
          jpeg,
          200,
          headers: {'content-type': 'image/jpeg'},
        );
      }),
    );
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  Future<String?> download(String url) => cache.downloadImage(
    scopeKey: 'profile:p1',
    url: url,
    itemId: 'item',
    variant: 'normal',
    expectedSha256: sha256.convert(jpeg).toString(),
    expectedMime: 'image/jpeg',
  );

  test('an https image is downloaded', () async {
    expect(await download('https://luuq.example/img.jpg'), isNotNull);
    expect(requested, hasLength(1));
  });

  test('a plain http or odd URL is never fetched', () async {
    for (final url in [
      'http://luuq.example/img.jpg',
      'ftp://luuq.example/img.jpg',
      'file:///etc/passwd',
      'not a url',
    ]) {
      expect(await download(url), isNull, reason: url);
    }
    expect(requested, isEmpty);
  });
}
