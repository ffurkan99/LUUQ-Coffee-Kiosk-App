part of '../../main.dart';

// VersionInfo is defined in lib/licensing/version_info.dart
// and exported through lib/licensing/update_service.dart.

enum UpdateState {
  updateAvailable,
  downloading,
  downloaded,
  verifying,
  readyToInstall,
  openingInstaller,
  failed,
}

enum _UpdateKioskState {
  secured,
  releasing,
  externalActivity,
  restoring,
  restoreFailed,
}

enum _UpdateExternalActivity {
  none,
  installPermissionSettings,
  packageInstaller,
}

enum _UpdatePrimaryAction {
  none,
  download,
  installVerifiedApk,
  grantPermission,
  retryKioskRestore,
}

class _UpdateDialog extends StatefulWidget {
  final LicenseStatus licenseStatus;

  const _UpdateDialog({required this.licenseStatus});

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog>
    with WidgetsBindingObserver {
  UpdateState _updateState = UpdateState.updateAvailable;
  double _progress = 0.0;
  String? _error;
  String _currentVersion = '...';
  String? _apkPath;
  _UpdatePrimaryAction _primaryAction = _UpdatePrimaryAction.download;
  _UpdateKioskState _kioskState = _UpdateKioskState.secured;
  _UpdateExternalActivity _externalActivity = _UpdateExternalActivity.none;
  bool _isHandlingExternalResume = false;
  ApkDownloadCancellationToken? _downloadCancellationToken;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    GlobalDialogTracker.isUpdateDialogOpen = true;
    _CafeKioskScreenState.resetTimer();
    _loadCurrentVersionAndCheckApk();
  }

  @override
  void dispose() {
    _downloadCancellationToken?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    GlobalDialogTracker.isUpdateDialogOpen = false;
    GlobalDialogTracker.isUpdateDownloading = false;
    GlobalDialogTracker.isUpdateVerifying = false;
    GlobalDialogTracker.isUpdateReadyToInstall = false;
    GlobalDialogTracker.isUpdateOpeningInstaller = false;
    _CafeKioskScreenState.resetTimer();
    if (Platform.isAndroid && _kioskState != _UpdateKioskState.secured) {
      debugPrint(
        '[UPDATE][SECURITY] Update dialog disposed while kiosk restore was pending.',
      );
      unawaited(_restoreKioskAfterUnexpectedDispose());
    }
    super.dispose();
  }

  Future<void> _restoreKioskAfterUnexpectedDispose() async {
    try {
      await UpdateService.restoreKioskModeAfterUpdateCancel();
      debugPrint(
        '[UPDATE][SECURITY] Kiosk restored after unexpected update dialog disposal.',
      );
    } catch (error, stackTrace) {
      debugPrint(
        '[UPDATE][SECURITY][CRITICAL] Kiosk restore failed after dialog disposal: '
        '$error\n$stackTrace',
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _externalActivity != _UpdateExternalActivity.none &&
        !_isHandlingExternalResume) {
      unawaited(_handleExternalResume());
    }
  }

  Future<void> _handleExternalResume() async {
    _isHandlingExternalResume = true;
    final resumedFrom = _externalActivity;
    debugPrint('[UPDATE][SECURITY] Resumed from ${resumedFrom.name}.');

    try {
      final restored = await _restoreKioskOrEnterMaintenance(
        'resume_from_${resumedFrom.name}',
      );
      if (!restored || !mounted) return;

      if (resumedFrom == _UpdateExternalActivity.installPermissionSettings) {
        await _resumeAfterPermissionSettings();
      } else if (resumedFrom == _UpdateExternalActivity.packageInstaller) {
        await _verifyPostInstall();
      }
    } finally {
      _isHandlingExternalResume = false;
    }
  }

  Future<void> _resumeAfterPermissionSettings() async {
    try {
      final bool hasPermission = await UpdateService.checkInstallPermission();
      debugPrint('[UPDATE] permission after settings resume=$hasPermission');
      if (!mounted) return;
      if (hasPermission) {
        final candidatePath = _apkPath;
        if (candidatePath == null) {
          _showReadyApkInvalidError();
          return;
        }
        debugPrint('[UPDATE] permission granted — continuing install flow');
        await _runInstallFlow(candidatePath);
        return;
      }
    } catch (error, stackTrace) {
      debugPrint(
        '[UPDATE][SECURITY] Permission check failed after resume: '
        '$error\n$stackTrace',
      );
    }

    if (!mounted) return;
    setState(() {
      _error = tr(
        'Bilinmeyen kaynaklardan yükleme izni verilmedi. Güncelleme için izin gerekiyor.',
        'Permission to install unknown apps was not granted. It is required for the update.',
      );
      _primaryAction = _UpdatePrimaryAction.grantPermission;
    });
    _changeState(UpdateState.failed);
  }

  void _setKioskState(_UpdateKioskState state) {
    if (!mounted) return;
    setState(() {
      _kioskState = state;
    });
  }

  Future<bool> _restoreKioskOrEnterMaintenance(String reason) async {
    if (!Platform.isAndroid) {
      _externalActivity = _UpdateExternalActivity.none;
      _setKioskState(_UpdateKioskState.secured);
      return true;
    }

    _setKioskState(_UpdateKioskState.restoring);
    try {
      await UpdateService.restoreKioskModeAfterUpdateCancel();
      _externalActivity = _UpdateExternalActivity.none;
      _setKioskState(_UpdateKioskState.secured);
      debugPrint('[UPDATE][SECURITY] Kiosk restore verified. reason=$reason');
      return true;
    } catch (error, stackTrace) {
      debugPrint(
        '[UPDATE][SECURITY][CRITICAL] Kiosk restore failed. reason=$reason '
        'error=$error\n$stackTrace',
      );
      AnalyticsService.instance.trackEvent(
        AnalyticsEvent(
          eventType: 'update_kiosk_restore_failed',
          screen: 'home',
          metadata: {'reason': reason},
        ),
      );
      if (mounted) {
        setState(() {
          _kioskState = _UpdateKioskState.restoreFailed;
          _error = tr(
            'Güvenli kiosk modu geri açılamadı. Uygulamayı kullanmayın; bakım yetkilisine haber verin.',
            'Secure kiosk mode could not be restored. Do not use the app; contact maintenance.',
          );
          _primaryAction = _UpdatePrimaryAction.retryKioskRestore;
        });
        _changeState(UpdateState.failed);
      }
      return false;
    }
  }

  Future<bool> _releaseKioskForExternalActivity(String reason) async {
    if (!Platform.isAndroid) return false;

    _setKioskState(_UpdateKioskState.releasing);
    try {
      if (!await UpdateService.isLockTaskActive()) {
        debugPrint(
          '[UPDATE][SECURITY] LockTask was inactive before release; restoring first.',
        );
        if (!await _restoreKioskOrEnterMaintenance('pre_release_$reason')) {
          return false;
        }
        _setKioskState(_UpdateKioskState.releasing);
      }

      await UpdateService.stopLockTaskForUpdate();
      final released = await UpdateService.waitForLockTaskRelease();
      if (!released) {
        throw StateError('LockTask did not release before $reason.');
      }

      _setKioskState(_UpdateKioskState.externalActivity);
      debugPrint('[UPDATE][SECURITY] Kiosk released for $reason.');
      return true;
    } catch (error, stackTrace) {
      debugPrint(
        '[UPDATE][SECURITY] Failed to release kiosk for $reason: '
        '$error\n$stackTrace',
      );
      final restored = await _restoreKioskOrEnterMaintenance(
        'release_failure_$reason',
      );
      if (restored && mounted) {
        setState(() {
          _error = tr(
            'Güncelleme ekranı güvenli şekilde açılamadı. Lütfen tekrar deneyin.',
            'The update screen could not be opened safely. Please try again.',
          );
          _primaryAction = reason == 'install_permission_settings'
              ? _UpdatePrimaryAction.grantPermission
              : _UpdatePrimaryAction.installVerifiedApk;
        });
        _changeState(UpdateState.failed);
      }
      return false;
    }
  }

  Future<void> _retryKioskRestore() async {
    final restored = await _restoreKioskOrEnterMaintenance('manual_retry');
    if (!restored || !mounted) return;
    final validatedPath = await _getFullyValidatedReadyApkPath();
    if (!mounted) return;
    setState(() {
      _error = tr(
        'Kiosk modu güvenli şekilde geri açıldı. Güncellemeyi daha sonra tekrar deneyebilirsiniz.',
        'Kiosk mode was restored securely. You can retry the update later.',
      );
      _primaryAction = validatedPath == null
          ? _UpdatePrimaryAction.download
          : _UpdatePrimaryAction.installVerifiedApk;
    });
    _changeState(UpdateState.failed);
  }

  Future<void> _closeDialogSafely() async {
    if (_kioskState != _UpdateKioskState.secured) {
      final restored = await _restoreKioskOrEnterMaintenance('dialog_close');
      if (!restored) return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<bool> _verifyAdminPinForUpdate() async {
    AnalyticsService.instance.trackEvent(
      AnalyticsEvent(eventType: 'update_pin_required', screen: 'home'),
    );
    GlobalDialogTracker.isAdminPinDialogOpen = true;
    _CafeKioskScreenState.resetTimer();

    try {
      final bool? pinResult = await showDialog<bool>(
        context: context,
        builder: (_) =>
            const _VirtualCanvasDialogWrapper(child: _AdminPinDialog()),
      );
      if (pinResult != true) return false;
      AnalyticsService.instance.trackEvent(
        AnalyticsEvent(eventType: 'update_pin_verified', screen: 'home'),
      );
      return true;
    } finally {
      GlobalDialogTracker.isAdminPinDialogOpen = false;
      _CafeKioskScreenState.resetTimer();
    }
  }

  Future<void> _discardInvalidReadyApk(String? path) async {
    if (path != null && path.isNotEmpty) {
      await UpdateService.deleteApkFile(File(path));
    }
    try {
      await LicenseStorage.clearDownloadedApkInfo();
    } catch (error, stackTrace) {
      debugPrint(
        '[UPDATE][SECURITY] Failed to clear invalid APK metadata: '
        '$error\n$stackTrace',
      );
    }
    if (!mounted) return;
    setState(() {
      _apkPath = null;
      _primaryAction = _UpdatePrimaryAction.download;
    });
  }

  Future<bool> _hasExpectedApkIdentity(String path) async {
    final apkInfo = await UpdateService.readApkPackageInfo(path);
    if (apkInfo == null) return false;

    final currentAppInfo = await PackageInfo.fromPlatform();
    final apkPackageName = apkInfo['packageName'] as String?;
    final apkVersionName = apkInfo['versionName'] as String?;
    final apkVersionCodeValue = apkInfo['versionCode'];
    final apkVersionCode = apkVersionCodeValue is num
        ? apkVersionCodeValue.toInt()
        : int.tryParse(apkVersionCodeValue?.toString() ?? '');
    final expectedParsed = VersionInfo.parse(
      widget.licenseStatus.latestVersion ?? '',
    );

    if (apkPackageName != currentAppInfo.packageName ||
        expectedParsed == null ||
        UpdateService.normalizeVersionName(apkVersionName ?? '') !=
            UpdateService.normalizeVersionName(expectedParsed.versionName)) {
      return false;
    }

    return expectedParsed.versionCode <= 0 ||
        apkVersionCode == expectedParsed.versionCode;
  }

  Future<String?> _getFullyValidatedReadyApkPath() async {
    String? candidatePath = _apkPath;
    try {
      final info = await LicenseStorage.getDownloadedApkInfo();
      candidatePath = info?['apk_path'] as String? ?? candidatePath;
      if (info == null || candidatePath == null || candidatePath.isEmpty) {
        await _discardInvalidReadyApk(candidatePath);
        return null;
      }

      final metadataAndHashValid = await UpdateService.isDownloadedApkValid(
        expectedVersion: widget.licenseStatus.latestVersion ?? '',
        expectedSha256: widget.licenseStatus.apkSha256 ?? '',
        expectedSize: widget.licenseStatus.apkSizeBytes,
      );
      final identityValid =
          metadataAndHashValid && await _hasExpectedApkIdentity(candidatePath);
      if (!identityValid) {
        debugPrint(
          '[UPDATE][SECURITY] Ready APK revalidation failed. path=$candidatePath',
        );
        await _discardInvalidReadyApk(candidatePath);
        return null;
      }

      if (mounted) {
        setState(() {
          _apkPath = candidatePath;
          _primaryAction = _UpdatePrimaryAction.installVerifiedApk;
        });
      }
      return candidatePath;
    } catch (error, stackTrace) {
      debugPrint(
        '[UPDATE][SECURITY] Ready APK validation raised an error: '
        '$error\n$stackTrace',
      );
      await _discardInvalidReadyApk(candidatePath);
      return null;
    }
  }

  void _showReadyApkInvalidError() {
    if (!mounted) return;
    setState(() {
      _error = tr(
        'Hazır güncelleme dosyası artık geçerli değil. Lütfen tekrar indirin.',
        'The prepared update file is no longer valid. Please download it again.',
      );
      _primaryAction = _UpdatePrimaryAction.download;
    });
    _changeState(UpdateState.failed);
  }

  Future<void> _loadCurrentVersionAndCheckApk() async {
    final version = await DeviceIdentityService.getAppVersion(
      bypassCache: true,
    );
    if (mounted) {
      setState(() {
        _currentVersion = version;
      });
    }

    final validatedPath = await _getFullyValidatedReadyApkPath();
    if (validatedPath != null && mounted) {
      _changeState(UpdateState.readyToInstall);
      AnalyticsService.instance.trackEvent(
        AnalyticsEvent(
          eventType: 'update_resume_install_available',
          screen: 'home',
        ),
      );
    }
  }

  void _changeState(UpdateState newState) {
    if (!mounted) return;
    setState(() {
      _updateState = newState;
      switch (newState) {
        case UpdateState.updateAvailable:
          _primaryAction = _UpdatePrimaryAction.download;
          break;
        case UpdateState.downloading:
        case UpdateState.downloaded:
        case UpdateState.verifying:
        case UpdateState.openingInstaller:
          _primaryAction = _UpdatePrimaryAction.none;
          break;
        case UpdateState.readyToInstall:
          _primaryAction = _UpdatePrimaryAction.installVerifiedApk;
          break;
        case UpdateState.failed:
          if (_primaryAction == _UpdatePrimaryAction.none) {
            _primaryAction = _UpdatePrimaryAction.download;
          }
          break;
      }
      GlobalDialogTracker.isUpdateDownloading =
          (newState == UpdateState.downloading);
      GlobalDialogTracker.isUpdateVerifying =
          (newState == UpdateState.verifying);
      GlobalDialogTracker.isUpdateReadyToInstall =
          (newState == UpdateState.readyToInstall);
      GlobalDialogTracker.isUpdateOpeningInstaller =
          (newState == UpdateState.openingInstaller);
    });
    _CafeKioskScreenState.resetTimer();
  }

  void _cancelDownload() {
    if (_updateState != UpdateState.downloading) return;
    debugPrint('[UPDATE] APK download cancellation requested by user.');
    _downloadCancellationToken?.cancel();
  }

  Future<void> _downloadAndInstall() async {
    if (!Platform.isAndroid) {
      debugPrint(
        '[UPDATE][SECURITY] Ignored APK update action on non-Android.',
      );
      return;
    }

    if (!await _verifyAdminPinForUpdate() || !mounted) return;

    // Every install attempt for an already downloaded APK passes through the
    // PIN dialog above, including ready-to-install, permission and retry states.
    if (_primaryAction == _UpdatePrimaryAction.installVerifiedApk ||
        _primaryAction == _UpdatePrimaryAction.grantPermission ||
        _updateState == UpdateState.readyToInstall) {
      final candidatePath = _apkPath;
      if (candidatePath == null) {
        _showReadyApkInvalidError();
        return;
      }
      await _runInstallFlow(candidatePath);
      return;
    }

    _changeState(UpdateState.downloading);
    setState(() {
      _error = null;
      _progress = 0.0;
      _primaryAction = _UpdatePrimaryAction.none;
    });

    AnalyticsService.instance.trackEvent(
      AnalyticsEvent(eventType: 'update_download_started', screen: 'home'),
    );

    File? downloadedFile;
    var keepVerifiedApk = false;
    final cancellationToken = ApkDownloadCancellationToken();
    _downloadCancellationToken = cancellationToken;

    try {
      final apkUrl = widget.licenseStatus.apkUrl;
      if (apkUrl == null || !apkUrl.startsWith('https://')) {
        throw const HttpException('Güvenli bağlantı (HTTPS) hatası.');
      }

      final File file = await UpdateService.downloadApk(apkUrl, (progress) {
        if (mounted) {
          setState(() {
            _progress = progress;
          });
        }
      }, cancellationToken: cancellationToken);
      downloadedFile = file;

      if (!mounted) return;

      _changeState(UpdateState.downloaded);
      _changeState(UpdateState.verifying);

      final expectedHash = widget.licenseStatus.apkSha256 ?? '';
      if (expectedHash.trim().isEmpty) {
        try {
          await file.delete();
        } catch (_) {}
        await LicenseStorage.clearDownloadedApkInfo();
        setState(() {
          _error = tr(
            'Güncelleme doğrulama bilgisi eksik.',
            'Update verification information is missing.',
          );
        });
        _changeState(UpdateState.failed);
        AnalyticsService.instance.trackEvent(
          AnalyticsEvent(eventType: 'update_hash_failed', screen: 'home'),
        );
        return;
      }

      final bool isHashValid =
          await UpdateService.verifySha256AndDeleteOnFailure(
            file,
            expectedHash,
          );
      if (!isHashValid) {
        try {
          await file.delete();
        } catch (_) {}
        await LicenseStorage.clearDownloadedApkInfo();
        setState(() {
          _error = tr(
            'Güncelleme dosyası doğrulanamadı. Lütfen tekrar indirin.',
            'The update file could not be verified. Please download it again.',
          );
        });
        _changeState(UpdateState.failed);
        AnalyticsService.instance.trackEvent(
          AnalyticsEvent(eventType: 'update_hash_failed', screen: 'home'),
        );
        return;
      }

      // Read and verify APK package/version info!
      debugPrint('[UPDATE] downloaded APK sha verified=true');
      debugPrint('[UPDATE] reading APK package info path=${file.path}');
      final apkInfo = await UpdateService.readApkPackageInfo(file.path);
      if (apkInfo == null) {
        try {
          await file.delete();
        } catch (_) {}
        await LicenseStorage.clearDownloadedApkInfo();
        setState(() {
          _error = tr(
            'İndirilen APK dosyası okunamadı.',
            'The downloaded APK file could not be read.',
          );
        });
        _changeState(UpdateState.failed);
        return;
      }

      final currentAppInfo = await PackageInfo.fromPlatform();
      final apkPackageName = apkInfo['packageName'] as String?;
      final apkVersionName = apkInfo['versionName'] as String?;
      // Same tolerant parse as _hasExpectedApkIdentity: the platform channel
      // may send a long (num) or a string; a cast to int? would throw.
      final apkVersionCodeValue = apkInfo['versionCode'];
      final apkVersionCode = apkVersionCodeValue is num
          ? apkVersionCodeValue.toInt()
          : int.tryParse(apkVersionCodeValue?.toString() ?? '');

      debugPrint('[UPDATE] downloadedApk packageName=$apkPackageName');
      debugPrint('[UPDATE] downloadedApk versionName=$apkVersionName');
      debugPrint('[UPDATE] downloadedApk versionCode=$apkVersionCode');
      debugPrint(
        '[UPDATE] expected latestVersion=${widget.licenseStatus.latestVersion ?? ""}',
      );

      if (apkPackageName != currentAppInfo.packageName) {
        try {
          await file.delete();
        } catch (_) {}
        await LicenseStorage.clearDownloadedApkInfo();
        setState(() {
          _error = tr(
            'İndirilen APK bu uygulama ile eşleşmiyor. Lütfen doğru APK dosyasını yükleyin.',
            'The downloaded APK does not match this application. Please publish the correct APK file.',
          );
        });
        _changeState(UpdateState.failed);
        debugPrint('[UPDATE] apk version verification failed');
        return;
      }

      final expectedParsed = VersionInfo.parse(
        widget.licenseStatus.latestVersion ?? '',
      );
      final actualVersionNameNormalized = UpdateService.normalizeVersionName(
        apkVersionName ?? '',
      );
      final expectedVersionNameNormalized = expectedParsed != null
          ? UpdateService.normalizeVersionName(expectedParsed.versionName)
          : '';

      // When the backend omits the build-number (versionCode == 0), only the
      // versionName needs to match.  This prevents false negatives when the
      // admin publishes without a '+BUILD' suffix.
      final versionCodeMismatch =
          expectedParsed != null &&
          expectedParsed.versionCode > 0 &&
          apkVersionCode != expectedParsed.versionCode;

      if (expectedParsed == null ||
          actualVersionNameNormalized != expectedVersionNameNormalized ||
          versionCodeMismatch) {
        try {
          await file.delete();
        } catch (_) {}
        await LicenseStorage.clearDownloadedApkInfo();
        final apkVerStr = apkVersionName != null
            ? 'v$apkVersionName${apkVersionCode != null ? '+$apkVersionCode' : ''}'
            : tr('bilinmiyor', 'unknown');
        setState(() {
          _error = tr(
            'İndirilen APK beklenen sürümle eşleşmiyor.\n\nBeklenen: ${widget.licenseStatus.latestVersion ?? 'bilinmiyor'}\nAPK içindeki sürüm: $apkVerStr\n\nLütfen APK’yı doğru pubspec.yaml version değeriyle yeniden build edip tekrar yayınlayın.',
            'The downloaded APK does not match the expected version.\n\nExpected: ${widget.licenseStatus.latestVersion ?? 'unknown'}\nVersion in APK: $apkVerStr\n\nRebuild the APK with the correct pubspec.yaml version and publish it again.',
          );
        });
        _apkPath = null;
        _changeState(UpdateState.failed);
        debugPrint('[UPDATE] apk version verification failed');
        return;
      }

      debugPrint('[UPDATE] apk version verification success');

      await LicenseStorage.saveDownloadedApkInfo(
        path: file.path,
        version: widget.licenseStatus.latestVersion ?? '',
        sha256: expectedHash,
        fileSize: widget.licenseStatus.apkSizeBytes ?? 0,
      );
      _apkPath = file.path;
      keepVerifiedApk = true;
      debugPrint('[UPDATE] saved downloaded apk state');

      AnalyticsService.instance.trackEvent(
        AnalyticsEvent(eventType: 'update_download_completed', screen: 'home'),
      );
      AnalyticsService.instance.trackEvent(
        AnalyticsEvent(eventType: 'update_ready_to_install', screen: 'home'),
      );

      _changeState(UpdateState.readyToInstall);

      // Deliberately no auto-install here: the admin chooses between
      // "Kurulumu Başlat" (PIN-gated via _downloadAndInstall) and
      // "Daha Sonra". The verified APK is persisted above, so a later
      // dialog open revalidates it and offers the install again.
    } on ApkDownloadCancelledException {
      AnalyticsService.instance.trackEvent(
        AnalyticsEvent(eventType: 'update_download_cancelled', screen: 'home'),
      );
      if (mounted) await _closeDialogSafely();
    } on ApkDownloadTimeoutException catch (error) {
      if (mounted) {
        setState(() {
          _error = switch (error.phase) {
            ApkDownloadTimeoutPhase.header => tr(
              'Güncelleme sunucusu zamanında yanıt vermedi. Lütfen tekrar deneyin.',
              'The update server did not respond in time. Please try again.',
            ),
            ApkDownloadTimeoutPhase.idleRead => tr(
              'Güncelleme indirmesi veri gelmediği için durduruldu. Lütfen tekrar deneyin.',
              'The update download was stopped because no data was received. Please try again.',
            ),
            ApkDownloadTimeoutPhase.total => tr(
              'Güncelleme indirmesi zaman sınırını aştı. Lütfen tekrar deneyin.',
              'The update download exceeded its time limit. Please try again.',
            ),
          };
        });
        _changeState(UpdateState.failed);
      }
      AnalyticsService.instance.trackEvent(
        AnalyticsEvent(
          eventType: 'update_download_failed',
          screen: 'home',
          metadata: {'kind': 'timeout', 'phase': error.phase.name},
        ),
      );
    } on ApkDownloadSizeException {
      if (mounted) {
        setState(() {
          _error = tr(
            'Güncelleme dosyası izin verilen maksimum boyutu aşıyor.',
            'The update file exceeds the maximum allowed size.',
          );
        });
        _changeState(UpdateState.failed);
      }
      AnalyticsService.instance.trackEvent(
        AnalyticsEvent(
          eventType: 'update_download_failed',
          screen: 'home',
          metadata: {'kind': 'size_limit'},
        ),
      );
    } catch (e) {
      final failureKind = classifyApkDownloadFailure(e);
      final errorText = e.toString();
      if (mounted) {
        final summary = switch (failureKind) {
          ApkDownloadFailureKind.storage => tr(
            'Güncelleme cihaza kaydedilemedi. Cihazın depolama alanını kontrol edin.',
            'The update could not be saved to the device. Check the device storage.',
          ),
          ApkDownloadFailureKind.network => tr(
            'Güncelleme sunucusuna bağlanılamadı. Cihazın internet bağlantısını kontrol edin.',
            'Could not connect to the update server. Check the device internet connection.',
          ),
          ApkDownloadFailureKind.badUrlOrResponse => tr(
            'Güncelleme adresi geçersiz veya sunucu beklenmedik yanıt verdi. Panel sürüm kaydını kontrol edin.',
            'The update address is invalid or the server responded unexpectedly. Check the release entry in the panel.',
          ),
          ApkDownloadFailureKind.unknown => tr(
            'Güncelleme indirilemedi. Lütfen tekrar deneyin.',
            'The update could not be downloaded. Please try again.',
          ),
        };
        // Bu diyalog PIN korumalı admin akışında açılır; teknik detay
        // sahadaki teşhis için bilinçli olarak gösterilir.
        final trimmedDetail = errorText.length > 300
            ? '${errorText.substring(0, 300)}…'
            : errorText;
        setState(() {
          _error =
              '$summary\n\n'
              '${tr('Teknik detay', 'Technical detail')}: $trimmedDetail';
        });
        _changeState(UpdateState.failed);
      }
      debugPrint('[UPDATE] APK download/verification failed: $e');
      AnalyticsService.instance.trackEvent(
        AnalyticsEvent(
          eventType: 'update_download_failed',
          screen: 'home',
          metadata: {
            'kind': failureKind.name,
            'error': errorText.length > 500
                ? errorText.substring(0, 500)
                : errorText,
          },
        ),
      );
    } finally {
      if (identical(_downloadCancellationToken, cancellationToken)) {
        _downloadCancellationToken = null;
      }
      if (downloadedFile != null && !keepVerifiedApk) {
        await UpdateService.deleteApkFile(downloadedFile);
      }
    }
  }

  Future<void> _runInstallFlow(String filePath) async {
    if (!Platform.isAndroid) {
      debugPrint('[UPDATE][SECURITY] APK installer blocked on non-Android.');
      return;
    }

    final validatedPath = await _getFullyValidatedReadyApkPath();
    if (!mounted) return;
    if (validatedPath == null || validatedPath != filePath) {
      _showReadyApkInvalidError();
      return;
    }

    _changeState(UpdateState.openingInstaller);
    debugPrint('[UPDATE] opening installer path=$validatedPath');

    bool hasPermission;
    try {
      hasPermission = await UpdateService.checkInstallPermission();
      debugPrint('[UPDATE] install permission=$hasPermission');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = tr(
          'Kurulum izni kontrol edilemedi. Kiosk modu açık kalacak.',
          'Install permission could not be checked. Kiosk mode will remain active.',
        );
        _primaryAction = _UpdatePrimaryAction.installVerifiedApk;
      });
      _changeState(UpdateState.failed);
      return;
    }

    if (!hasPermission) {
      final released = await _releaseKioskForExternalActivity(
        'install_permission_settings',
      );
      if (!released || !mounted) return;

      _externalActivity = _UpdateExternalActivity.installPermissionSettings;
      AnalyticsService.instance.trackEvent(
        AnalyticsEvent(eventType: 'update_permission_required', screen: 'home'),
      );
      debugPrint('[UPDATE] opening install permission settings');
      var settingsOpened = false;
      try {
        settingsOpened = await UpdateService.openInstallSettings();
        if (!settingsOpened) {
          throw StateError('Android install settings could not be opened.');
        }
      } catch (error, stackTrace) {
        debugPrint(
          '[UPDATE][SECURITY] Install settings launch failed: '
          '$error\n$stackTrace',
        );
      } finally {
        if (!settingsOpened) {
          _externalActivity = _UpdateExternalActivity.none;
          final restored = await _restoreKioskOrEnterMaintenance(
            'permission_settings_launch_failure',
          );
          if (restored && mounted) {
            setState(() {
              _error = tr(
                'Kurulum izni ekranı açılamadı. Lütfen tekrar deneyin.',
                'The install permission screen could not be opened. Please try again.',
              );
              _primaryAction = _UpdatePrimaryAction.grantPermission;
            });
            _changeState(UpdateState.failed);
          }
        }
      }
      return;
    }

    final released = await _releaseKioskForExternalActivity(
      'package_installer',
    );
    if (!released || !mounted) return;

    _externalActivity = _UpdateExternalActivity.packageInstaller;
    var installerOpened = false;
    try {
      debugPrint('[UPDATE] installer launched');
      final String result = await UpdateService.installApk(validatedPath);
      installerOpened = result == 'intent_started';
      if (!installerOpened) {
        throw StateError('Unexpected installer result: $result');
      }
      debugPrint('[UPDATE] installer intent started with result: $result');
      AnalyticsService.instance.trackEvent(
        AnalyticsEvent(eventType: 'update_install_started', screen: 'home'),
      );
    } catch (error, stackTrace) {
      debugPrint(
        '[UPDATE][SECURITY] Installer launch failed: $error\n$stackTrace',
      );
      AnalyticsService.instance.trackEvent(
        AnalyticsEvent(eventType: 'update_install_failed', screen: 'home'),
      );
    } finally {
      if (!installerOpened) {
        _externalActivity = _UpdateExternalActivity.none;
        final restored = await _restoreKioskOrEnterMaintenance(
          'installer_launch_failure',
        );
        if (restored && mounted) {
          setState(() {
            _error = tr(
              'Kurulum ekranı açılamadı. Lütfen tekrar deneyin.',
              'The installation screen could not be opened. Please try again.',
            );
            _primaryAction = _UpdatePrimaryAction.installVerifiedApk;
          });
          _changeState(UpdateState.failed);
        }
      }
    }
  }

  Future<void> _verifyPostInstall() async {
    try {
      await Future.delayed(const Duration(milliseconds: 1500));
      if (!mounted) return;

      final currentAppInfo = await PackageInfo.fromPlatform();
      final currentVersionStr =
          'v${currentAppInfo.version}+${currentAppInfo.buildNumber}';
      debugPrint(
        '[UPDATE] current installed version after resume=$currentVersionStr',
      );

      final latestVersionStr = widget.licenseStatus.latestVersion ?? '';
      debugPrint('[UPDATE] expected latestVersion=$latestVersionStr');

      final currentParsed = VersionInfo.parse(currentVersionStr);
      final latestParsed = VersionInfo.parse(latestVersionStr);

      // Installation is considered successful when the running version is the
      // same as, or newer than, the version we tried to install.
      final isSuccessful =
          currentParsed != null &&
          latestParsed != null &&
          currentParsed.isEqualOrNewerThan(latestParsed);

      if (isSuccessful) {
        debugPrint('[UPDATE] install verification success');
        AnalyticsService.instance.trackEvent(
          AnalyticsEvent(eventType: 'update_install_success', screen: 'home'),
        );
        await LicenseStorage.clearDownloadedApkInfo();
        if (mounted) {
          await LicenseService.instance.checkStatus();
          if (mounted) Navigator.of(context).pop();
        }
      } else {
        debugPrint('[UPDATE] install verification failed');
        setState(() {
          _error = tr(
            'Güncelleme kurulumu iptal edildi veya tamamlanmadı.',
            'The update installation was cancelled or did not complete.',
          );
          _primaryAction = _UpdatePrimaryAction.installVerifiedApk;
        });
        _changeState(UpdateState.failed);
      }
    } catch (error, stackTrace) {
      debugPrint(
        '[UPDATE] Post-install verification failed: $error\n$stackTrace',
      );
      if (!mounted) return;
      setState(() {
        _error = tr(
          'Kurulum sonucu doğrulanamadı. Mevcut sürüm kiosk modunda çalışmaya devam edecek.',
          'The installation result could not be verified. The current version will continue in kiosk mode.',
        );
        _primaryAction = _UpdatePrimaryAction.installVerifiedApk;
      });
      _changeState(UpdateState.failed);
    }
  }

  // Version comparison is handled by VersionInfo.compareVersionNames /
  // VersionInfo.isEqualOrNewerThan (lib/licensing/version_info.dart).

  Widget _buildStateWidget() {
    switch (_updateState) {
      case UpdateState.downloading:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: _progress,
                backgroundColor: Colors.white.withValues(alpha: 0.05),
                valueColor: const AlwaysStoppedAnimation<Color>(_gold),
                minHeight: 10,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '${tr('Güncelleme indiriliyor...', 'Downloading update...')} ${(_progress * 100).toInt()}%',
              style: const TextStyle(
                color: _cream,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        );
      case UpdateState.verifying:
        return Column(
          children: [
            const SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(_gold),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              tr(
                'Güncelleme dosyası doğrulanıyor...',
                'Verifying update file...',
              ),
              style: const TextStyle(
                color: _cream,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        );
      case UpdateState.readyToInstall:
        return Column(
          children: [
            const Icon(
              Icons.check_circle_outline_rounded,
              color: Colors.greenAccent,
              size: 48,
            ),
            const SizedBox(height: 12),
            Text(
              tr(
                'Güncelleme dosyası hazır. Kurulumu başlatabilirsiniz.',
                'Update file is ready. You can start installation.',
              ),
              style: const TextStyle(
                color: _cream,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        );
      case UpdateState.openingInstaller:
        return Column(
          children: [
            const SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(_gold),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              tr('Kurulum ekranı açılıyor...', 'Opening installer screen...'),
              style: const TextStyle(
                color: _cream,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        );
      case UpdateState.failed:
        if (_kioskState != _UpdateKioskState.restoreFailed) {
          return const SizedBox.shrink();
        }
        return Column(
          children: [
            const Icon(
              Icons.gpp_bad_rounded,
              color: Colors.redAccent,
              size: 48,
            ),
            const SizedBox(height: 12),
            Text(
              tr(
                'Güvenli mod geri yüklenene kadar bu ekran kapatılamaz.',
                'This screen cannot be closed until secure mode is restored.',
              ),
              style: const TextStyle(
                color: _cream,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        );
      case UpdateState.updateAvailable:
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildButtons() {
    if (_updateState == UpdateState.downloading) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          OutlinedButton(
            onPressed: _cancelDownload,
            style: OutlinedButton.styleFrom(
              foregroundColor: _cream,
              side: BorderSide(
                color: _cream.withValues(alpha: 0.3),
                width: 1.5,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            ),
            child: Text(
              tr('İndirmeyi İptal Et', 'Cancel Download'),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      );
    }

    if (_updateState == UpdateState.verifying ||
        _updateState == UpdateState.openingInstaller) {
      return const SizedBox.shrink();
    }

    if (_kioskState == _UpdateKioskState.restoreFailed ||
        _primaryAction == _UpdatePrimaryAction.retryKioskRestore) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          ElevatedButton(
            onPressed: _retryKioskRestore,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            ),
            child: Text(
              tr('Güvenli Modu Tekrar Dene', 'Retry Secure Mode'),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      );
    }

    final List<Widget> buttons = [];
    final String cancelLabel = (_updateState == UpdateState.failed)
        ? tr('Tamam', 'OK')
        : tr('Daha Sonra', 'Later');

    buttons.add(
      OutlinedButton(
        onPressed: () async {
          AnalyticsService.instance.trackEvent(
            AnalyticsEvent(eventType: 'update_later_clicked', screen: 'home'),
          );
          await _closeDialogSafely();
        },
        style: OutlinedButton.styleFrom(
          foregroundColor: _cream,
          side: BorderSide(color: _cream.withValues(alpha: 0.3), width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        ),
        child: Text(
          cancelLabel,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );

    buttons.add(const SizedBox(width: 16));

    if (_updateState == UpdateState.updateAvailable) {
      buttons.add(
        ElevatedButton(
          onPressed: _downloadAndInstall,
          style: ElevatedButton.styleFrom(
            backgroundColor: _gold,
            foregroundColor: _bgDark,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            elevation: 0,
          ),
          child: Text(
            tr('Güncellemeyi İndir', 'Download Update'),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      );
    } else if (_updateState == UpdateState.readyToInstall) {
      buttons.add(
        ElevatedButton(
          onPressed: _downloadAndInstall,
          style: ElevatedButton.styleFrom(
            backgroundColor: _gold,
            foregroundColor: _bgDark,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            elevation: 0,
          ),
          child: Text(
            tr('Kurulumu Başlat', 'Start Installation'),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      );
    } else if (_updateState == UpdateState.failed) {
      if (_primaryAction == _UpdatePrimaryAction.grantPermission) {
        buttons.add(
          ElevatedButton(
            onPressed: _downloadAndInstall,
            style: ElevatedButton.styleFrom(
              backgroundColor: _gold,
              foregroundColor: _bgDark,
              side: const BorderSide(color: _gold, width: 1.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            ),
            child: Text(
              tr('İzni Ver ve Devam Et', 'Grant Permission & Continue'),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        );
      } else if (_primaryAction == _UpdatePrimaryAction.installVerifiedApk) {
        buttons.add(
          ElevatedButton(
            onPressed: _downloadAndInstall,
            style: ElevatedButton.styleFrom(
              backgroundColor: _gold,
              foregroundColor: _bgDark,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              elevation: 0,
            ),
            child: Text(
              tr('Kurulumu Tekrar Başlat', 'Restart Installation'),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        );
      } else if (_primaryAction == _UpdatePrimaryAction.download) {
        buttons.add(
          ElevatedButton(
            onPressed: _downloadAndInstall,
            style: ElevatedButton.styleFrom(
              backgroundColor: _gold,
              foregroundColor: _bgDark,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              elevation: 0,
            ),
            child: Text(
              tr('Tekrar İndir', 'Download Again'),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        );
      }
    }

    return Row(mainAxisAlignment: MainAxisAlignment.end, children: buttons);
  }

  @override
  Widget build(BuildContext context) {
    final sizeMb = widget.licenseStatus.apkSizeBytes != null
        ? '${(widget.licenseStatus.apkSizeBytes! / (1024 * 1024)).toStringAsFixed(1)} MB'
        : tr('Bilinmiyor', 'Unknown');

    return PopScope(
      canPop: _kioskState == _UpdateKioskState.secured,
      child: Dialog(
        backgroundColor: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: const Color(0xFF1C1724),
              borderRadius: BorderRadius.circular(36),
              border: Border.all(color: _gold.withValues(alpha: 0.24)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.7),
                  blurRadius: 64,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _gold.withValues(alpha: 0.1),
                      ),
                      child: const Icon(
                        Icons.system_update_rounded,
                        color: _gold,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      tr('Yeni Sürüm Mevcut', 'New Version Available'),
                      style: const TextStyle(
                        color: _cream,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tr('Mevcut Sürüm', 'Current Version'),
                            style: const TextStyle(
                              color: _mutedText,
                              fontSize: _fsCaption,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _currentVersion,
                            style: const TextStyle(
                              color: _cream,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tr('Yeni Sürüm', 'New Version'),
                            style: const TextStyle(
                              color: _mutedText,
                              fontSize: _fsCaption,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.licenseStatus.latestVersion ?? '...',
                            style: const TextStyle(
                              color: _gold,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tr('Dosya Boyutu', 'File Size'),
                            style: const TextStyle(
                              color: _mutedText,
                              fontSize: _fsCaption,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            sizeMb,
                            style: const TextStyle(
                              color: _cream,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  tr('Güncelleme Notları:', 'Release Notes:'),
                  style: const TextStyle(
                    color: _mutedText,
                    fontSize: _fsCaption,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  constraints: const BoxConstraints(maxHeight: 150),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _cream.withValues(alpha: 0.05)),
                  ),
                  child: SingleChildScrollView(
                    child: Text(
                      widget.licenseStatus.releaseNotes ??
                          tr(
                            'Herhangi bir not bulunmuyor.',
                            'No release notes provided.',
                          ),
                      style: const TextStyle(
                        color: _cream,
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.redAccent.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      _error!,
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: _fsCaption,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
                const SizedBox(height: 32),
                _buildStateWidget(),
                const SizedBox(height: 16),
                _buildButtons(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
