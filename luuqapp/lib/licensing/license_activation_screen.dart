import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../main.dart' show tr;
import 'license_service.dart';
import 'license_status.dart';
import 'license_storage.dart';

class LicenseActivationScreen extends StatefulWidget {
  final VoidCallback onActivated;
  final String? errorMessage;
  final VoidCallback? onStorageFailure;

  /// Opened from a running trial to enter a full license key. The key form is
  /// shown directly; the saved (trial) state is never re-checked, because an
  /// active trial would close the screen at once via [onActivated].
  final bool upgradeMode;

  const LicenseActivationScreen({
    super.key,
    required this.onActivated,
    this.errorMessage,
    this.onStorageFailure,
    this.upgradeMode = false,
  });

  @override
  State<LicenseActivationScreen> createState() =>
      _LicenseActivationScreenState();
}

class _LicenseActivationScreenState extends State<LicenseActivationScreen>
    with WidgetsBindingObserver {
  final TextEditingController _keyController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  String? _savedLicenseKey;
  bool _showNewKeyInput = false;
  bool _isRetrying = false;

  @override
  void initState() {
    super.initState();
    _errorMessage = widget.errorMessage;
    if (widget.upgradeMode) {
      _showNewKeyInput = true;
    } else {
      _checkSavedKey();
    }
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _keyController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _retryCheckStatus();
    }
  }

  Future<void> _checkSavedKey() async {
    try {
      final key = await LicenseStorage.getLicenseKey();
      if (!mounted) return;
      setState(() {
        _savedLicenseKey = key;
        // Eğer yerelde kayıtlı bir key varsa, modu ne olursa olsun, pasif durum ekranını gösterelim:
        _showNewKeyInput = (key == null || key.isEmpty);
      });
      if (!_showNewKeyInput) {
        // Ekran ilk açıldığında otomatik olarak arka planda check atalım
        _retryCheckStatus();
      }
    } on LicenseStorageException catch (error, stackTrace) {
      _handleStorageFailure(error, stackTrace);
    }
  }

  void _handleStorageFailure(
    LicenseStorageException error,
    StackTrace stackTrace,
  ) {
    debugPrint(
      '[LICENSE][STORAGE] Activation flow blocked: $error\n$stackTrace',
    );
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _isRetrying = false;
      _errorMessage = LicenseService.getLocalizedError('storage_error');
    });
    widget.onStorageFailure?.call();
  }

  Future<void> _retryCheckStatus({bool force = false}) async {
    if (_isRetrying || _showNewKeyInput) return;
    if (_savedLicenseKey == null) return;

    setState(() {
      _isRetrying = true;
      if (force) {
        _isLoading = true;
      }
    });

    try {
      final status = await LicenseService.instance.checkStatus();
      if (mounted) {
        if (status.active) {
          widget.onActivated();
        } else {
          setState(() {
            _errorMessage = LicenseService.getLocalizedError(status.reason);
          });
        }
      }
    } on LicenseStorageException catch (error, stackTrace) {
      _handleStorageFailure(error, stackTrace);
    } catch (_) {
      // Hata durumunda network/server hatası gösterilebilir
      if (mounted) {
        setState(() {
          _errorMessage = LicenseService.getLocalizedError('network_error');
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRetrying = false;
          if (force) {
            _isLoading = false;
          }
        });
      }
    }
  }

  static const _bgDark = Color(0xFF16131D);
  static const _surface = Color(0xFF231E2D);
  static const _gold = Color(0xFFF9AB3E);
  static const _cream = Color(0xFFFFF7EC);
  static const _muted = Color(0xFF8A8694);

  Future<void> _activateLicense() async {
    final key = _keyController.text.trim();
    if (key.isEmpty) {
      setState(() {
        _errorMessage = tr(
          'Lütfen lisans anahtarını girin.',
          'Please enter the license key.',
        );
      });
      return;
    }

    final regExp = RegExp(
      r'^LUUQ-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$',
    );
    if (!regExp.hasMatch(key)) {
      setState(() {
        _errorMessage = tr(
          'Lütfen lisans anahtarını eksiksiz girin.',
          'Please enter the complete license key.',
        );
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final status = await LicenseService.instance.validateLicense(key);
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });

      if (status.active) {
        widget.onActivated();
      } else {
        setState(() {
          _errorMessage = LicenseService.getLocalizedError(status.reason);
        });
      }
    } on LicenseStorageException catch (error, stackTrace) {
      _handleStorageFailure(error, stackTrace);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = LicenseService.instance.currentStatus;
    final isTrialExpired =
        (status.mode == LicenseMode.trial && !status.active) ||
        (status.reason == 'trial_expired' ||
            status.reason == 'trial_already_used');
    final isTrialActive = status.active && status.mode == LicenseMode.trial;

    final String title;
    final String subtitle;
    final String? warningText;

    if (!_showNewKeyInput && _savedLicenseKey != null) {
      // Pasif veya Süresi Dolmuş Lisans ekranı görünümü
      final reason = status.reason ?? widget.errorMessage;
      if (reason == 'license_expired') {
        title = tr('Lisans Süresi Doldu', 'License Expired');
        subtitle = tr(
          'Lisans süresi dolmuş görünüyor. Lisans süresi uzatıldığında uygulama otomatik olarak yeniden bağlanacaktır.',
          'License seems to be expired. The app will reconnect automatically once the subscription is extended.',
        );
      } else if (reason == 'device_limit_reached') {
        title = tr('Cihaz Limiti Aşıldı', 'Device Limit Reached');
        subtitle = tr(
          'Bu lisans için cihaz limiti dolmuş. Lütfen yöneticinizle iletişime geçin.',
          'Device limit has been reached for this license. Please contact your administrator.',
        );
      } else {
        title = tr('Lisans Pasif', 'License Inactive');
        subtitle = tr(
          'Bu cihazdaki lisans şu anda aktif değil. Lisans tekrar aktif edildiğinde "Tekrar Dene" butonuna basınız.',
          'This license is currently inactive. When the licence is reactivated please press "Try Again" button.',
        );
      }
      warningText = null;
    } else {
      // Standart Lisans Aktivasyon / Form görünümü
      if (isTrialExpired) {
        title = tr('Deneme Süreniz Sona Erdi', 'Trial Period Expired');
        subtitle = tr(
          'Devam etmek için lisans anahtarı girin.',
          'Enter a license key to continue.',
        );
        warningText = tr(
          'Bu cihazda deneme sürümü daha önce kullanılmış.',
          'Trial version has already been used on this device.',
        );
      } else if (isTrialActive) {
        title = tr('Lisansı Aktifleştir', 'Activate License');
        subtitle = tr(
          'Deneme sürümünüz devam ediyor. Geçerli bir lisans anahtarı girerek lisanslı sürüme yükseltebilirsiniz.',
          'Your trial is active. You can upgrade to the licensed version by entering a valid license key.',
        );
        warningText = null;
      } else {
        title = tr('LUUQ Kiosk Aktivasyon', 'LUUQ Kiosk Activation');
        subtitle = tr(
          'Uygulamayı kullanmak için internet bağlantısı ve geçerli lisans anahtarı gereklidir.',
          'Internet connection and a valid license key are required to use the application.',
        );
        warningText = null;
      }
    }

    return Scaffold(
      backgroundColor: _bgDark,
      body: Center(
        child: SingleChildScrollView(
          child: Container(
            width: 480,
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 48),
            decoration: BoxDecoration(
              color: _surface.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(36),
              border: Border.all(
                color: _gold.withValues(alpha: 0.25),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 40,
                  offset: const Offset(0, 20),
                ),
              ],
            ),
            child: Stack(
              children: [
                if (Navigator.of(context).canPop())
                  Positioned(
                    right: 0,
                    top: 0,
                    child: IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded, color: _muted),
                    ),
                  ),
                Padding(
                  padding: EdgeInsets.only(
                    top: Navigator.of(context).canPop() ? 16.0 : 0.0,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Logo & Header
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _gold.withValues(alpha: 0.1),
                          border: Border.all(
                            color: _gold.withValues(alpha: 0.3),
                            width: 2,
                          ),
                        ),
                        child: Icon(
                          (!_showNewKeyInput && _savedLicenseKey != null)
                              ? Icons.cloud_off_rounded
                              : Icons.vpn_key_rounded,
                          color: _gold,
                          size: 40,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: _cream,
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        subtitle,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: _muted,
                          fontSize: 14,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 36),

                      // Error Message
                      if (_errorMessage != null) ...[
                        Container(
                          width: double.infinity,
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
                            _errorMessage!,
                            style: const TextStyle(
                              color: Colors.redAccent,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],

                      // Toggle View
                      if (!_showNewKeyInput && _savedLicenseKey != null) ...[
                        // Pasif Durum Butonları
                        if (_isLoading)
                          const CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(_gold),
                          )
                        else ...[
                          SizedBox(
                            width: double.infinity,
                            height: 54,
                            child: ElevatedButton(
                              onPressed: () => _retryCheckStatus(force: true),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _gold,
                                foregroundColor: _bgDark,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                              ),
                              child: Text(
                                tr('Tekrar Dene', 'Try Again'),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            height: 54,
                            child: OutlinedButton(
                              onPressed: () {
                                setState(() {
                                  _showNewKeyInput = true;
                                });
                              },
                              style: OutlinedButton.styleFrom(
                                foregroundColor: _gold,
                                side: const BorderSide(
                                  color: _gold,
                                  width: 1.5,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                              ),
                              child: Text(
                                tr('Yeni Lisans Gir', 'Enter New License'),
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ] else ...[
                        // Standart Lisans Form Alanı
                        TextField(
                          controller: _keyController,
                          enabled: !_isLoading,
                          // A shared kiosk keyboard must not learn the key
                          // and offer it to the next person.
                          autocorrect: false,
                          enableSuggestions: false,
                          enableIMEPersonalizedLearning: false,
                          style: const TextStyle(
                            color: _cream,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                          inputFormatters: [LicenseKeyFormatter()],
                          decoration: InputDecoration(
                            hintText: 'LUUQ-XXXX-XXXX-XXXX-XXXX',
                            hintStyle: const TextStyle(
                              color: _muted,
                              fontWeight: FontWeight.normal,
                            ),
                            filled: true,
                            fillColor: _bgDark.withValues(alpha: 0.5),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 18,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                              borderSide: BorderSide(
                                color: _gold.withValues(alpha: 0.2),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                              borderSide: const BorderSide(
                                color: _gold,
                                width: 2,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                              borderSide: BorderSide(
                                color: _gold.withValues(alpha: 0.2),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),

                        if (_isLoading)
                          const CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(_gold),
                          )
                        else ...[
                          SizedBox(
                            width: double.infinity,
                            height: 54,
                            child: ElevatedButton(
                              onPressed: _activateLicense,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _gold,
                                foregroundColor: _bgDark,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                elevation: 0,
                              ),
                              child: Text(
                                tr('Lisansı Aktifleştir', 'Activate License'),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                          if (warningText != null) ...[
                            const SizedBox(height: 20),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.redAccent.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Colors.redAccent.withValues(
                                    alpha: 0.25,
                                  ),
                                ),
                              ),
                              child: Text(
                                warningText,
                                style: const TextStyle(
                                  color: Colors.redAccent,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        ],
                      ],
                      const SizedBox(height: 32),

                      // Footer Note
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            (!_showNewKeyInput && _savedLicenseKey != null)
                                ? Icons.info_outline_rounded
                                : Icons.wifi_rounded,
                            color: _muted,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              (!_showNewKeyInput && _savedLicenseKey != null)
                                  ? tr(
                                      'Dilerseniz yukarıdaki butonla kayıtlı lisansı tekrar kontrol edebilirsiniz.',
                                      'You can check the registered license again with the button above.',
                                    )
                                  : tr(
                                      'Uygulamayı kullanmak için internet gereklidir.',
                                      'Internet connection is required to use the application.',
                                    ),
                              style: const TextStyle(
                                color: _muted,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class LicenseKeyFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final String newText = newValue.text;

    if (newText.isEmpty) {
      return newValue;
    }

    final String cleanNew = newText
        .replaceAll(RegExp(r'[^A-Za-z0-9]'), '')
        .toUpperCase();

    final bool isDeletion = newValue.text.length < oldValue.text.length;

    String clean = cleanNew;
    if (clean.startsWith('LUUQLUUQ')) {
      clean = clean.substring(4);
    }

    String raw = clean;
    if (!raw.startsWith('LUUQ')) {
      bool isPrefix = false;
      for (int i = 1; i <= 3; i++) {
        if (raw == 'LUUQ'.substring(0, i)) {
          isPrefix = true;
          break;
        }
      }
      if (!isPrefix) {
        raw = 'LUUQ$raw';
      }
    }

    if (raw.length > 20) {
      raw = raw.substring(0, 20);
    }

    final buffer = StringBuffer();
    for (int i = 0; i < raw.length; i++) {
      if (i > 0 && i % 4 == 0) {
        buffer.write('-');
      }
      buffer.write(raw[i]);
    }

    if (!isDeletion &&
        raw.isNotEmpty &&
        raw.length % 4 == 0 &&
        raw.length < 20) {
      buffer.write('-');
    }

    final String formatted = buffer.toString();

    int selectionIndex = newValue.selection.end;

    int cleanCharsBeforeCursor = 0;
    for (int i = 0; i < selectionIndex && i < newText.length; i++) {
      final String char = newText[i].toUpperCase();
      if (RegExp(r'[A-Z0-9]').hasMatch(char)) {
        cleanCharsBeforeCursor++;
      }
    }

    if (!clean.startsWith('LUUQ')) {
      bool isPrefix = false;
      for (int i = 1; i <= 3; i++) {
        if (clean == 'LUUQ'.substring(0, i)) {
          isPrefix = true;
          break;
        }
      }
      if (!isPrefix) {
        cleanCharsBeforeCursor += 4;
      }
    }

    if (clean.startsWith('LUUQLUUQ') && cleanCharsBeforeCursor >= 4) {
      cleanCharsBeforeCursor -= 4;
    }

    int newSelectionIndex = 0;
    int cleanCharsSeen = 0;
    while (newSelectionIndex < formatted.length &&
        cleanCharsSeen < cleanCharsBeforeCursor) {
      if (formatted[newSelectionIndex] != '-') {
        cleanCharsSeen++;
      }
      newSelectionIndex++;
    }

    if (newSelectionIndex < formatted.length &&
        formatted[newSelectionIndex] == '-') {
      newSelectionIndex++;
    }

    if (newSelectionIndex > formatted.length) {
      newSelectionIndex = formatted.length;
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: newSelectionIndex),
    );
  }
}
