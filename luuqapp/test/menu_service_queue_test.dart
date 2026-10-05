import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
      String? queuedIds;
      await until(() {
        unawaited(pending().then(
          (p) => queuedIds = p['wheel']?['values']?['wheel_item_ids']
              ?.toString(),
        ));
        return queuedIds == newer.toString();
      });
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
}
