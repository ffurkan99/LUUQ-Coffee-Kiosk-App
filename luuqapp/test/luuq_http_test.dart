import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luuqapp/net/luuq_http.dart';

void main() {
  test('app calls share one keep-alive connection', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final clientPorts = <int>[];
    server.listen((request) async {
      clientPorts.add(request.connectionInfo!.remotePort);
      await request.drain<void>();
      request.response.write('ok');
      await request.response.close();
    });
    final url = Uri.parse('http://127.0.0.1:${server.port}/check');

    // The app's own zone (expect() cannot run inside it).
    final (first, second, firstClient, secondClient) = await Zone.root.run(
      () async {
        final first = await luuqPost(url, body: '{}');
        final firstClient = debugSharedHttpClient;
        final second = await luuqPost(url, body: '{}');
        return (first, second, firstClient, debugSharedHttpClient);
      },
    );
    expect(first.body, 'ok');
    expect(second.body, 'ok');
    expect(firstClient, isNotNull);
    expect(identical(secondClient, firstClient), isTrue);
    // Both requests came over the same connection.
    expect(clientPorts, hasLength(2));
    expect(clientPorts.toSet(), hasLength(1));
  });

  test('a test zone client still answers (runWithClient)', () async {
    final response = await http.runWithClient(
      () => luuqPost(Uri.parse('https://example.invalid/x'), body: '{}'),
      () => MockClient((_) async => http.Response('mock', 200)),
    );
    expect(response.body, 'mock');
  });
}
