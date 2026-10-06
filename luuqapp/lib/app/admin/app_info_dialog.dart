part of '../../main.dart';

// ===== UYGULAMA BİLGİLERİ DİYALOGU =====

class _AppInfoDialog extends StatefulWidget {
  const _AppInfoDialog();

  @override
  State<_AppInfoDialog> createState() => _AppInfoDialogState();
}

class _AppInfoDialogState extends State<_AppInfoDialog> {
  String _deviceId = '...';
  String _appVersion = '...';
  String _internetStatus = '...';
  Color _internetColor = _muted;
  late final Timer _uptimeTimer;
  Duration _uptime = Duration.zero;

  @override
  void initState() {
    super.initState();
    _loadDiagnosticInfo();
    _uptime = DateTime.now().difference(_appStartTime);
    _uptimeTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _uptime = DateTime.now().difference(_appStartTime);
        });
      }
    });
  }

  @override
  void dispose() {
    _uptimeTimer.cancel();
    super.dispose();
  }

  Future<void> _loadDiagnosticInfo() async {
    final deviceId = await DeviceIdentityService.getDeviceId();
    final isConnected = await _checkInternet();
    final appVersion = await DeviceIdentityService.getAppVersion(
      bypassCache: true,
    );

    if (mounted) {
      setState(() {
        _deviceId = deviceId;
        _appVersion = appVersion;
        _internetStatus = isConnected
            ? tr('Bağlı (İnternet Var)', 'Connected (Online)')
            : tr('Bağlantı Yok (Çevrimdışı)', 'No Connection (Offline)');
        _internetColor = isConnected ? Colors.greenAccent : Colors.redAccent;
      });
    }
  }

  Future<bool> _checkInternet() async {
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 2));
      if (result.isNotEmpty && result.first.rawAddress.isNotEmpty) {
        return true;
      }
    } catch (_) {}
    return false;
  }

  String _formatUptime(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    final hoursStr = hours.toString().padLeft(2, '0');
    final minutesStr = minutes.toString().padLeft(2, '0');
    final secondsStr = seconds.toString().padLeft(2, '0');

    return '$hoursStr:$minutesStr:$secondsStr';
  }

  String _formatDateTime(DateTime? dt) {
    if (dt == null) return '-';
    final day = dt.day.toString().padLeft(2, '0');
    final month = dt.month.toString().padLeft(2, '0');
    final year = dt.year;
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    final second = dt.second.toString().padLeft(2, '0');
    return '$day.$month.$year $hour:$minute:$second';
  }

  Widget _buildFeatureChip(String label, bool isEnabled) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isEnabled
            ? Colors.greenAccent.withValues(alpha: 0.08)
            : Colors.redAccent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isEnabled
              ? Colors.greenAccent.withValues(alpha: 0.3)
              : Colors.redAccent.withValues(alpha: 0.3),
          width: 1.5,
        ),
        boxShadow: isEnabled
            ? [
                BoxShadow(
                  color: Colors.greenAccent.withValues(alpha: 0.05),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isEnabled
                ? Icons.check_circle_outline_rounded
                : Icons.lock_outline_rounded,
            color: isEnabled ? Colors.greenAccent : Colors.redAccent,
            size: 18,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: isEnabled ? _cream : _mutedText,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Dynamically retrieve platform, resolution, aspect ratio, device pixel ratio
    final view = PlatformDispatcher.instance.views.first;
    final physicalSize = view.physicalSize;
    final pixelRatio = view.devicePixelRatio;
    final width = (physicalSize.width / pixelRatio).round();
    final height = (physicalSize.height / pixelRatio).round();

    // Format aspect ratio
    String aspectRatioStr = '';
    if (width > 0 && height > 0) {
      final gcdVal = _gcd(width, height);
      final aspectX = (width / gcdVal).round();
      final aspectY = (height / gcdVal).round();
      aspectRatioStr = '$aspectX:$aspectY';
    } else {
      aspectRatioStr = '-';
    }

    final platformName = Platform.isAndroid
        ? 'Android'
        : Platform.isWindows
        ? 'Windows'
        : Platform.isIOS
        ? 'iOS'
        : Platform.isMacOS
        ? 'macOS'
        : Platform.isLinux
        ? 'Linux'
        : 'Unknown';

    final double screenHeight = MediaQuery.of(context).size.height;
    return Dialog(
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 720,
          maxHeight: screenHeight - 80,
        ),
        child: Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: const Color(0xFF1C1724),
            borderRadius: BorderRadius.circular(36),
            border: Border.all(
              color: Colors.tealAccent.withValues(alpha: 0.24),
            ),
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
              // Header (Pinned)
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.tealAccent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.info_outline_rounded,
                      color: Colors.tealAccent,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tr('UYGULAMA BİLGİLERİ', 'APP INFORMATION'),
                          style: const TextStyle(
                            color: _cream,
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          tr(
                            'Sistem Teşhis ve Geliştirici Sekmesi',
                            'System Diagnostics & Developer Tab',
                          ),
                          style: const TextStyle(
                            color: _mutedText,
                            fontSize: _fsCaption,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                    color: _muted,
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Scrollable Body
              Flexible(
                child: SingleChildScrollView(
                  child: ValueListenableBuilder<LicenseStatus>(
                    valueListenable: LicenseService.instance.statusNotifier,
                    builder: (context, status, _) {
                      final f = status.features;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Left Column: License & Software
                              Expanded(
                                child: _buildSectionCard(
                                  title: tr(
                                    'Yazılım & Lisans',
                                    'Software & License',
                                  ),
                                  accentColor: Colors.tealAccent,
                                  children: [
                                    _buildInfoRow(
                                      tr('Uygulama Sürümü', 'App Version'),
                                      _appVersion,
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 8.0,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            tr('Cihaz UUID', 'Device UUID'),
                                            style: const TextStyle(
                                              color: _mutedText,
                                              fontSize: _fsCaption,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 8,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.black.withValues(
                                                alpha: 0.25,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                              border: Border.all(
                                                color: Colors.white.withValues(
                                                  alpha: 0.05,
                                                ),
                                              ),
                                            ),
                                            child: SelectableText(
                                              _deviceId,
                                              style: const TextStyle(
                                                color: _cream,
                                                fontSize: _fsCaption,
                                                fontWeight: FontWeight.w900,
                                                fontFamily: 'monospace',
                                                letterSpacing: 0.5,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    _buildInfoRow(
                                      tr('Lisans Durumu', 'License Status'),
                                      status.active
                                          ? (status.mode == LicenseMode.licensed
                                                ? tr(
                                                    'Aktif (Lisanslı)',
                                                    'Active (Licensed)',
                                                  )
                                                : tr(
                                                    'Aktif (Deneme)',
                                                    'Active (Trial)',
                                                  ))
                                          : tr(
                                              'Devre Dışı / Lisans Yok',
                                              'Disabled / No License',
                                            ),
                                      valueColor: status.active
                                          ? (status.mode == LicenseMode.licensed
                                                ? Colors.greenAccent
                                                : _gold)
                                          : Colors.redAccent,
                                    ),
                                    if (status.plan != null &&
                                        status.plan!.isNotEmpty)
                                      _buildInfoRow(
                                        tr(
                                          'Plan / Lisans Tipi',
                                          'Plan / License Type',
                                        ),
                                        status.plan!,
                                      ),
                                    if (status.customerName != null)
                                      _buildInfoRow(
                                        tr('Müşteri', 'Customer'),
                                        status.customerName!,
                                      ),
                                    if (status.branchName != null)
                                      _buildInfoRow(
                                        tr('Şube', 'Branch'),
                                        status.branchName!,
                                      ),
                                    if (status.mode == LicenseMode.licensed &&
                                        status.expiresAt != null)
                                      _buildInfoRow(
                                        tr('Bitiş Tarihi', 'Expiry Date'),
                                        status.expiresAt!,
                                      ),
                                    if (status.mode == LicenseMode.trial &&
                                        status.trialExpiresAt != null)
                                      _buildInfoRow(
                                        tr('Deneme Bitiş', 'Trial Expiry'),
                                        status.trialExpiresAt!,
                                      ),
                                    _buildInfoRow(
                                      tr('Son Kontrol', 'Last Check'),
                                      _formatDateTime(status.lastCheckedAt),
                                      valueColor: Colors.tealAccent,
                                    ),
                                    if (status.mode == LicenseMode.trial) ...[
                                      const SizedBox(height: 14),
                                      SizedBox(
                                        width: double.infinity,
                                        height: 40,
                                        child: ElevatedButton.icon(
                                          onPressed: () {
                                            Navigator.of(context)
                                                .pop(); // close AppInfo dialog
                                            _openLicenseUpgradeDialog(context);
                                          },
                                          icon: const Icon(
                                            Icons.vpn_key_rounded,
                                            size: 16,
                                          ),
                                          label: Text(
                                            tr(
                                              'Lisans Anahtarı Gir',
                                              'Enter License Key',
                                            ),
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: _fsCaption,
                                            ),
                                          ),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: _gold,
                                            foregroundColor: _bgDark,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                            elevation: 0,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(width: 20),

                              // Right Column: Hardware, OS & Diagnostics
                              Expanded(
                                child: _buildSectionCard(
                                  title: tr(
                                    'Donanım & Teşhis',
                                    'Hardware & Diagnostics',
                                  ),
                                  accentColor: _gold,
                                  children: [
                                    _buildInfoRow(
                                      tr(
                                        'Platform / İşletim Sistemi',
                                        'Platform / OS',
                                      ),
                                      platformName,
                                    ),
                                    _buildInfoRow(
                                      tr(
                                        'Ekran Çözünürlüğü',
                                        'Screen Resolution',
                                      ),
                                      '$width x $height',
                                    ),
                                    _buildInfoRow(
                                      tr('Ekran Oranı', 'Aspect Ratio'),
                                      aspectRatioStr,
                                    ),
                                    _buildInfoRow(
                                      tr('Piksel Oranı', 'Pixel Ratio'),
                                      pixelRatio.toStringAsFixed(2),
                                    ),
                                    _buildInfoRow(
                                      tr(
                                        'Bağlantı Durumu',
                                        'Connection Status',
                                      ),
                                      _internetStatus,
                                      valueColor: _internetColor,
                                    ),
                                    _buildInfoRow(
                                      tr('Çalışma Süresi', 'Uptime'),
                                      _formatUptime(_uptime),
                                      valueColor: Colors.lightBlueAccent,
                                    ),
                                    _buildInfoRow(
                                      tr('Kiosk Kilidi', 'Kiosk Lockdown'),
                                      tr('Aktif', 'Active'),
                                      valueColor: Colors.lightBlueAccent,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          // Features Card
                          _buildSectionCard(
                            title: tr(
                              'Lisanslı Özellik İzinleri',
                              'Licensed Feature Permissions',
                            ),
                            accentColor: Colors.purpleAccent,
                            children: [
                              const SizedBox(height: 12),
                              GridView.count(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                crossAxisCount: 2,
                                crossAxisSpacing: 16,
                                mainAxisSpacing: 12,
                                childAspectRatio: 5.5,
                                children: [
                                  _buildFeatureChip(
                                    tr('Hesap Kimde', 'Who Pays'),
                                    f.whoPays,
                                  ),
                                  _buildFeatureChip(tr('Menü', 'Menu'), f.menu),
                                  _buildFeatureChip(
                                    tr('Çarkıfelek', 'Spin Wheel'),
                                    f.wheel,
                                  ),
                                  _buildFeatureChip(
                                    tr('İngilizce', 'English'),
                                    f.english,
                                  ),
                                  _buildFeatureChip(
                                    tr('Temizlik Modu', 'Cleaning Mode'),
                                    f.cleaningMode,
                                  ),
                                  _buildFeatureChip(
                                    tr('Manuel Çıkış', 'Manual Exit'),
                                    f.manualExit,
                                  ),
                                  _buildFeatureChip(
                                    tr(
                                      'Barista Önerisi Düzenleme',
                                      'Barista Recommendation',
                                    ),
                                    f.baristaRecommendation,
                                  ),
                                  _buildFeatureChip(
                                    tr(
                                      'Çark İçeriği Düzenleme',
                                      'Wheel Content',
                                    ),
                                    f.wheelContent,
                                  ),
                                  _buildFeatureChip(
                                    tr('Uygulama Teması', 'App Theme'),
                                    f.themes,
                                  ),
                                  _buildFeatureChip(
                                    tr('Ses Seviyesi', 'Volume Control'),
                                    f.volumeControl,
                                  ),
                                  _buildFeatureChip(
                                    tr('Analizler', 'Analytics'),
                                    f.analytics,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // Footer Close Button (Pinned)
              Align(
                alignment: Alignment.centerRight,
                child: BouncyButton(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 36,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.tealAccent,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.tealAccent.withValues(alpha: 0.25),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Text(
                      tr('Kapat', 'Close'),
                      style: const TextStyle(
                        color: _bgDark,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  int _gcd(int a, int b) {
    while (b != 0) {
      final t = b;
      b = a % b;
      a = t;
    }
    return a;
  }

  Widget _buildSectionCard({
    required String title,
    required List<Widget> children,
    required Color accentColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _surface.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: accentColor.withValues(alpha: 0.15),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: accentColor,
              fontSize: 15,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: _mutedText,
                fontSize: _fsCaption,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? _cream,
              fontSize: _fsCaption,
              fontWeight: FontWeight.w900,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}
