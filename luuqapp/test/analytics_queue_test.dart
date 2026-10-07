import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luuqapp/analytics/analytics_event.dart';
import 'package:luuqapp/analytics/analytics_queue.dart';
import 'package:luuqapp/analytics/analytics_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final service = AnalyticsService.instance;
  late Directory dir;
  late File queueFile;
  late DateTime clock;
  late List<Map<String, dynamic>> sent;
  var nextId = 0;

  AnalyticsQueueStore newStore() =>
      AnalyticsQueueStore(file: () async => queueFile, now: () => clock);

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('luuq_analytics_queue_');
    queueFile = File('${dir.path}/analytics_queue.json');
    clock = DateTime(2026, 10, 7, 12);
    sent = [];
    nextId = 0;
    service
      ..now = (() => clock)
      ..drainSpacing = Duration.zero
      ..envelopeOverride = (() async => {'device_id': 'dev-1'})
      ..newEventId = (() =>
          '00000000-0000-4000-8000-${(nextId++).toString().padLeft(12, '0')}')
      ..queueStoreForTesting = newStore();
  });

  tearDown(() async {
    await service.queueSaveIdle;
    service
      ..now = DateTime.now
      ..drainSpacing = const Duration(seconds: 2)
      ..envelopeOverride = null
      ..queueStoreForTesting = null;
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  const event = AnalyticsEvent(eventType: 'qr_click', screen: 'home');

  /// Runs [body] with track-event.php answering through [respond].
  Future<void> withServer(
    http.Response Function(Map<String, dynamic> body) respond,
    Future<void> Function() body,
  ) => http.runWithClient(
    body,
    () => MockClient((request) async {
      final decoded = jsonDecode(request.body) as Map<String, dynamic>;
      sent.add(decoded);
      return respond(decoded);
    }),
  );

  http.Response ok(_) => http.Response('{"success":true}', 200);

  test(
    'an offline event is queued and later sent with its id and age',
    () async {
      await http.runWithClient(
        () => service.sendNow(event),
        () => MockClient((_) async => throw const SocketException('offline')),
      );
      expect(service.queuedIds, hasLength(1));
      final id = service.queuedIds.single;

      clock = clock.add(const Duration(hours: 1));
      await withServer(ok, service.flushQueue);
      expect(sent.single['client_event_id'], id);
      expect(sent.single['queued_seconds'], 3600);
      expect(sent.single['event_type'], 'qr_click');
      expect(service.queuedIds, isEmpty);
    },
  );

  test('the queue survives a restart and contains no secrets', () async {
    await http.runWithClient(
      () => service.sendNow(event),
      () => MockClient((_) async => http.Response('down', 503)),
    );
    await service.queueSaveIdle;
    final text = await queueFile.readAsString();
    expect(text, isNot(contains('license_key')));
    expect(text, isNot(contains('dev-1')));
    // A new run starts with an empty store and reads the file back.
    service.queueStoreForTesting = newStore();
    await service.loadQueue();
    expect(service.queuedIds, hasLength(1));
  });

  test('holds at most 500 events, dropping the oldest', () async {
    await http.runWithClient(() async {
      for (var i = 0; i < 505; i++) {
        await service.sendNow(event);
      }
    }, () => MockClient((_) async => http.Response('{}', 429)));
    expect(service.queuedIds, hasLength(500));
    expect(service.queuedIds.first, endsWith('000000000005'));
  });

  test('responses are classified as the server contract says', () {
    expect(classifyTrackResponse(200, '{}'), TrackOutcome.delivered);
    expect(
      classifyTrackResponse(200, '{"success":true,"duplicate":true}'),
      TrackOutcome.delivered,
    );
    expect(
      classifyTrackResponse(400, '{"reason":"invalid_payload"}'),
      TrackOutcome.drop,
    );
    expect(
      classifyTrackResponse(403, '{"reason":"license_inactive"}'),
      TrackOutcome.drop,
    );
    expect(
      classifyTrackResponse(403, '{"reason":"https_required"}'),
      TrackOutcome.keep,
    );
    expect(classifyTrackResponse(429, '{}'), TrackOutcome.keep);
    expect(classifyTrackResponse(503, 'down'), TrackOutcome.keepCounted);
    expect(
      classifyTrackResponse(403, '<html>blocked</html>'),
      TrackOutcome.keepCounted,
    );
  });

  test('a rejected event is dropped, not queued', () async {
    await withServer(
      (_) => http.Response('{"success":false,"reason":"invalid_payload"}', 400),
      () => service.sendNow(event),
    );
    expect(service.queuedIds, isEmpty);
  });

  test('draining stops at the first 429 and keeps the order', () async {
    await http.runWithClient(() async {
      for (var i = 0; i < 3; i++) {
        await service.sendNow(event);
      }
    }, () => MockClient((_) async => throw const SocketException('offline')));
    final before = service.queuedIds;
    var calls = 0;
    await withServer((_) {
      calls++;
      return calls == 1
          ? http.Response('{}', 200)
          : http.Response('{"reason":"too_many_requests"}', 429);
    }, service.flushQueue);
    expect(calls, 2);
    expect(service.queuedIds, before.sublist(1));
  });

  test('a server error 20 times gives the event up', () async {
    await http.runWithClient(
      () => service.sendNow(event),
      () => MockClient((_) async => throw const SocketException('offline')),
    );
    for (var i = 0; i < AnalyticsService.maxServerAttempts; i++) {
      await withServer((_) => http.Response('down', 503), service.flushQueue);
    }
    expect(service.queuedIds, isEmpty);
  });

  test('events older than 7 days are dropped unsent', () async {
    await http.runWithClient(
      () => service.sendNow(event),
      () => MockClient((_) async => throw const SocketException('offline')),
    );
    clock = clock.add(const Duration(days: 8));
    await withServer(ok, service.flushQueue);
    expect(sent, isEmpty);
    expect(service.queuedIds, isEmpty);
  });

  test('a device clock that went back sends queued_seconds 0', () async {
    await http.runWithClient(
      () => service.sendNow(event),
      () => MockClient((_) async => throw const SocketException('offline')),
    );
    clock = clock.subtract(const Duration(minutes: 5));
    await withServer(ok, service.flushQueue);
    expect(sent.single['queued_seconds'], 0);
  });

  test('a corrupt queue file starts empty', () async {
    await queueFile.writeAsString('{not json');
    await service.loadQueue();
    expect(service.queuedIds, isEmpty);
  });

  test('a delivered live event sends what was queued', () async {
    await http.runWithClient(
      () => service.sendNow(event),
      () => MockClient((_) async => throw const SocketException('offline')),
    );
    await withServer(ok, () async {
      await service.sendNow(
        const AnalyticsEvent(eventType: 'menu_open', screen: 'menu'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    expect(sent.map((b) => b['event_type']), ['menu_open', 'qr_click']);
    expect(service.queuedIds, isEmpty);
  });
}
