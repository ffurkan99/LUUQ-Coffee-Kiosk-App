import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'menu_models.dart';

class MenuCache {
  MenuCache({http.Client? client, this.rootDirectory})
    : _client = client ?? http.Client();

  final http.Client _client;
  final Directory? rootDirectory;

  /// Files already hashed this session, keyed by path. A cached image is only
  /// re-hashed when its size or mtime changes, so the 30 s not_modified poll
  /// no longer reads every image on the UI isolate.
  final Map<String, ({int size, int mtimeMs, String sha})> _verified = {};

  /// Per item/variant download failures: the next sync skips a known-bad image
  /// until its backoff expires instead of refetching the whole menu each poll.
  final Map<String, ({int failures, DateTime retryAt})> _downloadFailures = {};

  static const Duration _maxBackoff = Duration(hours: 6);

  Future<Directory> _root() async {
    if (rootDirectory != null) {
      await rootDirectory!.create(recursive: true);
      return rootDirectory!;
    }
    final support = await getApplicationSupportDirectory();
    final directory = Directory(
      '${support.path}${Platform.pathSeparator}menu_cache',
    );
    await directory.create(recursive: true);
    return directory;
  }

  String _safeScope(String scopeKey) {
    final value = scopeKey.trim();
    if (value.isEmpty) return 'unscoped-disabled';
    return sha256.convert(utf8.encode(value)).toString();
  }

  Future<Directory> _scopeRoot(String scopeKey) async {
    final root = await _root();
    final directory = Directory(
      '${root.path}${Platform.pathSeparator}${_safeScope(scopeKey)}',
    );
    await directory.create(recursive: true);
    return directory;
  }

  Future<File> _activeFile(String scopeKey) async => File(
    '${(await _scopeRoot(scopeKey)).path}${Platform.pathSeparator}active.json',
  );

  Future<MenuCatalog?> readActive(String scopeKey) async {
    try {
      if (scopeKey.trim().isEmpty) return null;
      final file = await _activeFile(scopeKey);
      // A corrupt active.json falls back to the previous good snapshot.
      for (final source in [file, File('${file.path}.bak')]) {
        final catalog = await _readCatalogFile(source);
        if (catalog != null) return catalog;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<MenuCatalog?> _readCatalogFile(File source) async {
    try {
      if (!await source.exists()) return null;
      final decoded = jsonDecode(await source.readAsString());
      if (decoded is! Map) return null;
      return MenuCatalog.fromCacheJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return null;
    }
  }

  Future<void> writeActive(String scopeKey, MenuCatalog catalog) async {
    final file = await _activeFile(scopeKey);
    final temp = File('${file.path}.tmp');
    final backup = File('${file.path}.bak');
    await temp.writeAsString(catalog.encode(), flush: true);
    var movedCurrent = false;
    try {
      if (await backup.exists()) await backup.delete();
      if (await file.exists()) {
        await file.rename(backup.path);
        movedCurrent = true;
      }
      // The previous snapshot stays as .bak: readActive falls back to it if
      // the new active.json is ever unreadable.
      await temp.rename(file.path);
    } catch (_) {
      if (await file.exists()) {
        await file.delete();
      }
      if (movedCurrent && await backup.exists()) await backup.rename(file.path);
      rethrow;
    } finally {
      if (await temp.exists()) await temp.delete();
    }
  }

  Future<String?> downloadImage({
    required String scopeKey,
    required String url,
    required String itemId,
    String variant = 'normal',
    String? expectedSha256,
    String? expectedMime,
  }) async {
    final failureKey = '$scopeKey|$itemId|$variant';
    try {
      final path = await _downloadImage(
        scopeKey: scopeKey,
        url: url,
        itemId: itemId,
        variant: variant,
        expectedSha256: expectedSha256,
        expectedMime: expectedMime,
      );
      if (path == null) {
        _recordDownloadFailure(failureKey);
      } else {
        _downloadFailures.remove(failureKey);
      }
      return path;
    } catch (_) {
      _recordDownloadFailure(failureKey);
      rethrow;
    }
  }

  void _recordDownloadFailure(String key) {
    final failures = (_downloadFailures[key]?.failures ?? 0) + 1;
    // 1 min, 2 min, 4 min ... capped at 6 h.
    final minutes = 1 << (failures - 1).clamp(0, 9);
    final delay = Duration(minutes: minutes) > _maxBackoff
        ? _maxBackoff
        : Duration(minutes: minutes);
    _downloadFailures[key] = (
      failures: failures,
      retryAt: DateTime.now().add(delay),
    );
  }

  /// True while a recently failed image download is still backing off.
  bool isDownloadBackedOff(String scopeKey, String itemId, String variant) {
    final entry = _downloadFailures['$scopeKey|$itemId|$variant'];
    return entry != null && DateTime.now().isBefore(entry.retryAt);
  }

  Future<String?> _downloadImage({
    required String scopeKey,
    required String url,
    required String itemId,
    required String variant,
    String? expectedSha256,
    String? expectedMime,
  }) async {
    if (variant != 'normal' && variant != 'transparent') return null;
    final itemKey = sha256
        .convert(utf8.encode(itemId))
        .toString()
        .substring(0, 20);
    final normalizedExpectedHash = expectedSha256?.trim().toLowerCase();
    if (normalizedExpectedHash != null &&
        RegExp(r'^[a-f0-9]{64}$').hasMatch(normalizedExpectedHash)) {
      final root = await _scopeRoot(scopeKey);
      final cachedPath = await _findCachedImage(
        root: root,
        itemKey: itemKey,
        variant: variant,
        expectedSha256: normalizedExpectedHash,
        expectedMime: expectedMime,
      );
      if (cachedPath != null) return cachedPath;
    }

    // Menu images come from our server over HTTPS only; anything else could
    // be swapped in transit.
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https') return null;
    // Streamed with a byte cap: an oversized answer is cut off at 5 MB
    // instead of being held in memory whole first. Content-Length is only a
    // hint (it can be missing behind Cloudflare).
    final streamed = await _client
        .send(http.Request('GET', uri))
        .timeout(const Duration(seconds: 12));
    if (streamed.statusCode != 200 ||
        (streamed.contentLength ?? 0) > _maxImageBytes) {
      unawaited(streamed.stream.listen(null).cancel());
      return null;
    }
    final bytes = await _readCapped(
      streamed.stream,
      _maxImageBytes,
    ).timeout(const Duration(seconds: 30));
    if (bytes == null || bytes.isEmpty) return null;
    final mime = streamed.headers['content-type']
        ?.split(';')
        .first
        .toLowerCase();
    const allowed = {'image/jpeg', 'image/png', 'image/webp'};
    if (mime == null ||
        !allowed.contains(mime) ||
        (expectedMime != null &&
            expectedMime.trim().isNotEmpty &&
            mime != expectedMime.trim().toLowerCase()) ||
        (variant == 'transparent' && mime != 'image/png') ||
        !_hasImageSignature(bytes, mime)) {
      return null;
    }
    // Hashing runs off the UI isolate (as in isValidImage): a menu update
    // with many photos must not stall the wheel, snow or video.
    final digest = await _bytesSha256(bytes);
    if (normalizedExpectedHash != null &&
        normalizedExpectedHash.isNotEmpty &&
        digest != normalizedExpectedHash) {
      return null;
    }
    final root = await _scopeRoot(scopeKey);
    final extension = mime == 'image/png'
        ? 'png'
        : mime == 'image/webp'
        ? 'webp'
        : 'jpg';
    final file = File(
      '${root.path}${Platform.pathSeparator}images${Platform.pathSeparator}$itemKey-$variant-$digest.$extension',
    );
    await file.parent.create(recursive: true);
    if (await file.exists()) {
      final existingHash = await _pathSha256(file.path);
      if (existingHash == digest) return file.path;
      await file.delete();
    }
    final temp = File(
      '${file.path}.${DateTime.now().microsecondsSinceEpoch}.part',
    );
    try {
      await temp.writeAsBytes(bytes, flush: true);
      final writtenHash = await _pathSha256(temp.path);
      if (writtenHash != digest) return null;
      await temp.rename(file.path);
    } finally {
      if (await temp.exists()) await temp.delete();
    }
    return file.path;
  }

  static const int _maxImageBytes = 5 * 1024 * 1024;

  /// The whole body, or null as soon as it grows past [maxBytes] (returning
  /// from the loop cancels the download).
  static Future<Uint8List?> _readCapped(
    Stream<List<int>> stream,
    int maxBytes,
  ) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in stream) {
      builder.add(chunk);
      if (builder.length > maxBytes) return null;
    }
    return builder.takeBytes();
  }

  Future<String?> _findCachedImage({
    required Directory root,
    required String itemKey,
    required String variant,
    required String expectedSha256,
    String? expectedMime,
  }) async {
    final images = Directory('${root.path}${Platform.pathSeparator}images');
    if (!await images.exists()) return null;

    final prefix = '$itemKey-$variant-$expectedSha256.';
    await for (final entity in images.list(followLinks: false)) {
      if (entity is! File) continue;
      final separator = Platform.pathSeparator;
      final name = entity.path.split(separator).last;
      if (!name.startsWith(prefix)) continue;
      if (await isValidImage(
        entity.path,
        expectedSha256: expectedSha256,
        expectedMime: expectedMime,
      )) {
        return entity.path;
      }
    }
    return null;
  }

  Future<bool> isValidImage(
    String? path, {
    String? expectedSha256,
    String? expectedMime,
  }) async {
    if (path == null || path.isEmpty) return false;
    try {
      final file = File(path);
      // One stat per check: this runs for every image on every 30 s poll.
      final stat = await file.stat();
      if (stat.type == FileSystemEntityType.notFound || stat.size == 0) {
        return false;
      }
      final length = stat.size;
      final mtimeMs = stat.modified.millisecondsSinceEpoch;
      final expected = expectedSha256?.trim().toLowerCase();
      if (expected != null && expected.isNotEmpty) {
        // Verified before and unchanged since: no need to read it again.
        final known = _verified[path];
        if (known != null &&
            known.size == length &&
            known.mtimeMs == mtimeMs &&
            known.sha == expected) {
          return true;
        }
      }
      final extension = path.split('.').last.toLowerCase();
      final mime =
          expectedMime ??
          (extension == 'png'
              ? 'image/png'
              : extension == 'webp'
              ? 'image/webp'
              : extension == 'jpg' || extension == 'jpeg'
              ? 'image/jpeg'
              : null);
      if (mime == null) return false;
      final signature = await file
          .openRead(0, length < 12 ? length : 12)
          .fold<List<int>>(<int>[], (bytes, chunk) => bytes..addAll(chunk));
      if (!_hasImageSignature(signature, mime)) return false;
      if (expected == null || expected.isEmpty) return true;
      return await _fileSha256(file, length, mtimeMs) == expected;
    } catch (_) {
      return false;
    }
  }

  Future<String> _fileSha256(File file, int length, int mtimeMs) async {
    final known = _verified[file.path];
    if (known != null && known.size == length && known.mtimeMs == mtimeMs) {
      return known.sha;
    }
    final path = file.path;
    final digest = await _pathSha256(path);
    _verified[path] = (size: length, mtimeMs: mtimeMs, sha: digest);
    return digest;
  }

  /// SHA-256 of a file, read and hashed in a background isolate.
  static Future<String> _pathSha256(String path) => Isolate.run(
    () async => (await sha256.bind(File(path).openRead()).first).toString(),
  );

  /// SHA-256 of downloaded bytes, hashed in a background isolate.
  static Future<String> _bytesSha256(List<int> bytes) =>
      Isolate.run(() => sha256.convert(bytes).toString());

  @visibleForTesting
  static Future<String> bytesSha256ForTesting(List<int> bytes) =>
      _bytesSha256(bytes);

  @visibleForTesting
  static Future<String> pathSha256ForTesting(String path) => _pathSha256(path);

  /// Deletes cached images the active catalog no longer references, so every
  /// image change does not leave the old file behind forever.
  Future<void> pruneImages(String scopeKey, Set<String> keepPaths) async {
    try {
      final images = Directory(
        '${(await _scopeRoot(scopeKey)).path}${Platform.pathSeparator}images',
      );
      if (!await images.exists()) return;
      final keep = keepPaths.map((path) => File(path).absolute.path).toSet();
      await for (final entity in images.list(followLinks: false)) {
        if (entity is! File) continue;
        if (keep.contains(entity.absolute.path)) continue;
        // In-flight downloads write *.part files; leave those alone.
        if (entity.path.endsWith('.part')) continue;
        _verified.remove(entity.path);
        await entity.delete();
      }
    } catch (_) {
      // Pruning is housekeeping only; a failure must not break a sync.
    }
  }

  Future<File> _pendingFile(String scopeKey) async => File(
    '${(await _scopeRoot(scopeKey)).path}${Platform.pathSeparator}pending_config.json',
  );

  /// Wheel/barista writes that have not reached the server yet, per domain.
  Future<Map<String, Map<String, dynamic>>> readPendingConfig(
    String scopeKey,
  ) async {
    try {
      if (scopeKey.trim().isEmpty) return {};
      final file = await _pendingFile(scopeKey);
      if (!await file.exists()) return {};
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return {};
      return {
        for (final entry in decoded.entries)
          if (entry.value is Map)
            entry.key.toString(): Map<String, dynamic>.from(entry.value as Map),
      };
    } catch (_) {
      return {};
    }
  }

  Future<void> writePendingConfig(
    String scopeKey,
    Map<String, Map<String, dynamic>> pending,
  ) async {
    if (scopeKey.trim().isEmpty) return;
    final file = await _pendingFile(scopeKey);
    if (pending.isEmpty) {
      if (await file.exists()) await file.delete();
      return;
    }
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(pending), flush: true);
    await temp.rename(file.path);
  }

  bool _hasImageSignature(List<int> bytes, String mime) {
    if (mime == 'image/jpeg') {
      return bytes.length >= 3 &&
          bytes[0] == 0xff &&
          bytes[1] == 0xd8 &&
          bytes[2] == 0xff;
    }
    if (mime == 'image/png') {
      return bytes.length >= 8 &&
          bytes.take(8).join(',') == '137,80,78,71,13,10,26,10';
    }
    if (mime == 'image/webp') {
      return bytes.length >= 12 &&
          String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
          String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP';
    }
    return false;
  }

  /// Deletes every scope folder except [keepScopeKey]'s. Called after a
  /// successful write for the current scope, so caches of earlier profiles
  /// (re-enrollment) or the pre-profile legacy scope do not pile up.
  Future<void> pruneOtherScopes(String keepScopeKey) async {
    if (keepScopeKey.trim().isEmpty) return;
    final keep = _safeScope(keepScopeKey);
    final scopeFolder = RegExp(r'^[0-9a-f]{64}$');
    try {
      final root = await _root();
      await for (final entity in root.list(followLinks: false)) {
        if (entity is! Directory) continue;
        final name = entity.uri.pathSegments
            .where((segment) => segment.isNotEmpty)
            .last;
        if (name == keep || !scopeFolder.hasMatch(name)) continue;
        try {
          await entity.delete(recursive: true);
        } catch (_) {
          // A locked file is retried on the next successful sync.
        }
      }
    } catch (error) {
      debugPrint('[MENU][CACHE] prune other scopes failed: $error');
    }
  }

  Future<void> clearScope(String scopeKey) async {
    if (scopeKey.trim().isEmpty) return;
    final root = await _root();
    final directory = Directory(
      '${root.path}${Platform.pathSeparator}${_safeScope(scopeKey)}',
    );
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}
