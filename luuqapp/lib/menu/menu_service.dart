import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../licensing/device_identity_service.dart';
import '../licensing/license_config.dart';
import '../licensing/license_service.dart';
import '../licensing/license_status.dart';
import '../licensing/license_storage.dart';
import 'menu_cache.dart';
import '../net/luuq_http.dart';
import 'menu_models.dart';

/// Outcome of a local wheel/barista change, shown to the admin.
enum MenuPushResult {
  /// The server accepted the change.
  saved,

  /// Saved on this kiosk and queued; it is retried until the server takes it.
  queued,

  /// The server refused the change (item not on this kiosk's menu, feature
  /// disabled); it is dropped from the queue.
  rejected,

  /// Remote menu management is not active for this kiosk; local only.
  localOnly,
}

class MenuService {
  static final MenuService instance = MenuService._();
  MenuService._({MenuCache? cache}) : _cache = cache ?? MenuCache();

  /// An isolated instance with its own cache directory, for tests only; the
  /// app always uses [instance].
  @visibleForTesting
  factory MenuService.forTest({required MenuCache cache}) =>
      MenuService._(cache: cache);

  final ValueNotifier<MenuCatalog?> catalogNotifier =
      ValueNotifier<MenuCatalog?>(null);
  final MenuCache _cache;
  final Uuid _uuid = const Uuid();
  Future<void>? _syncInFlight;

  /// A forced sync requested while another sync runs. Every such caller
  /// awaits this one future, so none returns before the forced sync finishes.
  Completer<void>? _forcedFollowUp;
  bool _loadedCache = false;
  String? _loadedScopeKey;
  int _scopeEpoch = 0;

  /// Domains ('wheel', 'barista') with a local change not yet on the server,
  /// for the currently loaded scope. While set, the server's value for that
  /// domain must not overwrite the kiosk's newer local choice.
  final Set<String> _pendingDomains = <String>{};
  bool _flushingPending = false;

  /// Sends of queued writes run one at a time, so an older change can never
  /// reach the server after a newer one for the same domain.
  Future<void> _sendChain = Future<void>.value();

  /// Read-modify-writes of the pending file run one at a time. Queuing a new
  /// change runs outside [_sendChain], so without this an older send dropping
  /// its entry could write back a stale copy and erase the newer change.
  Future<void> _pendingWrites = Future<void>.value();

  Future<T> _updatePending<T>(Future<T> Function() update) {
    final run = _pendingWrites.then((_) => update());
    _pendingWrites = run.then((_) {}, onError: (_) {});
    return run;
  }

  /// A queued change older than this is dropped unsent: the server's value
  /// (possibly changed from the panel since) wins again.
  static const Duration pendingConfigMaxAge = Duration(hours: 24);

  /// The clock used for queue ages; replaced in tests.
  @visibleForTesting
  DateTime Function() now = DateTime.now;

  bool hasPendingConfig(String domain) => _pendingDomains.contains(domain);

  Future<String> _scopeKey(LicenseStatus status, String deviceId) async {
    final profileId =
        status.menuProfileId ?? await LicenseStorage.getMenuProfileId();
    if (profileId != null && profileId.trim().isNotEmpty) {
      return 'profile:${profileId.trim()}';
    }
    final licenseKey = await LicenseStorage.getLicenseKey() ?? 'no-license';
    final digest = sha256
        .convert(utf8.encode('$licenseKey|$deviceId'))
        .toString();
    return 'legacy:$digest';
  }

  Future<void> _ensureCacheLoaded(String scopeKey) async {
    if (_loadedCache && _loadedScopeKey == scopeKey) return;
    final previousScope = _loadedScopeKey;
    _loadedCache = true;
    _loadedScopeKey = scopeKey;
    _scopeEpoch++;
    final epoch = _scopeEpoch;
    // Read first, then publish once: assigning null first made the screen
    // flash the bundled menu on every scope load.
    final cached = await _cache.readActive(scopeKey);
    final pending = await _cache.readPendingConfig(scopeKey);
    if (epoch != _scopeEpoch) return;
    _pendingDomains
      ..clear()
      ..addAll(pending.keys);
    catalogNotifier.value = cached;
    if (previousScope != null &&
        previousScope != scopeKey &&
        previousScope.startsWith('profile:') &&
        scopeKey.startsWith('profile:')) {
      // A new profile means a new enrollment; the old profile is archived on
      // the server and its cache (and queued writes) must never come back.
      unawaited(_cache.clearScope(previousScope));
    }
  }

  Future<void> syncNow({LicenseStatus? status, bool force = false}) async {
    final running = _syncInFlight;
    if (running != null) {
      if (!force) return running;
      return (_forcedFollowUp ??= Completer<void>()).future;
    }

    final future = _sync(status: status, force: force).catchError((
      error,
      stackTrace,
    ) {
      debugPrint('[MENU][SYNC] $error\n$stackTrace');
    });
    _syncInFlight = future;
    try {
      await future;
    } finally {
      _syncInFlight = null;
      final followUp = _forcedFollowUp;
      if (followUp != null) {
        _forcedFollowUp = null;
        try {
          // Use the latest status, not the one captured by the first caller.
          await syncNow(force: true);
        } finally {
          followUp.complete();
        }
      }
    }
  }

  Future<void> _sync({LicenseStatus? status, required bool force}) async {
    final current = status ?? LicenseService.instance.currentStatus;
    if (!current.active || !current.features.menu) {
      catalogNotifier.value = null;
      _loadedCache = false;
      _loadedScopeKey = null;
      return;
    }

    final token =
        current.menuAccessToken ?? await LicenseStorage.getMenuAccessToken();
    if (token == null || token.isEmpty) {
      catalogNotifier.value = null;
      _loadedCache = false;
      _loadedScopeKey = null;
      return;
    }

    final deviceId = await DeviceIdentityService.getDeviceId();
    final scopeKey = await _scopeKey(current, deviceId);
    await _ensureCacheLoaded(scopeKey);
    final requestEpoch = _scopeEpoch;
    final fingerprint = await DeviceIdentityService.getDeviceFingerprintHash();
    final appVersion = await DeviceIdentityService.getAppVersion();
    final currentCatalog = catalogNotifier.value;
    final body = <String, dynamic>{
      'device_id': deviceId,
      'fingerprint': fingerprint,
      'menu_access_token': token,
      'app_version': appVersion,
      if (!force && currentCatalog != null) ...{
        'menu_version': currentCatalog.menuVersion,
        'wheel_revision': currentCatalog.wheelRevision,
        'barista_revision': currentCatalog.baristaRevision,
        if (currentCatalog.effectiveRevision != null)
          'effective_revision': currentCatalog.effectiveRevision,
      },
    };

    // Retry queued wheel/barista writes first, so the catalog fetched below
    // already reflects them.
    if (_pendingDomains.isNotEmpty) await _flushPendingConfig(scopeKey);

    var response = await _postMenu(body);
    if (response.statusCode == 401) {
      final refreshed = await LicenseService.instance.checkStatus();
      if (!refreshed.active || !refreshed.features.menu) {
        return;
      }
      final retryToken =
          refreshed.menuAccessToken ??
          await LicenseStorage.getMenuAccessToken();
      if (retryToken == null || retryToken.isEmpty) {
        return;
      }
      body['menu_access_token'] = retryToken;
      response = await _postMenu(body);
    }
    if (requestEpoch != _scopeEpoch) {
      return;
    }
    if (response.statusCode != 200) {
      return;
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) return;
    var data = Map<String, dynamic>.from(decoded);
    if (data['not_modified'] == true) {
      if (currentCatalog == null ||
          await _cachedImagesComplete(currentCatalog)) {
        return;
      }
      final recoveryBody = <String, dynamic>{
        'device_id': deviceId,
        'fingerprint': fingerprint,
        'menu_access_token': body['menu_access_token'],
        'app_version': appVersion,
      };
      response = await _postMenu(recoveryBody);
      if (response.statusCode != 200 || requestEpoch != _scopeEpoch) return;
      final recoveryDecoded = jsonDecode(response.body);
      if (recoveryDecoded is! Map) return;
      data = Map<String, dynamic>.from(recoveryDecoded);
      if (data['not_modified'] == true) return;
    }
    var catalog = MenuCatalog.fromApiJson(data);
    final responseProfile = catalog.menuProfileId;
    final currentProfile = await LicenseStorage.getMenuProfileId();
    if (currentProfile == null || responseProfile != currentProfile) {
      return;
    }
    catalog = await _materializeImages(catalog, scopeKey);
    if (requestEpoch != _scopeEpoch) return;
    await _cache.writeActive(scopeKey, catalog);
    // The kiosk may still show an older catalog (a new one is held back
    // while a customer or admin dialog is open, possibly over several syncs),
    // so the previous one and the one on screen keep their images.
    final previous = catalogNotifier.value;
    catalogNotifier.value = catalog;
    unawaited(_cache.pruneOtherScopes(scopeKey));
    unawaited(
      _cache.pruneImages(scopeKey, {
        for (final item in [
          ...catalog.items,
          ...?previous?.items,
          ...?_displayedCatalog?.items,
        ]) ...[
          if (item.localImagePath != null) item.localImagePath!,
          if (item.localTransparentImagePath != null)
            item.localTransparentImagePath!,
        ],
      }),
    );
  }

  MenuCatalog? _displayedCatalog;

  /// The kiosk reports which catalog it shows (null: the bundled menu), so
  /// image cleanup never removes files that are still on screen.
  void markDisplayed(MenuCatalog? catalog) => _displayedCatalog = catalog;

  Future<http.Response> _postMenu(Map<String, dynamic> body) => luuqPost(
    Uri.parse(LicenseConfig.menuUrl),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode(body),
  ).timeout(const Duration(seconds: 12));

  /// Image downloads run [_imageDownloadConcurrency] at a time: one by one, a
  /// new catalog on a slow network took minutes (two images per item, each up
  /// to a 12 s timeout) before it could be shown.
  static const int _imageDownloadConcurrency = 4;

  Future<MenuCatalog> _materializeImages(
    MenuCatalog catalog,
    String scopeKey,
  ) async {
    final items = [
      for (final category in catalog.categories) ...category.items,
    ];
    final materialized = List<RemoteMenuItem?>.filled(items.length, null);
    var next = 0;
    Future<void> worker() async {
      while (next < items.length) {
        final index = next++;
        materialized[index] = await _materializeItem(items[index], scopeKey);
      }
    }

    await Future.wait(
      List.generate(
        items.length < _imageDownloadConcurrency
            ? items.length
            : _imageDownloadConcurrency,
        (_) => worker(),
      ),
    );

    var index = 0;
    final categories = <RemoteMenuCategory>[];
    for (final category in catalog.categories) {
      final categoryItems = <RemoteMenuItem>[];
      for (var i = 0; i < category.items.length; i++) {
        categoryItems.add(materialized[index++]!);
      }
      categories.add(
        RemoteMenuCategory(
          id: category.id,
          nameTr: category.nameTr,
          nameEn: category.nameEn,
          descriptionTr: category.descriptionTr,
          descriptionEn: category.descriptionEn,
          iconKey: category.iconKey,
          items: categoryItems,
        ),
      );
    }
    return catalog.copyWithCategories(categories);
  }

  Future<RemoteMenuItem> _materializeItem(
    RemoteMenuItem item,
    String scopeKey,
  ) async {
    final localPath = await _ensureImage(
      scopeKey: scopeKey,
      itemId: item.id,
      variant: 'normal',
      currentPath: item.localImagePath,
      url: item.imageUrl,
      sha256: item.imageSha256,
      mime: item.imageMime,
    );
    final localTransparentPath = await _ensureImage(
      scopeKey: scopeKey,
      itemId: item.id,
      variant: 'transparent',
      currentPath: item.localTransparentImagePath,
      url: item.transparentImageUrl,
      sha256: item.transparentImageSha256,
      mime: item.transparentImageMime,
    );
    return item.copyWith(
      localImagePath: localPath,
      localTransparentImagePath: localTransparentPath,
      clearLocalImagePath: localPath == null,
      clearLocalTransparentImagePath: localTransparentPath == null,
    );
  }

  /// Returns a verified local path for one image variant, downloading it when
  /// needed, or null when none is available (renderer falls back).
  Future<String?> _ensureImage({
    required String scopeKey,
    required String itemId,
    required String variant,
    required String? currentPath,
    required String? url,
    required String? sha256,
    required String? mime,
  }) async {
    if (await _cache.isValidImage(
      currentPath,
      expectedSha256: sha256,
      expectedMime: mime,
    )) {
      return currentPath;
    }
    if (url == null ||
        url.isEmpty ||
        _cache.isDownloadBackedOff(scopeKey, itemId, variant)) {
      return null;
    }
    try {
      return await _cache.downloadImage(
        scopeKey: scopeKey,
        url: url,
        itemId: itemId,
        variant: variant,
        expectedSha256: sha256,
        expectedMime: mime,
      );
    } catch (_) {
      return null;
    }
  }

  /// Whether every image the catalog references is cached and verified.
  /// Images still backing off after a failed download count as complete, so
  /// one bad image does not trigger a full menu refetch on every poll.
  Future<bool> _cachedImagesComplete(MenuCatalog catalog) async {
    final scopeKey = _loadedScopeKey ?? '';
    for (final item in catalog.items) {
      for (final (variant, url, path, sha, mime) in [
        (
          'normal',
          item.imageUrl,
          item.localImagePath,
          item.imageSha256,
          item.imageMime,
        ),
        (
          'transparent',
          item.transparentImageUrl,
          item.localTransparentImagePath,
          item.transparentImageSha256,
          item.transparentImageMime,
        ),
      ]) {
        if (url == null || url.isEmpty) continue;
        if (_cache.isDownloadBackedOff(scopeKey, item.id, variant)) continue;
        if (!await _cache.isValidImage(
          path,
          expectedSha256: sha,
          expectedMime: mime,
        )) {
          return false;
        }
      }
    }
    return true;
  }

  Future<MenuPushResult> pushLocalWheel(List<String> itemIds) =>
      _queueAndPush('wheel', {'wheel_item_ids': itemIds});

  Future<MenuPushResult> pushLocalBarista({
    required String drinkId,
    required String dessertId,
  }) => _queueAndPush('barista', {
    'barista_drink_id': drinkId,
    'barista_dessert_id': dessertId,
  });

  /// Persists the change for the current profile scope, then tries to send it.
  /// The idempotency key is fixed when queued, so a retry after a lost
  /// response is applied by the server at most once.
  Future<MenuPushResult> _queueAndPush(
    String domain,
    Map<String, dynamic> values,
  ) async {
    final status = LicenseService.instance.currentStatus;
    if (!status.active || !status.features.menu) {
      return MenuPushResult.localOnly;
    }
    final deviceId = await DeviceIdentityService.getDeviceId();
    final scopeKey = await _scopeKey(status, deviceId);
    if (!scopeKey.startsWith('profile:')) return MenuPushResult.localOnly;
    await _ensureCacheLoaded(scopeKey);

    await _updatePending(() async {
      final pending = await _cache.readPendingConfig(scopeKey);
      pending[domain] = {
        'values': values,
        'idempotency_key': _uuid.v4(),
        'queued_at': now().toUtc().toIso8601String(),
      };
      await _cache.writePendingConfig(scopeKey, pending);
      if (_loadedScopeKey == scopeKey) _pendingDomains.add(domain);
    });

    final result = await _sendPending(scopeKey, domain);
    if (result == MenuPushResult.saved || result == MenuPushResult.rejected) {
      // Saved: fetch the new revision. Rejected: the kiosk shows a choice the
      // server refused, so bring back the server's value.
      await syncNow(status: status, force: true);
    }
    return result;
  }

  Future<void> _flushPendingConfig(String scopeKey) async {
    if (_flushingPending) return;
    _flushingPending = true;
    try {
      final pending = await _cache.readPendingConfig(scopeKey);
      for (final domain in pending.keys.toList()) {
        await _sendPending(scopeKey, domain);
      }
    } finally {
      _flushingPending = false;
    }
  }

  Future<MenuPushResult> _sendPending(String scopeKey, String domain) {
    final send = _sendChain.then((_) => _sendPendingNow(scopeKey, domain));
    _sendChain = send.then((_) {}, onError: (_) {});
    return send;
  }

  Future<MenuPushResult> _sendPendingNow(String scopeKey, String domain) async {
    // Read inside the chain: the entry may have been replaced by a newer
    // change (new idempotency key) while an earlier send was running.
    final pending = await _cache.readPendingConfig(scopeKey);
    final entry = pending[domain];
    if (entry == null) return MenuPushResult.saved;
    final values = entry['values'] is Map
        ? Map<String, dynamic>.from(entry['values'] as Map)
        : <String, dynamic>{};
    final idempotencyKey = entry['idempotency_key']?.toString() ?? '';

    Future<void> drop() => _updatePending(() async {
      final latest = await _cache.readPendingConfig(scopeKey);
      // Only drop the entry we sent; a newer change may have replaced it.
      if (latest[domain]?['idempotency_key']?.toString() == idempotencyKey) {
        latest.remove(domain);
        await _cache.writePendingConfig(scopeKey, latest);
        if (_loadedScopeKey == scopeKey) _pendingDomains.remove(domain);
      }
    });

    final queuedAt = DateTime.tryParse(entry['queued_at']?.toString() ?? '');
    if (queuedAt == null || now().difference(queuedAt) > pendingConfigMaxAge) {
      await drop();
      return MenuPushResult.rejected;
    }

    final adminToken = await LicenseStorage.getAdminSessionToken();
    if (adminToken == null || adminToken.isEmpty) {
      // Admin session expired (15 min) or never existed: keep it queued; the
      // next PIN unlock sends it.
      return MenuPushResult.queued;
    }
    final deviceId = await DeviceIdentityService.getDeviceId();
    final fingerprint = await DeviceIdentityService.getDeviceFingerprintHash();

    Future<http.Response> post(String accessToken) => luuqPost(
      Uri.parse(LicenseConfig.menuConfigUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'domain': domain,
        ...values,
        'idempotency_key': idempotencyKey,
        'device_id': deviceId,
        'fingerprint': fingerprint,
        'menu_access_token': accessToken,
        'admin_session_token': adminToken,
      }),
    ).timeout(const Duration(seconds: 12));

    try {
      final accessToken = await LicenseStorage.getMenuAccessToken();
      if (accessToken == null || accessToken.isEmpty) {
        return MenuPushResult.queued;
      }
      var response = await post(accessToken);
      var reason = _reasonOf(response);
      if (response.statusCode == 401 && reason != 'invalid_admin_token') {
        // Expired menu access token: refresh it through check-status once.
        final refreshed = await LicenseService.instance.checkStatus();
        final retryToken =
            refreshed.menuAccessToken ??
            await LicenseStorage.getMenuAccessToken();
        if (refreshed.active && retryToken != null && retryToken.isNotEmpty) {
          response = await post(retryToken);
          reason = _reasonOf(response);
        }
      }

      if (response.statusCode == 200) {
        await drop();
        return MenuPushResult.saved;
      }
      if (reason == 'invalid_admin_token') {
        await LicenseStorage.clearAdminSessionToken();
        return MenuPushResult.queued;
      }
      if (response.statusCode == 422 ||
          response.statusCode == 400 ||
          reason == 'feature_disabled' ||
          reason == 'menu_scope_mismatch') {
        // Permanent refusal: retrying would loop forever.
        await drop();
        return MenuPushResult.rejected;
      }
      return MenuPushResult.queued;
    } catch (error, stackTrace) {
      debugPrint('[MENU][CONFIG] $error\n$stackTrace');
      return MenuPushResult.queued;
    }
  }

  static String? _reasonOf(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      return decoded is Map ? decoded['reason']?.toString() : null;
    } catch (_) {
      return null;
    }
  }

  void dispose() {
    catalogNotifier.dispose();
  }
}
