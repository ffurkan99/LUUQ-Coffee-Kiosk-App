import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luuqapp/menu/menu_cache.dart';
import 'package:luuqapp/menu/menu_models.dart';

void main() {
  group('remote menu media model', () {
    test(
      'reads and writes both image variants while old payloads stay valid',
      () {
        final catalog = MenuCatalog.fromApiJson({
          'schema_version': 1,
          'menu_version': 2,
          'catalog_revision': 3,
          'wheel_revision': 4,
          'barista_revision': 5,
          'catalog': {
            'categories': [
              {
                'id': 'category-id',
                'name_tr': 'İçecekler',
                'name_en': 'Drinks',
                'items': [
                  {
                    'id': 'item-id',
                    'category_id': 'category-id',
                    'name_tr': 'Aynı ad',
                    'name_en': 'First translation',
                    'tags': ['Klasik'],
                    'tags_en': ['Classic'],
                    'image_url': 'https://example.test/normal',
                    'image_sha256': List.filled(64, 'a').join(),
                    'image_mime': 'image/jpeg',
                    'transparent_image_url': 'https://example.test/cutout',
                    'transparent_image_sha256': List.filled(64, 'b').join(),
                    'transparent_image_mime': 'image/png',
                  },
                ],
              },
            ],
          },
        });

        final item = catalog.items.single;
        expect(item.imageSha256, List.filled(64, 'a').join());
        expect(item.transparentImageSha256, List.filled(64, 'b').join());
        expect(item.tagsEn, ['Classic']);
        expect(
          RemoteMenuItem.fromJson({
            'id': 'old-item',
            'category_id': 'old-category',
            'name_tr': 'Eski',
          }).transparentImageUrl,
          isNull,
        );
        final encoded = catalog.toJson()['catalog'] as Map<String, dynamic>;
        final roundTrip = MenuCatalog.fromApiJson({'catalog': encoded});
        expect(
          roundTrip.items.single.transparentImageUrl,
          'https://example.test/cutout',
        );
      },
    );

    test('same Turkish label keeps each product translation independent', () {
      const itemA = RemoteMenuItem(
        id: 'a',
        categoryId: 'c',
        nameTr: 'Aynı ad',
        nameEn: 'Translation A',
      );
      const itemB = RemoteMenuItem(
        id: 'b',
        categoryId: 'c',
        nameTr: 'Aynı ad',
        nameEn: 'Translation B',
      );

      expect(
        menuTextForLanguage(
          turkish: itemA.nameTr,
          english: itemA.nameEn,
          useEnglish: true,
        ),
        'Translation A',
      );
      expect(
        menuTextForLanguage(
          turkish: itemB.nameTr,
          english: itemB.nameEn,
          useEnglish: true,
        ),
        'Translation B',
      );
    });

    test('drops an image with a malformed content hash, keeps the item', () {
      final item = RemoteMenuItem.fromJson({
        'id': 'item',
        'category_id': 'category',
        'image_url': 'https://example.test/a.jpg',
        'image_sha256': 'not-a-hash',
      });
      expect(item.id, 'item');
      expect(item.imageUrl, isNull);
      expect(item.imageSha256, isNull);
    });

    test('one malformed item does not reject the whole catalog', () {
      final catalog = MenuCatalog.fromApiJson({
        'catalog': {
          'categories': [
            {
              'id': 'c1',
              'name_tr': 'Kahve',
              'items': [
                {'id': 'ok', 'category_id': 'c1', 'name_tr': 'Latte'},
                {'category_id': 'c1', 'name_tr': 'No id'},
              ],
            },
            {'name_tr': 'Category without id'},
          ],
        },
      });
      expect(catalog.categories, hasLength(1));
      expect(catalog.items.map((item) => item.id), ['ok']);
    });

    test('server JSON cannot point the renderer at a local file', () {
      final json = {
        'catalog': {
          'categories': [
            {
              'id': 'c1',
              'items': [
                {
                  'id': 'i1',
                  'category_id': 'c1',
                  'local_image_path': '/data/secret.png',
                  'image_asset': 'assets/menu/cay.jpeg',
                },
              ],
            },
          ],
        },
      };
      final fromApi = MenuCatalog.fromApiJson(json).items.single;
      expect(fromApi.localImagePath, isNull);
      expect(fromApi.imageAsset, 'assets/menu/cay.jpeg');
      expect(
        MenuCatalog.fromCacheJson(json).items.single.localImagePath,
        '/data/secret.png',
      );
    });

    test('only bundled menu assets are accepted as image_asset', () {
      final item = RemoteMenuItem.fromJson({
        'id': 'i',
        'category_id': 'c',
        'image_asset': '../../secret.png',
      });
      expect(item.imageAsset, isNull);
    });
  });

  group('menu image cache integrity', () {
    late Directory directory;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp(
        'luuq_menu_media_test_',
      );
    });

    tearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });

    test(
      'content changes produce a new cache path instead of stale bytes',
      () async {
        final first = _png(1);
        final second = _png(2);
        var payload = first;
        final client = MockClient(
          (_) async => http.Response.bytes(
            payload,
            200,
            headers: {'content-type': 'image/png'},
          ),
        );
        final cache = MenuCache(client: client, rootDirectory: directory);
        final pathA = await cache.downloadImage(
          scopeKey: 'profile:one',
          url: 'https://example.test/menu',
          itemId: '../latte',
          expectedSha256: sha256.convert(first).toString(),
          expectedMime: 'image/png',
        );
        payload = second;
        final pathB = await cache.downloadImage(
          scopeKey: 'profile:one',
          url: 'https://example.test/menu',
          itemId: '../latte',
          expectedSha256: sha256.convert(second).toString(),
          expectedMime: 'image/png',
        );

        expect(pathA, isNotNull);
        expect(pathB, isNotNull);
        expect(pathA, isNot(pathB));
        expect(await File(pathA!).readAsBytes(), first);
        expect(await File(pathB!).readAsBytes(), second);
        expect(pathB, isNot(contains('..')));
      },
    );

    test(
      'reuses a verified image across catalog revisions before requesting it',
      () async {
        final bytes = _png(4);
        var requests = 0;
        final cache = MenuCache(
          rootDirectory: directory,
          client: MockClient((_) async {
            requests++;
            return http.Response.bytes(
              bytes,
              200,
              headers: {'content-type': 'image/png'},
            );
          }),
        );
        final hash = sha256.convert(bytes).toString();
        final firstPath = await cache.downloadImage(
          scopeKey: 'profile:one',
          url: 'https://example.test/menu?signature=first',
          itemId: 'latte',
          expectedSha256: hash,
          expectedMime: 'image/png',
        );
        final nextRevisionPath = await cache.downloadImage(
          scopeKey: 'profile:one',
          url: 'https://example.test/menu?signature=renewed',
          itemId: 'latte',
          expectedSha256: hash,
          expectedMime: 'image/png',
        );

        expect(firstPath, isNotNull);
        expect(nextRevisionPath, firstPath);
        expect(requests, 1);
      },
    );

    test(
      'downloads only the image variant whose content hash changed',
      () async {
        final normalV1 = _png(5);
        final normalV2 = _png(6);
        final transparent = _png(7);
        var normalPayload = normalV1;
        var requests = 0;
        final cache = MenuCache(
          rootDirectory: directory,
          client: MockClient((request) async {
            requests++;
            final isTransparent = request.url.path.endsWith('/transparent');
            return http.Response.bytes(
              isTransparent ? transparent : normalPayload,
              200,
              headers: {'content-type': 'image/png'},
            );
          }),
        );

        final normalPathV1 = await cache.downloadImage(
          scopeKey: 'profile:one',
          url: 'https://example.test/normal',
          itemId: 'latte',
          expectedSha256: sha256.convert(normalV1).toString(),
          expectedMime: 'image/png',
        );
        final transparentPath = await cache.downloadImage(
          scopeKey: 'profile:one',
          url: 'https://example.test/transparent',
          itemId: 'latte',
          variant: 'transparent',
          expectedSha256: sha256.convert(transparent).toString(),
          expectedMime: 'image/png',
        );
        normalPayload = normalV2;
        final normalPathV2 = await cache.downloadImage(
          scopeKey: 'profile:one',
          url: 'https://example.test/normal',
          itemId: 'latte',
          expectedSha256: sha256.convert(normalV2).toString(),
          expectedMime: 'image/png',
        );
        final unchangedTransparentPath = await cache.downloadImage(
          scopeKey: 'profile:one',
          url: 'https://example.test/transparent?renewed=true',
          itemId: 'latte',
          variant: 'transparent',
          expectedSha256: sha256.convert(transparent).toString(),
          expectedMime: 'image/png',
        );

        expect(normalPathV1, isNotNull);
        expect(normalPathV2, isNot(normalPathV1));
        expect(unchangedTransparentPath, transparentPath);
        expect(requests, 3);
      },
    );

    test(
      'redownloads a cached file only when its bytes fail verification',
      () async {
        final bytes = _png(8);
        var requests = 0;
        final cache = MenuCache(
          rootDirectory: directory,
          client: MockClient((_) async {
            requests++;
            return http.Response.bytes(
              bytes,
              200,
              headers: {'content-type': 'image/png'},
            );
          }),
        );
        final hash = sha256.convert(bytes).toString();
        final path = await cache.downloadImage(
          scopeKey: 'profile:one',
          url: 'https://example.test/menu',
          itemId: 'latte',
          expectedSha256: hash,
          expectedMime: 'image/png',
        );
        await File(path!).writeAsBytes(_png(99), flush: true);
        final repairedPath = await cache.downloadImage(
          scopeKey: 'profile:one',
          url: 'https://example.test/menu?renewed=true',
          itemId: 'latte',
          expectedSha256: hash,
          expectedMime: 'image/png',
        );

        expect(repairedPath, path);
        expect(requests, 2);
        expect(await File(repairedPath!).readAsBytes(), bytes);
      },
    );

    test('rejects hash and MIME mismatches without committing a file', () async {
      final bytes = _png(3);
      final cache = MenuCache(
        rootDirectory: directory,
        client: MockClient(
          (_) async => http.Response.bytes(
            bytes,
            200,
            headers: {'content-type': 'image/png'},
          ),
        ),
      );
      final wrongHash = await cache.downloadImage(
        scopeKey: 'profile:one',
        url: 'https://example.test/menu',
        itemId: 'latte',
        expectedSha256: List.filled(64, 'f').join(),
      );
      final wrongMime = await cache.downloadImage(
        scopeKey: 'profile:one',
        url: 'https://example.test/menu',
        itemId: 'latte',
        expectedMime: 'image/jpeg',
      );

      expect(wrongHash, isNull);
      expect(wrongMime, isNull);
      final images = Directory(
        '${directory.path}${Platform.pathSeparator}'
        '${sha256.convert(utf8.encode('profile:one'))}${Platform.pathSeparator}images',
      );
      expect(await images.exists(), isFalse);
    });

    test(
      'transparent variant requires PNG signature and matching digest',
      () async {
        final bytes = _jpeg();
        final cache = MenuCache(
          rootDirectory: directory,
          client: MockClient(
            (_) async => http.Response.bytes(
              bytes,
              200,
              headers: {'content-type': 'image/jpeg'},
            ),
          ),
        );
        final path = await cache.downloadImage(
          scopeKey: 'profile:one',
          url: 'https://example.test/cutout',
          itemId: 'latte',
          variant: 'transparent',
        );
        expect(path, isNull);
      },
    );
  });
}

List<int> _png(int suffix) => [137, 80, 78, 71, 13, 10, 26, 10, suffix];
List<int> _jpeg() => [0xff, 0xd8, 0xff, 0x00, 0x01];
