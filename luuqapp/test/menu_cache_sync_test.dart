import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luuqapp/menu/menu_cache.dart';
import 'package:luuqapp/menu/menu_models.dart';

const _pngBytes = <int>[137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13];

MenuCatalog _catalog(String name) => MenuCatalog.fromApiJson({
  'menu_version': 1,
  'catalog': {
    'categories': [
      {
        'id': 'c1',
        'name_tr': 'Kahve',
        'items': [
          {'id': 'i1', 'category_id': 'c1', 'name_tr': name},
        ],
      },
    ],
  },
});

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('luuq_menu_sync_test_');
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('pending config round-trips per scope and clears when empty', () async {
    final cache = MenuCache(rootDirectory: directory);
    await cache.writePendingConfig('profile:a', {
      'wheel': {
        'values': {'wheel_item_ids': List.generate(8, (i) => 'w$i')},
        'idempotency_key': 'k-1',
      },
    });
    expect((await cache.readPendingConfig('profile:a')).keys, ['wheel']);
    expect(await cache.readPendingConfig('profile:b'), isEmpty);

    await cache.writePendingConfig('profile:a', {});
    expect(await cache.readPendingConfig('profile:a'), isEmpty);
  });

  test('a corrupt active.json falls back to the previous snapshot', () async {
    final cache = MenuCache(rootDirectory: directory);
    await cache.writeActive('profile:a', _catalog('Eski'));
    await cache.writeActive('profile:a', _catalog('Yeni'));
    expect((await cache.readActive('profile:a'))!.items.single.nameTr, 'Yeni');

    final scopeDir = directory.listSync().whereType<Directory>().single;
    File('${scopeDir.path}${Platform.pathSeparator}active.json')
        .writeAsStringSync('{broken');
    expect((await cache.readActive('profile:a'))!.items.single.nameTr, 'Eski');
  });

  test('failed downloads back off instead of refetching every poll', () async {
    var requests = 0;
    final cache = MenuCache(
      rootDirectory: directory,
      client: MockClient((_) async {
        requests++;
        return http.Response('nope', 404);
      }),
    );
    expect(cache.isDownloadBackedOff('profile:a', 'i1', 'normal'), isFalse);
    final path = await cache.downloadImage(
      scopeKey: 'profile:a',
      url: 'https://example.test/i1.png',
      itemId: 'i1',
    );
    expect(path, isNull);
    expect(requests, 1);
    expect(cache.isDownloadBackedOff('profile:a', 'i1', 'normal'), isTrue);
    expect(cache.isDownloadBackedOff('profile:b', 'i1', 'normal'), isFalse);
  });

  test('a successful download clears the backoff', () async {
    var fail = true;
    final digest = sha256.convert(_pngBytes).toString();
    final cache = MenuCache(
      rootDirectory: directory,
      client: MockClient((_) async {
        if (fail) return http.Response('nope', 500);
        return http.Response.bytes(
          _pngBytes,
          200,
          headers: {'content-type': 'image/png'},
        );
      }),
    );
    Future<String?> download() => cache.downloadImage(
      scopeKey: 'profile:a',
      url: 'https://example.test/i1.png',
      itemId: 'i1',
      expectedSha256: digest,
    );
    expect(await download(), isNull);
    fail = false;
    final path = await download();
    expect(path, isNotNull);
    expect(cache.isDownloadBackedOff('profile:a', 'i1', 'normal'), isFalse);
    expect(await cache.isValidImage(path, expectedSha256: digest), isTrue);
  });

  test('cached hash is reused until the file changes', () async {
    final cache = MenuCache(rootDirectory: directory);
    final file = File('${directory.path}${Platform.pathSeparator}a.png')
      ..writeAsBytesSync(_pngBytes);
    final digest = sha256.convert(_pngBytes).toString();
    expect(await cache.isValidImage(file.path, expectedSha256: digest), isTrue);

    // Same size, different bytes and a new mtime: must be re-hashed.
    final tampered = List<int>.from(_pngBytes)..[11] = 99;
    file.writeAsBytesSync(tampered);
    file.setLastModifiedSync(DateTime.now().add(const Duration(seconds: 5)));
    expect(
      await cache.isValidImage(file.path, expectedSha256: digest),
      isFalse,
    );
  });

  test('an oversized image without Content-Length is cut off at 5 MB', () async {
    var chunksSent = 0;
    final cache = MenuCache(
      rootDirectory: directory,
      client: MockClient.streaming((request, _) async {
        Stream<List<int>> body() async* {
          for (var i = 0; i < 6; i++) {
            chunksSent++;
            yield List<int>.filled(1024 * 1024, 0);
          }
        }

        return http.StreamedResponse(
          body(),
          200,
          headers: {'content-type': 'image/png'},
        );
      }),
    );
    final path = await cache.downloadImage(
      scopeKey: 'profile:a',
      url: 'https://example.test/big.png',
      itemId: 'big',
    );
    expect(path, isNull);
    expect(chunksSent, lessThan(7));
  });

  test('a Content-Length above 5 MB is refused before reading', () async {
    var read = false;
    final cache = MenuCache(
      rootDirectory: directory,
      client: MockClient.streaming((request, _) async {
        Stream<List<int>> body() async* {
          read = true;
          yield _pngBytes;
        }

        return http.StreamedResponse(
          body(),
          200,
          contentLength: 6 * 1024 * 1024,
          headers: {'content-type': 'image/png'},
        );
      }),
    );
    final path = await cache.downloadImage(
      scopeKey: 'profile:a',
      url: 'https://example.test/big.png',
      itemId: 'big',
    );
    expect(path, isNull);
    expect(read, isFalse);
  });

  test('a verified image is not read again while unchanged', () async {
    final cache = MenuCache(rootDirectory: directory);
    final file = File('${directory.path}${Platform.pathSeparator}v.png')
      ..writeAsBytesSync(_pngBytes);
    final digest = sha256.convert(_pngBytes).toString();
    final stamp = DateTime(2026, 10, 7, 12);
    file.setLastModifiedSync(stamp);
    expect(await cache.isValidImage(file.path, expectedSha256: digest), isTrue);

    // Same size and mtime but unreadable content: the cached verdict stands.
    final broken = List<int>.filled(_pngBytes.length, 0);
    file.writeAsBytesSync(broken);
    file.setLastModifiedSync(stamp);
    expect(await cache.isValidImage(file.path, expectedSha256: digest), isTrue);
  });

  test('pruneImages keeps referenced files and deletes the rest', () async {
    final cache = MenuCache(rootDirectory: directory);
    await cache.writeActive('profile:a', _catalog('X'));
    final scopeDir = directory.listSync().whereType<Directory>().single;
    final images = Directory('${scopeDir.path}${Platform.pathSeparator}images')
      ..createSync();
    final keep = File('${images.path}${Platform.pathSeparator}keep.png')
      ..writeAsBytesSync(_pngBytes);
    final stale = File('${images.path}${Platform.pathSeparator}stale.png')
      ..writeAsBytesSync(_pngBytes);
    final partial = File('${images.path}${Platform.pathSeparator}x.png.1.part')
      ..writeAsBytesSync(_pngBytes);

    await cache.pruneImages('profile:a', {keep.path});
    expect(keep.existsSync(), isTrue);
    expect(stale.existsSync(), isFalse);
    expect(partial.existsSync(), isTrue);
  });

  test('cache json encodes pending-safe catalogs', () {
    final encoded = jsonDecode(_catalog('Y').encode()) as Map<String, dynamic>;
    expect(MenuCatalog.fromCacheJson(encoded).items.single.nameTr, 'Y');
  });
}
