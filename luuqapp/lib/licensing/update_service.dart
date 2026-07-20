import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'license_storage.dart';

export 'version_info.dart';

enum ApkDownloadTimeoutPhase { header, idleRead, total }

class ApkDownloadTimeoutException implements Exception {
  final ApkDownloadTimeoutPhase phase;

  const ApkDownloadTimeoutException(this.phase);

  @override
  String toString() => 'APK download timed out during ${phase.name}.';
}

class ApkDownloadCancelledException implements Exception {
  const ApkDownloadCancelledException();

  @override
  String toString() => 'APK download was cancelled.';
}

class ApkDownloadSizeException implements Exception {
  final int maximumBytes;

  const ApkDownloadSizeException(this.maximumBytes);

  @override
  String toString() => 'APK exceeds the maximum size of $maximumBytes bytes.';
}

class ApkDownloadCancellationToken {
  final Completer<void> _cancelled = Completer<void>();

  bool get isCancelled => _cancelled.isCompleted;
  Future<void> get whenCancelled => _cancelled.future;

  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }
}

/// Coarse cause buckets for a failed APK download, used to show the admin an
/// actionable message instead of a single generic one and to tag the remote
/// analytics event so failures can be diagnosed without device access.
enum ApkDownloadFailureKind { storage, network, badUrlOrResponse, unknown }

ApkDownloadFailureKind classifyApkDownloadFailure(Object error) {
  // FileSystemException also implements IOException; check it before the
  // network family so storage problems keep their specific bucket.
  if (error is FileSystemException) return ApkDownloadFailureKind.storage;
  if (error is SocketException || error is HandshakeException) {
    return ApkDownloadFailureKind.network;
  }
  if (error is HttpException || error is FormatException) {
    return ApkDownloadFailureKind.badUrlOrResponse;
  }
  return ApkDownloadFailureKind.unknown;
}

class ApkDownloadPolicy {
  static const int maximumApkBytes = 200 * 1024 * 1024;
  static const Duration headerTimeout = Duration(seconds: 15);
  static const Duration idleReadTimeout = Duration(seconds: 30);
  static const Duration totalTimeout = Duration(minutes: 20);
  static const int maximumRedirects = 5;

  const ApkDownloadPolicy._();
}

class _ApkDownloadAbortSignal {
  final StreamController<Object> _controller =
      StreamController<Object>.broadcast(sync: true);
  Object? _error;
  bool _closed = false;

  Object? get error => _error;
  Stream<Object> get stream => _controller.stream;

  void abort(Object error) {
    if (_error != null || _closed) return;
    _error = error;
    _controller.add(error);
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _controller.close();
  }
}

/// Testable streamed APK downloader. Production access remains behind
/// [UpdateService.downloadApk], which enforces the Android-only policy.
class ApkDownloader {
  static const String temporaryFileName = 'luuq_update_temp.apk';
  static const Duration _cleanupTimeout = Duration(seconds: 2);

  final http.Client client;
  final Directory destinationDirectory;
  final int maximumBytes;
  final Duration headerTimeout;
  final Duration idleReadTimeout;
  final Duration totalTimeout;
  final int maximumRedirects;

  ApkDownloader({
    required this.client,
    required this.destinationDirectory,
    this.maximumBytes = ApkDownloadPolicy.maximumApkBytes,
    this.headerTimeout = ApkDownloadPolicy.headerTimeout,
    this.idleReadTimeout = ApkDownloadPolicy.idleReadTimeout,
    this.totalTimeout = ApkDownloadPolicy.totalTimeout,
    this.maximumRedirects = ApkDownloadPolicy.maximumRedirects,
  });

  File get temporaryFile => File(
    '${destinationDirectory.path}${Platform.pathSeparator}$temporaryFileName',
  );

  Future<File> download(
    String url,
    void Function(double progress) onProgress, {
    ApkDownloadCancellationToken? cancellationToken,
  }) async {
    final initialUri = Uri.tryParse(url);
    if (initialUri == null ||
        initialUri.scheme.toLowerCase() != 'https' ||
        initialUri.host.isEmpty) {
      throw const FormatException('APK URL must use HTTPS.');
    }

    final apkFile = temporaryFile;
    await _deleteIfExists(apkFile);

    final abortSignal = _ApkDownloadAbortSignal();

    final totalTimer = Timer(
      totalTimeout,
      () => abortSignal.abort(
        const ApkDownloadTimeoutException(ApkDownloadTimeoutPhase.total),
      ),
    );
    if (cancellationToken != null) {
      if (cancellationToken.isCancelled) {
        abortSignal.abort(const ApkDownloadCancelledException());
      } else {
        unawaited(
          cancellationToken.whenCancelled.then(
            (_) => abortSignal.abort(const ApkDownloadCancelledException()),
          ),
        );
      }
    }

    IOSink? sink;
    StreamIterator<List<int>>? iterator;
    var succeeded = false;

    try {
      var currentUri = initialUri;
      late http.StreamedResponse response;

      for (var redirectCount = 0; ; redirectCount++) {
        final request = http.Request('GET', currentUri)
          ..followRedirects = false;
        response = await _awaitStep(
          client.send(request),
          abortSignal,
          timeout: headerTimeout,
          timeoutError: const ApkDownloadTimeoutException(
            ApkDownloadTimeoutPhase.header,
          ),
        );

        if (!_isRedirect(response.statusCode)) break;
        if (redirectCount >= maximumRedirects) {
          throw const HttpException('Too many APK download redirects.');
        }

        final location = response.headers['location'];
        if (location == null || location.trim().isEmpty) {
          throw const HttpException('APK redirect has no location.');
        }
        final redirectedUri = currentUri.resolve(location);
        if (redirectedUri.scheme.toLowerCase() != 'https' ||
            redirectedUri.host.isEmpty) {
          throw const HttpException('APK redirect must remain on HTTPS.');
        }
        currentUri = redirectedUri;
      }

      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'Server returned status code ${response.statusCode}',
        );
      }

      final contentLength = response.contentLength;
      if (contentLength != null && contentLength > maximumBytes) {
        throw ApkDownloadSizeException(maximumBytes);
      }

      var receivedBytes = 0;
      sink = apkFile.openWrite();
      iterator = StreamIterator<List<int>>(response.stream);

      while (await _awaitStep(
        iterator.moveNext(),
        abortSignal,
        timeout: idleReadTimeout,
        timeoutError: const ApkDownloadTimeoutException(
          ApkDownloadTimeoutPhase.idleRead,
        ),
      )) {
        final chunk = iterator.current;
        if (receivedBytes + chunk.length > maximumBytes) {
          throw ApkDownloadSizeException(maximumBytes);
        }

        sink.add(chunk);
        receivedBytes += chunk.length;
        if (contentLength != null && contentLength > 0) {
          onProgress((receivedBytes / contentLength).clamp(0.0, 1.0));
        }
      }

      await _awaitStep(sink.flush(), abortSignal);
      await _awaitStep(sink.close(), abortSignal);
      sink = null;
      onProgress(1.0);
      succeeded = true;
      return apkFile;
    } catch (_) {
      try {
        await iterator?.cancel().timeout(_cleanupTimeout);
      } catch (_) {}
      try {
        await sink?.close().timeout(_cleanupTimeout);
      } catch (_) {}
      await _deleteIfExists(apkFile);
      rethrow;
    } finally {
      totalTimer.cancel();
      if (!succeeded) await _deleteIfExists(apkFile);
      await abortSignal.close();
    }
  }

  static bool _isRedirect(int statusCode) =>
      statusCode == HttpStatus.movedPermanently ||
      statusCode == HttpStatus.found ||
      statusCode == HttpStatus.seeOther ||
      statusCode == HttpStatus.temporaryRedirect ||
      statusCode == HttpStatus.permanentRedirect;

  static Future<T> _awaitStep<T>(
    Future<T> operation,
    _ApkDownloadAbortSignal abortSignal, {
    Duration? timeout,
    Object? timeoutError,
  }) {
    final existingAbort = abortSignal.error;
    if (existingAbort != null) {
      return Future<T>.error(existingAbort, StackTrace.current);
    }

    final completer = Completer<T>();
    Timer? stepTimer;
    late final StreamSubscription<Object> abortSubscription;

    operation.then(
      (value) {
        if (!completer.isCompleted) completer.complete(value);
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      },
    );
    abortSubscription = abortSignal.stream.listen((error) {
      if (!completer.isCompleted) {
        completer.completeError(error, StackTrace.current);
      }
    });
    if (timeout != null) {
      stepTimer = Timer(timeout, () {
        if (!completer.isCompleted) {
          completer.completeError(
            timeoutError ?? TimeoutException('APK download step timed out.'),
            StackTrace.current,
          );
        }
      });
    }

    return completer.future.whenComplete(() async {
      stepTimer?.cancel();
      await abortSubscription.cancel();
    });
  }

  static Future<void> _deleteIfExists(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (error) {
      debugPrint('[UPDATE] Failed to clean temporary APK: $error');
    }
  }
}

class UpdateService {
  static const _channel = MethodChannel('luuqapp/apk_install');

  static bool get _supportsApkInstaller =>
      Platform.isAndroid ||
      (!kIsWeb &&
          kDebugMode &&
          debugDefaultTargetPlatformOverride == TargetPlatform.android);

  /// Clean up old APK files in the temporary directory (keeps current valid downloaded APK if under 24 hours old)
  static Future<void> cleanupOldUpdateApks() async {
    try {
      final apkInfo = await LicenseStorage.getDownloadedApkInfo();
      final String? validPath = apkInfo?['apk_path'] as String?;

      final tempDir = await getTemporaryDirectory();
      if (await tempDir.exists()) {
        final List<FileSystemEntity> files = tempDir.listSync();
        final now = DateTime.now();
        for (var file in files) {
          if (file is File && file.path.endsWith('.apk')) {
            // Keep the downloaded APK if it matches the valid path and is less than 24 hours old
            if (validPath != null && file.path == validPath) {
              final lastModified = await file.lastModified();
              if (now.difference(lastModified).inHours < 24) {
                continue;
              }
            }
            try {
              await file.delete();
            } catch (_) {}
          }
        }
      }
    } catch (_) {}
  }

  /// Check if the locally downloaded APK is present and matches expected version/sha256/size
  static Future<bool> isDownloadedApkValid({
    required String expectedVersion,
    required String expectedSha256,
    int? expectedSize,
  }) async {
    try {
      final info = await LicenseStorage.getDownloadedApkInfo();
      if (info == null) {
        return false;
      }
      final path = info['apk_path'] as String?;
      final version = info['version'] as String?;
      final sha256Val = info['sha256'] as String?;
      final storedSizeValue = info['file_size'];
      final storedSize = storedSizeValue is num
          ? storedSizeValue.toInt()
          : int.tryParse(storedSizeValue?.toString() ?? '');

      if (path == null || version == null || sha256Val == null) {
        return false;
      }

      if (version != expectedVersion ||
          sha256Val.trim().toLowerCase() !=
              expectedSha256.trim().toLowerCase()) {
        return false;
      }

      final file = File(path);
      if (!await file.exists()) {
        return false;
      }

      if (expectedSize != null && expectedSize > 0) {
        if (storedSize != expectedSize) {
          return false;
        }
        final actualSize = await file.length();
        if (actualSize != expectedSize) {
          return false;
        }
      }

      final bool isHashValid = await verifySha256(file, expectedSha256);
      if (!isHashValid) {
        return false;
      }

      return true;
    } catch (_) {
      return false;
    }
  }

  /// Check if we have permission to install packages (Android O+)
  static Future<bool> checkInstallPermission() async {
    if (!_supportsApkInstaller) return false;
    try {
      final bool? result = await _channel.invokeMethod<bool>(
        'checkInstallPermission',
      );
      return result ?? false;
    } catch (error) {
      debugPrint(
        '[UPDATE][SECURITY] Failed to check install permission: $error',
      );
      rethrow;
    }
  }

  /// Open Android settings screen for Unknown App Sources
  static Future<bool> openInstallSettings() async {
    if (!_supportsApkInstaller) return false;
    try {
      final bool? result = await _channel.invokeMethod<bool>(
        'openInstallSettings',
      );
      return result ?? false;
    } catch (error) {
      debugPrint('[UPDATE][SECURITY] Failed to open install settings: $error');
      return false;
    }
  }

  /// Download the APK from url using a stream and track progress
  static Future<File> downloadApk(
    String url,
    void Function(double progress) onProgress, {
    ApkDownloadCancellationToken? cancellationToken,
  }) async {
    if (!_supportsApkInstaller) {
      throw UnsupportedError('APK download is only supported on Android.');
    }

    final client = http.Client();
    try {
      final tempDir = await getTemporaryDirectory();
      return ApkDownloader(
        client: client,
        destinationDirectory: tempDir,
      ).download(url, onProgress, cancellationToken: cancellationToken);
    } finally {
      client.close();
    }
  }

  static Future<bool> verifySha256AndDeleteOnFailure(
    File file,
    String expectedHash,
  ) async {
    final valid = await verifySha256(file, expectedHash);
    if (!valid) await deleteApkFile(file);
    return valid;
  }

  static Future<void> deleteApkFile(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (error) {
      debugPrint('[UPDATE] Failed to delete APK file: $error');
    }
  }

  /// Verify the file SHA-256 hash in a streaming fashion to prevent OOM errors
  static Future<bool> verifySha256(File file, String expectedHash) async {
    if (expectedHash.trim().isEmpty) {
      return false;
    }
    try {
      final stream = file.openRead();
      final output = await sha256.bind(stream).first;
      final hash = output.toString();
      return hash.toLowerCase() == expectedHash.trim().toLowerCase();
    } catch (_) {
      return false;
    }
  }

  /// Trigger Android APK installation screen via MethodChannel
  static Future<String> installApk(String filePath) async {
    if (!_supportsApkInstaller) {
      throw UnsupportedError('APK installation is only supported on Android.');
    }
    final result = await _channel.invokeMethod<String>('installApk', {
      'path': filePath,
    });
    return result ?? 'unknown';
  }

  /// Check if lock task / screen pinning is active
  static Future<bool> isLockTaskActive() async {
    if (!_supportsApkInstaller) return false;
    final bool? result = await _channel.invokeMethod<bool>('isLockTaskActive');
    return result ?? false;
  }

  /// Poll until lock task is truly released (or timeout).
  /// Returns true if lock task was released within [timeoutMs], false on timeout.
  static Future<bool> waitForLockTaskRelease({
    int timeoutMs = 3000,
    int pollIntervalMs = 200,
  }) async {
    if (!_supportsApkInstaller) return true;
    final deadline = DateTime.now().add(Duration(milliseconds: timeoutMs));
    while (DateTime.now().isBefore(deadline)) {
      final active = await isLockTaskActive();
      if (!active) return true;
      await Future.delayed(Duration(milliseconds: pollIntervalMs));
    }
    return false;
  }

  /// Poll until lock task is active again (or timeout).
  static Future<bool> _waitForLockTaskActivation({
    int timeoutMs = 3000,
    int pollIntervalMs = 200,
  }) async {
    if (!_supportsApkInstaller) return true;
    final deadline = DateTime.now().add(Duration(milliseconds: timeoutMs));
    while (DateTime.now().isBefore(deadline)) {
      final active = await isLockTaskActive();
      if (active) return true;
      await Future.delayed(Duration(milliseconds: pollIntervalMs));
    }
    return false;
  }

  /// Stop lock task temporarily for updating
  static Future<void> stopLockTaskForUpdate() async {
    if (!_supportsApkInstaller) {
      throw UnsupportedError(
        'LockTask update flow is only supported on Android.',
      );
    }
    await _channel.invokeMethod('stopLockTaskForUpdate');
  }

  /// Restore lock task after updating is completed or cancelled
  static Future<void> restoreKioskModeAfterUpdateCancel() async {
    if (!_supportsApkInstaller) return;
    if (await isLockTaskActive()) return;
    await _channel.invokeMethod('restoreKioskModeAfterUpdateCancel');
    if (!await _waitForLockTaskActivation()) {
      throw StateError('LockTask did not become active after restore request.');
    }
  }

  /// Enable Kiosk Mode lock task (screen pinning) on Android
  static Future<void> enableKioskMode() async {
    if (!_supportsApkInstaller) return;
    try {
      await _channel.invokeMethod('enableKioskMode');
    } catch (error) {
      debugPrint('[KIOSK] Failed to enable kiosk mode: $error');
    }
  }

  /// Disable Kiosk Mode lock task (screen pinning) on Android
  static Future<void> disableKioskMode() async {
    if (!_supportsApkInstaller) return;
    try {
      await _channel.invokeMethod('disableKioskMode');
    } catch (error) {
      debugPrint('[KIOSK] Failed to disable kiosk mode: $error');
    }
  }

  /// Read packageName, versionName, and versionCode from APK archive
  static Future<Map<String, dynamic>?> readApkPackageInfo(
    String filePath,
  ) async {
    if (!_supportsApkInstaller) return null;
    try {
      final Map<dynamic, dynamic>? result = await _channel
          .invokeMethod<Map<dynamic, dynamic>>('readApkPackageInfo', {
            'path': filePath,
          });
      if (result == null) return null;
      return Map<String, dynamic>.from(result);
    } catch (e) {
      debugPrint('[UPDATE] Error reading APK package info: $e');
      return null;
    }
  }

  /// Normalize a version name string to a 3-segment format (e.g. 1.1 -> 1.1.0)
  static String normalizeVersionName(String ver) {
    var clean = ver.trim();
    if (clean.startsWith('v') || clean.startsWith('V')) {
      clean = clean.substring(1);
    }
    final segments = clean.split('.');
    if (segments.length == 1 && segments[0].isNotEmpty) {
      return '${segments[0]}.0.0';
    } else if (segments.length == 2) {
      return '${segments[0]}.${segments[1]}.0';
    }
    return clean;
  }
}
