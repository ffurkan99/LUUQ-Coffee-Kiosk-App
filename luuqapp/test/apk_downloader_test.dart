import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luuqapp/licensing/update_service.dart';

void main() {
  late Directory testDirectory;
  final clients = <http.Client>[];

  setUp(() async {
    testDirectory = await Directory.systemTemp.createTemp(
      'luuq_apk_download_test_',
    );
  });

  tearDown(() async {
    for (final client in clients) {
      client.close();
    }
    clients.clear();
    if (await testDirectory.exists()) {
      await testDirectory.delete(recursive: true);
    }
  });

  ApkDownloader downloader(
    Future<http.StreamedResponse> Function(
      http.BaseRequest request,
      http.ByteStream body,
    )
    handler, {
    int maximumBytes = 1024,
    Duration headerTimeout = const Duration(seconds: 1),
    Duration idleReadTimeout = const Duration(seconds: 1),
    Duration totalTimeout = const Duration(seconds: 2),
    Directory? destinationDirectory,
  }) {
    final client = MockClient.streaming(handler);
    clients.add(client);
    return ApkDownloader(
      client: client,
      destinationDirectory: destinationDirectory ?? testDirectory,
      maximumBytes: maximumBytes,
      headerTimeout: headerTimeout,
      idleReadTimeout: idleReadTimeout,
      totalTimeout: totalTimeout,
    );
  }

  test('successful streamed download keeps the completed APK', () async {
    final bytes = <int>[1, 2, 3, 4, 5];
    final progress = <double>[];
    final subject = downloader(
      (_, _) async => http.StreamedResponse(
        Stream.value(bytes),
        HttpStatus.ok,
        contentLength: bytes.length,
      ),
    );

    final file = await subject.download(
      'https://updates.example.test/app.apk',
      progress.add,
    );

    expect(await file.readAsBytes(), bytes);
    expect(progress.last, 1.0);
    expect(await subject.temporaryFile.exists(), isTrue);
  });

  test('user cancellation removes a partially downloaded APK', () async {
    late StreamController<List<int>> streamController;
    streamController = StreamController<List<int>>(
      onListen: () => streamController.add(<int>[1, 2, 3]),
    );
    addTearDown(streamController.close);
    final token = ApkDownloadCancellationToken();
    final subject = downloader(
      (_, _) async => http.StreamedResponse(
        streamController.stream,
        HttpStatus.ok,
        contentLength: 10,
      ),
    );

    final future = subject.download(
      'https://updates.example.test/app.apk',
      (_) => token.cancel(),
      cancellationToken: token,
    );

    await expectLater(future, throwsA(isA<ApkDownloadCancelledException>()));
    expect(await subject.temporaryFile.exists(), isFalse);
  });

  test('header timeout removes any stale temporary APK', () async {
    final subject = downloader(
      (_, _) => Completer<http.StreamedResponse>().future,
      headerTimeout: const Duration(milliseconds: 40),
    );
    await subject.temporaryFile.writeAsBytes(<int>[9, 9, 9]);

    await expectLater(
      subject.download('https://updates.example.test/app.apk', (_) {}),
      throwsA(
        isA<ApkDownloadTimeoutException>().having(
          (error) => error.phase,
          'phase',
          ApkDownloadTimeoutPhase.header,
        ),
      ),
    );
    expect(await subject.temporaryFile.exists(), isFalse);
  });

  test('idle-read timeout removes a partially downloaded APK', () async {
    late StreamController<List<int>> streamController;
    streamController = StreamController<List<int>>(
      onListen: () => streamController.add(<int>[1, 2, 3]),
    );
    addTearDown(streamController.close);
    final subject = downloader(
      (_, _) async => http.StreamedResponse(
        streamController.stream,
        HttpStatus.ok,
        contentLength: 10,
      ),
      idleReadTimeout: const Duration(milliseconds: 40),
    );

    await expectLater(
      subject.download('https://updates.example.test/app.apk', (_) {}),
      throwsA(
        isA<ApkDownloadTimeoutException>().having(
          (error) => error.phase,
          'phase',
          ApkDownloadTimeoutPhase.idleRead,
        ),
      ),
    );
    expect(await subject.temporaryFile.exists(), isFalse);
  });

  test('total timeout stops an active stream and removes the APK', () async {
    final subject = downloader(
      (_, _) async => http.StreamedResponse(
        Stream<List<int>>.periodic(
          const Duration(milliseconds: 5),
          (_) => <int>[1],
        ),
        HttpStatus.ok,
      ),
      idleReadTimeout: const Duration(milliseconds: 100),
      totalTimeout: const Duration(milliseconds: 60),
    );

    await expectLater(
      subject.download('https://updates.example.test/app.apk', (_) {}),
      throwsA(
        isA<ApkDownloadTimeoutException>().having(
          (error) => error.phase,
          'phase',
          ApkDownloadTimeoutPhase.total,
        ),
      ),
    );
    expect(await subject.temporaryFile.exists(), isFalse);
  });

  test('oversized Content-Length is rejected before writing', () async {
    final subject = downloader(
      (_, _) async => http.StreamedResponse(
        const Stream<List<int>>.empty(),
        HttpStatus.ok,
        contentLength: 101,
      ),
      maximumBytes: 100,
    );

    await expectLater(
      subject.download('https://updates.example.test/app.apk', (_) {}),
      throwsA(isA<ApkDownloadSizeException>()),
    );
    expect(await subject.temporaryFile.exists(), isFalse);
  });

  test('unknown-length oversized stream is stopped and cleaned', () async {
    final subject = downloader(
      (_, _) async => http.StreamedResponse(
        Stream<List<int>>.fromIterable(<List<int>>[
          List<int>.filled(60, 1),
          List<int>.filled(60, 2),
        ]),
        HttpStatus.ok,
      ),
      maximumBytes: 100,
    );

    await expectLater(
      subject.download('https://updates.example.test/app.apk', (_) {}),
      throwsA(isA<ApkDownloadSizeException>()),
    );
    expect(await subject.temporaryFile.exists(), isFalse);
  });

  test('stream failure removes the partially written APK', () async {
    final stream = Stream<List<int>>.multi((controller) {
      controller.add(<int>[1, 2, 3]);
      controller.addError(const SocketException('stream disconnected'));
      controller.close();
    });
    final subject = downloader(
      (_, _) async => http.StreamedResponse(stream, HttpStatus.ok),
    );

    await expectLater(
      subject.download('https://updates.example.test/app.apk', (_) {}),
      throwsA(isA<SocketException>()),
    );
    expect(await subject.temporaryFile.exists(), isFalse);
  });

  test('redirect downgrade to HTTP is rejected and cleaned', () async {
    final subject = downloader(
      (_, _) async => http.StreamedResponse(
        const Stream<List<int>>.empty(),
        HttpStatus.found,
        headers: {'location': 'http://cdn.example.test/app.apk'},
      ),
    );

    await expectLater(
      subject.download('https://updates.example.test/app.apk', (_) {}),
      throwsA(isA<HttpException>()),
    );
    expect(await subject.temporaryFile.exists(), isFalse);
  });

  test('disk write failure leaves no temporary APK', () async {
    final blockingFile = File(
      '${testDirectory.path}${Platform.pathSeparator}not_a_directory',
    );
    await blockingFile.writeAsString('block');
    final invalidDirectory = Directory(blockingFile.path);
    final subject = downloader(
      (_, _) async => http.StreamedResponse(
        Stream.value(<int>[1, 2, 3]),
        HttpStatus.ok,
        contentLength: 3,
      ),
      destinationDirectory: invalidDirectory,
    );

    await expectLater(
      subject.download('https://updates.example.test/app.apk', (_) {}),
      throwsA(isA<FileSystemException>()),
    );
    expect(await subject.temporaryFile.exists(), isFalse);
  });

  test('checksum failure deletes the completed temporary APK', () async {
    final file = File(
      '${testDirectory.path}${Platform.pathSeparator}${ApkDownloader.temporaryFileName}',
    );
    await file.writeAsBytes(<int>[1, 2, 3, 4]);

    final valid = await UpdateService.verifySha256AndDeleteOnFailure(
      file,
      '0000000000000000000000000000000000000000000000000000000000000000',
    );

    expect(valid, isFalse);
    expect(await file.exists(), isFalse);
  });

  test('production maximum APK size is 200 MiB', () {
    expect(ApkDownloadPolicy.maximumApkBytes, 200 * 1024 * 1024);
  });
}
