import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:luuqapp/licensing/feature_flags.dart';
import 'package:luuqapp/licensing/license_config.dart';
import 'package:luuqapp/licensing/license_service.dart';
import 'package:luuqapp/licensing/license_status.dart';
import 'package:luuqapp/menu/menu_cache.dart';
import 'package:luuqapp/menu/menu_service.dart';

const _profileId = 'profile-1';

Map<String, Object?> _catalogResponse() => {
  'active': true,
  'menu_profile_id': _profileId,
  'effective_revision': 'rev-1',
  'catalog': {
    'categories': [
      {
        'id': 'c1',
        'name_tr': 'Kahve',
        'items': [
          {'id': 'i1', 'category_id': 'c1', 'name_tr': 'Latte'},
        ],
      },
    ],
  },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  late MenuCache cache;
  late MenuService service;
  late List<Map<String, dynamic>> configBodies;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('luuq_menu_queue_');
    cache = MenuCache(rootDirectory: directory);
    service = MenuService.forTest(cache: cache);
    configBodies = [];
    FlutterSecureStorage.setMockInitialValues({
      'device_id': 'test-device-id',
      'device_fingerprint_hash': 'test-device-fingerprint',
      'license_key': 'LUUQ-TEST',
      'menu_access_token': 'access-token',
      'menu_profile_id': _profileId,
      'menu_admin_session_token': 'admin-token',
    });
    PackageInfo.setMockInitialValues(
      appName: 'LUUQ',
      packageName: 'com.luuq.kiosk',
      version: '1.1.0',
      buildNumber: '13',
      buildSignature: '',
    );
    LicenseService.instance.statusNotifier.value = const LicenseStatus(
      active: true,
      mode: LicenseMode.licensed,
      features: FeatureFlags.proDefault,
      menuAccessToken: 'access-token',
      menuProfileId: _profileId,
    );
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  /// Serves menu.php with a catalog and answers menu-config.php with [config].
  MockClient client(
    FutureOr<http.Response> Function(Map<String, dynamic>) config,
  ) => MockClient((request) async {
    if (request.url.toString() == LicenseConfig.menuConfigUrl) {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      configBodies.add(body);
      return config(body);
    }
    if (request.url.toString() == LicenseConfig.menuUrl) {
      return http.Response(jsonEncode(_catalogResponse()), 200);
    }
    return http.Response('{}', 404);
  });

  Future<Map<String, Map<String, dynamic>>> pending() =>
      cache.readPendingConfig('profile:$_profileId');

  final wheel = List.generate(8, (i) => 'w$i');

  test('200 empties the queue and reports saved', () async {
    final result = await http.runWithClient(
      () => service.pushLocalWheel(wheel),
      () => client((_) => http.Response('{"active":true}', 200)),
    );
    expect(result, MenuPushResult.saved);
    expect(await pending(), isEmpty);
    expect(service.hasPendingConfig('wheel'), isFalse);
    expect(configBodies.single['wheel_item_ids'], wheel);
  });

  test('a theme change is sent as the theme domain', () async {
    final result = await http.runWithClient(
      () => service.pushLocalTheme('newYear'),
      () => client((_) => http.Response('{"active":true}', 200)),
    );
    expect(result, MenuPushResult.saved);
    expect(configBodies.single['domain'], 'theme');
    expect(configBodies.single['theme'], 'newYear');
    expect(service.hasPendingConfig('theme'), isFalse);
  });

  test('422 drops the change and reports rejected', () async {
    final result = await http.runWithClient(
      () => service.pushLocalWheel(wheel),
      () => client(
        (_) => http.Response('{"reason":"wheel_item_not_active"}', 422),
      ),
    );
    expect(result, MenuPushResult.rejected);
    expect(await pending(), isEmpty);
    expect(service.hasPendingConfig('wheel'), isFalse);
  });

  test(
    'network failure keeps it queued and retries with the same key',
    () async {
      final first = await http.runWithClient(
        () => service.pushLocalBarista(drinkId: 'd1', dessertId: 's1'),
        () => client((_) => throw const SocketException('offline')),
      );
      expect(first, MenuPushResult.queued);
      expect(service.hasPendingConfig('barista'), isTrue);
      final queuedKey = (await pending())['barista']!['idempotency_key'];

      await http.runWithClient(
        () => service.syncNow(),
        () => client((_) => http.Response('{"active":true}', 200)),
      );
      expect(configBodies, hasLength(2));
      expect(configBodies.last['idempotency_key'], queuedKey);
      expect(configBodies.first['idempotency_key'], queuedKey);
      expect(await pending(), isEmpty);
      expect(service.hasPendingConfig('barista'), isFalse);
    },
  );

  test('invalid_admin_token keeps the change queued', () async {
    final result = await http.runWithClient(
      () => service.pushLocalWheel(wheel),
      () =>
          client((_) => http.Response('{"reason":"invalid_admin_token"}', 401)),
    );
    expect(result, MenuPushResult.queued);
    expect((await pending()).keys, ['wheel']);
  });

  test('a forced sync during a running sync waits for the follow-up', () async {
    final gate = Completer<void>();
    var menuCalls = 0;
    final mock = MockClient((request) async {
      if (request.url.toString() == LicenseConfig.menuUrl) {
        menuCalls++;
        if (menuCalls == 1) await gate.future;
        return http.Response(jsonEncode(_catalogResponse()), 200);
      }
      return http.Response('{}', 404);
    });
    await http.runWithClient(() async {
      final first = service.syncNow();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      var forcedDone = false;
      final forced = service
          .syncNow(force: true)
          .then((_) => forcedDone = true);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(forcedDone, isFalse);
      gate.complete();
      await first;
      await forced;
      expect(forcedDone, isTrue);
      expect(menuCalls, 2, reason: 'the forced follow-up sync must have run');
    }, () => mock);
  });
  test('rejected change triggers a forced sync to restore the server value',
      () async {
    var menuCalls = 0;
    final mock = MockClient((request) async {
      if (request.url.toString() == LicenseConfig.menuConfigUrl) {
        return http.Response('{"reason":"wheel_item_not_active"}', 422);
      }
      if (request.url.toString() == LicenseConfig.menuUrl) {
        menuCalls++;
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body.containsKey('menu_version'), isFalse,
            reason: 'a forced sync never sends a not_modified hint');
        return http.Response(jsonEncode(_catalogResponse()), 200);
      }
      return http.Response('{}', 404);
    });
    final result = await http.runWithClient(
      () => service.pushLocalWheel(wheel),
      () => mock,
    );
    expect(result, MenuPushResult.rejected);
    expect(menuCalls, 1);
    expect(service.catalogNotifier.value, isNotNull);
  });

  test('a queued change older than 24 hours is dropped unsent', () async {
    final first = await http.runWithClient(
      () => service.pushLocalWheel(wheel),
      () => client((_) => throw const SocketException('offline')),
    );
    expect(first, MenuPushResult.queued);
    expect(configBodies, hasLength(1));

    final queuedAt = DateTime.now();
    service.now = () => queuedAt.add(const Duration(hours: 25));
    await http.runWithClient(
      () => service.syncNow(),
      () => client((_) => http.Response('{"active":true}', 200)),
    );
    expect(configBodies, hasLength(1), reason: 'the expired entry is not sent');
    expect(await pending(), isEmpty);
    expect(service.hasPendingConfig('wheel'), isFalse);
  });

  test('sends run one at a time and a newer change is sent after the older',
      () async {
    // Watches the queue through recorded writes: reading the file while the
    // service replaces it fails on Windows (rename over an open file).
    final gated = _GatedCache(rootDirectory: directory);
    service = MenuService.forTest(cache: gated);
    final firstResponse = Completer<void>();
    var inFlight = 0;
    var maxInFlight = 0;
    final mock = MockClient((request) async {
      if (request.url.toString() == LicenseConfig.menuConfigUrl) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        configBodies.add(body);
        inFlight++;
        maxInFlight = inFlight > maxInFlight ? inFlight : maxInFlight;
        if (configBodies.length == 1) await firstResponse.future;
        inFlight--;
        return http.Response('{"active":true}', 200);
      }
      if (request.url.toString() == LicenseConfig.menuUrl) {
        return http.Response(jsonEncode(_catalogResponse()), 200);
      }
      return http.Response('{}', 404);
    });
    final newer = List.generate(8, (i) => 'n$i');
    await http.runWithClient(() async {
      Future<void> until(bool Function() done) async {
        for (var i = 0; i < 200 && !done(); i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(done(), isTrue);
      }

      final older = service.pushLocalWheel(wheel);
      await until(() => configBodies.length == 1);
      final newest = service.pushLocalWheel(newer);
      // The newer change is queued (replacing the older entry) but not sent.
      await until(
        () => gated.writes.isNotEmpty &&
            gated.writes.last['wheel']?['values']?['wheel_item_ids']
                    ?.toString() ==
                newer.toString(),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(configBodies, hasLength(1),
          reason: 'the newer send waits for the older one');
      firstResponse.complete();
      expect(await older, MenuPushResult.saved);
      expect(await newest, MenuPushResult.saved);
    }, () => mock);
    expect(maxInFlight, 1);
    expect(configBodies.first['wheel_item_ids'], wheel);
    expect(configBodies.last['wheel_item_ids'], newer);
    expect(await pending(), isEmpty);
  });

  test('menu images download four at a time and all arrive', () async {
    // A valid JPEG body and its hash, shared by every item.
    final jpeg = [0xff, 0xd8, 0xff, ...List<int>.filled(64, 1)];
    final jpegSha = sha256OfBytes(jpeg);
    var inFlight = 0;
    var maxInFlight = 0;
    var downloads = 0;
    final imageClient = MockClient((request) async {
      inFlight++;
      maxInFlight = inFlight > maxInFlight ? inFlight : maxInFlight;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      inFlight--;
      downloads++;
      return http.Response.bytes(jpeg, 200,
          headers: {'content-type': 'image/jpeg'});
    });
    final imageCache = MenuCache(client: imageClient, rootDirectory: directory);
    service = MenuService.forTest(cache: imageCache);
    final response = _catalogResponse();
    final items = [
      for (var i = 0; i < 10; i++)
        {
          'id': 'img$i',
          'category_id': 'c1',
          'name_tr': 'Ürün $i',
          'image_url': 'https://example.test/img$i.jpg',
          'image_sha256': jpegSha,
          'image_mime': 'image/jpeg',
        },
    ];
    ((response['catalog'] as Map)['categories'] as List).first['items'] = items;
    await http.runWithClient(
      () => service.syncNow(force: true),
      () => MockClient((request) async {
        if (request.url.toString() == LicenseConfig.menuUrl) {
          return http.Response(jsonEncode(response), 200);
        }
        return http.Response('{}', 404);
      }),
    );
    expect(downloads, 10);
    expect(maxInFlight, 4);
    final catalog = service.catalogNotifier.value!;
    expect(catalog.items.every((item) => item.localImagePath != null), isTrue);
    expect(catalog.items.map((item) => item.id).toList(),
        [for (var i = 0; i < 10; i++) 'img$i'],
        reason: 'order is kept');
  });

  test('a change queued while the older send is finishing is not lost',
      () async {
    final gated = _GatedCache(rootDirectory: directory);
    service = MenuService.forTest(cache: gated);
    final mock = MockClient((request) async {
      if (request.url.toString() == LicenseConfig.menuConfigUrl) {
        configBodies.add(jsonDecode(request.body) as Map<String, dynamic>);
        // The next pending read is the older send dropping its own entry.
        if (configBodies.length == 1) gated.holdNextRead = true;
        return http.Response('{"active":true}', 200);
      }
      if (request.url.toString() == LicenseConfig.menuUrl) {
        return http.Response(jsonEncode(_catalogResponse()), 200);
      }
      return http.Response('{}', 404);
    });
    final newer = List.generate(8, (i) => 'n$i');
    bool newerQueued() => gated.writes.any(
          (w) =>
              w['wheel']?['values']?['wheel_item_ids']?.toString() ==
              newer.toString(),
        );
    await http.runWithClient(() async {
      final older = service.pushLocalWheel(wheel);
      await gated.held.future;
      final newest = service.pushLocalWheel(newer);
      // Let the newer change reach the queue if nothing holds it back.
      for (var i = 0; i < 10 && !newerQueued(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      gated.release.complete();
      expect(await older, MenuPushResult.saved);
      expect(await newest, MenuPushResult.saved);
    }, () => mock);
    expect(
      configBodies.map((b) => b['wheel_item_ids']).toList(),
      [wheel, newer],
      reason: 'the newer change must still be sent',
    );
    expect(await gated.readPendingConfig('profile:$_profileId'), isEmpty);
  });

  test('images of the catalog on screen survive later syncs', () async {
    List<int> jpegFor(String id) => [0xff, 0xd8, 0xff, ...utf8.encode(id)];
    final imageClient = MockClient(
      (request) async => http.Response.bytes(
        jpegFor(request.url.pathSegments.last.split('.').first),
        200,
        headers: {'content-type': 'image/jpeg'},
      ),
    );
    final imageCache = MenuCache(client: imageClient, rootDirectory: directory);
    service = MenuService.forTest(cache: imageCache);
    Map<String, Object?> catalogWith(String id) {
      final response = _catalogResponse();
      response['effective_revision'] = 'rev-$id';
      ((response['catalog'] as Map)['categories'] as List).first['items'] = [
        {
          'id': id,
          'category_id': 'c1',
          'name_tr': 'Ürün $id',
          'image_url': 'https://example.test/$id.jpg',
          'image_sha256': sha256OfBytes(jpegFor(id)),
          'image_mime': 'image/jpeg',
        },
      ];
      return response;
    }

    Future<void> syncTo(String id) => http.runWithClient(
      () => service.syncNow(force: true),
      () => MockClient((request) async {
        if (request.url.toString() == LicenseConfig.menuUrl) {
          return http.Response(jsonEncode(catalogWith(id)), 200);
        }
        return http.Response('{}', 404);
      }),
    );

    await syncTo('a');
    final shown = service.catalogNotifier.value!;
    final shownImage = shown.items.single.localImagePath!;
    // The kiosk shows catalog "a" while a customer dialog holds back newer ones.
    service.markDisplayed(shown);
    await syncTo('b');
    await syncTo('c');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(File(shownImage).existsSync(), isTrue);
  });

}

String sha256OfBytes(List<int> bytes) => sha256.convert(bytes).toString();

/// Records pending-config writes and can hold one read open after it has
/// read the file, so a test can interleave a newer change with an in-flight
/// send at an exact point.
class _GatedCache extends MenuCache {
  _GatedCache({required super.rootDirectory});

  final writes = <Map<String, Map<String, dynamic>>>[];
  final held = Completer<void>();
  final release = Completer<void>();
  bool holdNextRead = false;

  @override
  Future<Map<String, Map<String, dynamic>>> readPendingConfig(
    String scopeKey,
  ) async {
    final result = await super.readPendingConfig(scopeKey);
    if (holdNextRead) {
      holdNextRead = false;
      held.complete();
      await release.future;
    }
    return result;
  }

  @override
  Future<void> writePendingConfig(
    String scopeKey,
    Map<String, Map<String, dynamic>> pending,
  ) async {
    await super.writePendingConfig(scopeKey, pending);
    writes.add({
      for (final entry in pending.entries) entry.key: Map.of(entry.value),
    });
  }
}
