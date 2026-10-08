import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

http.Client? _shared;
bool _loggedMode = false;

/// POSTs to the LUUQ server over one long-lived, keep-alive connection, so
/// the 30 s license and menu checks and the analytics events do not each
/// open a new TLS connection.
///
/// Only the app's own (root) zone shares the client. In any other zone, such
/// as a test's `http.runWithClient`, this is the plain [http.post], which uses
/// that zone's client exactly as before.
Future<http.Response> luuqPost(
  Uri url, {
  Map<String, String>? headers,
  Object? body,
}) {
  final shared = identical(Zone.current, Zone.root);
  if (kDebugMode && !_loggedMode) {
    _loggedMode = true;
    debugPrint('[NET] shared client: ${shared ? 'yes' : 'no'}');
  }
  if (!shared) return http.post(url, headers: headers, body: body);
  final client = _shared ??= IOClient(
    HttpClient()
      ..connectionTimeout = const Duration(seconds: 10)
      ..idleTimeout = const Duration(seconds: 45),
  );
  return client.post(url, headers: headers, body: body);
}

/// Test hook: the shared client, once a root-zone call has created it.
@visibleForTesting
http.Client? get debugSharedHttpClient => _shared;
