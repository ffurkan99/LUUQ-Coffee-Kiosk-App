part of '../../main.dart';

/// Test hook: names of the wheel items the visible kiosk shows.
@visibleForTesting
List<String> debugKioskWheelItemNames() =>
    _CafeKioskScreenState.activeInstance?._wheelMenuItems
        .map((item) => item.name)
        .toList(growable: false) ??
    const [];

/// Test hook: the barista drink/dessert the visible kiosk recommends.
@visibleForTesting
({String? drink, String? dessert}) debugKioskBaristaNames() {
  final state = _CafeKioskScreenState.activeInstance;
  return (
    drink: state?._currentBaristaDrink?.name,
    dessert: state?._currentBaristaDessert?.name,
  );
}

class CafeKioskScreen extends StatefulWidget {
  const CafeKioskScreen({super.key});

  @override
  State<CafeKioskScreen> createState() => _CafeKioskScreenState();
}

class _CafeKioskScreenState extends State<CafeKioskScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  static _CafeKioskScreenState? activeInstance;

  static void resetTimer() {
    activeInstance?._resetIdleTimer();
  }

  late final AnimationController _spinController;

  late final AnimationController _pulseController;

  final Random _random = Random();
  DrinkMood? _selectedMood;

  // _wheelTurns is replaced by _spinController.value
  double _dragStartAngle = 0;
  double _dragBaseTurns = 0;
  bool _isDragging = false;
  bool _isClockwise = true;
  Drink? _selectedDrink;
  bool _showResult = false;
  final _pointerSim = WheelPointerSimulation();
  final _pointerAngle = ValueNotifier<double>(0);
  late final Ticker _pointerTicker = createTicker(_handlePointerTick);
  Duration? _pointerLastElapsed;
  int _pointerPegCount = 0;
  double _pointerRimRadius = 0;
  _MenuItem? _baristaDrink;
  _MenuItem? _baristaDessert;
  late List<_MenuItem> _wheelMenuItems = _defaultWheelMenuItems();
  MenuCatalog? _pendingRemoteCatalog;
  bool _pendingBundledRestore = false;
  int _logoTapCount = 0;
  Timer? _logoTapTimer;
  bool _hasTrackedUpdateSeen = false;

  bool _isLoading = true;
  double _loadingProgress = 0.0;
  bool _isAppActive = true;
  String _loadingStatus = tr('Sistem yükleniyor...', 'System loading...');

  // Idle state handling
  Timer? _idleTimer;
  bool _isIdle = true;
  bool _isInCleaningMode = false;
  final _spinSound = _SpinTickSound();

  void _showProductDetailDialog(_MenuItem item, {Object? heroTag}) {
    if (!currentFeatureFlags.menu) {
      showFeatureLockedDialog(context, tr('Ürün Detayı', 'Product Detail'));
      return;
    }
    _showKioskDialog<void>(
      context,
      _ProductDetailDialog(item: item, heroTag: heroTag),
      label: _menuItemName(item),
    );
  }

  void _showUpdateDialog(BuildContext context, LicenseStatus status) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _VirtualCanvasDialogWrapper(
        child: _UpdateDialog(licenseStatus: status),
      ),
    );
  }

  // AFK background video
  VideoPlayerController? _videoController;
  // Marks controllers already disposed without keeping them alive (a Set grew
  // by one controller per failed video retry, for months on a 24/7 kiosk).
  final Expando<bool> _disposedVideoControllers = Expando<bool>(
    'disposedVideoController',
  );
  int _videoInitGeneration = 0;
  bool _videoUnavailable = false;

  /// A video failure (e.g. a decoder error after the TV wakes from standby)
  /// is retried after these delays, the last one repeating, instead of
  /// leaving the idle screen without its video until the app restarts.
  static const List<Duration> _videoRetryDelays = [
    Duration(minutes: 1),
    Duration(minutes: 5),
    Duration(minutes: 15),
  ];
  Timer? _videoRetryTimer;
  int _videoRetryCount = 0;
  bool _videoFailureLogged = false;

  List<Drink> get _filteredDrinks {
    final wheelDrinks = _wheelMenuItems.map(_drinkFromMenuItem).toList();
    if (_selectedMood == null) {
      return wheelDrinks;
    }
    return wheelDrinks
        .where((drink) => drink.moods.contains(_selectedMood))
        .toList();
  }

  bool get _canSpin =>
      !_spinController.isAnimating && _filteredDrinks.isNotEmpty;

  void _handleGlobalPointerEvent(PointerEvent event) {
    if (_isLoading) {
      return; // Ignore any input/pointer events during startup preloading
    }
    if (event is PointerDownEvent) {
      _resetIdleTimer(fromTap: true);
    }
  }

  void _resetIdleTimer({bool fromTap = false}) {
    _tryApplyPendingRemoteMenu();
    _idleTimer?.cancel();
    if (_isInCleaningMode) return;
    if (GlobalDialogTracker.shouldPauseIdleTimer()) return;
    if (_isIdle) {
      if (!fromTap) return;
      setState(() => _isIdle = false);
    }
    final idleTimeout = GlobalDialogTracker.isAdminSessionOpen
        ? const Duration(seconds: 90)
        : GlobalDialogTracker.isCustomerDialogOpen ||
              GlobalDialogTracker.isUpdateDialogOpen
        ? const Duration(seconds: 60)
        : const Duration(seconds: 15);
    _idleTimer = Timer(idleTimeout, () {
      if (_isInCleaningMode) return;
      if (GlobalDialogTracker.shouldPauseIdleTimer()) return;
      if (mounted && !_spinController.isAnimating) {
        // Pop all active dialogs/popups to go back to the main menu before transitioning to AFK
        Navigator.of(context).popUntil((route) => route.isFirst);

        setState(() {
          _isIdle = true;
          _showResult = false;
          _selectedMood = null;
        });
        if (!MediaQuery.disableAnimationsOf(context) &&
            _videoController != null) {
          unawaited(_playVideoIfAllowed(_videoController!));
        }
      }
    });
  }

  /// Tells the admin whether a wheel/barista change reached the server. The
  /// change is already applied and saved locally; this only reports sync.
  void _reportMenuPush(Future<MenuPushResult> push) {
    unawaited(
      push.then((result) {
        if (!mounted || result == MenuPushResult.localOnly) return;
        final messenger = ScaffoldMessenger.maybeOf(context);
        if (messenger == null) return;
        final text = switch (result) {
          MenuPushResult.saved => tr(
            'Değişiklik sunucuya kaydedildi.',
            'Change saved to the server.',
          ),
          MenuPushResult.queued => tr(
            'Bu kioskta kaydedildi; bağlantı gelince sunucuya gönderilecek.',
            'Saved on this kiosk; it will be sent when the connection returns.',
          ),
          MenuPushResult.rejected => tr(
            'Sunucu bu seçimi kabul etmedi (ürün bu kioskun menüsünde yok ya da özellik kapalı).',
            'The server rejected this choice (item not on this kiosk menu or feature disabled).',
          ),
          MenuPushResult.localOnly => '',
        };
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              text,
              style: const TextStyle(
                color: _cream,
                fontWeight: FontWeight.bold,
              ),
            ),
            backgroundColor: const Color(0xFF231E2D),
            duration: const Duration(seconds: 3),
          ),
        );
      }),
    );
  }

  void _handleRemoteMenuChanged() {
    final catalog = MenuService.instance.catalogNotifier.value;
    final busy =
        GlobalDialogTracker.shouldDeferMenuChanges() ||
        _spinController.isAnimating;
    if (catalog == null) {
      _pendingRemoteCatalog = null;
      if (_activeMenuCategories.isEmpty) return;
      // Like a new catalog, the switch back to the bundled menu waits until
      // no spin or admin dialog is using the current items.
      if (busy) {
        _pendingBundledRestore = true;
        return;
      }
      _restoreBundledMenu();
      return;
    }
    _pendingBundledRestore = false;
    if (busy) {
      _pendingRemoteCatalog = catalog;
      return;
    }
    _applyRemoteCatalogToScreen(catalog);
  }

  void _tryApplyPendingRemoteMenu() {
    if (GlobalDialogTracker.shouldDeferMenuChanges() ||
        _spinController.isAnimating) {
      return;
    }
    if (_pendingBundledRestore) {
      _pendingBundledRestore = false;
      if (_activeMenuCategories.isNotEmpty) _restoreBundledMenu();
      return;
    }
    final catalog = _pendingRemoteCatalog;
    if (catalog == null) return;
    _pendingRemoteCatalog = null;
    _applyRemoteCatalogToScreen(catalog);
  }

  /// The menu feature was turned off, the license was revoked or the device
  /// moved to a profile with no cached catalog: drop the previous profile's
  /// remote catalog and resolve the wheel/barista against the bundled menu.
  void _restoreBundledMenu() {
    MenuService.instance.markDisplayed(null);
    _activeMenuCategories = <String, List<_MenuItem>>{};
    _activeMenuCategoryIcons.clear();
    _activeMenuCategoryDescriptions.clear();
    _activeMenuCategoryDescriptionsEn.clear();
    _activeMenuCategoryNamesEn.clear();
    _activeMenuCategoryNamesById.clear();
    final bundledWheel = (_LuuqSettings.instance.wheelItems ?? const <String>[])
        .map(_findMenuItemByName)
        .whereType<_MenuItem>()
        .toList(growable: false);
    final settings = _LuuqSettings.instance;
    final drink = settings.baristaDrink == null
        ? null
        : _findMenuItemByName(settings.baristaDrink!);
    final dessert = settings.baristaDessert == null
        ? null
        : _findMenuItemByName(settings.baristaDessert!);
    if (!mounted) return;
    setState(() {
      _wheelMenuItems = bundledWheel.length == 8
          ? bundledWheel
          : _defaultWheelMenuItems(keep: bundledWheel);
      _baristaDrink = drink;
      _baristaDessert = dessert;
      _selectedDrink = null;
      _showResult = false;
    });
  }

  /// The locally saved barista pick resolved against the current catalog.
  _MenuItem? _savedBaristaItem({required bool drink}) {
    final settings = _LuuqSettings.instance;
    final id = drink ? settings.baristaDrinkId : settings.baristaDessertId;
    final name = drink ? settings.baristaDrink : settings.baristaDessert;
    return (id == null ? null : _findMenuItemById(id)) ??
        (name == null ? null : _findMenuItemByName(name));
  }

  void _applyRemoteCatalogToScreen(MenuCatalog catalog) {
    MenuService.instance.markDisplayed(catalog);
    _applyRemoteMenuCatalog(catalog);
    // A local wheel/barista change still queued for the server must not be
    // overwritten by the (older) server value.
    final wheelPending = MenuService.instance.hasPendingConfig('wheel');
    final baristaPending = MenuService.instance.hasPendingConfig('barista');
    final remoteWheel = wheelPending
        ? const <_MenuItem>[]
        : catalog.wheelItemIds
              .map(_findMenuItemById)
              .whereType<_MenuItem>()
              .toList(growable: false);
    final configuredWheel = remoteWheel.length == 8
        ? remoteWheel
        : (_LuuqSettings.instance.wheelItemIds ?? const <String>[])
              .map(_findMenuItemById)
              .whereType<_MenuItem>()
              .toList(growable: false);
    final migratedWheel = configuredWheel.length == 8
        ? configuredWheel
        : (_LuuqSettings.instance.wheelItems ?? const <String>[])
              .map(_findMenuItemByName)
              .whereType<_MenuItem>()
              .toList(growable: false);
    final drink = baristaPending || catalog.baristaDrinkId == null
        ? (baristaPending ? _savedBaristaItem(drink: true) : null)
        : _findMenuItemById(catalog.baristaDrinkId!);
    final dessert = baristaPending || catalog.baristaDessertId == null
        ? (baristaPending ? _savedBaristaItem(drink: false) : null)
        : _findMenuItemById(catalog.baristaDessertId!);
    if (migratedWheel.length == 8) {
      _LuuqSettings.instance.wheelItemIds = migratedWheel
          .map((item) => item.id)
          .whereType<String>()
          .toList(growable: false);
      _LuuqSettings.instance.wheelItems = migratedWheel
          .map((item) => item.name)
          .toList(growable: false);
    }
    final migratedDrink =
        drink ??
        (_LuuqSettings.instance.baristaDrink == null
            ? null
            : _findMenuItemByName(_LuuqSettings.instance.baristaDrink!));
    final migratedDessert =
        dessert ??
        (_LuuqSettings.instance.baristaDessert == null
            ? null
            : _findMenuItemByName(_LuuqSettings.instance.baristaDessert!));
    if (migratedDrink != null) {
      _LuuqSettings.instance.baristaDrinkId = migratedDrink.id;
      _LuuqSettings.instance.baristaDrink = migratedDrink.name;
    }
    if (migratedDessert != null) {
      _LuuqSettings.instance.baristaDessertId = migratedDessert.id;
      _LuuqSettings.instance.baristaDessert = migratedDessert.name;
    }
    unawaited(_LuuqSettings.instance.save());
    if (mounted) {
      setState(() {
        // Without a full configured wheel, keep the current items that still
        // exist in this menu (as the new objects, with current prices and
        // photos), drop removed ones and fill up from the default picks.
        if (migratedWheel.length == 8) {
          _wheelMenuItems = migratedWheel;
        } else {
          final kept = _wheelMenuItems
              .map(_resolveInCurrentMenu)
              .whereType<_MenuItem>()
              .toList(growable: false);
          _wheelMenuItems = kept.length == 8
              ? kept
              : _defaultWheelMenuItems(keep: kept);
        }
        // A barista pick removed from the menu falls back to the default
        // recommendation (null here) instead of advertising a deleted item.
        _baristaDrink =
            migratedDrink ??
            (_baristaDrink == null
                ? null
                : _resolveInCurrentMenu(_baristaDrink!));
        _baristaDessert =
            migratedDessert ??
            (_baristaDessert == null
                ? null
                : _resolveInCurrentMenu(_baristaDessert!));
      });
    }
  }

  /// [item] as it exists in the current menu (by id, else by name), or null.
  _MenuItem? _resolveInCurrentMenu(_MenuItem item) {
    final id = item.id;
    return (id == null ? null : _findMenuItemById(id)) ??
        _findMenuItemByName(item.name);
  }

  @override
  void initState() {
    super.initState();
    activeInstance = this;
    UpdateService.enableKioskMode();
    FeatureSyncService.instance.start(this);
    // Events a previous run could not send (sent after the next good check).
    unawaited(AnalyticsService.instance.loadQueue());
    LicenseService.instance.statusNotifier.addListener(
      _handleLicenseStatusChange,
    );
    FeatureSyncService.instance.connectionLost.addListener(
      _handleConnectionChange,
    );

    // Load persisted stable IDs first; names remain a one-time legacy fallback.
    final savedWheelIds = _LuuqSettings.instance.wheelItemIds;
    final loadedById = (savedWheelIds ?? const <String>[])
        .map(_findMenuItemById)
        .whereType<_MenuItem>()
        .toList();
    if (loadedById.length == 8) {
      _wheelMenuItems = loadedById;
    } else if (_LuuqSettings.instance.wheelItems != null) {
      // Bundled menu items carry no stable id, so names stay the fallback.
      final loadedItems = _LuuqSettings.instance.wheelItems!
          .map(_findMenuItemByName)
          .whereType<_MenuItem>()
          .toList();
      if (loadedItems.length == 8) {
        _wheelMenuItems = loadedItems;
      }
    }

    // Load persisted barista picks
    if (_LuuqSettings.instance.baristaDrink != null) {
      _baristaDrink = _LuuqSettings.instance.baristaDrinkId == null
          ? _findMenuItemByName(_LuuqSettings.instance.baristaDrink!)
          : _findMenuItemById(_LuuqSettings.instance.baristaDrinkId!);
    }
    if (_LuuqSettings.instance.baristaDessert != null) {
      _baristaDessert = _LuuqSettings.instance.baristaDessertId == null
          ? _findMenuItemByName(_LuuqSettings.instance.baristaDessert!)
          : _findMenuItemById(_LuuqSettings.instance.baristaDessertId!);
    }

    GestureBinding.instance.pointerRouter.addGlobalRoute(
      _handleGlobalPointerEvent,
    );
    appLanguageNotifier.addListener(_handleLanguageChange);
    appThemeNotifier.addListener(_handleThemeChange);
    appVolumeNotifier.addListener(_handleVolumeChange);
    _spinController = AnimationController(
      vsync: this,
      lowerBound: double.negativeInfinity,
      upperBound: double.infinity,
      value: 0.0,
      duration: const Duration(milliseconds: 5000),
    )..addListener(_handleSpinFrame);

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    MenuService.instance.catalogNotifier.addListener(_handleRemoteMenuChanged);
    unawaited(_loadRunningAppVersion());
    _handleRemoteMenuChanged();
    unawaited(
      MenuService.instance.syncNow(
        status: LicenseService.instance.currentStatus,
      ),
    );

    _isAppActive =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);

    // Initialize AFK video
    _initVideo();

    // Load analytics data
    unawaited(_LuuqAnalytics.instance.load());

    // Don't reset idle timer on start - stay in AFK mode
    // _resetIdleTimer();

    // Start pre-caching images after first frame when context is safe
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _precacheImages();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotionPreference();
  }

  void _disposeVideoController(VideoPlayerController controller) {
    if (_disposedVideoControllers[controller] == true) return;
    _disposedVideoControllers[controller] = true;
    controller.removeListener(_handleVideoValueChanged);
    unawaited(_disposeVideoControllerSafely(controller));
  }

  Future<void> _disposeVideoControllerSafely(
    VideoPlayerController controller,
  ) async {
    try {
      await controller.dispose();
    } catch (error) {
      debugPrint('[VIDEO] dispose failed: $error');
    }
  }

  void _disableVideo({
    VideoPlayerController? controller,
    required String reason,
    Object? error,
  }) {
    _videoInitGeneration++;
    _videoUnavailable = true;
    final target = controller ?? _videoController;
    if (identical(_videoController, target)) {
      _videoController = null;
    }
    if (target != null) _disposeVideoController(target);

    if (!_videoFailureLogged) {
      _videoFailureLogged = true;
      final detail = error == null ? '' : ' error=$error';
      debugPrint('[VIDEO] disabled: $reason.$detail');
    }
    _videoRetryTimer?.cancel();
    final delay =
        _videoRetryDelays[min(_videoRetryCount, _videoRetryDelays.length - 1)];
    _videoRetryCount++;
    _videoRetryTimer = Timer(delay, () {
      if (mounted && _videoController == null) unawaited(_initVideo());
    });
    if (mounted) setState(() {});
  }

  void _handleVideoValueChanged() {
    final controller = _videoController;
    if (controller == null || !controller.value.hasError) return;
    _disableVideo(
      controller: controller,
      reason: 'native playback error',
      error: controller.value.errorDescription,
    );
  }

  Future<void> _playVideoIfAllowed(VideoPlayerController controller) async {
    if (!mounted ||
        _videoUnavailable ||
        !identical(_videoController, controller) ||
        !isVideoReadyForRender(controller.value, unavailable: false)) {
      return;
    }
    try {
      await controller.play();
    } catch (error) {
      if (identical(_videoController, controller)) {
        _disableVideo(
          controller: controller,
          reason: 'playback start failed',
          error: error,
        );
      }
    }
  }

  Future<void> _pauseVideoIfReady(VideoPlayerController controller) async {
    if (!controller.value.isInitialized || controller.value.hasError) return;
    try {
      await controller.pause();
    } catch (error) {
      if (identical(_videoController, controller)) {
        _disableVideo(
          controller: controller,
          reason: 'pause failed',
          error: error,
        );
      }
    }
  }

  void _syncMotionPreference() {
    final controller = _videoController;
    if (MediaQuery.disableAnimationsOf(context) || !_isAppActive) {
      _pulseController.stop();
      _pulseController.value = 0.5;
      if (controller != null) {
        unawaited(_pauseVideoIfReady(controller));
      }
    } else {
      if (!_pulseController.isAnimating) _pulseController.repeat(reverse: true);
      if (controller != null) {
        unawaited(_playVideoIfAllowed(controller));
      }
    }
  }

  Future<void> _initVideo() async {
    final generation = ++_videoInitGeneration;
    VideoPlayerController? controller;
    try {
      _videoUnavailable = false;
      if (Platform.isWindows) {
        // Let the Windows runner finish creating its graphics surface before
        // the native video plugin allocates its shared texture.
        await Future.delayed(const Duration(milliseconds: 300));
        if (!mounted || generation != _videoInitGeneration) return;

        // On Windows, asset videos must be loaded from the data directory
        final exePath = Platform.resolvedExecutable;
        final exeDir = File(exePath).parent.path;
        final videoFile = File(
          '$exeDir${Platform.pathSeparator}data${Platform.pathSeparator}'
          'flutter_assets${Platform.pathSeparator}assets${Platform.pathSeparator}'
          'luuqtanitim.mp4',
        );
        if (!await videoFile.exists()) {
          _disableVideo(reason: 'asset missing', error: videoFile.path);
          return;
        }
        controller = VideoPlayerController.file(videoFile);
      } else {
        // On Android/iOS, natively use asset loader
        controller = VideoPlayerController.asset('assets/luuqtanitim.mp4');
      }

      if (!mounted || generation != _videoInitGeneration) {
        _disposeVideoController(controller);
        return;
      }
      _videoController = controller;
      controller.addListener(_handleVideoValueChanged);
      await controller.setLooping(true);
      await controller.setVolume(0.0);
      await controller.initialize();

      if (!mounted ||
          generation != _videoInitGeneration ||
          !identical(_videoController, controller)) {
        _disposeVideoController(controller);
        return;
      }
      if (!isVideoReadyForRender(controller.value, unavailable: false)) {
        _disableVideo(
          controller: controller,
          reason: 'initialize returned an unusable video state',
          error: controller.value.errorDescription,
        );
        return;
      }

      _videoRetryCount = 0;
      setState(() {});
      if (_isAppActive && !MediaQuery.disableAnimationsOf(context)) {
        unawaited(_playVideoIfAllowed(controller));
      }
    } catch (error) {
      if (generation != _videoInitGeneration || !mounted) {
        if (controller != null) _disposeVideoController(controller);
        return;
      }
      _disableVideo(
        controller: controller,
        reason: 'initialize failed',
        error: error,
      );
    }
  }

  String _wheelImagePath(String path) {
    return path
        .replaceFirst('assets/menu/png/', 'assets/menu/')
        .replaceAll('assets/menu/', 'assets/menu/png/')
        .replaceAll('.jpg', '.png')
        .replaceAll('.jpeg', '.png')
        .replaceAll('.webp', '.png');
  }

  Future<void> _precacheImages() async {
    // Only assets visible on the first idle screen and immediately after the
    // first tap may block startup. The rest of the menu warms in the
    // background, so a large asset catalog cannot hold the kiosk on its
    // loading screen.
    final criticalProviders = <ImageProvider>{
      ResizeImage(
        const AssetImage('assets/logo.png'),
        width: _logoCacheWidth,
      ),
      for (final qr in const [
        'assets/instagramqr.png',
        'assets/mapsqr.png',
        'assets/wifiqr.png',
      ])
        ResizeImage(AssetImage(qr), width: _qrCacheWidth),
    };

    Set<String> assetKeys = {};
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      assetKeys = manifest.listAssets().toSet();
    } catch (e) {
      debugPrint('Failed to load asset manifest: $e');
    }

    final criticalList = criticalProviders.toList();
    for (var offset = 0; offset < criticalList.length; offset += 4) {
      if (!mounted) return;
      final end = min(offset + 4, criticalList.length);
      await Future.wait(
        criticalList.sublist(offset, end).map(_precacheImageSafely),
      );
      if (!mounted) return;
      setState(() {
        _loadingProgress = end / criticalList.length;
        _loadingStatus = tr(
          'Görseller hazırlanıyor... ($end/${criticalList.length})',
          'Preparing images... ($end/${criticalList.length})',
        );
      });
    }

    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _isIdle = true;
    });
    AnalyticsService.instance.trackAppStarted();
    if (_isAppActive &&
        !MediaQuery.disableAnimationsOf(context) &&
        _videoController != null) {
      unawaited(_playVideoIfAllowed(_videoController!));
    }
    unawaited(_precacheDeferredMenuImages(assetKeys));
  }

  Future<void> _precacheImageSafely(ImageProvider provider) async {
    if (!mounted) return;
    try {
      await precacheImage(provider, context);
    } catch (e) {
      debugPrint('Error pre-caching image: $e');
    }
  }

  Future<void> _precacheDeferredMenuImages(Set<String> assetKeys) async {
    final providers = <ImageProvider>{};
    // Wheel images are the first deferred batch, so they normally finish while
    // the idle screen is visible without delaying that screen itself.
    for (final item in _wheelMenuItems) {
      final path = item.imagePath;
      if (path == null) continue;
      final wheelPath = _wheelImagePath(path);
      if (assetKeys.isEmpty || assetKeys.contains(wheelPath)) {
        // Same provider the wheel draws with (cacheWidth: 136); a plain
        // AssetImage would decode the full-size picture into a cache entry
        // the wheel never uses.
        providers.add(ResizeImage(AssetImage(wheelPath), width: 136));
      }
    }
    for (final category in _currentMenuCategories.values) {
      for (final item in category) {
        final path = item.imagePath;
        if (path == null ||
            (assetKeys.isNotEmpty && !assetKeys.contains(path))) {
          continue;
        }
        // Grid cards use this cache size. Full-resolution detail images remain
        // lazy and are decoded only when a customer opens the detail view.
        providers.add(ResizeImage(AssetImage(path), width: 176));
      }
    }

    final providerList = providers.toList();
    for (var offset = 0; offset < providerList.length; offset += 4) {
      if (!mounted) return;
      final end = min(offset + 4, providerList.length);
      await Future.wait(
        providerList.sublist(offset, end).map(_precacheImageSafely),
      );
      await Future<void>.delayed(Duration.zero);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final isActive = state == AppLifecycleState.resumed;
    _isAppActive = isActive;

    if (isActive) {
      _syncMotionPreference();
      _wakePointer();
      if (!_isLoading && !_isIdle) {
        _resetIdleTimer();
      }
      return;
    }

    _idleTimer?.cancel();
    _pulseController.stop(canceled: false);
    _pointerTicker.stop();
    final controller = _videoController;
    if (controller != null) {
      unawaited(_pauseVideoIfReady(controller));
    }
  }

  String? _runningAppVersion;

  Future<void> _loadRunningAppVersion() async {
    final version = await DeviceIdentityService.getAppVersion();
    if (!mounted) return;
    setState(() => _runningAppVersion = version);
  }

  /// The text of the closed-screen notice, or null when the kiosk is open.
  ({String title, String body})? _serviceBlockMessage(LicenseStatus status) {
    if (!status.active) return null;
    if (FeatureSyncService.instance.connectionLost.value) {
      return (
        title: tr('İnternet Bağlantısı Yok', 'No Internet Connection'),
        body: tr(
          'Kiosk sunucuya bağlanamıyor. Bağlantı geri geldiğinde ekran kendiliğinden açılacak.',
          'The kiosk cannot reach the server. The screen will reopen by itself when the connection is back.',
        ),
      );
    }
    if (status.maintenanceEnabled) {
      final message = status.maintenanceMessage?.trim() ?? '';
      return (
        title: tr('Bakım Çalışması', 'Under Maintenance'),
        body: message.isNotEmpty
            ? message
            : tr(
                'Sistem bakım çalışması nedeniyle geçici olarak hizmet dışıdır. Lütfen daha sonra tekrar deneyiniz.',
                'The system is temporarily unavailable for maintenance. Please try again later.',
              ),
      );
    }
    final current = _runningAppVersion;
    if (current != null &&
        VersionInfo.isBelowMinimum(current, status.minimumAppVersion)) {
      return (
        title: tr('Güncelleme Gerekli', 'Update Required'),
        body: tr(
          'Bu uygulama sürümü artık desteklenmiyor. Lütfen yöneticinize haber verin; güncelleme sol üstteki düğmeden yapılabilir.',
          'This app version is no longer supported. Please contact the administrator; the update can be started from the button at the top left.',
        ),
      );
    }
    return null;
  }

  @override
  void dispose() {
    if (activeInstance == this) {
      activeInstance = null;
    }
    FeatureSyncService.instance.stopIfOwner(this);
    _videoRetryTimer?.cancel();
    LicenseService.instance.statusNotifier.removeListener(
      _handleLicenseStatusChange,
    );
    FeatureSyncService.instance.connectionLost.removeListener(
      _handleConnectionChange,
    );
    MenuService.instance.catalogNotifier.removeListener(
      _handleRemoteMenuChanged,
    );
    GestureBinding.instance.pointerRouter.removeGlobalRoute(
      _handleGlobalPointerEvent,
    );
    appLanguageNotifier.removeListener(_handleLanguageChange);
    appThemeNotifier.removeListener(_handleThemeChange);
    appVolumeNotifier.removeListener(_handleVolumeChange);
    WidgetsBinding.instance.removeObserver(this);
    _videoInitGeneration++;
    final videoController = _videoController;
    _videoController = null;
    if (videoController != null) {
      _disposeVideoController(videoController);
    }
    _pointerTicker.dispose();
    _pointerAngle.dispose();
    _spinController.dispose();
    _pulseController.dispose();
    _idleTimer?.cancel();
    _logoTapTimer?.cancel();
    super.dispose();
  }

  void _handleLicenseStatusChange() {
    if (!LicenseService.instance.currentFeatureFlags.english) {
      if (appLanguageNotifier.value == AppLanguage.en) {
        appLanguageNotifier.value = AppLanguage.tr;
      }
    }
  }

  void _handleConnectionChange() {
    if (mounted) setState(() {});
  }

  void _handleLanguageChange() {
    if (mounted) {
      setState(() {});
      AnalyticsService.instance.trackLanguageChanged(
        appLanguageNotifier.value.name,
      );
    }
  }

  void _handleThemeChange() {
    if (mounted) {
      setState(() {});
    }
  }

  void _handleVolumeChange() {
    if (mounted) {
      setState(() {});
    }
  }

  void _handleSpinFrame() => _wakePointer();

  /// Runs the pointer simulation while the wheel moves or the pointer still
  /// swings; it stops itself once everything is at rest, so an idle kiosk
  /// spends nothing on it.
  void _wakePointer() {
    if (!_isAppActive || _pointerTicker.isActive) return;
    _pointerLastElapsed = null;
    _pointerTicker.start();
  }

  void _handlePointerTick(Duration elapsed) {
    final previous = _pointerLastElapsed;
    _pointerLastElapsed = elapsed;
    final seconds = previous == null
        ? 1 / 60
        : (elapsed - previous).inMicroseconds / Duration.microsecondsPerSecond;
    final releases = _pointerSim.advance(
      turns: _spinController.value,
      pegCount: _pointerPegCount,
      rimRadius: _pointerRimRadius,
      seconds: seconds,
    );
    // The tick sounds when the pointer slips off a peg and snaps back.
    if (releases > 0) _spinSound.playTick();
    _pointerAngle.value = MediaQuery.disableAnimationsOf(context)
        ? 0
        : _pointerSim.angle;
    if (_pointerSim.isSettled &&
        !_spinController.isAnimating &&
        !_isDragging) {
      _pointerTicker.stop();
    }
  }

  String _findCategoryForDrink(Drink drink) {
    for (final entry in _currentMenuCategories.entries) {
      for (final item in entry.value) {
        // drink.fullName trMenu ile çevrilmiş addır; İngilizce modda ham
        // item.name ile eşleşmez, çevrilmiş adla da karşılaştırılmalı.
        if (item.name == drink.fullName ||
            _menuItemName(item) == drink.fullName ||
            item.name == drink.shortName) {
          return entry.key;
        }
      }
    }
    return 'Çark';
  }

  void _spinWheel({
    bool clockwise = true,
    Duration? duration,
    Curve curve = Curves.easeInOutQuart,
  }) {
    if (!currentFeatureFlags.wheel) {
      showFeatureLockedDialog(context, tr('Çark Çevirme', 'Wheel Spin'));
      return;
    }
    final available = _filteredDrinks;
    if (!_canSpin) return;

    _resetIdleTimer(); // reset on spin start
    unawaited(_LuuqAnalytics.instance.incrementWheelSpins());
    AnalyticsService.instance.trackWheelSpinStart();

    final nextDrink = available[_random.nextInt(available.length)];
    final segmentTurns = 1 / available.length;
    final selectedIndex = available.indexOf(nextDrink);

    // The center of the selected segment in turns
    final targetCenterTurns = selectedIndex * segmentTurns + (segmentTurns / 2);

    // Tiny random offset to keep pointer well within the segment's visual center
    final randomOffset = (0.5 - _random.nextDouble()) * (segmentTurns * 0.3);

    final currentModulo = _spinController.value % 1;
    double desiredModulo = (-targetCenterTurns + randomOffset) % 1;
    if (desiredModulo < 0) desiredModulo += 1.0;

    double diff = desiredModulo - currentModulo;
    if (clockwise) {
      if (diff <= 0) diff += 1.0;
    } else {
      if (diff >= 0) diff -= 1.0;
    }

    // 4 extra full spins for dramatic effect
    final targetTurns = _spinController.value + diff + (clockwise ? 4 : -4);

    final spinDuration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : duration ?? const Duration(milliseconds: 5000);
    _spinController.duration = spinDuration;

    setState(() {
      _showResult = false;
      _isIdle = false; // Never idle while spinning
    });

    _spinController.animateTo(targetTurns, curve: curve).whenComplete(() {
      if (!mounted) return;
      setState(() {
        _selectedDrink = nextDrink;
        _showResult = true;
      });
      _spinSound.playResult();
      _resetIdleTimer(); // Restart idle timer after spin finishes

      AnalyticsService.instance.trackWheelSpinResult(
        _generateSlug(nextDrink.fullName),
        nextDrink.fullName,
        _findCategoryForDrink(nextDrink),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final available = _isLoading ? <Drink>[] : _filteredDrinks;
    final isSpinning = _isLoading ? false : _spinController.isAnimating;
    final videoController = _videoController;
    final showVideo =
        videoController != null &&
        isVideoReadyForRender(
          videoController.value,
          unavailable: _videoUnavailable,
        );

    return ValueListenableBuilder<LicenseStatus>(
      valueListenable: LicenseService.instance.statusNotifier,
      builder: (context, licenseStatus, _) {
        return PopScope(
          canPop: false,
          child: _isLoading
              ? Scaffold(backgroundColor: _bgDark, body: _buildLoadingScreen())
              : MouseRegion(
                  onHover: (_) => _resetIdleTimer(fromTap: false),
                  child: Listener(
                    onPointerDown: (_) => _resetIdleTimer(fromTap: true),
                    onPointerMove: (_) => _resetIdleTimer(fromTap: false),
                    behavior: HitTestBehavior.translucent,
                    child: Scaffold(
                      body: Stack(
                        children: [
                          // Global video background
                          if (showVideo)
                            SizedBox.expand(
                              child: FittedBox(
                                fit: BoxFit.cover,
                                child: SizedBox(
                                  width: videoController.value.size.width,
                                  height: videoController.value.size.height,
                                  child: VideoPlayer(videoController),
                                ),
                              ),
                            ),
                          if (!showVideo)
                            const SizedBox.expand(
                              child: ColoredBox(color: _bgDark),
                            ),
                          // Global Dark overlay
                          Container(
                            color: Colors.black.withValues(alpha: 0.40),
                          ),

                          // VIRTUAL CANVAS (Responsive Width, Fixed Height 1080)
                          LayoutBuilder(
                            builder: (context, constraints) {
                              // Eliminate pillarboxing by calculating a dynamic width based on actual screen aspect ratio
                              final screenAspectRatio =
                                  constraints.maxWidth / constraints.maxHeight;
                              // Ensure canvas is at least 1920px wide
                              final virtualWidthDynamic = max(
                                1920.0,
                                1080.0 * screenAspectRatio,
                              );

                              return Center(
                                child: FittedBox(
                                  fit: BoxFit.contain,
                                  child: MediaQuery(
                                    data: MediaQuery.of(context).copyWith(
                                      size: Size(virtualWidthDynamic, 1080.0),
                                    ),
                                    child: SizedBox(
                                      width: virtualWidthDynamic,
                                      height: 1080.0,
                                      child: Stack(
                                        children: [
                                          // Main UI Content & AFK Overlay
                                          Positioned.fill(
                                            child: AnimatedSwitcher(
                                              duration: const Duration(
                                                milliseconds: 1000,
                                              ),
                                              switchInCurve: Curves.easeInOut,
                                              switchOutCurve: Curves.easeInOut,
                                              child: _isIdle
                                                  ? LayoutBuilder(
                                                      key: const ValueKey(
                                                        'afk_overlay',
                                                      ),
                                                      builder:
                                                          (
                                                            context,
                                                            constraints,
                                                          ) {
                                                            return _buildAfkOverlayContent(
                                                              constraints,
                                                            );
                                                          },
                                                    )
                                                  : SizedBox(
                                                      key: const ValueKey(
                                                        'main_layout',
                                                      ),
                                                      child:
                                                          _buildCanvasMainLayout(
                                                            available,
                                                            isSpinning,
                                                            virtualWidthDynamic,
                                                          ),
                                                    ),
                                            ),
                                          ),

                                          // MAINTENANCE / UPDATE REQUIRED: covers the
                                          // customer UI; the update badge and the
                                          // logo (admin access) stay above it.
                                          if (_serviceBlockMessage(
                                                licenseStatus,
                                              )
                                              case final blockMessage?)
                                            Positioned.fill(
                                              child: _buildServiceBlockOverlay(
                                                blockMessage,
                                              ),
                                            ),

                                          // UPDATE BADGE
                                          if (Platform.isAndroid &&
                                              licenseStatus.updateAvailable)
                                            Positioned(
                                              left: 40,
                                              top: 40,
                                              child: _buildUpdateBadge(
                                                context,
                                                licenseStatus,
                                              ),
                                            ),

                                          // ANIMATED LOGO
                                          Positioned.fill(
                                            child: AnimatedAlign(
                                              duration: const Duration(
                                                milliseconds: 2000,
                                              ),
                                              curve: Curves.easeInOutQuint,
                                              alignment: _isIdle
                                                  ? const Alignment(0, -0.25)
                                                  : const Alignment(0, -1.0),
                                              child: GestureDetector(
                                                behavior:
                                                    HitTestBehavior.translucent,
                                                onTap: _handleLogoTap,
                                                child: AnimatedContainer(
                                                  duration: const Duration(
                                                    milliseconds: 2000,
                                                  ),
                                                  curve: Curves.easeInOutQuint,
                                                  width: _logoSize(context),
                                                  height: _logoSize(context),
                                                  child: Stack(
                                                    clipBehavior: Clip.none,
                                                    children: [
                                                      Positioned.fill(
                                                        child: Image.asset(
                                                          'assets/logo.png',
                                                          cacheWidth:
                                                              _logoCacheWidth,
                                                          fit: BoxFit.contain,
                                                          errorBuilder: (context, error, stackTrace) {
                                                            return Container(
                                                              decoration: BoxDecoration(
                                                                color: Colors
                                                                    .white
                                                                    .withValues(
                                                                      alpha:
                                                                          0.05,
                                                                    ),
                                                                shape: BoxShape
                                                                    .circle,
                                                              ),
                                                              child: const Center(
                                                                child: Text(
                                                                  'LOGO',
                                                                  style: TextStyle(
                                                                    color:
                                                                        _cream,
                                                                    fontSize:
                                                                        24,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .bold,
                                                                  ),
                                                                ),
                                                              ),
                                                            );
                                                          },
                                                        ),
                                                      ),
                                                      if (appThemeNotifier
                                                              .value ==
                                                          AppTheme.newYear)
                                                        Positioned(
                                                          top:
                                                              -_logoSize(
                                                                context,
                                                              ) *
                                                              0.15,
                                                          right:
                                                              -_logoSize(
                                                                context,
                                                              ) *
                                                              0.035,
                                                          width:
                                                              _logoSize(
                                                                context,
                                                              ) *
                                                              0.5,
                                                          height:
                                                              _logoSize(
                                                                context,
                                                              ) *
                                                              0.5,
                                                          child: IgnorePointer(
                                                            child: Transform.rotate(
                                                              angle: 0.10,
                                                              child: const CustomPaint(
                                                                painter:
                                                                    _SantaHatPainter(),
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ), // close Positioned.fill for logo
                                          // Trial Version Watermark Banner
                                          if (LicenseService
                                                      .instance
                                                      .currentStatus
                                                      .mode ==
                                                  LicenseMode.trial &&
                                              !_isIdle)
                                            Positioned(
                                              left: 40,
                                              bottom: 40,
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 16,
                                                      vertical: 8,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFF1C1724)
                                                      .withValues(alpha: 0.8),
                                                  borderRadius:
                                                      BorderRadius.circular(20),
                                                  border: Border.all(
                                                    color: _gold.withValues(
                                                      alpha: 0.4,
                                                    ),
                                                  ),
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: Colors.black
                                                          .withValues(
                                                            alpha: 0.3,
                                                          ),
                                                      blurRadius: 8,
                                                    ),
                                                  ],
                                                ),
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    const Icon(
                                                      Icons
                                                          .info_outline_rounded,
                                                      color: _gold,
                                                      size: 16,
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Text(
                                                      '${tr('Deneme Sürümü', 'Trial Version')} (${getTrialRemainingText()})',
                                                      style: const TextStyle(
                                                        color: _cream,
                                                        fontSize: _fsCaption,
                                                        fontWeight:
                                                            FontWeight.w900,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 12),
                                                    GestureDetector(
                                                      onTap: () =>
                                                          _openLicenseUpgradeDialog(
                                                            context,
                                                          ),
                                                      child: Container(
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 10,
                                                              vertical: 4,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          color: _gold,
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                10,
                                                              ),
                                                        ),
                                                        child: Text(
                                                          tr(
                                                            'Lisans Gir',
                                                            'Enter License',
                                                          ),
                                                          style:
                                                              const TextStyle(
                                                                color: _bgDark,
                                                                fontSize:
                                                                    _fsBadge,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w900,
                                                              ),
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                          // Language Switcher
                          Positioned(
                            top: 24,
                            right: 24,
                            child: AnimatedOpacity(
                              opacity: _isIdle ? 0.0 : 1.0,
                              duration: const Duration(milliseconds: 300),
                              child: IgnorePointer(
                                ignoring: _isIdle,
                                child: const _LanguageSwitcher(),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
        );
      },
    );
  }

  double _logoSize(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < 700) {
      return _isIdle ? 220 : 96;
    }
    if (width < 1100) {
      return _isIdle ? 340 : 160;
    }
    return _isIdle ? 480 : 280;
  }

  void _handleLogoTap() {
    _logoTapTimer?.cancel();
    _logoTapCount += 1;
    _logoTapTimer = Timer(const Duration(seconds: 2), () {
      _logoTapCount = 0;
    });

    if (_logoTapCount >= 5) {
      _logoTapCount = 0;
      _logoTapTimer?.cancel();
      _openAdminPin();
    }
  }

  Future<void> _openAdminPin() async {
    GlobalDialogTracker.isAdminSessionOpen = true;
    try {
      await _runAdminSession();
    } finally {
      GlobalDialogTracker.isAdminSessionOpen = false;
    }
    if (mounted && !_isIdle) {
      _resetIdleTimer();
    }
  }

  Future<void> _runAdminSession() async {
    _resetIdleTimer();
    final unlocked = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) =>
          const _VirtualCanvasDialogWrapper(child: _AdminPinDialog()),
    );
    if (!mounted) return;
    if (unlocked == true) {
      AnalyticsService.instance.trackAdminOpenSuccess();
      AnalyticsService.instance.trackAdminMenuOpened();
      var keepAdminOpen = true;
      while (mounted && keepAdminOpen && !_isIdle) {
        final adminSection = await showDialog<_AdminSection>(
          // ignore: use_build_context_synchronously
          context: context,
          barrierDismissible: true,
          builder: (_) =>
              const _VirtualCanvasDialogWrapper(child: _AdminHubDialog()),
        );
        if (!mounted || adminSection == null || _isIdle) {
          keepAdminOpen = false;
          break;
        }

        if (adminSection == _AdminSection.barista) {
          final currentDrink = _currentBaristaDrink;
          final currentDessert = _currentBaristaDessert;
          if (currentDrink == null || currentDessert == null) {
            await _showAdminError(
              // ignore: use_build_context_synchronously
              context,
              tr(
                'Menüde tavsiye edilecek içecek veya tatlı yok. Önce panelden menüye ekleyin.',
                'The menu has no drink or dessert to recommend. Add them in the panel first.',
              ),
              title: tr('Liste boş', 'Nothing to choose'),
            );
            continue;
          }
          await showDialog<void>(
            // ignore: use_build_context_synchronously
            context: context,
            barrierDismissible: true,
            builder: (_) => _VirtualCanvasDialogWrapper(
              child: _BaristaAdminDialog(
                drinkOptions: _recommendationDrinkOptions,
                dessertOptions: _recommendationDessertOptions,
                selectedDrink: currentDrink,
                selectedDessert: currentDessert,
                blockedItems: _wheelMenuItems,
                onSave: (drink, dessert) {
                  setState(() {
                    _baristaDrink = drink;
                    _baristaDessert = dessert;
                  });
                  _LuuqSettings.instance.baristaDrink = drink.name;
                  _LuuqSettings.instance.baristaDessert = dessert.name;
                  _LuuqSettings.instance.baristaDrinkId = drink.id;
                  _LuuqSettings.instance.baristaDessertId = dessert.id;
                  unawaited(_saveSettingsInBackground('barista'));
                  // Bundled items have no id; pushing nulls would clear the
                  // profile's server-side barista override.
                  final drinkId = drink.id;
                  final dessertId = dessert.id;
                  if (drinkId != null && dessertId != null) {
                    _reportMenuPush(
                      MenuService.instance.pushLocalBarista(
                        drinkId: drinkId,
                        dessertId: dessertId,
                      ),
                    );
                  }

                  AnalyticsService.instance.trackBaristaRecommendationUpdated(
                    drink.name,
                    'drink',
                  );
                  AnalyticsService.instance.trackBaristaRecommendationUpdated(
                    dessert.name,
                    'dessert',
                  );
                },
              ),
            ),
          );
        } else if (adminSection == _AdminSection.wheel) {
          if (_wheelMenuItems.length != 8) {
            await _showAdminError(
              // ignore: use_build_context_synchronously
              context,
              tr(
                'Menüde çark için yeterli ürün yok (8 gerekli).',
                'The menu does not have enough items for the wheel (8 needed).',
              ),
              title: tr('Liste boş', 'Nothing to choose'),
            );
            continue;
          }
          await showDialog<void>(
            // ignore: use_build_context_synchronously
            context: context,
            barrierDismissible: true,
            builder: (_) => _VirtualCanvasDialogWrapper(
              child: _WheelContentAdminDialog(
                initialItems: _wheelMenuItems,
                iceCoffeeOptions: _iceCoffeeOptions,
                hotCoffeeOptions: _hotCoffeeOptions,
                dessertOptions: _recommendationDessertOptions,
                cocktailOptions: _cocktailOptions,
                herbalTeaOptions: _herbalTeaOptions,
                iceCreamOptions: _iceCreamOptions,
                blockedItems: [
                  _currentBaristaDrink,
                  _currentBaristaDessert,
                ].whereType<_MenuItem>().toList(growable: false),
                onSave: (items) {
                  setState(() {
                    _wheelMenuItems = items;
                    _selectedMood = null;
                    _selectedDrink = null;
                    _showResult = false;
                  });
                  _LuuqSettings.instance.wheelItems = items
                      .map((e) => e.name)
                      .toList();
                  final itemIds = items
                      .map((e) => e.id)
                      .whereType<String>()
                      .toList(growable: false);
                  // Only persist ids when every item has one; a partial list
                  // would shadow the name fallback on the next start.
                  _LuuqSettings.instance.wheelItemIds =
                      itemIds.length == items.length ? itemIds : null;
                  unawaited(_saveSettingsInBackground('wheel'));
                  if (itemIds.length == 8) {
                    _reportMenuPush(
                      MenuService.instance.pushLocalWheel(itemIds),
                    );
                  }

                  AnalyticsService.instance.trackWheelContentUpdated(
                    items.length,
                    items.map((e) => e.name).toList(),
                  );
                },
              ),
            ),
          );
        } else if (adminSection == _AdminSection.clean) {
          final confirmClean = await showDialog<bool>(
            // ignore: use_build_context_synchronously
            context: context,
            builder: (context) => AlertDialog(
              backgroundColor: const Color(0xFF1C1724),
              title: Text(
                tr('Ekran Temizleme Modu', 'Screen Cleaning Mode'),
                style: TextStyle(color: _cream),
              ),
              content: Text(
                tr(
                  'Ekran temizleme modunu başlatmak istediğinize emin misiniz? 30 saniye boyunca dokunmatik kilitlenecektir.',
                  'Start screen cleaning mode? The touchscreen will be locked for 30 seconds.',
                ),
                style: const TextStyle(color: _mutedText),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(
                    tr('Hayır', 'No'),
                    style: TextStyle(color: _mutedText),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text(
                    tr('Evet, Başlat', 'Yes, Start'),
                    style: const TextStyle(color: Colors.lightBlueAccent),
                  ),
                ),
              ],
            ),
          );
          if (confirmClean == true) {
            AnalyticsService.instance.trackCleaningModeStarted(
              screen: 'admin_menu',
            );
            setState(() {
              _isInCleaningMode = true;
            });
            _idleTimer?.cancel();
            await showDialog<void>(
              // ignore: use_build_context_synchronously
              context: context,
              barrierDismissible: false,
              builder: (_) => const _CleaningModeDialog(),
            );
            // A license redirect may have replaced this screen meanwhile.
            if (!mounted) return;
            setState(() {
              _isInCleaningMode = false;
            });
            _resetIdleTimer(fromTap: true);
          }
        } else if (adminSection == _AdminSection.analytics) {
          AnalyticsService.instance.trackAnalyticsOpened();
          await showDialog<void>(
            // ignore: use_build_context_synchronously
            context: context,
            barrierDismissible: true,
            builder: (_) => const _VirtualCanvasDialogWrapper(
              child: _AnalyticsAdminDialog(),
            ),
          );
        } else if (adminSection == _AdminSection.theme) {
          await showDialog<void>(
            // ignore: use_build_context_synchronously
            context: context,
            barrierDismissible: true,
            builder: (_) => const _VirtualCanvasDialogWrapper(
              child: _ThemeSelectionDialog(),
            ),
          );
        } else if (adminSection == _AdminSection.volume) {
          await showDialog<void>(
            // ignore: use_build_context_synchronously
            context: context,
            barrierDismissible: true,
            builder: (_) => const _VirtualCanvasDialogWrapper(
              child: _VolumeSelectionDialog(),
            ),
          );
        } else if (adminSection == _AdminSection.info) {
          AnalyticsService.instance.trackAppInfoOpened();
          await showDialog<void>(
            // ignore: use_build_context_synchronously
            context: context,
            barrierDismissible: true,
            builder: (_) =>
                const _VirtualCanvasDialogWrapper(child: _AppInfoDialog()),
          );
        } else if (adminSection == _AdminSection.exit) {
          final confirmExit = await showDialog<bool>(
            // ignore: use_build_context_synchronously
            context: context,
            builder: (context) => AlertDialog(
              backgroundColor: const Color(0xFF1C1724),
              title: Text(
                tr('Uygulamadan Çık', 'Exit App'),
                style: TextStyle(color: _cream),
              ),
              content: Text(
                tr(
                  'Kiosk uygulamasını kapatıp masaüstüne dönmek istediğinize emin misiniz?',
                  'Close the kiosk app and return to the home screen?',
                ),
                style: const TextStyle(color: _mutedText),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(
                    tr('Hayır', 'No'),
                    style: TextStyle(color: _mutedText),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text(
                    tr('Evet, Çık', 'Yes, Exit'),
                    style: TextStyle(color: Colors.redAccent),
                  ),
                ),
              ],
            ),
          );
          if (confirmExit == true) {
            AnalyticsService.instance.trackManualExitClicked();
            await Future.delayed(const Duration(milliseconds: 300));
            exit(0);
          }
        }
      }
    }
    if (mounted && !_isIdle) {
      _resetIdleTimer();
    }
  }

  Widget _buildCenterArea(List<Drink> available, bool isSpinning) {
    final isCompact = MediaQuery.sizeOf(context).width < 700;
    if (available.isEmpty) {
      return Center(
        child: Text(
          tr(
            'Bu moda uygun içecek bulunamadı.',
            'No drinks found matching this mood.',
          ),
          style: const TextStyle(fontSize: 24, color: Colors.white54),
        ),
      );
    }

    final pulseMultiplier = _isIdle ? 1.5 : 1.0;

    return Column(
      children: [
        // Logo Space
        SizedBox(height: isCompact ? 12 : 160),

        // Wheel Area
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wheelSize =
                  min(constraints.maxWidth, constraints.maxHeight) *
                  (isCompact ? 0.92 : 0.85);
              final rimRadius = wheelSize / 2 - _wheelRimInset;
              if (_pointerPegCount != available.length ||
                  _pointerRimRadius != rimRadius) {
                // New pegs (menu change, resize): let the pointer react.
                if (_pointerPegCount == 0 &&
                    available.isNotEmpty &&
                    _spinController.value == 0) {
                  // The first wheel starts with a segment under the
                  // pointer, not a border (a peg pressing on it).
                  final halfSegment = 0.5 / available.length;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && _spinController.value == 0) {
                      _spinController.value = halfSegment;
                    }
                  });
                }
                _pointerPegCount = available.length;
                _pointerRimRadius = rimRadius;
                _wakePointer();
              }
              return SizedBox(
                width: wheelSize * 1.3,
                height: wheelSize * 1.3,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Outer Glow Pulse
                    AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, child) {
                        final opacity = isSpinning
                            ? 0.8
                            : 0.4 +
                                  (_pulseController.value *
                                      0.4 *
                                      pulseMultiplier);
                        final scale = isSpinning
                            ? 1.0
                            : 1.0 +
                                  (_pulseController.value *
                                      0.05 *
                                      pulseMultiplier);
                        return Transform.scale(
                          scale: scale,
                          child: Container(
                            width: wheelSize * 1.15,
                            height: wheelSize * 1.15,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: [
                                  _gold.withValues(
                                    alpha: 0.15 * opacity.clamp(0.0, 1.0),
                                  ),
                                  _gold.withValues(alpha: 0.0),
                                ],
                                stops: const [0.65, 1.0],
                              ),
                            ),
                          ),
                        );
                      },
                    ),

                    // Curved Arrows
                    if (!isSpinning && !_isDragging)
                      AnimatedBuilder(
                        animation: _pulseController,
                        builder: (context, child) {
                          return CustomPaint(
                            size: Size.square(wheelSize * 1.12),
                            painter: _CurvedArrowsPainter(
                              animationValue: _pulseController.value,
                            ),
                          );
                        },
                      ),

                    // The Actual Wheel
                    RepaintBoundary(
                      child: SizedBox(
                        width: wheelSize,
                        height: wheelSize,
                        child: GestureDetector(
                          onPanStart: (details) {
                            if (!currentFeatureFlags.wheel) {
                              showFeatureLockedDialog(
                                context,
                                tr('Çark Çevirme', 'Wheel Spin'),
                              );
                              return;
                            }
                            if (isSpinning) return;
                            final localCenter = Offset(
                              wheelSize / 2,
                              wheelSize / 2,
                            );
                            _dragStartAngle = atan2(
                              details.localPosition.dy - localCenter.dy,
                              details.localPosition.dx - localCenter.dx,
                            );
                            _dragBaseTurns = _spinController.value;
                            setState(() => _isDragging = true);
                          },
                          onPanUpdate: (details) {
                            if (isSpinning || !_isDragging) return;
                            final localCenter = Offset(
                              wheelSize / 2,
                              wheelSize / 2,
                            );
                            final currentAngle = atan2(
                              details.localPosition.dy - localCenter.dy,
                              details.localPosition.dx - localCenter.dx,
                            );
                            final angleDiff = currentAngle - _dragStartAngle;
                            final newTurns =
                                _dragBaseTurns + (angleDiff / (2 * pi));
                            _isClockwise = newTurns > _spinController.value;
                            _spinController.value = newTurns;
                          },
                          onPanEnd: (details) {
                            if (isSpinning || !_isDragging) return;
                            setState(() => _isDragging = false);
                            final velocity =
                                details.velocity.pixelsPerSecond.distance;
                            if (velocity > 400) {
                              // Faster fling = shorter duration (more dramatic)
                              final ms = (5500 - (velocity * 1.2))
                                  .clamp(2000.0, 5000.0)
                                  .toInt();
                              _spinWheel(
                                clockwise: _isClockwise,
                                duration: Duration(milliseconds: ms),
                                curve: Curves.easeOutCubic,
                              );
                            }
                          },
                          child: AnimatedBuilder(
                            animation: _spinController,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                CustomPaint(
                                  painter: _DrinkWheelPainter(
                                    drinks: available,
                                    selectedDrink: _selectedDrink,
                                    showResult: _showResult,
                                  ),
                                ),
                                ...available.asMap().entries.map((entry) {
                                  final i = entry.key;
                                  final drink = entry.value;
                                  final sweep = 2 * pi / available.length;
                                  final startAngle = -pi / 2 + i * sweep;
                                  final labelAngle = startAngle + sweep / 2;

                                  // Rotate the item so its top points outward
                                  // At -pi/2 (top), we want 0 rotation so it is upright.
                                  final rotationAngle = labelAngle + pi / 2;

                                  final isSelected =
                                      _showResult && drink == _selectedDrink;

                                  return Transform.rotate(
                                    angle: rotationAngle,
                                    child: Align(
                                      alignment: Alignment.topCenter,
                                      child: Padding(
                                        padding: const EdgeInsets.only(top: 20),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            // Drink Image or Icon
                                            Container(
                                              width: 68,
                                              height: 68,
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: Colors.white
                                                      .withValues(alpha: 0.15),
                                                  width: 1.5,
                                                ),
                                                color: Colors.black.withValues(
                                                  alpha: 0.1,
                                                ),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: Colors.black
                                                        .withValues(alpha: 0.3),
                                                    blurRadius: 4,
                                                  ),
                                                ],
                                              ),
                                              clipBehavior: Clip.antiAlias,
                                              child: _buildMenuImage(
                                                fallbackIcon: drink.icon,
                                                assetPath: drink.imagePath,
                                                remoteImageUrl:
                                                    drink.remoteImageUrl,
                                                transparentAssetPath:
                                                    drink
                                                        .transparentImagePath ??
                                                    (drink.imagePath
                                                                ?.startsWith(
                                                                  'assets/',
                                                                ) ==
                                                            true
                                                        ? _wheelImagePath(
                                                            drink.imagePath!,
                                                          )
                                                        : null),
                                                transparentRemoteImageUrl: drink
                                                    .remoteTransparentImageUrl,
                                                preferTransparent: true,
                                                cacheWidth: 136,
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            // Tangential (MERKEZE DİK) Text
                                            SizedBox(
                                              width: 110,
                                              child: Text(
                                                displayUpper(drink.shortName),
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  color: isSelected
                                                      ? Colors.white
                                                      : Colors.white.withValues(
                                                          alpha: 0.95,
                                                        ),
                                                  fontSize: isSelected
                                                      ? 15
                                                      : 14,
                                                  fontWeight: isSelected
                                                      ? FontWeight.w900
                                                      : FontWeight.w800,
                                                  letterSpacing: 0.5,
                                                  height: 1.1,
                                                  shadows: [
                                                    const Shadow(
                                                      color: Colors.black87,
                                                      blurRadius: 4,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                }),
                              ],
                            ),
                            builder: (context, child) {
                              final double angle =
                                  _spinController.value * 2 * pi;
                              return Transform.rotate(
                                angle: angle,
                                child: child,
                              );
                            },
                          ),
                        ),
                      ),
                    ),

                    // Pointer: a spring-loaded flapper that catches on the
                    // rim pegs (WheelPointerSimulation, driven by
                    // _handlePointerTick).
                    Positioned(
                      top:
                          (wheelSize * 1.3 - wheelSize) / 2 +
                          _wheelRimInset -
                          WheelPointerSimulation.restTipGap -
                          WheelPointerSimulation.length,
                      child: RepaintBoundary(
                        child: ValueListenableBuilder<double>(
                          valueListenable: _pointerAngle,
                          builder: (context, angle, child) {
                            return Transform.rotate(
                              angle: angle,
                              alignment: Alignment.topCenter,
                              child: child,
                            );
                          },
                          child: SizedBox(
                            width: 44,
                            height: WheelPointerSimulation.length,
                            child: CustomPaint(painter: _PointerPainter()),
                          ),
                        ),
                      ),
                    ),

                    // Center Hub
                    Center(
                      child: RepaintBoundary(
                        child: BouncyButton(
                          onTap: isSpinning ? null : _spinWheel,
                          child: Container(
                            width: 84,
                            height: 84,
                            decoration: BoxDecoration(
                              color: _gold,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.4),
                                  blurRadius: 15,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                              border: Border.all(color: _bgDark, width: 4),
                            ),
                            child: Center(
                              child: AnimatedBuilder(
                                animation: _pulseController,
                                builder: (context, child) {
                                  final double scale = isSpinning
                                      ? 1.0
                                      : 1.0 +
                                            (Curves.easeInOut.transform(
                                                  _pulseController.value,
                                                ) *
                                                0.12 *
                                                pulseMultiplier);
                                  return Transform.scale(
                                    scale: scale,
                                    child: child,
                                  );
                                },
                                child: const Icon(
                                  Icons.touch_app_rounded,
                                  color: _bgDark,
                                  size: 40,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),

        SizedBox(height: isCompact ? 12 : 24),

        // Large Spin Button
        AnimatedBuilder(
          animation: _pulseController,
          builder: (context, child) {
            final scale = isSpinning
                ? 1.0
                : 1.0 + (_pulseController.value * 0.02 * pulseMultiplier);
            return Transform.scale(scale: scale, child: child);
          },
          child: RepaintBoundary(
            child: BouncyButton(
              onTap: isSpinning ? null : _spinWheel,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SizedBox(
                    height: isCompact ? 62 : 88,
                    width: min(constraints.maxWidth, isCompact ? 320 : 380),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: isSpinning
                            ? _surface.withValues(alpha: 0.8)
                            : _gold,
                        borderRadius: BorderRadius.circular(
                          isCompact ? 24 : 44,
                        ),
                        boxShadow: isSpinning
                            ? []
                            : [
                                BoxShadow(
                                  color: _gold.withValues(alpha: 0.6),
                                  blurRadius: 20,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                      ),
                      child: Center(
                        child: Text(
                          isSpinning
                              ? tr('SEÇİLİYOR...', 'SELECTING...')
                              : (_showResult
                                    ? tr('TEKRAR ÇEVİR', 'SPIN AGAIN')
                                    : tr('ÇARKI ÇEVİR', 'SPIN THE WHEEL')),
                          style: TextStyle(
                            color: isSpinning ? Colors.white54 : _bgDark,
                            fontSize: isCompact ? 20 : 32,
                            fontWeight: FontWeight.w900,
                            letterSpacing: isCompact ? 0.8 : 2,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildResultArea(Drink drink) {
    final isCompact = MediaQuery.sizeOf(context).width < 700;
    final menuItem = _menuItemForDrink(drink);
    final resultName = menuItem == null
        ? drink.fullName
        : _menuItemName(menuItem);
    final resultDescription = menuItem == null
        ? drink.description
        : _menuItemDescription(menuItem);
    final resultImagePath = menuItem?.imagePath;
    final resultImageUrl = menuItem?.remoteImageUrl ?? drink.remoteImageUrl;

    return TweenAnimationBuilder<double>(
      key: ValueKey('result_${drink.shortName}'),
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 1200),
      // One flash that fades out; a bouncing curve would flicker it.
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        final flashIntensity = (1.0 - value).clamp(0.0, 1.0);

        return Container(
          padding: EdgeInsets.all(isCompact ? 12 : 16),
          width: double.infinity,
          height: double.infinity,
          // The thick flash edge is painted on top, so the content does not
          // move while it thins out.
          foregroundDecoration: flashIntensity > 0
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: flashIntensity * 0.8),
                    width: 3 * flashIntensity,
                  ),
                )
              : null,
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(32),
            border: Border.all(
              color: Color.lerp(
                _gold.withValues(alpha: 0.4),
                Colors.white,
                flashIntensity,
              )!,
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: _gold.withValues(alpha: 0.10 + (flashIntensity * 0.3)),
                blurRadius: 24 + (flashIntensity * 36),
                spreadRadius: 4 + (flashIntensity * 10),
              ),
            ],
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                top: -4,
                right: -4,
                child: GestureDetector(
                  onTap: () {
                    setState(() => _showResult = false);
                    _resetIdleTimer();
                  },
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.1),
                      ),
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      color: Colors.white70,
                      size: 16,
                    ),
                  ),
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: isCompact ? 100 : 120,
                    height: isCompact ? 100 : 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _gold.withValues(alpha: 0.35),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: _gold.withValues(
                            alpha: 0.12 + (flashIntensity * 0.3),
                          ),
                          blurRadius: 16 + (flashIntensity * 16),
                          spreadRadius: 1 + (flashIntensity * 3),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: _productHero(
                      menuItem == null
                          ? null
                          : _productHeroTag('result', menuItem),
                      _buildResultVisual(
                        drink: drink,
                        imagePath: resultImagePath,
                        remoteImageUrl: resultImageUrl,
                        size: isCompact ? 100 : 120,
                      ),
                    ),
                  ),
                  SizedBox(width: isCompact ? 12 : 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          tr('BUGÜNKÜ SEÇİMİN', 'YOUR PICK TODAY'),
                          style: const TextStyle(
                            fontSize: _fsBadge,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 3,
                            color: _gold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        ShaderMask(
                          shaderCallback: (bounds) => const LinearGradient(
                            colors: [_cream, _gold],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ).createShader(bounds),
                          child: Text(
                            resultName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: isCompact ? 18 : 22,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              height: 1.1,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          resultDescription,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: isCompact ? 11 : 12,
                            color: _cream.withValues(alpha: 0.7),
                            height: 1.3,
                          ),
                        ),
                        if (menuItem != null) ...[
                          const SizedBox(height: 10),
                          BouncyButton(
                            onTap: () => _showProductDetailDialog(
                              menuItem,
                              heroTag: _productHeroTag('result', menuItem),
                            ),
                            child: Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: isCompact ? 12 : 14,
                                vertical: isCompact ? 5 : 6,
                              ),
                              decoration: BoxDecoration(
                                color: _gold.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: _gold.withValues(alpha: 0.25),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    menuItem.price,
                                    style: const TextStyle(
                                      color: _gold,
                                      fontSize: _fsCaption,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Icon(
                                    Icons.arrow_forward_ios_rounded,
                                    color: _gold,
                                    size: 10,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
