import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:luuqapp/licensing/update_service.dart';

void main() {
  group('classifyApkDownloadFailure', () {
    test('maps filesystem errors to storage', () {
      expect(
        classifyApkDownloadFailure(
          const FileSystemException('write failed', '/tmp/x.apk'),
        ),
        ApkDownloadFailureKind.storage,
      );
    });

    test('maps socket and TLS errors to network', () {
      expect(
        classifyApkDownloadFailure(const SocketException('unreachable')),
        ApkDownloadFailureKind.network,
      );
      expect(
        classifyApkDownloadFailure(const HandshakeException('bad cert')),
        ApkDownloadFailureKind.network,
      );
    });

    test('maps http and format errors to badUrlOrResponse', () {
      expect(
        classifyApkDownloadFailure(
          const HttpException('Server returned status code 403'),
        ),
        ApkDownloadFailureKind.badUrlOrResponse,
      );
      expect(
        classifyApkDownloadFailure(
          const FormatException('APK URL must use HTTPS.'),
        ),
        ApkDownloadFailureKind.badUrlOrResponse,
      );
    });

    test('maps anything else to unknown', () {
      expect(
        classifyApkDownloadFailure(StateError('boom')),
        ApkDownloadFailureKind.unknown,
      );
    });

    test('storage wins over the generic IOException family', () {
      // FileSystemException implements IOException; classification must not
      // shadow it behind a broader network bucket.
      const Object error = FileSystemException('disk full');
      expect(classifyApkDownloadFailure(error), ApkDownloadFailureKind.storage);
    });
  });
}
