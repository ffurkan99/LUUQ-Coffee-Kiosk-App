import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luuqapp/licensing/update_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProviderChannel = MethodChannel(
    'plugins.flutter.io/path_provider',
  );
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('luuq_download_client_test');
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    messenger.setMockMethodCallHandler(pathProviderChannel, (call) async {
      if (call.method == 'getTemporaryDirectory') return tempDir.path;
      return null;
    });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(pathProviderChannel, null);
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('downloadApk keeps its HTTP client open until the request runs', () async {
    // flutter_test's fake network answers every request with HTTP 400. If the
    // request actually executes, ApkDownloader throws the "status code 400"
    // HttpException. If the client is closed too early (the try/finally +
    // await-less return trap), a "Client is already closed" ClientException
    // surfaces instead — the exact failure seen on kiosk devices.
    await expectLater(
      UpdateService.downloadApk(
        'https://updates.example.test/app.apk',
        (_) {},
      ),
      throwsA(
        isA<HttpException>().having(
          (error) => error.message,
          'message',
          contains('400'),
        ),
      ),
    );
  });
}
