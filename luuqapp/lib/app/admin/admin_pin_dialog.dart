part of '../../main.dart';

class _AdminPinDialog extends StatefulWidget {
  const _AdminPinDialog();

  @override
  State<_AdminPinDialog> createState() => _AdminPinDialogState();
}

class _AdminPinDialogState extends State<_AdminPinDialog> {
  String _pin = '';
  bool _isLoading = false;
  String? _errorMessage;

  void _press(String value) {
    if (_pin.length >= 4 || _isLoading) return;
    setState(() {
      _errorMessage = null;
      _pin += value;
    });
  }

  void _backspace() {
    if (_pin.isEmpty || _isLoading) return;
    setState(() {
      _errorMessage = null;
      _pin = _pin.substring(0, _pin.length - 1);
    });
  }

  Future<void> _verifyPin() async {
    if (_pin.length < 4 || _isLoading) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final deviceId = await DeviceIdentityService.getDeviceId();
      final fingerprint =
          await DeviceIdentityService.getDeviceFingerprintHash();
      final status = LicenseService.instance.currentStatus;

      final String licenseMode = status.mode == LicenseMode.licensed
          ? 'licensed'
          : status.mode == LicenseMode.trial
          ? 'trial'
          : 'none';

      final appVersion = await DeviceIdentityService.getAppVersion();
      // Proof of the enrolled kiosk; the device ID alone is not enough.
      final licenseKey = await LicenseStorage.getLicenseKey();

      final response = await http
          .post(
            Uri.parse(LicenseConfig.verifyAdminPinUrl),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'device_id': deviceId,
              'device_fingerprint_hash': fingerprint,
              'license_key': ?licenseKey,
              'license_mode': licenseMode,
              'pin': _pin,
              'app_version': appVersion,
              'platform': Platform.operatingSystem.toLowerCase(),
            }),
          )
          .timeout(LicenseConfig.apiTimeout);

      if (!mounted) return;

      final bodyStr = response.body.trim();
      Map<String, dynamic>? data;
      try {
        final decoded = json.decode(bodyStr);
        if (decoded is Map<String, dynamic>) {
          data = decoded;
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('verifyAdminPin JSON decode error: $e. Body: $bodyStr');
        }
      }

      if (data != null) {
        final dynamic successVal = data['success'];
        final bool success =
            successVal == true ||
            successVal == 'true' ||
            successVal == 1 ||
            successVal == '1';
        if (success) {
          final adminSessionToken = data['admin_session_token']?.toString();
          if (adminSessionToken != null && adminSessionToken.isNotEmpty) {
            await LicenseStorage.saveAdminSessionToken(adminSessionToken);
            // A fresh admin session lets queued wheel/barista writes go out now
            // instead of on the next 30 s poll.
            if (MenuService.instance.hasPendingConfig('wheel') ||
                MenuService.instance.hasPendingConfig('barista')) {
              // force: a sync already running would otherwise be reused and
              // the queue would wait for the next poll.
              unawaited(MenuService.instance.syncNow(force: true));
            }
          }
          if (!mounted) return;
          AnalyticsService.instance.trackAdminPinVerifySuccess();
          Navigator.of(context).pop(true);
        } else {
          final reason = data['reason']?.toString() ?? 'invalid_pin';
          AnalyticsService.instance.trackAdminPinVerifyFailed(reason);
          setState(() {
            _pin = '';
            _errorMessage = _getLocalizedPinError(reason);
          });
        }
      } else {
        throw HttpException(
          'Status: ${response.statusCode}, Body: ${response.body}',
        );
      }
    } catch (e) {
      debugPrint('verifyAdminPin error details: $e');
      if (!mounted) return;
      AnalyticsService.instance.trackAdminPinVerifyFailed('network_error');
      setState(() {
        _pin = '';
        _errorMessage = _getLocalizedPinError('network_error');
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String _getLocalizedPinError(String reason) {
    switch (reason) {
      case 'invalid_pin':
        return tr('PIN hatalı.', 'PIN is incorrect.');
      case 'pin_not_set':
        return tr(
          'Bu cihaz için admin PIN tanımlanmamış. Lütfen yöneticinizle iletişime geçin.',
          'Admin PIN is not set for this device. Please contact your administrator.',
        );
      case 'license_not_found':
        return tr('Lisans bilgisi bulunamadı.', 'License not found.');
      case 'license_inactive':
        return tr('Lisans aktif değil.', 'License inactive.');
      case 'license_expired':
        return tr('Lisans süresi dolmuş.', 'License expired.');
      case 'rate_limited':
        return tr(
          'Çok fazla hatalı deneme yapıldı. Lütfen biraz bekleyin.',
          'Too many failed attempts. Please wait a moment.',
        );
      case 'device_binding_mismatch':
      case 'invalid_device_id':
        return tr(
          'Bu cihaz lisansla eşleşmiyor. Lisans ekranından anahtarı tekrar girerek cihazı yeniden kaydedin.',
          'This device does not match the license. Re-enter the license key to register the device again.',
        );
      default:
        return tr(
          'Sunucuya bağlanılamadı. Lütfen internet bağlantınızı kontrol edin.',
          'Failed to connect to the server. Please check your internet connection.',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 380,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF1C1724),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: _gold.withValues(alpha: 0.24)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.65),
                  blurRadius: 50,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_rounded, color: _gold, size: 36),
                const SizedBox(height: 14),
                Text(
                  tr('Admin PIN', 'Admin PIN'),
                  style: const TextStyle(
                    color: _cream,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _errorMessage ??
                      tr(
                        'Admin menüsüne erişmek için 4 haneli PIN\'i girin.',
                        'Enter 4-digit PIN to access admin menu.',
                      ),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _errorMessage != null
                        ? Colors.redAccent
                        : _mutedText,
                    fontSize: _fsCaption,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(4, (index) {
                    final filled = index < _pin.length;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      width: 16,
                      height: 16,
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: filled ? _gold : Colors.transparent,
                        border: Border.all(
                          color: filled
                              ? _gold
                              : Colors.white.withValues(alpha: 0.25),
                          width: 2,
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 24),
                GridView.count(
                  shrinkWrap: true,
                  crossAxisCount: 3,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.25,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    for (final digit in [
                      '1',
                      '2',
                      '3',
                      '4',
                      '5',
                      '6',
                      '7',
                      '8',
                      '9',
                    ])
                      _PinKey(
                        label: digit,
                        onTap: _isLoading ? null : () => _press(digit),
                      ),
                    const SizedBox.shrink(),
                    _PinKey(
                      label: '0',
                      onTap: _isLoading ? null : () => _press('0'),
                    ),
                    _PinKey(
                      icon: Icons.backspace_rounded,
                      onTap: (_isLoading || _pin.isEmpty) ? null : _backspace,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: BouncyButton(
                        onTap: _isLoading
                            ? null
                            : () => Navigator.of(context).pop(false),
                        child: Container(
                          height: 50,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.08),
                            ),
                          ),
                          child: Text(
                            tr('Kapat', 'Close'),
                            style: const TextStyle(
                              color: _cream,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: BouncyButton(
                        onTap: (_pin.length < 4 || _isLoading)
                            ? null
                            : _verifyPin,
                        child: Opacity(
                          opacity: (_pin.length < 4 || _isLoading) ? 0.4 : 1.0,
                          child: Container(
                            height: 50,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: _gold,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                if (_pin.length == 4)
                                  BoxShadow(
                                    color: _gold.withValues(alpha: 0.3),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                              ],
                            ),
                            child: Text(
                              tr('Devam Et', 'Continue'),
                              style: const TextStyle(
                                color: Color(0xFF1C1724),
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (_isLoading)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(32),
                ),
                child: const Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(_gold),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PinKey extends StatelessWidget {
  const _PinKey({this.label, this.icon, required this.onTap});

  final String? label;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return BouncyButton(
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? 0.45 : 1.0,
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _bgDark.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: icon == null
              ? Text(
                  label!,
                  style: const TextStyle(
                    color: _cream,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                  ),
                )
              : Icon(icon, color: _cream, size: 24),
        ),
      ),
    );
  }
}
