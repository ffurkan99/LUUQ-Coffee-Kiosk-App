import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:video_player/video_player.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

import 'licensing/license_gate.dart';
import 'licensing/license_service.dart';
import 'licensing/license_storage.dart';
import 'licensing/feature_flags.dart';
import 'licensing/device_identity_service.dart';
import 'licensing/license_status.dart';
import 'licensing/feature_sync_service.dart';
import 'licensing/license_activation_screen.dart';
import 'licensing/license_config.dart';
import 'licensing/update_service.dart';
import 'analytics/analytics_service.dart';
import 'analytics/analytics_event.dart';
import 'src/who_pays/lottery_machine_view.dart';
import 'src/who_pays/lottery_simulation.dart';

FeatureFlags get currentFeatureFlags =>
    LicenseService.instance.currentFeatureFlags;

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

String _generateSlug(String name) {
  return name
      .toLowerCase()
      .replaceAll(RegExp(r'[ıİ]'), 'i')
      .replaceAll(RegExp(r'[şŞ]'), 's')
      .replaceAll(RegExp(r'[ğĞ]'), 'g')
      .replaceAll(RegExp(r'[üÜ]'), 'u')
      .replaceAll(RegExp(r'[öÖ]'), 'o')
      .replaceAll(RegExp(r'[çÇ]'), 'c')
      .replaceAll(RegExp(r'[^a-z0-9\s-]'), '')
      .replaceAll(RegExp(r'\s+'), '_')
      .replaceAll(RegExp(r'-+'), '_');
}

void showFeatureLockedDialog(
  BuildContext context,
  String featureName, {
  String? customMessage,
  String? screen,
  String? featureKey,
}) {
  final status = LicenseService.instance.currentStatus;
  if (kDebugMode) {
    debugPrint('UI FEATURE LOCK CONTROL:');
    debugPrint('  featureName: $featureName');
    debugPrint('  featureValue: false');
    debugPrint('  currentMode: ${status.mode.name}');
    debugPrint('  currentPlan: ${status.plan ?? 'null'}');
  }
  AnalyticsService.instance.trackLockedFeatureClick(
    featureKey ?? _generateSlug(featureName),
    featureName,
    screen ?? 'home',
  );
  showDialog(
    context: context,
    builder: (context) {
      final isLicensedMode = status.mode == LicenseMode.licensed;

      final title = isLicensedMode
          ? tr('Özellik Devre Dışı', 'Feature Disabled')
          : tr('Lisanslı Sürüm Özelliği', 'Premium Feature');

      final description = isLicensedMode
          ? tr(
              '“$featureName” özelliği yöneticiniz tarafından devre dışı bırakılmıştır. Bu özelliği kullanmak için lütfen yöneticinizle iletişime geçin.',
              '“$featureName” feature has been disabled by your administrator. Please contact your administrator to use this feature.',
            )
          : (customMessage ??
                tr(
                  '“$featureName” özelliği deneme sürümünde kilitlidir. Devam etmek için lütfen lisans edinin.',
                  '“$featureName” feature is locked in the trial version. Please obtain a license to continue.',
                ));

      return Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 420,
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: const Color(0xFF1C1724),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: _gold.withValues(alpha: 0.24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.65),
                blurRadius: 24,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _gold.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.lock_outline_rounded,
                  color: _gold,
                  size: 48,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                title,
                style: const TextStyle(
                  color: _cream,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                description,
                style: const TextStyle(
                  color: _muted,
                  fontSize: 14,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              if (isLicensedMode)
                BouncyButton(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: _gold,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      tr('Kapat', 'Close'),
                      style: const TextStyle(
                        color: _bgDark,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                  ),
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: BouncyButton(
                        onTap: () => Navigator.of(context).pop(),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            color: _surface.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.1),
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            tr('Kapat', 'Close'),
                            style: const TextStyle(
                              color: _cream,
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: BouncyButton(
                        onTap: () {
                          Navigator.of(context).pop();
                          _openLicenseUpgradeDialog(context);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            color: _gold,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            tr('Lisans Gir', 'Enter License'),
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
            ],
          ),
        ),
      );
    },
  );
}

void _openLicenseUpgradeDialog(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (context) => LicenseActivationScreen(
        onActivated: () {
          Navigator.of(context).pop();
        },
      ),
    ),
  );
}

String getTrialRemainingText() {
  final status = LicenseService.instance.currentStatus;
  if (status.mode != LicenseMode.trial) return '';
  if (status.trialExpiresAt == null) return '';
  try {
    final expiry = DateTime.parse(status.trialExpiresAt!);
    final diff = expiry.difference(DateTime.now());
    if (diff.isNegative) {
      return tr('Süre doldu', 'Expired');
    }
    if (diff.inDays >= 1) {
      return tr('Kalan: ${diff.inDays} Gün', 'Remaining: ${diff.inDays} Days');
    } else if (diff.inHours >= 1) {
      return tr(
        'Kalan: ${diff.inHours} Saat',
        'Remaining: ${diff.inHours} Hours',
      );
    } else {
      return tr('Kalan: < 1 Saat', 'Remaining: < 1 Hour');
    }
  } catch (_) {
    return '';
  }
}

late final DateTime _appStartTime;

void main() async {
  _appStartTime = DateTime.now();
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(UpdateService.cleanupOldUpdateApks());
  await _LuuqSettings.instance.load();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  await _loadAppTheme();
  await _loadAppVolume();
  runApp(const LuuqApp());
}

const _bgDark = Color(0xFF16131D); // Deep dark warm navy/brown
const _surface = Color(0xFF231E2D);
const _gold = Color(0xFFF9AB3E);
const _caramel = Color(
  0xFFD88E2B,
); // Complementary darker shade of the new gold
const _mint = Color(0xFF48C9B0);
const _cream = Color(0xFFFFF7EC);
const _muted = Color(0xFF8A8694);

const _preferredMenuNames = <String, List<String>>{
  'Double Espresso': ['Espresso Double'],
  'Espresso': ['Espresso Double'],
  'Iced Americano': ['Ice Americano', 'Americano'],
  'Americano': ['Ice Americano', 'Americano'],
  'Caffe Latte': ['Latte'],
  'Latte': ['Latte'],
  'Caramel Macchiato': ['Caramel Macchiato'],
  'Mocha': ['Mocha', 'Ice Mocha'],
  'Caffe Mocha': ['Mocha'],
  'Cold Brew': ['Cold Brew'],
  'Caramel Frappe': ['Ice Caramel Latte', 'Caramel Latte'],
  'Frappe': ['Ice Caramel Latte', 'Caramel Latte'],
  'Matcha Latte': ['Ice Matcha Latte', 'Matcha Mix'],
  'Matcha': ['Ice Matcha Latte', 'Matcha Mix'],
  'Peach Iced Tea': ['Çay'],
  'Iced Tea': ['Çay'],
  'Hot Chocolate': ['Sıcak Çikolata'],
  'Hot Choco': ['Sıcak Çikolata'],
};

class _SpinTickSound {
  static const _channel = MethodChannel('luuqapp/spin_sound');

  DateTime? _lastPlayedAt;

  void playTick() {
    final now = DateTime.now();
    final lastPlayedAt = _lastPlayedAt;
    if (lastPlayedAt != null &&
        now.difference(lastPlayedAt) < const Duration(milliseconds: 28)) {
      return;
    }
    _lastPlayedAt = now;
    unawaited(_playTick());
  }

  void playResult() {
    unawaited(_playResult());
  }

  void stop() {}

  Future<void> _playTick() async {
    try {
      if (Platform.isAndroid || Platform.isWindows) {
        await _channel.invokeMethod<void>('tick', <String, dynamic>{
          'volume': appVolumeNotifier.value,
        });
      } else {
        await SystemSound.play(SystemSoundType.click);
      }
    } catch (_) {
      await SystemSound.play(SystemSoundType.click);
    }
  }

  Future<void> _playResult() async {
    try {
      if (Platform.isAndroid || Platform.isWindows) {
        await _channel.invokeMethod<void>('result', <String, dynamic>{
          'volume': appVolumeNotifier.value * 0.65,
        });
      } else {
        await SystemSound.play(SystemSoundType.alert);
      }
    } catch (_) {
      await SystemSound.play(SystemSoundType.alert);
    }
  }
}

enum AppLanguage { tr, en }

final ValueNotifier<AppLanguage> appLanguageNotifier = ValueNotifier(
  AppLanguage.tr,
);

enum AppTheme { summer, winter, feast, newYear, normal }

final ValueNotifier<AppTheme> appThemeNotifier = ValueNotifier<AppTheme>(
  AppTheme.summer,
);
final ValueNotifier<double> appVolumeNotifier = ValueNotifier<double>(1.0);

class _LuuqSettings {
  static final _LuuqSettings instance = _LuuqSettings._();
  _LuuqSettings._();

  AppTheme theme = AppTheme.summer;
  double volume = 1.0;
  String? baristaDrink;
  String? baristaDessert;
  List<String>? wheelItems;

  Future<File> _getFile() async {
    try {
      final dir = await getApplicationSupportDirectory();
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return File('${dir.path}/luuq_settings.json');
    } catch (_) {
      return File('luuq_settings.json');
    }
  }

  Future<void> load() async {
    try {
      final file = await _getFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        final jsonMap = json.decode(content) as Map<String, dynamic>;

        final themeStr = jsonMap['theme'] as String?;
        if (themeStr != null) {
          theme = AppTheme.values.firstWhere(
            (e) => e.name == themeStr,
            orElse: () => AppTheme.summer,
          );
        }

        volume = (jsonMap['volume'] as num?)?.toDouble() ?? 1.0;
        baristaDrink = jsonMap['baristaDrink'] as String?;
        baristaDessert = jsonMap['baristaDessert'] as String?;

        final list = jsonMap['wheelItems'] as List<dynamic>?;
        if (list != null) {
          wheelItems = list.cast<String>();
        }
      }
    } catch (_) {}
  }

  Future<bool> save() async {
    try {
      final file = await _getFile();
      final jsonMap = {
        'theme': theme.name,
        'volume': volume,
        'baristaDrink': baristaDrink,
        'baristaDessert': baristaDessert,
        'wheelItems': wheelItems,
      };
      await file.writeAsString(json.encode(jsonMap));
      return true;
    } catch (error, stackTrace) {
      debugPrint(
        '[SETTINGS] Failed to persist application settings: '
        '$error\n$stackTrace',
      );
      return false;
    }
  }
}

Future<void> _loadAppTheme() async {
  appThemeNotifier.value = _LuuqSettings.instance.theme;
}

Future<bool> _saveAppTheme(AppTheme theme) async {
  final previousTheme = _LuuqSettings.instance.theme;
  _LuuqSettings.instance.theme = theme;
  appThemeNotifier.value = theme;
  final saved = await _LuuqSettings.instance.save();
  if (!saved) {
    _LuuqSettings.instance.theme = previousTheme;
    appThemeNotifier.value = previousTheme;
  }
  return saved;
}

Future<void> _loadAppVolume() async {
  appVolumeNotifier.value = _LuuqSettings.instance.volume;
}

Future<bool> _saveAppVolume(double volume) async {
  final previousVolume = _LuuqSettings.instance.volume;
  _LuuqSettings.instance.volume = volume;
  appVolumeNotifier.value = volume;
  final saved = await _LuuqSettings.instance.save();
  if (!saved) {
    _LuuqSettings.instance.volume = previousVolume;
    appVolumeNotifier.value = previousVolume;
  }
  return saved;
}

Future<void> _saveSettingsInBackground(String source) async {
  final saved = await _LuuqSettings.instance.save();
  if (!saved) {
    debugPrint('[SETTINGS] Background save failed. source=$source');
  }
}

String tr(String trText, String enText) {
  return appLanguageNotifier.value == AppLanguage.tr ? trText : enText;
}

const Map<String, String> _menuDict = {
  'Hafif': 'Light',
  'Güçlü': 'Strong',
  'Ferah': 'Fresh',
  'Tatlı': 'Sweet',
  'Sıcak': 'Warm',
  'Eğlenceli': 'Fun',
  'Dingin': 'Calm',
  'Dengeli': 'Balanced',
  'Filtre Kahve': 'Filter Coffee',
  'Espresso': 'Espresso',
  'Türk Kahvesi': 'Turkish Coffee',
  'Sıcak Çikolata': 'Hot Chocolate',
  'Soğuk Kahve': 'Iced Coffee',
  'Çay': 'Tea',
  'Limonata': 'Lemonade',
  'Meyve Suyu': 'Fruit Juice',
  'Pasta': 'Cake',
  'Kurabiye': 'Cookie',
  'Kek': 'Muffin',
  'Tiramisu': 'Tiramisu',
  'San Sebastian': 'San Sebastian',
  'Kruvasan': 'Croissant',
  'Sandviç': 'Sandwich',
  'Tost': 'Toast',
  'İçecekler': 'Drinks',
  'Tatlılar': 'Desserts',
  'Tüm Modlar': 'All Moods',
  'İçecek': 'Drink',
  'Tümü': 'All',
  // Category names
  'Espresso Kahveler': 'Espresso Coffees',
  'Filtre Kahveler': 'Filter Coffees',
  'Sıcak İçecekler': 'Hot Drinks',
  'Ice Kahveler': 'Iced Coffees',
  'LUUQ Kokteyl': 'LUUQ Cocktail',
  'Bitki Çayları': 'Herbal Teas',
  'Meşrubatlar': 'Soft Drinks',
  'Pasta & Tatlı': 'Pastry & Dessert',
  'LUUQ Chocolate': 'LUUQ Chocolate',
  'Termos & Seramik': 'Thermos & Ceramic',
  'Dondurmalar': 'Ice Creams',
  'Ekstralar': 'Extras',
  // Category descriptions
  'Yoğun, klasik ve taze espresso bazlı favoriler.':
      'Intense, classic and fresh espresso-based favorites.',
  'Özenle seçilmiş yöresel çekirdekler ve özel demlemeler.':
      'Carefully selected regional beans and special brews.',
  'İçinizi ısıtacak geleneksel ve modern sıcak lezzetler.':
      'Traditional and modern hot flavors to warm you up.',
  'Günün her saati ferahlık veren buzlu kahve alternatifleri.':
      'Refreshing iced coffee alternatives for any time of day.',
  'LUUQ imzalı alkolsüz, ferahlatıcı ve özel reçeteli karışımlar.':
      'LUUQ signature non-alcoholic, refreshing special blends.',
  'Doğadan gelen rahatlatıcı ve canlandırıcı özel bitki harmanları.':
      'Relaxing and invigorating herbal blends from nature.',
  'Taze meyvelerle hazırlanan buzlu yaz şölenleri.':
      'Frozen summer treats made with fresh fruits.',
  'Patlayan boba incileriyle dolu eğlenceli ve serinletici lezzetler.':
      'Fun and refreshing flavors full of popping boba pearls.',
  'Kıvamlı, yoğun ve tatlı krizlerine birebir sütlü serinlik.':
      'Thick, creamy milkshakes for your sweet cravings.',
  'Yaz aylarının en serinletici ve leziz dondurma çeşitleri.':
      'The most refreshing and delicious ice cream varieties of the summer months.',
  'Klasik gazozlar, doğal sodalar ve enerji veren içecekler.':
      'Classic sodas, natural sparkling waters and energy drinks.',
  'Kahvenize mükemmel eşlik edecek taptaze, el yapımı tatlılar.':
      'Freshly made, handcrafted desserts to pair with your coffee.',
  'LUUQ ustalarından özel yapım premium artizan çikolatalar.':
      'Premium artisan chocolates handcrafted by LUUQ masters.',
  'Taze ekmeklerle hazırlanan, doyurucu ve leziz atıştırmalıklar.':
      'Satisfying and delicious snacks made with fresh bread.',
  'LUUQ deneyimini gittiğiniz her yere taşıyacak şık tasarımlar.':
      'Stylish designs to carry the LUUQ experience everywhere.',
  'İçeceğinizi tamamen kişiselleştirebileceğiniz ekstra dokunuşlar.':
      'Extra touches to fully customize your drink.',
  'Vanilya': 'Vanilla',
  'Kakao': 'Cocoa',
  'Karamel': 'Caramel',
  'Antep Fıstığı': 'Pistachio',
  'Limon': 'Lemon',
  'Kavun': 'Melon',
  'Çilek': 'Strawberry',
  'Karadut': 'Black Mulberry',
  'Bal Badem': 'Honey Almond',
  'Bubble Gum': 'Bubble Gum',
  'Blue Sky': 'Blue Sky',
  'Meyve Şöleni': 'Fruit Feast',
  'Oreo': 'Oreo',
  'Klasik ve yoğun gerçek vanilya çekirdeği lezzeti.':
      'Classic and intense real vanilla bean flavor.',
  'Yoğun çikolata dolgulu geleneksel kakao keyfi.':
      'Traditional cocoa treat with intense chocolate flavor.',
  'Karamel soslu tatlı ve kremamsı dondurma.':
      'Sweet and creamy ice cream with caramel sauce.',
  'Taze Antep fıstığı parçacıklarıyla zenginleşen lezzet.':
      'Flavor enriched with fresh pistachio pieces.',
  'Ekşi ve ferahlatıcı gerçek limon aroması.':
      'Tart and refreshing real lemon flavor.',
  'Yaz kavununun tatlı ve sulu serinliği.':
      'Sweet and juicy coolness of summer melon.',
  'Taze yaz çilekleriyle hazırlanan meyveli dondurma.':
      'Fruit ice cream prepared with fresh summer strawberries.',
  'Doğal karadut taneleriyle tatlı-ekşi ferahlık.':
      'Sweet-sour refreshment with natural black mulberry grains.',
  'Süzme bal ve çıtır badem parçacıklarının uyumu.':
      'Harmony of strained honey and crunchy almond pieces.',
  'Eğlenceli sakız aromalı çocuksu tat.':
      'Playful bubble gum flavored childhood treat.',
  'Farklı ve özel aromasıyla gökyüzü mavisi lezzet.':
      'Sky blue flavor with a unique and special aroma.',
  'Karışık yaz meyvelerinin eşsiz uyumu.':
      'Unique harmony of mixed summer fruits.',
  'Çıtır Oreo bisküvi parçacıklarıyla kremamsı dondurma.':
      'Creamy ice cream with crunchy Oreo cookie pieces.',
  // Tags
  'Popüler': 'Popular',
  'Yeni': 'New',
  'Klasik': 'Classic',
  'Soğuk': 'Cold',

  'Ahududu ve taze limonun canlandırıcı uyumu':
      'Refreshing harmony of raspberry and fresh lemon',
  'Ananas ve bademin hafif tatlı uyumu':
      'Lightly sweet harmony of pineapple and almond',
  'Antep fıstıklı rüya': 'Pistachio dream',
  'Ağızda patlayan şekerli eğlenceli tatlı': 'Fun dessert with popping candy',
  'Badem kremalı limonlu zarif tart':
      'Elegant tart with almond cream and lemon',
  'Baharatlı çay ve kremamsı süt': 'Spiced tea and creamy milk',
  'Bardakta taze meyveli kat kat lezzet':
      'Layered treat with fresh fruit in a glass',
  'Baskın espresso tadı ve bol köpüklü sıcak süt.':
      'Intense espresso flavor and hot milk with plenty of foam.',
  'Bağışıklık destekleyici zencefil, limon ve bal kürü':
      'Immune-boosting ginger, lemon and honey cure',
  'Beyaz çikolata sevenlere özel spesiyal':
      'Special treat for white chocolate lovers',
  'Beyaz çikolatalı latte': 'White chocolate latte',
  'Beyaz çikolatalı mocha': 'White chocolate mocha',
  'Beyaz çikolatalı süt': 'White chocolate milk',
  'Beyaz çikolatalı şelale tasarımlı pasta':
      'Cake with white chocolate waterfall design',
  'Bol Oreo bisküvili klasik peynir tatlısı':
      'Classic cheesecake with plenty of Oreo cookies',
  'Bol fıstıklı çıtır hamurlu Fransız tartı':
      'French tart with crispy pastry and lots of pistachios',
  'Buz gibi serinletici, şeftali aromalı tatlı siyah çay.':
      'Ice-cold refreshing, peach flavored sweet black tea.',
  'Buz gibi su ve yoğun espresso. Ferahlatıcı ve net.':
      'Ice-cold water and intense espresso. Refreshing and clean.',
  'Buzlu beyaz mocha': 'Iced white mocha',
  'Buzlu filtre kahve': 'Iced filter coffee',
  'Buzlu flat white': 'Iced flat white',
  'Buzlu karamel latte': 'Iced caramel latte',
  'Buzlu karamel macchiato': 'Iced caramel macchiato',
  'Buzlu matcha sütlü': 'Iced matcha latte',
  'Buzlu sade americano': 'Iced black americano',
  'Buzlu sütlü espresso': 'Iced espresso with milk',
  'Buzlu sütlü filtre': 'Iced filter coffee with milk',
  'Ananas, portakal ve limonun ferah tropikal buluşması.':
      'A refreshing tropical blend of pineapple, orange, and lemon.',
  'Buzlu çikolatalı mocha': 'Iced chocolate mocha',
  'Buzlu, karamelli ve sütlü tatlı kahve rüyası.':
      'Iced, caramel and milky sweet coffee dream.',
  'Cam şişede doğal kaynak suyu': 'Natural spring water in a glass bottle',
  'Damla sakızı aromalı sahlep': 'Sahlep flavored with mastic gum',
  'Dev çikolatalı kurabiye turtası': 'Giant chocolate cookie pie',
  'Doğa yeşili tonlarında şık termos': 'Stylish thermos in forest green tones',
  'Doğal mineralli su': 'Natural sparkling mineral water',
  'Doğal mineralli su büyük boy': 'Natural sparkling mineral water large size',
  'Egzotik baharatlı karamel rüyası': 'Exotic spiced caramel dream',
  'Yoğun mango aromasıyla egzotik ve ferah bir frozen.':
      'An exotic and refreshing frozen with intense mango aroma.',
  'Egzotik meyve karışımı': 'Exotic fruit mix',
  'Egzotik yeşil çay ve meyve harmonisi': 'Exotic green tea and fruit harmony',
  'Ekşi vişnelerle dengelenmiş tatlı tart':
      'Sweet tart balanced with sour cherries',
  'El yapımı özel seramik çay demliği': 'Handmade custom ceramic teapot',
  'Enerji veren klasik lezzet': 'Classic energizing flavor',
  'Ergonomik beyaz renkli pratik termos': 'Ergonomic white practical thermos',
  'Erimiş 4 peynirli doyurucu bagel': 'Hearty bagel with 4 melted cheeses',
  'Espresso ile ıslatılmış mascarpone peynirli klasik':
      'Classic tiramisu with espresso-soaked ladyfingers and mascarpone cheese',
  'Espresso ve az süt, sert ve yoğun':
      'Espresso and a dash of milk, strong and intense',
  'Espresso üzerine dondurma': 'Affogato - Ice cream topped with espresso',
  'Meyvemsi notalar, canlı aroma ve hafif çiçeksi bir bitiş.':
      'Fruity notes, vibrant aroma, and a light floral finish.',
  'Farklı aromalarda ekstra şurup ilavesi':
      'Extra syrup addition in different flavors',
  'Ferahlatıcı limon ve canlandırıcı zencefil':
      'Refreshing lemon and invigorating ginger',
  'Ferahlatıcı misket limonu': 'Refreshing lime',
  'Frambuaz ve beyaz çikolata': 'Raspberry and white chocolate',
  'Frambuazlı mocha': 'Raspberry mocha',
  'Fındık kreması dolgulu sıcak kruvasan':
      'Warm croissant filled with hazelnut cream',
  'Fındık ve fıstık dolgulu neşe küpleri':
      'Joy cubes filled with hazelnut and pistachio',
  'Fındıklı karışım': 'Hazelnut mix',
  'Geleneksel demlik çay': 'Traditional brewed pot tea',
  'Geleneksel kesme dondurma formunda pasta':
      'Traditional Turkish style cut ice cream cake',
  'Geleneksel köpüklü Türk kahvesi': 'Traditional frothy Turkish coffee',
  'Geleneksel tahin, karamel ve çilek füzyonu':
      'Traditional fusion of tahini, caramel and strawberry',
  'Gerçek Belçika çikolatası ilavesi': 'Real Belgian chocolate addition',
  'Gerçek çikolata parçalarıyla hazırlanan sıcak, tatlı kış klasiği.':
      'Warm, sweet winter classic prepared with real chocolate chips.',
  'Fındıksı aroma, dolgun gövde ve dengeli kahve karakteri.':
      'Nutty aroma, full body, and a balanced coffee character.',
  'Guava patlaması': 'Guava blast',
  'Günlük taze cabata ekmeğine lezzetler':
      'Flavors on daily fresh ciabatta bread',
  'Günlük taze demlenen, sade ve dengeli klasik filtre kahve.':
      'Daily fresh-brewed, plain, and balanced classic filter coffee.',
  'Günün stresini alan rahatlatıcı papatya ve melisa':
      'Relaxing chamomile and lemon balm to relieve daily stress',
  'Hafif ekşi frambuaz ve yeşil fıstık şöleni':
      'Slightly sour raspberry and green pistachio feast',
  'Haki yeşili dayanıklı çelik termos': 'Khaki green durable steel thermos',
  'Halka şeklinde badem kremalı Fransız tatlısı':
      'Ring-shaped French pastry with almond cream (Paris-Brest)',
  'Hassas mideler için laktozsuz süt alternatifi':
      'Lactose-free milk alternative for sensitive stomachs',
  'Haşhaşlı taze ekmek içinde özel peynir':
      'Special cheese in fresh poppy seed bread',
  'Hindi füme ve yeşillikli hafif öğün':
      'Light meal with smoked turkey and greens',
  'Isı yalıtımlı mat siyah çelik termos': 'Insulated matte black steel thermos',
  'Yuzu ferahlığı ve şeftali tatlılığı bir arada.':
      'Yuzu freshness and peach sweetness combined.',
  'Japon yeşil çayı ve sütün huzur veren lezzeti.':
      'The peaceful taste of Japanese green tea and milk.',
  'Kahvenize ekstra bir shot espresso':
      'An extra shot of espresso for your coffee',
  'Kahverengi tonlarında sızdırmaz termos': 'Leak-proof thermos in brown tones',
  'Karamel aromalı sütlü kahve keyfi': 'Caramel flavored milk coffee pleasure',
  'Karamel sos ve vanilyalı süt': 'Caramel sauce and vanilla milk',
  'Karamelli affogato yorumu': 'Caramel affogato twist',
  'Klasik Beyoğlu gazozu ferahlığı': 'Classic Beyoglu soda freshness',
  'Çilek aroması ve boba incileriyle tatlı, eğlenceli bir içim.':
      'A sweet and fun drink with strawberry aroma and boba pearls.',
  'Dengeli gövde, zarif asidite ve yumuşak içimli filtre kahve.':
      'Balanced body, elegant acidity, and smooth-drinking filter coffee.',
  'Krem renkli zarif çelik termos': 'Elegant cream colored steel thermos',
  'Kremamsı beyaz çikolata ve kavrulmuş fındık':
      'Creamy white chocolate and roasted hazelnuts',
  'Kremamsı süt köpüğü ile klasik İtalyan lezzeti':
      'Classic Italian taste with creamy milk foam',
  'Kuzu kulağı otlu özel tarif': 'Special recipe with sorrel herb',
  'Köpüksü hafifliğiyle yoğun çikolata':
      'Intense chocolate with foamy lightness',
  'Közlenmiş biber ve roast beef eti': 'Roasted peppers and roast beef',
  'Künefe ve fıstık dolgulu meşhur Dubai çikolatası':
      'Famous Dubai chocolate filled with kadayif and pistachio',
  'Orman meyvelerinin tatlı-ekşi ferahlığıyla hazırlanır.':
      'Prepared with the sweet and sour freshness of forest berries.',
  'Kızarmış marshmallow ve çikolatalı kupa':
      'Toasted marshmallow and hot chocolate mug',
  'Limon ferahlığıyla beyaz çikolatalı blondie':
      'White chocolate blondie with lemon freshness',
  'Limonlu soğuk kahve': 'Iced coffee with lemon',
  'Luuq ustalarından özel çikolata lokumu':
      'Special chocolate delight from LUUQ masters',
  'Yoğun mango aroması ve boba incileriyle tropik lezzet.':
      'A tropical flavor with intense mango aroma and boba pearls.',
  'Mat siyah geniş hacimli mug termos': 'Matte black large capacity travel mug',
  'Matcha karışım kokteyl': 'Matcha mix cocktail',
  'Minimal beyaz tasarımlı kompakt termos':
      'Compact thermos with minimal white design',
  'Misket limonu kremalı hafif ekler': 'Light eclairs with lime cream',
  'Modern gri tasarımlı günlük termos': 'Daily thermos with modern gray design',
  'Nane ferahlığıyla zenginleşen serin limonata keyfi.':
      'Cool lemonade pleasure enriched with mint freshness.',
  'Naneli mocha': 'Mint mocha',
  'Oreo bisküvi parçalı latte': 'Oreo biscuit chunk latte',
  'Oreo parçalı buzlu latte': 'Iced latte with Oreo pieces',
  'Orijinal Lotus bisküvi kremalı porsiyonluk ekler':
      'Individual eclairs with original Lotus biscuit cream',
  'Orijinal Nutella ile hazırlanan yoğun lezzet':
      'Intense flavor prepared with original Nutella',
  'Renk değiştiren büyüleyici kokteyl': 'Mesmerizing color-changing cocktail',
  'Reyhan aromalı efsanevi gazoz': 'Legendary sweet basil flavored soda',
  'Rose gold renkli şık çelik termos': 'Stylish steel thermos in rose gold',
  'Rubika özel mocha': 'Rubika special mocha',
  'Sade ve güçlü espresso suyla buluşur':
      'Plain and strong espresso meets water',
  'San Sebastian tarzı yanık üst kabuklu':
      'San Sebastian style burnt-top cheesecake',
  'Soğuk suda saatlerce demlenmiş, yumuşak içimli yüksek kafein.':
      'Brewed in cold water for hours, smooth taste with high caffeine.',
  'Taze filtre kahvenin sütle yumuşatılmış sıcak yorumu.':
      'Warm milk-softened version of fresh filter coffee.',
  'Tabağıyla birlikte el yapımı kahve kupası':
      'Handmade coffee mug with saucer',
  'Tam tahıllı ekmek, ezine peyniri ve domates':
      'Whole grain bread, ezine cheese and tomato',
  'Taptaze meyveler ve boba incileriyle ferah bir bubble tea.':
      'A refreshing bubble tea with fresh fruits and boba pearls.',
  'Tarçın aromalı geleneksel sahlep': 'Traditional sahlep with cinnamon aroma',
  'Tarçın ve karamelize elmalı çıtır tart':
      'Crispy tart with cinnamon and caramelized apple',
  'Tatlı ekşi karışım': 'Sweet and sour mix',
  'Tatlı sunumları için özel tasarım tabak':
      'Specially designed plate for sweet servings',
  'Tatlı çikolatanın sıcak kahveyle efsane uyumu.':
      'Legendary harmony of sweet chocolate with hot coffee.',
  'Tatlınıza veya içeceğinize ekstra çikolata/karamel sos':
      'Extra chocolate/caramel sauce to your dessert or drink',
  'Taze fırınlanmış badem kremalı kruvasan':
      'Freshly baked croissant with almond cream',
  'Taze muz dilimleri ilavesi': 'Fresh banana slice addition',
  'Taze yeşilliklerle dana jambonlu sandviç':
      'Beef ham sandwich with fresh greens',
  'Taze çilek dilimleri ilavesi': 'Fresh strawberry slice addition',
  'Tek kişilik taze meyveli hafif pasta': 'Light fresh fruit cake for one',
  'Tek kişilik özel tasarım kahve seti': 'Custom design coffee set for one',
  'Tek kullanımlık doğal süzme bal': 'Single-use natural strained honey',
  'Tek shot espresso': 'Single shot espresso',
  'Tost makinesinde ısıtılmış kaşarlı panini':
      'Panini with kashar cheese toasted in press',
  'Tropik meyveler ve yeşil elma boba ile canlı bir içim.':
      'A vibrant drink with tropical fruits and green apple boba.',
  'Tropikal lezzet': 'Tropical flavor',
  'Tropikal meyveli serinletici kokteyl': 'Refreshing tropical fruit cocktail',
  'Türk kahveli özel kokteyl': 'Special cocktail with Turkish coffee',
  'Uzak doğunun mistik bitkisel lezzeti':
      'Mystic herbal flavor of the Far East',
  '12 saat soğuk demleme, yumuşak içim ve ferah kahve aroması.':
      '12 hours cold brew, smooth taste, and refreshing coffee aroma.',
  'Vanilya ve kakaolu klasik mermer kek':
      'Classic marble cake with vanilla and cocoa',
  'Vanilya ve matcha füzyonu': 'Vanilla and matcha fusion',
  'Vanilya şurubu, sıcak süt, espresso ve nefis karamel.':
      'Vanilla syrup, hot milk, espresso and delicious caramel.',
  'Vanilyalı altın kokteyl': 'Vanilla gold cocktail',
  'Waffle aromalı taze sıkım': 'Freshly squeezed juice with waffle aroma',
  'Yanık kabuklu, akışkan içiyle İspanyol klasiği':
      'Spanish classic with burnt crust and creamy interior',
  'Karpuzun serinliği, çileğin tatlı aromasıyla birleşir.':
      'The coolness of watermelon meets the sweet aroma of strawberry.',
  'Yoğun bitter çikolata ve taze portakal aroması':
      'Intense dark chocolate and fresh orange flavor',
  'Yoğun fıstıklı dilimlenmiş dev cheesecake':
      'Giant sliced cheesecake with intense pistachio',
  'Yoğun kakao lezzeti': 'Intense cocoa flavor',
  'Yulaf ezmeli sağlıklı sandviç seçeneği': 'Healthy oatmeal sandwich option',
  'Yumuşak içimli sıcak süt ve dengeli espresso.':
      'Smooth hot milk and balanced espresso.',
  'Yumuşak sütlü espresso klasiği': 'Soft milk espresso classic',
  'Zencefil aromalı serinletici gazoz': 'Refreshing ginger flavored soda',
  'Zencefilli ejderha meyveli': 'Ginger dragon fruit',
  'Zeytinyağlı foccacia arası ezine': 'Ezine cheese in olive oil focaccia',
  'Çarkıfelek meyvesi ve çikolata buluşması':
      'Passion fruit and chocolate meeting',
  'Çift pişirme Türk kahvesi': 'Double brewed Turkish coffee',
  'Çift shot espresso': 'Double shot espresso',
  'Çikolata ve espresso buluşması': 'Chocolate and espresso meeting',
  'Çilek aromasıyla canlanan ferah ve serin limonata.':
      'Fresh and cool lemonade enlivened with strawberry aroma.',
  'Çilek, vanilya ve sihirli süslemeler':
      'Strawberry, vanilla and magic decorations',
  'Çilekli misket limonu': 'Strawberry lime',
  'Çocukların favorisi çikolatalı özel pasta':
      'Special chocolate cake - kids\' favorite',
  'Çıtır gofret parçalı rüya gibi çikolata':
      'Dreamlike chocolate with crispy wafer pieces',
  'Çıtır haşhaş ve taze limonlu kek dilimi':
      'Cake slice with crunchy poppy seeds and fresh lemon',
  'Özel baharatlar ve Madagaskar vanilyası harmanı':
      'Blend of special spices and Madagascar vanilla',
  'Özel cam şişede premium maden suyu':
      'Premium sparkling water in a special glass bottle',
  'Özel kubbe tasarım çikolatalı pasta': 'Special dome design chocolate cake',
  'Özel şekliyle orman meyveli çıtır tart':
      'Crispy tart with wild berries in a special shape',
  'Üstü dondurmalı sahlep': 'Sahlep topped with ice cream',
  'Üç çikolatalı yoğun brownie': 'Rich triple chocolate brownie',
  'İki kişilik şık Türk kahvesi fincan takımı':
      'Elegant Turkish coffee cup set for two',
  'İnce dokulu süt ile kadifemsi espresso':
      'Velvety espresso with microfoam milk',
  'İncecik süt köpüğü altında yoğun espresso deneyimi.':
      'Intense espresso experience under a thin layer of milk foam.',
  'İtalyan ekmeğinde ince dilim hindi füme':
      'Thinly sliced smoked turkey in Italian bread',
  'İtalyan klasiği; yoğun, sert ve uyanış garantili.':
      'Italian classic; intense, strong and guaranteed awakening.',
  'İtalyan pesto soslu ızgara tavuk':
      'Grilled chicken with Italian pesto sauce',
  'İçecekler için ekstra meyve püresi': 'Extra fruit puree for drinks',
  'İçeceğinize ekstra patlayan meyve incileri':
      'Extra popping fruit boba pearls for your drink',
  'İçeceğinize fındık aromalı bitkisel süt':
      'Hazelnut flavored plant-based milk for your drink',
  'İçeceğinize vegan badem sütü alternatifi':
      'Vegan almond milk alternative for your drink',
  'İçeceğinize vegan yulaf sütü alternatifi':
      'Vegan oat milk alternative for your drink',
  'İçeceğinizin veya tatlınızın yanına bir top dondurma':
      'A scoop of ice cream on the side of your drink or dessert',
  'İçeceğinizin üzerine taze krem şanti':
      'Fresh whipped cream on top of your drink',
  'İçi bol fıstıklı çıtır cheesecake':
      'Crispy cheesecake with plenty of pistachios inside',
  'İçi taze krema dolgulu çikolata topları':
      'Chocolate balls filled with fresh cream',
  'İçi ıslak, vişne taneli brownie rüyası':
      'Fudgy brownie dream with sour cherry pieces',

  // --- Missing Drink and Food Translations ---
  // Filtre & Sıcak Kahveler
  'Filtre Sütlü': 'Filter Coffee with Milk',
  'Klasik Filtre': 'Classic Filter Coffee',
  'Guatamala': 'Guatemala',
  'Damla Sakızlı Sahlep': 'Sahlep with Mastic Gum',
  'Dondurma Sahlep': 'Sahlep with Ice Cream',
  'Double Türk Kahvesi': 'Double Turkish Coffee',
  'Frambuazlı Sıcak Beyaz Çikolata': 'Raspberry Hot White Chocolate',
  'Tarçınlı Sahlep': 'Sahlep with Cinnamon',

  // Ice & Soğuk Kahveler
  'Ice Filtre Kahve': 'Iced Filter Coffee',
  'Ice Sütlü Filtre Kahve': 'Iced Filter Coffee with Milk',

  // Kokteyller & Bitki Çayları
  'Luuq Kuzu Kulağı Kokteyl': 'Luuq Sorrel Cocktail',
  'Ahududu Limon': 'Raspberry Lemon',
  'Gripsavar': 'Flu Fighter',
  'Limon Zencefil': 'Lemon Ginger',

  // Frozen & Bubble Tea
  'Frozen Ananas & Portakal & Limon': 'Frozen Pineapple & Orange & Lemon',
  'Frozen Karpuz & Çilek': 'Frozen Watermelon & Strawberry',
  'Frozen Orman Meyveleri': 'Frozen Forest Berries',
  'Frozen Yuzu & Şeftali': 'Frozen Yuzu & Peach',
  'Çilekli Limonata': 'Strawberry Lemonade',
  'Naneli Limonata': 'Mint Lemonade',

  // Milkshakeler & Meşrubatlar
  'Milkshake Beyaz Çikolata & Fındık': 'White Chocolate & Hazelnut Milkshake',
  'Milkshake Bitter & Portakal': 'Dark Chocolate & Orange Milkshake',
  'Milkshake Nutella': 'Nutella Milkshake',
  'Milkshake Tahin & Karamel & Çilek': 'Tahini, Caramel & Strawberry Milkshake',
  'Beyoğlu Klasik': 'Beyoglu Classic Soda',
  'Beyoğlu Reyhan': 'Beyoglu Basil Soda',
  'Beyoğlu Zencefil': 'Beyoglu Ginger Soda',
  'Damla Soda (200 ml)': 'Damla Mineral Water (200 ml)',
  'Damla Soda (330 ml)': 'Damla Mineral Water (330 ml)',
  'Damla Cam Su (330 ml)': 'Damla Still Water (330 ml)',
  'Uludağ Premium Soda': 'Uludag Premium Mineral Water',

  // Pastalar & Tatlılar
  'Allgo Dom Pasta': 'Allgo Dome Cake',
  'Ananas Badem Mono Pasta': 'Pineapple Almond Mono Cake',
  'Antep Dolgulu Cheesecake': 'Pistachio Filled Cheesecake',
  'Antep Fıstıklı Tart': 'Pistachio Tart',
  'Bademli Kruvasan': 'Almond Croissant',
  'Blondie Limon': 'Lemon Blondie',
  'Cheesecake Patlayan Şeker': 'Popping Candy Cheesecake',
  'Cheesecake San Sebastian': 'San Sebastian Cheesecake',
  'Çikolatalı Cookie Pie': 'Chocolate Cookie Pie',
  'Çikolatalı Tırtıl Pasta': 'Chocolate Caterpillar Cake',
  'Elmalı Tart': 'Apple Tart',
  'Fındıklı Kruvasan': 'Hazelnut Croissant',
  'Frambuaz & Antep Fıstıklı Kek': 'Raspberry & Pistachio Cake',
  'Frambuazlı Mono Pasta': 'Raspberry Mono Cake',
  'Kesme Fındıklı Pasta': 'Slices of Hazelnut Ice Cream Cake',
  'Lime Ekler': 'Lime Eclairs',
  'Limon & Frangipane Tart': 'Lemon & Frangipane Tart',
  'Limon & Haşhaşlı Baton Kek': 'Lemon & Poppy Seed Loaf Cake',
  'Lotus Mono Ekler': 'Lotus Mono Eclairs',
  'Luuq Çikolatalı Mousse Pasta': 'LUUQ Chocolate Mousse Cake',
  'Mermer Baton Kek': 'Classic Marble Loaf Cake',
  'Orman Meyveli Cup': 'Wild Berry Cup Dessert',
  'Orman Meyveli Elips Tart': 'Wild Berry Ellipse Tart',
  'Passion & Çikolatalı Tart': 'Passion Fruit & Chocolate Tart',
  'Smores Cup': 'S\'mores Cup Dessert',
  'Trio Chocolate Browni': 'Trio Chocolate Brownie',
  'Üçgen Dilim Fıstıklı Cheesecake': 'Triangle Slice Pistachio Cheesecake',
  'Vişneli Tart': 'Cherry Tart',
  'Vişneli Brownie': 'Cherry Brownie',
  'White Cascada Dom Pasta': 'White Cascada Dome Cake',
  'Yanık Cheesecake': 'Burnt Cheesecake',

  // Sandviçler
  'Dana Jambon': 'Beef Ham',
  'Haşhaşlı Cabata Sandviç': 'Poppy Seed Ciabatta Sandwich',
  'Ezine Peynirli Tahıllı Cabata Sandviç':
      'Ezine Cheese Whole Grain Ciabatta Sandwich',
  'Haşhaşlı 4 Peynirli Bagel Sandviç': 'Poppy Seed 4-Cheese Bagel Sandwich',
  'Haşhaşlı Cabata Hindi Füme Tahıllı':
      'Poppy Seed Whole Grain Smoked Turkey Ciabatta',
  'Cabata Sandviç': 'Ciabatta Sandwich',
  'Pesto Soslu Tavuklu Sandviç': 'Pesto Chicken Sandwich',
  'Tahıllı Üçgen Panini': 'Whole Grain Triangle Panini',
  'Yedi Foccacia Ezine Peynirli Sandviç':
      'Olive Oil Focaccia Ezine Cheese Sandwich',
  'Yedi Foccacia Hindi Sandviç': 'Olive Oil Focaccia Turkey Sandwich',
  'Yedi Roast Beef Sandviç': 'Roast Beef Sandwich',
  'Yulaflı Cabata': 'Oatmeal Ciabatta',

  // Termos & Seramikler
  'Seramik Demlik': 'Ceramic Teapot',
  'Seramik Double Türk Kahvesi Seti': 'Ceramic Double Turkish Coffee Cup Set',
  'Seramik Kupa - Altlık': 'Handmade Ceramic Mug & Saucer',
  'Seramik Pasta Tabağı': 'Ceramic Dessert Plate',
  'Seramik Türk Kahvesi Seti': 'Ceramic Turkish Coffee Cup Set',
  'Trm04s Rose 400 ml Termos': 'Trm04s Rose 400 ml Thermos',
  'Trm094 Beyaz Ofset 350 ml Çelik Termos':
      'Trm094 White Offset 350 ml Steel Thermos',
  'Trm094 K.rengi Ofset 350 ml Çelik Termos':
      'Trm094 Brown Offset 350 ml Steel Thermos',
  'Trm119 Siyah 500 ml Çelik Mug Termos':
      'Trm119 Black 500 ml Steel Travel Mug',
  'Trm159 Haki 350 ml Çelik Termos': 'Trm159 Khaki 350 ml Steel Thermos',
  'Trm159 Krem 350 ml Çelik Termos': 'Trm159 Cream 350 ml Steel Thermos',
  'Trm175 Siyah 500 ml Çelik Termos': 'Trm175 Black 500 ml Steel Thermos',
  'Trm173 Yeşil 350 ml Çelik Termos': 'Trm173 Green 350 ml Steel Thermos',
  'Trm185-B 380 ml Beyaz Termos': 'Trm185-B 380 ml White Thermos',
  'Trm185-G 380 ml Gri Termos': 'Trm185-G 380 ml Gray Thermos',

  // Ekstralar
  'Bademli Süt': 'Almond Milk',
  'Bubble': 'Boba Pearls',
  'Balparmak (7 gr)': 'Balparmak Honey (7g)',
  'Calebaut': 'Callebaut Chocolate',
  'Dondurma': 'Ice Cream',
  'Ekstra Çilek (Meyve)': 'Extra Strawberry (Fruit)',
  'Ekstra Muz (Meyve)': 'Extra Banana (Fruit)',
  'Laktozsuz Süt': 'Lactose-Free Milk',
  'Fındık Süt': 'Hazelnut Milk',
  'Krema': 'Cream',
  'Püre': 'Puree',
  'Shot': 'Espresso Shot',
  'Sos': 'Sauce',
  'Şurup': 'Syrup',
  'Yulaf Süt': 'Oat Milk',
};

String trMenu(String text) {
  if (appLanguageNotifier.value == AppLanguage.tr) return text;
  return _menuDict[text] ?? text;
}

class LuuqApp extends StatelessWidget {
  const LuuqApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: appLanguageNotifier,
      builder: (context, language, child) {
        return MaterialApp(
          navigatorKey: navigatorKey,
          debugShowCheckedModeBanner: false,
          title: 'LUUQ Kiosk',
          builder: (context, child) {
            return MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.0)),
              child: child!,
            );
          },
          scrollBehavior: const MaterialScrollBehavior().copyWith(
            dragDevices: {
              PointerDeviceKind.mouse,
              PointerDeviceKind.touch,
              PointerDeviceKind.stylus,
              PointerDeviceKind.unknown,
            },
          ),
          theme: ThemeData(
            useMaterial3: true,
            scaffoldBackgroundColor: _bgDark,
            colorScheme: ColorScheme.fromSeed(
              seedColor: _caramel,
              brightness: Brightness.dark,
              surface: _surface,
            ),
            textTheme: ThemeData.dark().textTheme.apply(
              bodyColor: _cream,
              displayColor: _cream,
              fontFamily: 'Roboto',
            ),
            pageTransitionsTheme: const PageTransitionsTheme(
              builders: {
                TargetPlatform.android: ZoomPageTransitionsBuilder(),
                TargetPlatform.iOS: ZoomPageTransitionsBuilder(),
                TargetPlatform.macOS: ZoomPageTransitionsBuilder(),
                TargetPlatform.windows: ZoomPageTransitionsBuilder(),
                TargetPlatform.linux: ZoomPageTransitionsBuilder(),
                TargetPlatform.fuchsia: ZoomPageTransitionsBuilder(),
              },
            ),
          ),
          home: const LicenseGate(),
        );
      },
    );
  }
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
  int? _lastWheelTickIndex;
  _MenuItem? _baristaDrink;
  _MenuItem? _baristaDessert;
  late List<_MenuItem> _wheelMenuItems = _defaultWheelMenuItems();
  int _logoTapCount = 0;
  Timer? _logoTapTimer;
  bool _hasTrackedUpdateSeen = false;

  bool _isLoading = true;
  double _loadingProgress = 0.0;
  bool _isAppActive = true;
  String _loadingStatus = 'Sistem yükleniyor...';

  // Idle state handling
  Timer? _idleTimer;
  bool _isIdle = true;
  bool _isInCleaningMode = false;
  final _spinSound = _SpinTickSound();

  void _showProductDetailDialog(_MenuItem item) {
    if (!currentFeatureFlags.menu) {
      showFeatureLockedDialog(context, tr('Ürün Detayı', 'Product Detail'));
      return;
    }
    showDialog(
      context: context,
      builder: (context) =>
          _VirtualCanvasDialogWrapper(child: _ProductDetailDialog(item: item)),
    );
  }

  Widget _buildUpdateBadge(BuildContext context, LicenseStatus status) {
    if (!_hasTrackedUpdateSeen) {
      _hasTrackedUpdateSeen = true;
      AnalyticsService.instance.trackEvent(
        AnalyticsEvent(eventType: 'update_available_seen', screen: 'home'),
      );
    }
    return InkWell(
      onTap: () {
        AnalyticsService.instance.trackEvent(
          AnalyticsEvent(eventType: 'update_prompt_opened', screen: 'home'),
        );
        _showUpdateDialog(context, status);
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF9AB3E).withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: const Color(0xFFF9AB3E).withValues(alpha: 0.5),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Color(0xFFF9AB3E),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              tr('Yeni Sürüm Mevcut', 'New Version Available'),
              style: const TextStyle(
                color: Color(0xFFFFF7EC),
                fontSize: 14,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
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
    _idleTimer?.cancel();
    if (_isInCleaningMode) return;
    if (GlobalDialogTracker.shouldPauseIdleTimer()) return;
    if (_isIdle) {
      if (!fromTap) return;
      setState(() => _isIdle = false);
    }
    _idleTimer = Timer(const Duration(seconds: 15), () {
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
        if (_videoController != null && _videoController!.value.isInitialized) {
          _videoController!.play();
        }
      }
    });
  }

  _MenuItem? _findMenuItemByName(String name) {
    for (final list in _menuCategories.values) {
      for (final item in list) {
        if (item.name == name) {
          return item;
        }
      }
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    activeInstance = this;
    UpdateService.enableKioskMode();
    FeatureSyncService.instance.start();
    LicenseService.instance.statusNotifier.addListener(
      _handleLicenseStatusChange,
    );

    // Load persisted wheel items
    if (_LuuqSettings.instance.wheelItems != null) {
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
      _baristaDrink = _findMenuItemByName(_LuuqSettings.instance.baristaDrink!);
    }
    if (_LuuqSettings.instance.baristaDessert != null) {
      _baristaDessert = _findMenuItemByName(
        _LuuqSettings.instance.baristaDessert!,
      );
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

  Future<void> _initVideo() async {
    try {
      if (Platform.isWindows) {
        // Add a small delay to prevent D3D surface binding errors during hot restart
        await Future.delayed(const Duration(milliseconds: 300));

        // On Windows, asset videos must be loaded from the data directory
        final exePath = Platform.resolvedExecutable;
        final exeDir = File(exePath).parent.path;
        final videoPath = '$exeDir/data/flutter_assets/assets/luuqtanitim.mp4';
        _videoController = VideoPlayerController.file(File(videoPath));
      } else {
        // On Android/iOS, natively use asset loader
        _videoController = VideoPlayerController.asset(
          'assets/luuqtanitim.mp4',
        );
      }

      await _videoController!.setLooping(true);
      await _videoController!.setVolume(0.0);
      await _videoController!.initialize();

      if (mounted) {
        setState(() {});
        if (_isAppActive) {
          _videoController!.play();
        }
      }
    } catch (e) {
      debugPrint('Video init error: $e');
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
      const AssetImage('assets/logo.png'),
      const AssetImage('assets/instagramqr.png'),
      const AssetImage('assets/mapsqr.png'),
      const AssetImage('assets/wifiqr.png'),
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
        _videoController != null &&
        _videoController!.value.isInitialized) {
      _videoController!.play();
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
        providers.add(AssetImage(wheelPath));
      }
    }
    for (final category in _menuCategories.values) {
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
      if (!_pulseController.isAnimating) {
        _pulseController.repeat(reverse: true);
      }
      if (_videoController?.value.isInitialized ?? false) {
        unawaited(_videoController!.play());
      }
      if (!_isLoading && !_isIdle) {
        _resetIdleTimer();
      }
      return;
    }

    _idleTimer?.cancel();
    _pulseController.stop(canceled: false);
    if (_videoController?.value.isInitialized ?? false) {
      unawaited(_videoController!.pause());
    }
  }

  Widget _buildLoadingScreen() {
    return Container(
      decoration: const BoxDecoration(
        color: _bgDark,
        gradient: RadialGradient(
          colors: [Color(0xFF282136), _bgDark],
          radius: 1.2,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Pulsing Logo
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                final scale = 0.96 + (_pulseController.value * 0.08);
                return Transform.scale(scale: scale, child: child);
              },
              child: Image.asset(
                'assets/logo.png',
                width: 250,
                height: 250,
                fit: BoxFit.contain,
                errorBuilder: (c, e, s) => const Icon(
                  Icons.restaurant_menu_rounded,
                  color: _gold,
                  size: 100,
                ),
              ),
            ),
            const SizedBox(height: 48),
            // Brand Subtitle
            Text(
              tr('LUUQ COFFEE ROASTERY', 'LUUQ COFFEE ROASTERY'),
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: 8,
                color: _gold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              tr('LEZZET DENEYİMİ YÜKLENİYOR', 'LOADING FLAVOR EXPERIENCE'),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                letterSpacing: 4,
                color: _cream.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 60),
            // Progress Bar Container
            Container(
              width: 500,
              height: 8,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withValues(alpha: 0.03)),
              ),
              child: Stack(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 100),
                    width: 500 * _loadingProgress,
                    height: 8,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [_gold, _caramel]),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: _gold.withValues(alpha: 0.4),
                          blurRadius: 12,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // Status Text
            Text(
              _loadingStatus,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: _cream.withValues(alpha: 0.7),
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    if (activeInstance == this) {
      activeInstance = null;
    }
    FeatureSyncService.instance.stop();
    LicenseService.instance.statusNotifier.removeListener(
      _handleLicenseStatusChange,
    );
    GestureBinding.instance.pointerRouter.removeGlobalRoute(
      _handleGlobalPointerEvent,
    );
    appLanguageNotifier.removeListener(_handleLanguageChange);
    appThemeNotifier.removeListener(_handleThemeChange);
    appVolumeNotifier.removeListener(_handleVolumeChange);
    WidgetsBinding.instance.removeObserver(this);
    _spinSound.stop();
    _spinController.dispose();
    _pulseController.dispose();
    _videoController?.dispose();
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

  void _toggleMood(DrinkMood mood) {
    if (_spinController.isAnimating) return;
    setState(() {
      _showResult = false;
      if (_selectedMood == mood) {
        _selectedMood = null;
      } else {
        _selectedMood = mood;
      }
    });
    _resetIdleTimer();
  }

  void _handleSpinFrame() {
    _playWheelCollisionIfNeeded(_filteredDrinks, _spinController.value);
  }

  void _startWheelCollisionTracking(List<Drink> available, double turns) {
    _lastWheelTickIndex = _wheelTickIndex(available, turns);
  }

  void _playWheelCollisionIfNeeded(List<Drink> available, double turns) {
    final tickIndex = _wheelTickIndex(available, turns);
    if (tickIndex == null) return;

    final lastTickIndex = _lastWheelTickIndex;
    if (lastTickIndex == null) {
      _lastWheelTickIndex = tickIndex;
      return;
    }

    if (tickIndex != lastTickIndex) {
      _lastWheelTickIndex = tickIndex;
      _spinSound.playTick();
    }
  }

  int? _wheelTickIndex(List<Drink> available, double turns) {
    if (available.isEmpty) return null;
    final segmentTurns = 1 / available.length;
    return (turns / segmentTurns).floor();
  }

  String _findCategoryForDrink(Drink drink) {
    for (final entry in _menuCategories.entries) {
      for (final item in entry.value) {
        if (item.name == drink.fullName || item.name == drink.shortName) {
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

    final spinDuration = duration ?? const Duration(milliseconds: 5000);
    _spinController.duration = spinDuration;

    setState(() {
      _showResult = false;
      _isIdle = false; // Never idle while spinning
    });

    _startWheelCollisionTracking(available, _spinController.value);

    _spinController.animateTo(targetTurns, curve: curve).whenComplete(() {
      _spinSound.stop();
      if (!mounted) return;
      setState(() {
        _selectedDrink = nextDrink;
        _showResult = true;
        _lastWheelTickIndex = null;
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
                          if (_videoController != null &&
                              _videoController!.value.isInitialized)
                            SizedBox.expand(
                              child: FittedBox(
                                fit: BoxFit.cover,
                                child: SizedBox(
                                  width: _videoController!.value.size.width,
                                  height: _videoController!.value.size.height,
                                  child: VideoPlayer(_videoController!),
                                ),
                              ),
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
                                                          fit: BoxFit.contain,
                                                          errorBuilder:
                                                              (
                                                                context,
                                                                error,
                                                                stackTrace,
                                                              ) {
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
                                                                            FontWeight.bold,
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
                                                              0.09,
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
                                                              angle: 0.15,
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
                                                  color: const Color(
                                                    0xFF1C1724,
                                                  ).withValues(alpha: 0.8),
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
                                                        fontSize: 13,
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
                                                                fontSize: 11,
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

  Widget _buildAfkOverlayContent(BoxConstraints constraints) {
    final isCompact = constraints.maxWidth < 700;
    final horizontalPadding = isCompact ? 16.0 : 32.0;
    final contentWidth = min(
      constraints.maxWidth - (horizontalPadding * 2),
      isCompact ? 520.0 : 720.0,
    );

    return Stack(
      children: [
        if (appThemeNotifier.value == AppTheme.feast)
          const _FeastThemeCandyRain(count: 15),
        Align(
          alignment: Alignment(0, isCompact ? 0.70 : 0.78),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: SizedBox(
                width: contentWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, child) {
                        final offset = -1.4 + (_pulseController.value * 2.8);
                        return ShaderMask(
                          blendMode: BlendMode.srcIn,
                          shaderCallback: (bounds) {
                            return LinearGradient(
                              colors: const [
                                Colors.white,
                                Colors.white,
                                _gold,
                                _caramel,
                                Colors.white,
                                Colors.white,
                              ],
                              stops: const [0.0, 0.30, 0.45, 0.52, 0.68, 1.0],
                              begin: Alignment(offset - 1.0, 0),
                              end: Alignment(offset + 1.0, 0),
                            ).createShader(bounds);
                          },
                          child: child,
                        );
                      },
                      child: Text(
                        appThemeNotifier.value == AppTheme.feast
                            ? tr('BAYRAMINIZ KUTLU OLSUN', 'HAPPY EID')
                            : tr('HOŞGELDİNİZ', 'WELCOME'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: isCompact
                              ? (appThemeNotifier.value == AppTheme.feast
                                    ? 28
                                    : 38)
                              : (appThemeNotifier.value == AppTheme.feast
                                    ? 46
                                    : 56),
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: isCompact ? 2 : 4,
                        ),
                      ),
                    ),
                    SizedBox(height: isCompact ? 16 : 22),
                    _buildAfkConnections(isCompact: isCompact),
                    SizedBox(height: isCompact ? 20 : 28),
                    AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, child) {
                        return Text(
                          tr(
                            'Başlamak için ekrana dokunun',
                            'Tap the screen to start',
                          ),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: isCompact ? 16 : 24,
                            fontWeight: FontWeight.w500,
                            color: Colors.white.withValues(
                              alpha:
                                  0.9 *
                                  (0.3 + (_pulseController.value * 0.7)).clamp(
                                    0.0,
                                    1.0,
                                  ),
                            ),
                          ),
                        );
                      },
                      child: Text(
                        tr(
                          'Başlamak için ekrana dokunun',
                          'Tap the screen to start',
                        ),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: isCompact ? 16 : 24,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withValues(alpha: 0.88),
                          letterSpacing: isCompact ? 1.5 : 3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAfkConnections({required bool isCompact}) {
    final qrSize = isCompact ? 62.0 : 88.0;
    final cardWidth = isCompact ? double.infinity : 560.0;
    final slideDistance = isCompact ? 0.08 : 0.12;

    return TweenAnimationBuilder<Offset>(
      key: ValueKey(_isIdle),
      tween: Tween<Offset>(
        begin: _isIdle ? Offset(-slideDistance, 0) : Offset.zero,
        end: _isIdle ? Offset.zero : Offset(slideDistance, 0),
      ),
      duration: const Duration(milliseconds: 1400),
      curve: Curves.easeInOutQuint,
      builder: (context, offset, child) {
        return FractionalTranslation(translation: offset, child: child);
      },
      child: Container(
        width: cardWidth,
        padding: EdgeInsets.symmetric(
          horizontal: isCompact ? 14 : 22,
          vertical: isCompact ? 14 : 18,
        ),
        decoration: BoxDecoration(
          color: _surface.withValues(alpha: 0.34),
          borderRadius: BorderRadius.circular(isCompact ? 24 : 30),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.22),
              blurRadius: 28,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              tr('BAĞLANTILARIMIZ', 'OUR CONNECTIONS'),
              style: TextStyle(
                color: _gold,
                fontSize: 13,
                fontWeight: FontWeight.w900,
                letterSpacing: 3,
              ),
            ),
            SizedBox(height: isCompact ? 12 : 14),
            Row(
              children: [
                Expanded(
                  child: _buildAfkQrItem(
                    assetPath: 'assets/instagramqr.png',
                    title: 'INSTAGRAM',
                    size: qrSize,
                  ),
                ),
                _buildAfkDivider(isCompact),
                Expanded(
                  child: _buildAfkQrItem(
                    assetPath: 'assets/mapsqr.png',
                    title: 'GOOGLE MAPS',
                    size: qrSize,
                  ),
                ),
                _buildAfkDivider(isCompact),
                Expanded(
                  child: _buildAfkQrItem(
                    assetPath: 'assets/wifiqr.png',
                    title: 'LUUQ WI-FI',
                    size: qrSize,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAfkDivider(bool isCompact) {
    return Container(
      width: 1,
      height: isCompact ? 58 : 78,
      margin: EdgeInsets.symmetric(horizontal: isCompact ? 6 : 10),
      color: Colors.white.withValues(alpha: 0.13),
    );
  }

  Widget _buildAfkQrItem({
    required String assetPath,
    required String title,
    required double size,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.asset(
            assetPath,
            width: size,
            height: size,
            fit: BoxFit.cover,
          ),
        ),
        const SizedBox(height: 8),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            title,
            maxLines: 1,
            style: const TextStyle(
              color: _cream,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
            ),
          ),
        ),
      ],
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
    _idleTimer?.cancel();
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
          await showDialog<void>(
            // ignore: use_build_context_synchronously
            context: context,
            barrierDismissible: true,
            builder: (_) => _VirtualCanvasDialogWrapper(
              child: _BaristaAdminDialog(
                drinkOptions: _recommendationDrinkOptions,
                dessertOptions: _recommendationDessertOptions,
                selectedDrink: _currentBaristaDrink,
                selectedDessert: _currentBaristaDessert,
                blockedItems: _wheelMenuItems,
                onSave: (drink, dessert) {
                  setState(() {
                    _baristaDrink = drink;
                    _baristaDessert = dessert;
                  });
                  _LuuqSettings.instance.baristaDrink = drink.name;
                  _LuuqSettings.instance.baristaDessert = dessert.name;
                  unawaited(_saveSettingsInBackground('barista'));

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
                blockedItems: [_currentBaristaDrink, _currentBaristaDessert],
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
                  unawaited(_saveSettingsInBackground('wheel'));

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
              content: const Text(
                'Ekran temizleme modunu başlatmak istediğinize emin misiniz? 30 saniye boyunca dokunmatik kilitlenecektir.',
                style: TextStyle(color: _muted),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(
                    tr('Hayır', 'No'),
                    style: TextStyle(color: _muted),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text(
                    'Evet, Başlat',
                    style: TextStyle(color: Colors.lightBlueAccent),
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
              content: const Text(
                'Kiosk uygulamasını kapatıp masaüstüne dönmek istediğinize emin misiniz?',
                style: TextStyle(color: _muted),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(
                    tr('Hayır', 'No'),
                    style: TextStyle(color: _muted),
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

  List<_MenuItem> get _recommendationDrinkOptions {
    const dessertCategories = {'Pasta & TatlÄ±', 'LUUQ Chocolate'};
    const hiddenCategories = {'Ekstralar', 'Termos & Seramik', 'SandviÃ§'};
    return _menuCategories.entries
        .where(
          (entry) =>
              !dessertCategories.contains(entry.key) &&
              !hiddenCategories.contains(entry.key),
        )
        .expand((entry) => entry.value)
        .toList(growable: false);
  }

  List<_MenuItem> get _recommendationDessertOptions {
    return [
      ...?_menuCategories['Pasta & Tatlı'],
      ...?_menuCategories['LUUQ Chocolate'],
    ];
  }

  List<_MenuItem> get _iceCoffeeOptions => _itemsForCategoryIcons([
    Icons.ac_unit_rounded,
    Icons.severe_cold_rounded,
    Icons.sports_bar_rounded,
    Icons.bubble_chart_rounded,
    Icons.icecream_rounded,
  ]);

  List<_MenuItem> get _hotCoffeeOptions => _itemsForCategoryIcons([
    Icons.local_cafe_rounded,
    Icons.coffee_maker_rounded,
    Icons.whatshot_rounded,
  ]);

  List<_MenuItem> get _cocktailOptions =>
      _itemsForCategoryIcons([Icons.local_bar_rounded]);

  List<_MenuItem> get _herbalTeaOptions =>
      _itemsForCategoryIcons([Icons.eco_rounded]);

  List<_MenuItem> get _iceCreamOptions =>
      _menuCategories['Dondurmalar'] ?? const [];

  List<_MenuItem> _itemsForCategoryIcons(List<IconData> icons) {
    final items = <_MenuItem>[];
    for (final entry in _categoryIcons.entries) {
      if (icons.contains(entry.value)) {
        items.addAll(_menuCategories[entry.key] ?? const []);
      }
    }
    return items;
  }

  _MenuItem get _currentBaristaDrink {
    final options = _recommendationDrinkOptions;
    return _baristaDrink ?? options.first;
  }

  _MenuItem get _currentBaristaDessert {
    final options = _recommendationDessertOptions;
    return _baristaDessert ?? options.first;
  }

  Widget _buildCanvasMainLayout(
    List<Drink> available,
    bool isSpinning,
    double virtualWidth,
  ) {
    const double sideWidth = 480.0;
    const double columnGap = 28.0;

    // Exact logical sizes for the widgets. FittedBox will gracefully scale them down if needed.
    const double headerSlotHeight = 140.0;
    const double rowGap = 24.0;
    const double filterSlotHeight = 400.0;
    const double billCardHeight =
        240.0; // Increased to 240 to prevent 11px overflow
    const double bottomSlotHeight = 240.0;

    return Stack(
      children: [
        if (appThemeNotifier.value == AppTheme.feast)
          const _FeastThemeCandyRain(),
        if (appThemeNotifier.value == AppTheme.newYear)
          const _NewYearThemeSnowRain(),
        // LEFT COLUMN
        Positioned(
          left: 12.0, // daha da yaklastirildi
          top: 32.0,
          bottom: 64.0, // alt pay birakildi
          width: sideWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: headerSlotHeight),
              const SizedBox(height: rowGap),
              Expanded(
                flex: filterSlotHeight.toInt(),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.center,
                  child: SizedBox(
                    width: sideWidth,
                    height: filterSlotHeight,
                    child: _buildBaristaRecommendation(),
                  ),
                ),
              ),
              const SizedBox(height: rowGap),
              Expanded(
                flex: billCardHeight.toInt(),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.center,
                  child: SizedBox(
                    width: sideWidth,
                    height: billCardHeight,
                    child: _buildBillGameCard(),
                  ),
                ),
              ),
              const SizedBox(height: rowGap),
              Expanded(
                flex: bottomSlotHeight.toInt(),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.bottomCenter,
                  child: SizedBox(
                    width: sideWidth,
                    height: bottomSlotHeight,
                    child: _buildSocialArea(),
                  ),
                ),
              ),
            ],
          ),
        ),

        // CENTER AREA
        Positioned(
          left: 12.0 + sideWidth + columnGap,
          right: 12.0 + sideWidth + columnGap,
          top: 32.0,
          bottom: 64.0,
          child: _buildCenterArea(available, isSpinning),
        ),

        // RIGHT COLUMN
        Positioned(
          right: 12.0, // daha da yaklastirildi
          top: 32.0,
          bottom: 64.0, // alt pay birakildi
          width: sideWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: headerSlotHeight),
              const SizedBox(height: rowGap),
              Expanded(
                flex: filterSlotHeight.toInt(),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.center,
                  child: SizedBox(
                    width: sideWidth,
                    height: filterSlotHeight,
                    child: _buildRightTopBlankCard(isSpinning),
                  ),
                ),
              ),
              const SizedBox(height: rowGap),
              Expanded(
                flex: billCardHeight.toInt(),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.center,
                  child: SizedBox(
                    width: sideWidth,
                    height: billCardHeight,
                    child: _buildResultSwitcher(),
                  ),
                ),
              ),
              const SizedBox(height: rowGap),
              Expanded(
                flex: bottomSlotHeight.toInt(),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.bottomCenter,
                  child: SizedBox(
                    width: sideWidth,
                    height: bottomSlotHeight,
                    child: _buildMenuButton(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildResultSwitcher() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 800),
      switchInCurve: Curves.easeOutBack,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.95, end: 1.0).animate(animation),
            child: child,
          ),
        );
      },
      child: _showResult && _selectedDrink != null
          ? _buildResultArea(_selectedDrink!)
          : _buildEmptyResultArea(),
    );
  }

  Widget _buildBaristaRecommendation() {
    final isCompact = MediaQuery.sizeOf(context).width < 700;
    final drink = _currentBaristaDrink;
    final dessert = _currentBaristaDessert;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isCompact ? 16 : 22),
      decoration: BoxDecoration(
        color: _surface.withValues(alpha: 0.27),
        borderRadius: BorderRadius.circular(isCompact ? 24 : 32),
        border: Border.all(color: _gold.withValues(alpha: 0.25), width: 1.5),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 24),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.star_rounded, color: _gold, size: isCompact ? 24 : 32),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  tr('BARİSTANIN TAVSİYESİ', 'BARISTA\'S PICK'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _gold,
                    fontSize: isCompact ? 20 : 28,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ),
          Expanded(
            child: Center(
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _buildRecommendationBox(
                        icon: Icons.local_cafe_rounded,
                        label: tr('İçecek', 'Drink'),
                        value: trMenu(drink.name),
                        imagePath: drink.imagePath,
                        onTap: () => _showProductDetailDialog(drink),
                      ),
                    ),
                    SizedBox(width: isCompact ? 12 : 16),
                    Expanded(
                      child: _buildRecommendationBox(
                        icon: Icons.cake_rounded,
                        label: tr('Tatlı', 'Dessert'),
                        value: trMenu(dessert.name),
                        imagePath: dessert.imagePath,
                        onTap: () => _showProductDetailDialog(dessert),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecommendationBox({
    required IconData icon,
    required String label,
    required String value,
    required String? imagePath,
    required VoidCallback onTap,
  }) {
    final isCompact = MediaQuery.sizeOf(context).width < 700;
    return BouncyButton(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          vertical: isCompact ? 16 : 20,
          horizontal: 8,
        ),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.02),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.15),
            width: 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: isCompact ? 72 : 88,
              height: isCompact ? 72 : 88,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              clipBehavior: Clip.antiAlias,
              child: imagePath == null
                  ? Icon(icon, color: _cream, size: isCompact ? 32 : 38)
                  : Image.asset(
                      imagePath,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Icon(
                          icon,
                          color: _cream,
                          size: isCompact ? 32 : 38,
                        );
                      },
                    ),
            ),
            SizedBox(height: isCompact ? 14 : 16),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _muted.withValues(alpha: 0.9),
                fontSize: isCompact ? 13 : 14,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _cream,
                fontSize: isCompact ? 14 : 16,
                fontWeight: FontWeight.w600,
                height: 1.2,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ignore: unused_element
  Widget _buildFilterArea() {
    final isCompact = MediaQuery.sizeOf(context).width < 700;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isCompact ? 16 : 24),
      decoration: BoxDecoration(
        color: _surface.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 20),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.tune_rounded, color: _gold, size: isCompact ? 24 : 32),
              const SizedBox(width: 12),
              Text(
                tr('DAMAK MODU', 'TASTE MODE'),
                style: TextStyle(
                  fontSize: isCompact ? 20 : 28,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                  color: _gold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            tr(
              'Damak modunu seç, çarkı çevir, içeceğini keşfet.',
              'Choose your mood, spin the wheel, discover your drink.',
            ),
            style: TextStyle(
              fontSize: 18,
              color: _muted,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final crossAxisCount = constraints.maxWidth < 420 ? 2 : 3;
              return GridView.count(
                crossAxisCount: crossAxisCount,
                shrinkWrap: true,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: isCompact ? 2.45 : 2.2,
                physics: const NeverScrollableScrollPhysics(),
                children: DrinkMood.values.map((mood) {
                  final isSelected = _selectedMood == mood;
                  return GestureDetector(
                    onTap: () => _toggleMood(mood),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? _gold
                            : _bgDark.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isSelected
                              ? _cream
                              : Colors.white.withValues(alpha: 0.05),
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            mood.icon,
                            size: isCompact ? 19 : 24,
                            color: isSelected ? _bgDark : _cream,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                mood.label,
                                maxLines: 1,
                                style: TextStyle(
                                  color: isSelected ? _bgDark : _cream,
                                  fontSize: isCompact ? 15 : 18,
                                  fontWeight: isSelected
                                      ? FontWeight.w900
                                      : FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
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
                            _startWheelCollisionTracking(
                              available,
                              _spinController.value,
                            );
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
                            _playWheelCollisionIfNeeded(available, newTurns);
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
                            } else {
                              setState(() {
                                _lastWheelTickIndex = null;
                              });
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
                                              child: drink.imagePath == null
                                                  ? Icon(
                                                      drink.icon,
                                                      color: Colors.white70,
                                                      size: 32,
                                                    )
                                                  : Image.asset(
                                                      drink.imagePath!
                                                          .replaceFirst(
                                                            'assets/menu/png/',
                                                            'assets/menu/',
                                                          )
                                                          .replaceAll(
                                                            'assets/menu/',
                                                            'assets/menu/png/',
                                                          )
                                                          .replaceAll(
                                                            '.jpg',
                                                            '.png',
                                                          )
                                                          .replaceAll(
                                                            '.jpeg',
                                                            '.png',
                                                          )
                                                          .replaceAll(
                                                            '.webp',
                                                            '.png',
                                                          ),
                                                      fit: BoxFit.cover,
                                                      errorBuilder: (c, e, s) =>
                                                          Icon(
                                                            drink.icon,
                                                            color:
                                                                Colors.white70,
                                                            size: 32,
                                                          ),
                                                    ),
                                            ),
                                            const SizedBox(height: 8),
                                            // Tangential (MERKEZE DİK) Text
                                            SizedBox(
                                              width: 110,
                                              child: Text(
                                                drink.shortName.toUpperCase(),
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

                    // Pointer
                    Positioned(
                      top:
                          (wheelSize * 1.3 - wheelSize) / 2 -
                          44, // Moved UP to sit exactly on the outer ring
                      child: AnimatedBuilder(
                        animation: _spinController,
                        builder: (context, child) {
                          double wobbleAngle = 0.0;

                          if (isSpinning || _isDragging) {
                            final turns = _spinController.value;
                            final segmentTurns = 1.0 / available.length;
                            final segmentProgress =
                                ((turns / segmentTurns) % 1.0 + 1.0) % 1.0;

                            if (_isClockwise) {
                              if (segmentProgress > 0.80) {
                                final t = (segmentProgress - 0.80) / 0.20;
                                wobbleAngle =
                                    -0.35 * Curves.easeIn.transform(t);
                              } else if (segmentProgress < 0.25) {
                                final t = segmentProgress / 0.25;
                                wobbleAngle =
                                    -0.35 *
                                    (1.0 - Curves.elasticOut.transform(t));
                              }
                            } else {
                              if (segmentProgress < 0.20) {
                                final t = (0.20 - segmentProgress) / 0.20;
                                wobbleAngle = 0.35 * Curves.easeIn.transform(t);
                              } else if (segmentProgress > 0.75) {
                                final t = (1.0 - segmentProgress) / 0.25;
                                wobbleAngle =
                                    0.35 *
                                    (1.0 - Curves.elasticOut.transform(t));
                              }
                            }
                          }

                          return Transform.rotate(
                            angle: wobbleAngle,
                            alignment: Alignment.topCenter,
                            child: child,
                          );
                        },
                        child: SizedBox(
                          width: 44,
                          height: 44,
                          child: CustomPaint(painter: _PointerPainter()),
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

  Widget _buildEmptyResultArea() {
    final isCompact = MediaQuery.sizeOf(context).width < 700;
    return Container(
      key: const ValueKey('empty'),
      width: double.infinity,
      padding: EdgeInsets.all(isCompact ? 12 : 16),
      decoration: BoxDecoration(
        color: _surface.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              final op = 0.3 + (_pulseController.value * 0.4);
              return Icon(
                Icons.coffee_rounded,
                size: isCompact ? 36 : 48,
                color: _gold.withValues(alpha: op.clamp(0.0, 1.0)),
              );
            },
          ),
          SizedBox(height: isCompact ? 8 : 12),
          Text(
            tr('Kararsız mısın?', 'Undecided?'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: isCompact ? 18 : 22,
              fontWeight: FontWeight.w700,
              color: _cream,
              letterSpacing: 1,
            ),
          ),
          SizedBox(height: isCompact ? 6 : 8),
          Text(
            tr(
              'Damak modunu seç, çarkı çevir,\niçeceğini LUUQ seçsin.',
              'Choose your mood, spin the wheel,\nlet LUUQ select your drink.',
            ),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: isCompact ? 12 : 13,
              color: _muted,
              height: 1.4,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultArea(Drink drink) {
    final isCompact = MediaQuery.sizeOf(context).width < 700;
    final menuItem = _menuItemForDrink(drink);
    final resultName = trMenu(menuItem?.name ?? drink.fullName);
    final resultDescription = trMenu(
      (menuItem?.desc.isNotEmpty ?? false) ? menuItem!.desc : drink.description,
    );
    final resultImagePath = menuItem?.imagePath;

    return TweenAnimationBuilder<double>(
      key: ValueKey('result_${drink.shortName}'),
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 1200),
      curve: Curves.elasticOut,
      builder: (context, value, child) {
        final flashIntensity = (1.0 - value).clamp(0.0, 1.0);

        return Container(
          padding: EdgeInsets.all(isCompact ? 12 : 16),
          width: double.infinity,
          height: double.infinity,
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(32),
            border: Border.all(
              color: Color.lerp(
                _gold.withValues(alpha: 0.4),
                Colors.white,
                flashIntensity,
              )!,
              width: 1.5 + (flashIntensity * 3),
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
                    child: _buildResultVisual(
                      drink: drink,
                      imagePath: resultImagePath,
                      size: isCompact ? 100 : 120,
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
                            fontSize: 10,
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
                            onTap: () => _showProductDetailDialog(menuItem),
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
                                      fontSize: 13,
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

  Widget _buildRightTopBlankCard(bool isSpinning) {
    final theme = appThemeNotifier.value;

    if (theme == AppTheme.winter) {
      final List<_MenuItem> hotDrinks = [];
      final espresso = _menuCategories['Espresso Kahveler'] ?? [];
      final hot = _menuCategories['Sıcak İçecekler'] ?? [];

      for (final item in [...espresso, ...hot]) {
        if (item.imagePath != null) {
          final pngPath = item.imagePath!
              .replaceFirst('assets/menu/png/', 'assets/menu/')
              .replaceAll('assets/menu/', 'assets/menu/png/')
              .replaceAll('.jpg', '.png')
              .replaceAll('.jpeg', '.png')
              .replaceAll('.webp', '.png');

          hotDrinks.add(
            _MenuItem(
              item.name,
              item.price,
              item.icon,
              desc: item.desc,
              tags: item.tags,
              imagePath: pngPath,
            ),
          );
        }
      }

      return _CocktailShowcaseCard(
        cocktails: hotDrinks,
        onTap: _showProductDetailDialog,
        isSpinning: isSpinning,
      );
    } else if (theme == AppTheme.normal) {
      final List<_MenuItem> allDrinks = [];
      const drinkCategoryNames = [
        'Espresso Kahveler',
        'Filtre Kahveler',
        'Sıcak İçecekler',
        'Ice Kahveler',
        'LUUQ Kokteyl',
        'Bitki Çayları',
        'Frozen',
        'Bubble Tea',
        'Milkshake',
        'Meşrubatlar',
      ];

      for (final catName in drinkCategoryNames) {
        final items = _menuCategories[catName] ?? [];
        for (final item in items) {
          if (item.imagePath != null) {
            final pngPath = item.imagePath!
                .replaceFirst('assets/menu/png/', 'assets/menu/')
                .replaceAll('assets/menu/', 'assets/menu/png/')
                .replaceAll('.jpg', '.png')
                .replaceAll('.jpeg', '.png')
                .replaceAll('.webp', '.png');

            allDrinks.add(
              _MenuItem(
                item.name,
                item.price,
                item.icon,
                desc: item.desc,
                tags: item.tags,
                imagePath: pngPath,
              ),
            );
          }
        }
      }

      // Shuffle with a stable seed so it rotates consistently without jumping
      allDrinks.shuffle(Random(42));

      return _CocktailShowcaseCard(
        cocktails: allDrinks,
        onTap: _showProductDetailDialog,
        isSpinning: isSpinning,
      );
    } else if (theme == AppTheme.feast) {
      final List<_MenuItem> desserts = [];
      final pasta = _menuCategories['Pasta & Tatlı'] ?? [];
      final choco = _menuCategories['LUUQ Chocolate'] ?? [];

      for (final item in [...pasta, ...choco]) {
        if (item.imagePath != null) {
          final pngPath = item.imagePath!
              .replaceFirst('assets/menu/png/', 'assets/menu/')
              .replaceAll('assets/menu/', 'assets/menu/png/')
              .replaceAll('.jpg', '.png')
              .replaceAll('.jpeg', '.png')
              .replaceAll('.webp', '.png');

          desserts.add(
            _MenuItem(
              item.name,
              item.price,
              item.icon,
              desc: item.desc,
              tags: item.tags,
              imagePath: pngPath,
            ),
          );
        }
      }

      return _CocktailShowcaseCard(
        cocktails: desserts,
        onTap: _showProductDetailDialog,
        isSpinning: isSpinning,
      );
    } else {
      final List<_MenuItem> cocktails = [];
      final list = _menuCategories['LUUQ Kokteyl'] ?? [];
      for (final item in list) {
        if (item.imagePath != null) {
          final pngPath = item.imagePath!
              .replaceFirst('assets/menu/png/', 'assets/menu/')
              .replaceAll('assets/menu/', 'assets/menu/png/')
              .replaceAll('.jpg', '.png')
              .replaceAll('.jpeg', '.png')
              .replaceAll('.webp', '.png');
          cocktails.add(
            _MenuItem(
              item.name,
              item.price,
              item.icon,
              desc: item.desc,
              tags: item.tags,
              imagePath: pngPath,
            ),
          );
        }
      }
      return _CocktailShowcaseCard(
        cocktails: cocktails,
        onTap: _showProductDetailDialog,
        isSpinning: isSpinning,
      );
    }
  }

  Widget buildResultFooter({
    required String resultName,
    required bool isCompact,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 16 : 20,
        vertical: isCompact ? 14 : 16,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Container(
            width: isCompact ? 34 : 40,
            height: isCompact ? 34 : 40,
            decoration: BoxDecoration(
              color: _mint.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.check_rounded,
              color: _mint,
              size: isCompact ? 20 : 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr('Seçimin hazır', 'Your pick is ready'),
                  style: TextStyle(
                    color: _mint,
                    fontSize: isCompact ? 14 : 15,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  resultName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.72),
                    fontSize: isCompact ? 12 : 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultVisual({
    required Drink drink,
    required String? imagePath,
    required double size,
  }) {
    final iconSize = size * 0.58;

    if (imagePath == null) {
      return Icon(drink.icon, size: iconSize, color: _gold);
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _gold.withValues(alpha: 0.35), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
          BoxShadow(color: _gold.withValues(alpha: 0.10), blurRadius: 28),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.asset(
        imagePath,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            color: _bgDark,
            alignment: Alignment.center,
            child: Icon(drink.icon, size: iconSize * 0.85, color: _gold),
          );
        },
      ),
    );
  }

  _MenuItem? _menuItemForDrink(Drink drink) {
    final preferredNames =
        _preferredMenuNames[drink.fullName] ??
        _preferredMenuNames[drink.shortName] ??
        [drink.fullName, drink.shortName];
    final allItems = _menuCategories.values.expand((items) => items).toList();
    _MenuItem? fallbackMatch;

    for (final preferredName in preferredNames) {
      final match = _firstMenuMatch(
        allItems,
        (item) =>
            _normalizeMenuName(trMenu(item.name)) ==
            _normalizeMenuName(preferredName),
      );
      if (match?.imagePath != null) return match;
      fallbackMatch ??= match;
    }
    if (fallbackMatch != null) return fallbackMatch;

    for (final preferredName in preferredNames) {
      final normalized = _normalizeMenuName(preferredName);
      final match = _firstMenuMatch(
        allItems,
        (item) => _normalizeMenuName(trMenu(item.name)).contains(normalized),
      );
      if (match?.imagePath != null) return match;
      fallbackMatch ??= match;
    }
    if (fallbackMatch != null) return fallbackMatch;

    final fullName = _normalizeMenuName(drink.fullName);
    return _firstMenuMatch(
      allItems,
      (item) => fullName.contains(_normalizeMenuName(trMenu(item.name))),
    );
  }

  _MenuItem? _firstMenuMatch(
    Iterable<_MenuItem> items,
    bool Function(_MenuItem item) test,
  ) {
    for (final item in items) {
      if (test(item)) return item;
    }
    return null;
  }

  String _normalizeMenuName(String value) {
    return value
        .toLowerCase()
        .replaceAll('ice ', 'iced ')
        .replaceAll('caffe ', '')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '');
  }

  Widget _buildBillGameCard() {
    final isCompact = MediaQuery.sizeOf(context).width < 700;

    Widget content = Container(
      width: double.infinity,
      padding: EdgeInsets.all(isCompact ? 16 : 22),
      decoration: BoxDecoration(
        color: _surface.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 20),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.groups_rounded,
                color: _mint,
                size: isCompact ? 24 : 32,
              ),
              const SizedBox(width: 12),
              Text(
                tr('HESAP KİMDE?', 'WHO PAYS?'),
                style: TextStyle(
                  fontSize: isCompact ? 20 : 28,
                  fontWeight: FontWeight.w900,
                  color: _mint,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            tr(
              'Hesabı kimin ödeyeceğini heyecanlı bir şekilde belirle!',
              'Determine who pays the bill in an exciting way!',
            ),
            style: TextStyle(
              fontSize: isCompact ? 15 : 18,
              color: _muted,
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: isCompact ? 16 : 14),
          GestureDetector(
            onTap: () async {
              if (!currentFeatureFlags.whoPays) {
                showFeatureLockedDialog(context, tr('Hesap Kimde', 'Who Pays'));
                return;
              }
              _idleTimer?.cancel();
              await _showAnimatedDialog(
                const _HesapKimdeDialog(),
                'HesapKimde',
                barrierDismissible: false,
              );
              if (mounted) {
                _resetIdleTimer();
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: _bgDark,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _mint.withValues(alpha: 0.4)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.casino_rounded, color: _mint, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    tr('Mini Çarkı Aç', 'Open Mini Wheel'),
                    style: const TextStyle(
                      color: _mint,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    if (!currentFeatureFlags.whoPays) {
      return GestureDetector(
        onTap: () =>
            showFeatureLockedDialog(context, tr('Hesap Kimde', 'Who Pays')),
        child: Stack(
          children: [
            Opacity(opacity: 0.4, child: content),
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(32),
                ),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1C1724).withValues(alpha: 0.8),
                      shape: BoxShape.circle,
                      border: Border.all(color: _gold.withValues(alpha: 0.5)),
                    ),
                    child: const Icon(
                      Icons.lock_rounded,
                      color: _gold,
                      size: 28,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return content;
  }

  Widget _buildMenuButton() {
    final isCompact = MediaQuery.sizeOf(context).width < 700;
    return BouncyButton(
      onTap: () async {
        if (!currentFeatureFlags.menu) {
          showFeatureLockedDialog(context, tr('Ürün Menüsü', 'Product Menu'));
          return;
        }
        _idleTimer?.cancel();
        unawaited(_LuuqAnalytics.instance.incrementMenuClicks());
        await _showAnimatedDialog(const _MenuDialog(), 'Menu');
        if (mounted) {
          _resetIdleTimer();
        }
      },
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(vertical: isCompact ? 20 : 32),
        decoration: BoxDecoration(
          color: _gold,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: _gold.withValues(alpha: 0.3),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.menu_book_rounded,
              color: _bgDark,
              size: isCompact ? 38 : 56,
            ),
            SizedBox(height: isCompact ? 10 : 16),
            Text(
              tr('TÜM MENÜYÜ İNCELE', 'BROWSE FULL MENU'),
              style: TextStyle(
                fontSize: isCompact ? 16 : 22,
                fontWeight: FontWeight.w900,
                color: _bgDark,
                letterSpacing: isCompact ? 0.8 : 2,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAnimatedDialog(
    Widget dialogWidget,
    String label, {
    bool barrierDismissible = true,
  }) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: barrierDismissible,
      barrierLabel: label,
      barrierColor: Colors.black.withValues(alpha: 0.40),
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (context, anim1, anim2) {
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: barrierDismissible
                ? () {
                    Navigator.of(context).pop();
                  }
                : null,
            child: _VirtualCanvasDialogWrapper(
              child: GestureDetector(
                onTap: () {}, // Prevent taps inside the dialog from closing it
                child: dialogWidget,
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, anim1, anim2, child) {
        return FadeTransition(
          opacity: anim1,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.9, end: 1.0).animate(
              CurvedAnimation(
                parent: anim1,
                curve: Curves.easeOutCubic,
                reverseCurve: Curves.easeIn,
              ),
            ),
            child: child,
          ),
        );
      },
    );
  }

  void _showLargeQR(String assetPath, String title) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'LargeQR',
      barrierColor: Colors.black.withValues(alpha: 0.40),
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (context, anim1, anim2) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5.0, sigmaY: 5.0),
          child: GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Scaffold(
              backgroundColor: Colors.transparent,
              body: _VirtualCanvasDialogWrapper(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      tr('KAPATMAK İÇİN DOKUNUN', 'TAP TO CLOSE'),
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 4,
                      ),
                    ),
                    const SizedBox(height: 40),
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(40),
                        boxShadow: [
                          BoxShadow(
                            color: _gold.withValues(alpha: 0.3),
                            blurRadius: 100,
                            spreadRadius: 20,
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: Image.asset(
                          assetPath,
                          width: 500,
                          height: 500,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    const SizedBox(height: 40),
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 54,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 6,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, anim1, anim2, child) {
        return FadeTransition(
          opacity: anim1,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.9, end: 1.0).animate(
              CurvedAnimation(
                parent: anim1,
                curve: Curves.easeOutCubic,
                reverseCurve: Curves.easeIn,
              ),
            ),
            child: child,
          ),
        );
      },
    );
  }

  Widget _buildSocialArea() {
    final isCompact = MediaQuery.sizeOf(context).width < 700;
    final qrSize = isCompact ? 82.0 : 102.0;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 16 : 18,
        vertical: isCompact ? 16 : 14,
      ),
      decoration: BoxDecoration(
        color: _surface.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 20),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              // Pulse controller goes 0 -> 1 -> 0. We'll map this to a sweeping offset.
              final offset = -1.0 + (_pulseController.value * 2.0);
              return ShaderMask(
                blendMode: BlendMode.srcIn,
                shaderCallback: (bounds) {
                  return LinearGradient(
                    colors: [_gold, _gold, Colors.white, _gold, _gold],
                    stops: const [0.0, 0.35, 0.5, 0.65, 1.0],
                    begin: Alignment(offset - 1.5, 0.0),
                    end: Alignment(offset + 1.5, 0.0),
                  ).createShader(bounds);
                },
                child: Text(
                  tr('BAĞLANTILARIMIZ', 'OUR CONNECTIONS'),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 3,
                    color: Colors.white,
                  ),
                ),
              );
            },
          ),
          SizedBox(height: isCompact ? 16 : 10),
          if (isCompact)
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 14,
              runSpacing: 18,
              children: [
                _buildSocialQrItem(
                  assetPath: 'assets/instagramqr.png',
                  title: 'INSTAGRAM',
                  size: qrSize,
                ),
                _buildSocialQrItem(
                  assetPath: 'assets/mapsqr.png',
                  title: 'GOOGLE MAPS',
                  size: qrSize,
                ),
                _buildSocialQrItem(
                  assetPath: 'assets/wifiqr.png',
                  title: 'LUUQ WI-FI',
                  size: qrSize,
                ),
              ],
            )
          else
            Row(
              children: [
                Expanded(
                  child: _buildSocialQrItem(
                    assetPath: 'assets/instagramqr.png',
                    title: 'INSTAGRAM',
                    size: qrSize,
                  ),
                ),
                _buildSocialDivider(),
                Expanded(
                  child: _buildSocialQrItem(
                    assetPath: 'assets/mapsqr.png',
                    title: 'GOOGLE MAPS',
                    size: qrSize,
                  ),
                ),
                _buildSocialDivider(),
                Expanded(
                  child: _buildSocialQrItem(
                    assetPath: 'assets/wifiqr.png',
                    title: 'LUUQ WI-FI',
                    size: qrSize,
                  ),
                ),
              ],
            ),
          const SizedBox(height: 16),
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              final opacity = 0.35 + (_pulseController.value * 0.45);
              return Opacity(
                opacity: opacity,
                child: Text(
                  tr('BÜYÜTMEK İÇİN DOKUNUN', 'TAP TO ENLARGE'),
                  style: const TextStyle(
                    color: _cream,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSocialDivider() {
    return Container(
      width: 1,
      height: 92,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: Colors.white.withValues(alpha: 0.13),
    );
  }

  Widget _buildSocialQrItem({
    required String assetPath,
    required String title,
    required double size,
  }) {
    return BouncyButton(
      onTap: () {
        final linkType = title.toLowerCase().contains('instagram')
            ? 'instagram'
            : title.toLowerCase().contains('wifi')
            ? 'wifi'
            : title.toLowerCase().contains('maps')
            ? 'maps'
            : 'other';
        AnalyticsService.instance.trackQrClick(linkType);
        AnalyticsService.instance.trackLinksClick();
        _showLargeQR(assetPath, title);
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.asset(
              assetPath,
              width: size,
              height: size,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              title,
              maxLines: 1,
              style: const TextStyle(
                color: _cream,
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

const List<Color> _billPalette = [
  Color(0xFFE8B445), // Gold
  Color(0xFF48C9B0), // Mint
  Color(0xFFFF7675), // Soft Red
  Color(0xFF74B9FF), // Soft Blue
  Color(0xFFA29BFE), // Purple
  Color(0xFF55EFC4), // Light Green
];

// ===== HESAP KİMDE DIALOG =====
class _HesapKimdeDialog extends StatefulWidget {
  const _HesapKimdeDialog();

  @override
  State<_HesapKimdeDialog> createState() => _HesapKimdeDialogState();
}

class _HesapKimdeDialogState extends State<_HesapKimdeDialog> {
  int _personCount = 2;
  int? _result;
  final _rand = Random();

  late List<Color> _playerColors;
  int? _editingPlayerIndex;

  bool _isAnimating = false;
  int _winnerIndex = 0;

  @override
  void initState() {
    super.initState();
    _initColors();
    AnalyticsService.instance.trackWhoPaysClick();
  }

  void _initColors() {
    _playerColors = List.generate(
      _personCount,
      (i) => _billPalette[i % _billPalette.length],
    );
  }

  void _spin() {
    if (_isAnimating) return;

    unawaited(_LuuqAnalytics.instance.incrementWhoPaysPlays());

    setState(() {
      _result = null; // Hide previous result
      _winnerIndex = _rand.nextInt(_personCount);
      _isAnimating = true;
      _editingPlayerIndex = null;
    });
  }

  void _selectPlayerColor(int playerIndex, Color color) {
    if (_isAnimating) return;
    final existingIndex = _playerColors.indexOf(color);
    setState(() {
      _playerColors = List<Color>.from(_playerColors);
      if (existingIndex != -1 && existingIndex != playerIndex) {
        final previousColor = _playerColors[playerIndex];
        _playerColors[existingIndex] = previousColor;
      }
      _playerColors[playerIndex] = color;
      _editingPlayerIndex = null;
      _result = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 480,
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(40),
          border: Border.all(color: _mint.withValues(alpha: 0.3), width: 2),
          boxShadow: [
            BoxShadow(
              color: _mint.withValues(alpha: 0.1),
              blurRadius: 40,
              spreadRadius: 10,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.groups_rounded, color: _mint, size: 32),
                const SizedBox(width: 12),
                Text(
                  tr('HESAP KİMDE?', 'WHO PAYS?'),
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: _cream,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              tr(
                'Kişi sayısını seç ve topları karıştır!',
                'Select number of people and mix the balls!',
              ),
              style: const TextStyle(
                fontSize: 16,
                color: _muted,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 24),

            // Person count selector
            Wrap(
              spacing: 12,
              children: [2, 3, 4, 5, 6].map((count) {
                final selected = _personCount == count;
                return Semantics(
                  button: true,
                  selected: selected,
                  label: tr('$count kişi', '$count people'),
                  child: GestureDetector(
                    onTap: _isAnimating
                        ? null
                        : () {
                            setState(() {
                              _personCount = count;
                              _result = null;
                              _editingPlayerIndex = null;
                              _initColors();
                            });
                          },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: selected ? _mint : _bgDark,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: selected
                              ? _mint
                              : Colors.white.withValues(alpha: 0.1),
                          width: selected ? 3 : 1,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          '$count',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: selected ? _bgDark : _cream,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),

            // Player Cards (Color Pickers)
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: List.generate(_personCount, (index) {
                final color = _playerColors[index];
                final isEditing = _editingPlayerIndex == index;
                return Semantics(
                  button: true,
                  selected: isEditing,
                  label: tr(
                    '${index + 1}. kişinin rengini değiştir',
                    'Change color for person ${index + 1}',
                  ),
                  child: GestureDetector(
                    onTap: _isAnimating
                        ? null
                        : () {
                            setState(() {
                              _editingPlayerIndex = isEditing ? null : index;
                              _result = null;
                            });
                          },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: isEditing
                            ? color.withValues(alpha: 0.2)
                            : _bgDark,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isEditing
                              ? color
                              : Colors.white.withValues(alpha: 0.1),
                          width: isEditing ? 2 : 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 1),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            tr('${index + 1}. Kişi', 'Person ${index + 1}'),
                            style: TextStyle(
                              color: isEditing ? color : Colors.white70,
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),

            // Color Palette Picker Popup
            if (_editingPlayerIndex != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.05),
                  ),
                ),
                child: Wrap(
                  spacing: 12,
                  children: _billPalette.map((color) {
                    final isSelected =
                        _playerColors[_editingPlayerIndex!] == color;
                    return Semantics(
                      button: true,
                      selected: isSelected,
                      label: tr('Oyuncu rengi', 'Player color'),
                      child: GestureDetector(
                        onTap: _isAnimating
                            ? null
                            : () => _selectPlayerColor(
                                _editingPlayerIndex!,
                                color,
                              ),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected
                                  ? Colors.white
                                  : Colors.transparent,
                              width: isSelected ? 3 : 0,
                            ),
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color: color.withValues(alpha: 0.5),
                                      blurRadius: 8,
                                    ),
                                  ]
                                : [],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],

            const SizedBox(height: 32),

            // Lottery Machine Area
            _LotteryMachine(
              personCount: _personCount,
              playerColors: _playerColors,
              winnerIndex: _winnerIndex,
              isAnimating: _isAnimating,
              showResult: _result != null,
              onComplete: () {
                if (!mounted) return;
                setState(() {
                  _result = _winnerIndex + 1;
                  _isAnimating = false;
                });
              },
            ),

            const SizedBox(height: 32),

            // Spin button & Result
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: (_result != null && !_isAnimating)
                  ? Column(
                      key: ValueKey(_result),
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 32,
                            vertical: 20,
                          ),
                          decoration: BoxDecoration(
                            color: _bgDark,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: _gold.withValues(alpha: 0.5),
                              width: 2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: _gold.withValues(alpha: 0.15),
                                blurRadius: 20,
                              ),
                            ],
                          ),
                          child: Text(
                            tr(
                              'Hesap $_result. kişide! 🎉',
                              'Person $_result pays the bill! 🎉',
                            ),
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              color: _playerColors[_result! - 1],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        GestureDetector(
                          onTap: _spin,
                          child: Text(
                            tr('Tekrar Çek', 'Draw Again'),
                            style: TextStyle(
                              color: _mint,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                      ],
                    )
                  : Semantics(
                      key: const ValueKey('spin_btn'),
                      button: true,
                      enabled: !_isAnimating,
                      label: tr(
                        'Topları karıştır ve sonucu seç',
                        'Mix balls and draw',
                      ),
                      child: GestureDetector(
                        onTap: _isAnimating ? null : _spin,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 48,
                            vertical: 18,
                          ),
                          decoration: BoxDecoration(
                            color: _isAnimating ? _muted : _mint,
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: _isAnimating
                                ? []
                                : [
                                    BoxShadow(
                                      color: _mint.withValues(alpha: 0.4),
                                      blurRadius: 16,
                                      offset: const Offset(0, 6),
                                    ),
                                  ],
                          ),
                          child: Text(
                            _isAnimating
                                ? tr('KARILIYOR...', 'MIXING...')
                                : tr('KARIŞTIR & ÇEK!', 'MIX & DRAW!'),
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              color: _bgDark,
                              letterSpacing: 2,
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 24),

            // Close button
            GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Text(
                tr('Kapat', 'Close'),
                style: TextStyle(
                  color: _muted,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===== HESAP KİMDE - LOTTERY MACHINE WIDGET =====

class _LotteryMachine extends StatefulWidget {
  final int personCount;
  final List<Color> playerColors;
  final int winnerIndex;
  final bool isAnimating;
  final bool showResult;
  final VoidCallback onComplete;

  const _LotteryMachine({
    required this.personCount,
    required this.playerColors,
    required this.winnerIndex,
    required this.isAnimating,
    required this.showResult,
    required this.onComplete,
  });

  @override
  State<_LotteryMachine> createState() => _LotteryMachineState();
}

class _LotteryMachineState extends State<_LotteryMachine>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late WhoPaysLotterySimulation _simulation;

  final _spinSound = _SpinTickSound();
  final _seedRandom = Random();
  DateTime? _lastImpactSoundAt;
  bool _reduceMotion = false;

  int get _safeWinnerIndex =>
      widget.winnerIndex.clamp(0, widget.personCount - 1);

  @override
  void initState() {
    super.initState();
    _simulation = _createSimulation(seed: widget.personCount * 997);
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: _simulation.durationMilliseconds),
    );
    _controller.addListener(_handleAnimationTick);
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        _spinSound.playResult();
        widget.onComplete();
      }
    });
  }

  WhoPaysLotterySimulation _createSimulation({required int seed}) {
    return WhoPaysLotterySimulation(
      personCount: widget.personCount,
      winnerIndex: _safeWinnerIndex,
      seed: seed,
    );
  }

  void _syncControllerDuration() {
    _controller.duration = Duration(
      milliseconds: _reduceMotion ? 180 : _simulation.durationMilliseconds,
    );
  }

  void _handleAnimationTick() {
    if (!mounted || !widget.isAnimating) return;

    if (_reduceMotion) {
      _simulation.advanceReducedMotion(_controller.value);
      return;
    }

    final report = _simulation.advanceTo(
      _controller.value * _simulation.durationSeconds,
    );
    if (report.maxImpactSpeed < 90) return;

    final now = DateTime.now();
    final lastImpactSoundAt = _lastImpactSoundAt;
    if (lastImpactSoundAt != null &&
        now.difference(lastImpactSoundAt) < const Duration(milliseconds: 60)) {
      return;
    }
    _lastImpactSoundAt = now;
    _spinSound.playTick();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion == reduceMotion) return;

    _reduceMotion = reduceMotion;
    _syncControllerDuration();
  }

  @override
  void didUpdateWidget(covariant _LotteryMachine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isAnimating && !oldWidget.isAnimating) {
      _lastImpactSoundAt = null;
      final previous = _simulation;
      _simulation = WhoPaysLotterySimulation(
        personCount: widget.personCount,
        winnerIndex: _safeWinnerIndex,
        seed: _seedRandom.nextInt(0x7fffffff),
        initialState:
            previous.personCount == widget.personCount &&
                previous.phase == WhoPaysLotteryPhase.seated
            ? previous.exportState()
            : null,
      );
      _syncControllerDuration();
      _controller.forward(from: 0);
    } else if (!widget.showResult && oldWidget.showResult) {
      _controller.reset();
      _simulation = _createSimulation(seed: widget.personCount * 997);
      _syncControllerDuration();
    } else if (widget.personCount != oldWidget.personCount) {
      _controller.reset();
      _simulation = _createSimulation(seed: widget.personCount * 997);
      _syncControllerDuration();
    }
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_handleAnimationTick)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion:
          widget.showResult && _simulation.phase == WhoPaysLotteryPhase.seated,
      label:
          widget.showResult && _simulation.phase == WhoPaysLotteryPhase.seated
          ? tr(
              'Kazanan top çıkışta: ${widget.winnerIndex + 1}. kişi',
              'Winning ball in chute: person ${widget.winnerIndex + 1}',
            )
          : widget.showResult
          ? tr('Kazanan top hazırlanıyor', 'Preparing winning ball')
          : widget.isAnimating
          ? tr('Toplar karıştırılıyor', 'Balls are mixing')
          : tr(
              '${widget.personCount} oyuncu topu hazır',
              '${widget.personCount} player balls ready',
            ),
      child: WhoPaysLotteryMachineView(
        key: const ValueKey('who_pays_machine'),
        simulation: _simulation,
        playerColors: widget.playerColors,
        repaint: _controller,
      ),
    );
  }
}

// ===== MENÜ DIALOG (Veri Tabanlı) =====

class _MenuItem {
  const _MenuItem(
    this.name,
    this.price,
    this.icon, {
    this.desc = '',
    this.tags = const [],
    this.imagePath,
  });
  final String name;
  final String price;
  final IconData icon;
  final String desc;
  final List<String> tags;
  final String? imagePath;
}

// Category icons
const _categoryIcons = <String, IconData>{
  'Espresso Kahveler': Icons.local_cafe_rounded,
  'Filtre Kahveler': Icons.coffee_maker_rounded,
  'Sıcak İçecekler': Icons.whatshot_rounded,
  'Ice Kahveler': Icons.ac_unit_rounded,
  'LUUQ Kokteyl': Icons.local_bar_rounded,
  'Bitki Çayları': Icons.eco_rounded,
  'Frozen': Icons.severe_cold_rounded,
  'Bubble Tea': Icons.bubble_chart_rounded,
  'Milkshake': Icons.icecream_rounded,
  'Dondurmalar': Icons.icecream_outlined,
  'Meşrubatlar': Icons.sports_bar_rounded,
  'Pasta & Tatlı': Icons.cake_rounded,
  'LUUQ Chocolate': Icons.cookie_rounded,
  'Sandviç': Icons.lunch_dining_rounded,
  'Termos & Seramik': Icons.coffee_rounded,
  'Ekstralar': Icons.add_circle_outline_rounded,
};

// Category descriptions for hero section
const _categoryDescriptions = <String, String>{
  'Espresso Kahveler': 'Yoğun, klasik ve taze espresso bazlı favoriler.',
  'Filtre Kahveler': 'Özenle seçilmiş yöresel çekirdekler ve özel demlemeler.',
  'Sıcak İçecekler': 'İçinizi ısıtacak geleneksel ve modern sıcak lezzetler.',
  'Ice Kahveler': 'Günün her saati ferahlık veren buzlu kahve alternatifleri.',
  'LUUQ Kokteyl':
      'LUUQ imzalı alkolsüz, ferahlatıcı ve özel reçeteli karışımlar.',
  'Bitki Çayları':
      'Doğadan gelen rahatlatıcı ve canlandırıcı özel bitki harmanları.',
  'Frozen': 'Taze meyvelerle hazırlanan buzlu yaz şölenleri.',
  'Bubble Tea':
      'Patlayan boba incileriyle dolu eğlenceli ve serinletici lezzetler.',
  'Milkshake': 'Kıvamlı, yoğun ve tatlı krizlerine birebir sütlü serinlik.',
  'Dondurmalar': 'Yaz aylarının en serinletici ve leziz dondurma çeşitleri.',
  'Meşrubatlar': 'Klasik gazozlar, doğal sodalar ve enerji veren içecekler.',
  'Pasta & Tatlı':
      'Kahvenize mükemmel eşlik edecek taptaze, el yapımı tatlılar.',
  'LUUQ Chocolate': 'LUUQ ustalarından özel yapım premium artizan çikolatalar.',
  'Sandviç': 'Taze ekmeklerle hazırlanan, doyurucu ve leziz atıştırmalıklar.',
  'Termos & Seramik':
      'LUUQ deneyimini gittiğiniz her yere taşıyacak şık tasarımlar.',
  'Ekstralar':
      'İçeceğinizi tamamen kişiselleştirebileceğiniz ekstra dokunuşlar.',
};

// Tag colors
const _tagStyles = <String, Color>{
  'Popüler': Color(0xFFE8B445),
  'Special': Color(0xFFE879A8),
  'Yazın İyisi': Color(0xFF4ECDC4),
  'Soğuk': Color(0xFF74B9FF),
  'Sıcak': Color(0xFFFF7675),
  'Tatlı': Color(0xFFFDA7DF),
  'Sert': Color(0xFFA29BFE),
  'Klasik': Color(0xFFB2BEC3),
  'Yeni': Color(0xFF55EFC4),
};

const _menuCategories = {
  'Espresso Kahveler': [
    _MenuItem(
      'Americano',
      '185₺ / 205₺',
      Icons.local_cafe_rounded,
      desc: 'Sade ve güçlü espresso suyla buluşur',
      tags: ['Klasik'],
      imagePath: 'assets/menu/americano.jpg',
    ),
    _MenuItem(
      'Cappuccino',
      '210₺ / 230₺',
      Icons.local_cafe_rounded,
      desc: 'Kremamsı süt köpüğü ile klasik İtalyan lezzeti',
      tags: ['Sıcak', 'Klasik'],
      imagePath: 'assets/menu/cappucino.jpg',
    ),
    _MenuItem(
      'Caramel Latte',
      '250₺ / 270₺',
      Icons.local_cafe_rounded,
      desc: 'Karamel aromalı sütlü kahve keyfi',
      tags: ['Tatlı'],
      imagePath: 'assets/menu/caramellatte.jpg',
    ),
    _MenuItem(
      'Caramel Macchiato',
      '250₺ / 270₺',
      Icons.local_cafe_rounded,
      desc: 'Karamel sos ve vanilyalı süt',
      tags: ['Tatlı', 'Popüler'],
      imagePath: 'assets/menu/caramelmacchiato.jpg',
    ),
    _MenuItem(
      'Cortado S',
      '200₺',
      Icons.local_cafe_rounded,
      desc: 'Espresso ve az süt, sert ve yoğun',
      imagePath: 'assets/menu/cortado.jpg',
    ),
    _MenuItem(
      'Espresso Double',
      '145₺',
      Icons.local_cafe_rounded,
      desc: 'Çift shot espresso',
      tags: ['Sert'],
      imagePath: 'assets/menu/espressodouble.jpg',
    ),
    _MenuItem(
      'Espresso Single',
      '125₺',
      Icons.local_cafe_rounded,
      desc: 'Tek shot espresso',
      imagePath: 'assets/menu/espressodouble.jpg',
    ),
    _MenuItem(
      'Flat White',
      '250₺',
      Icons.local_cafe_rounded,
      desc: 'İnce dokulu süt ile kadifemsi espresso',
      tags: ['Popüler'],
      imagePath: 'assets/menu/flatwhite.jpg',
    ),
    _MenuItem(
      'Latte',
      '200₺ / 220₺',
      Icons.local_cafe_rounded,
      desc: 'Yumuşak sütlü espresso klasiği',
      tags: ['Sıcak', 'Popüler'],
      imagePath: 'assets/menu/latte.jpg',
    ),
    _MenuItem(
      'Mocha',
      '240₺ / 260₺',
      Icons.local_cafe_rounded,
      desc: 'Çikolata ve espresso buluşması',
      tags: ['Tatlı'],
      imagePath: 'assets/menu/mocha.jpg',
    ),
    _MenuItem(
      'Oreo Latte',
      '240₺ / 260₺',
      Icons.local_cafe_rounded,
      desc: 'Oreo bisküvi parçalı latte',
      imagePath: 'assets/menu/oreolattesicak.jpeg',
    ),
    _MenuItem(
      'White Mocha',
      '240₺ / 260₺',
      Icons.local_cafe_rounded,
      desc: 'Beyaz çikolatalı mocha',
      imagePath: 'assets/menu/whitemocha.jpg',
    ),
  ],
  'Filtre Kahveler': [
    _MenuItem(
      'Cold Brew',
      '220₺',
      Icons.coffee_maker_rounded,
      desc: '12 saat soğuk demleme, yumuşak içim ve ferah kahve aroması.',
      tags: ['Soğuk', 'Popüler'],
    ),
    _MenuItem(
      'Colombia',
      '210₺ / 230₺',
      Icons.coffee_maker_rounded,
      desc: 'Dengeli gövde, zarif asidite ve yumuşak içimli filtre kahve.',
      imagePath: 'assets/menu/klasikfiltre.jpg',
    ),
    _MenuItem(
      'Etiyopya',
      '210₺ / 230₺',
      Icons.coffee_maker_rounded,
      desc: 'Meyvemsi notalar, canlı aroma ve hafif çiçeksi bir bitiş.',
      imagePath: 'assets/menu/klasikfiltre.jpg',
    ),
    _MenuItem(
      'Filtre Sütlü',
      '190₺ / 210₺',
      Icons.coffee_maker_rounded,
      desc: 'Taze filtre kahvenin sütle yumuşatılmış sıcak yorumu.',
    ),
    _MenuItem(
      'Guatamala',
      '210₺ / 230₺',
      Icons.coffee_maker_rounded,
      desc: 'Fındıksı aroma, dolgun gövde ve dengeli kahve karakteri.',
      imagePath: 'assets/menu/klasikfiltre.jpg',
    ),
    _MenuItem(
      'Klasik Filtre',
      '170₺ / 190₺',
      Icons.coffee_maker_rounded,
      desc: 'Günlük taze demlenen, sade ve dengeli klasik filtre kahve.',
      tags: ['Klasik'],
      imagePath: 'assets/menu/klasikfiltre.jpg',
    ),
  ],
  'Sıcak İçecekler': [
    _MenuItem(
      'Chai Tea Latte',
      '265₺',
      Icons.emoji_food_beverage_rounded,
      desc: 'Baharatlı çay ve kremamsı süt',
      tags: ['Sıcak'],
    ),
    _MenuItem(
      'Çay',
      '90₺',
      Icons.emoji_food_beverage_rounded,
      desc: 'Geleneksel demlik çay',
      imagePath: 'assets/menu/cay.jpeg',
    ),
    _MenuItem(
      'Damla Sakızlı Sahlep',
      '245₺',
      Icons.emoji_food_beverage_rounded,
      desc: 'Damla sakızı aromalı sahlep',
      tags: ['Sıcak'],
    ),
    _MenuItem(
      'Dondurma Sahlep',
      '255₺',
      Icons.emoji_food_beverage_rounded,
      desc: 'Üstü dondurmalı sahlep',
    ),
    _MenuItem(
      'Double Türk Kahvesi',
      '160₺',
      Icons.emoji_food_beverage_rounded,
      desc: 'Çift pişirme Türk kahvesi',
      tags: ['Sert'],
      imagePath: 'assets/menu/turkkahvesi.jpg',
    ),
    _MenuItem(
      'Frambuazlı Sıcak Beyaz Çikolata',
      '245₺',
      Icons.emoji_food_beverage_rounded,
      desc: 'Frambuaz ve beyaz çikolata',
      tags: ['Tatlı'],
      imagePath: 'assets/menu/frambuazsicakbeyazcikolata.jpg',
    ),
    _MenuItem(
      'Sıcak Çikolata',
      '235₺ / 255₺',
      Icons.emoji_food_beverage_rounded,
      desc: 'Yoğun kakao lezzeti',
      tags: ['Tatlı', 'Popüler'],
      imagePath: 'assets/menu/sicakcikolata.jpeg',
    ),
    _MenuItem(
      'Tarçınlı Sahlep',
      '235₺',
      Icons.emoji_food_beverage_rounded,
      desc: 'Tarçın aromalı geleneksel sahlep',
    ),
    _MenuItem(
      'Türk Kahvesi',
      '140₺',
      Icons.emoji_food_beverage_rounded,
      desc: 'Geleneksel köpüklü Türk kahvesi',
      tags: ['Klasik'],
      imagePath: 'assets/menu/turkkahvesi.jpg',
    ),
    _MenuItem(
      'Mocha Mint',
      '250₺',
      Icons.emoji_food_beverage_rounded,
      desc: 'Naneli mocha',
      tags: ['Sıcak'],
    ),
    _MenuItem(
      'Nuttymix',
      '250₺',
      Icons.emoji_food_beverage_rounded,
      desc: 'Fındıklı karışım',
      tags: ['Sıcak'],
      imagePath: 'assets/menu/png/latte.png',
    ),
    _MenuItem(
      'Raspberry Mocha',
      '250₺',
      Icons.emoji_food_beverage_rounded,
      desc: 'Frambuazlı mocha',
      tags: ['Sıcak'],
    ),
    _MenuItem(
      'Vani Gold',
      '240₺',
      Icons.emoji_food_beverage_rounded,
      desc: 'Vanilyalı altın kokteyl',
      tags: ['Sıcak'],
    ),
    _MenuItem(
      'Vanicha',
      '240₺',
      Icons.emoji_food_beverage_rounded,
      desc: 'Vanilya ve matcha füzyonu',
      tags: ['Sıcak'],
    ),
    _MenuItem(
      'Vitte Latte',
      '240₺',
      Icons.emoji_food_beverage_rounded,
      desc: 'Beyaz çikolatalı latte',
      tags: ['Sıcak'],
    ),
    _MenuItem(
      'Vitte Milk',
      '240₺',
      Icons.emoji_food_beverage_rounded,
      desc: 'Beyaz çikolatalı süt',
      tags: ['Sıcak'],
    ),
  ],
  'Ice Kahveler': [
    _MenuItem(
      'Affogato',
      '240₺',
      Icons.ac_unit_rounded,
      desc: 'Espresso üzerine dondurma',
      tags: ['Soğuk', 'Tatlı'],
    ),
    _MenuItem(
      'Ice Americano',
      '185₺',
      Icons.ac_unit_rounded,
      desc: 'Buzlu sade americano',
      tags: ['Soğuk'],
      imagePath: 'assets/menu/iceamericano.jpg',
    ),
    _MenuItem(
      'Ice Caramel Latte',
      '250₺',
      Icons.ac_unit_rounded,
      desc: 'Buzlu karamel latte',
      tags: ['Soğuk', 'Tatlı'],
      imagePath: 'assets/menu/icecaramellatte.jpg',
    ),
    _MenuItem(
      'Ice Caramel Macchiato',
      '250₺',
      Icons.ac_unit_rounded,
      desc: 'Buzlu karamel macchiato',
      tags: ['Soğuk', 'Popüler'],
      imagePath: 'assets/menu/icecaramelmacchiato.jpg',
    ),
    _MenuItem(
      'Ice Filtre Kahve',
      '170₺',
      Icons.ac_unit_rounded,
      desc: 'Buzlu filtre kahve',
    ),
    _MenuItem(
      'Ice Flat White',
      '250₺',
      Icons.ac_unit_rounded,
      desc: 'Buzlu flat white',
      imagePath: 'assets/menu/iceflatwhite.jpg',
    ),
    _MenuItem(
      'Ice Latte',
      '200₺',
      Icons.ac_unit_rounded,
      desc: 'Buzlu sütlü espresso',
      tags: ['Soğuk', 'Popüler'],
      imagePath: 'assets/menu/icelatte.jpg',
    ),
    _MenuItem(
      'Ice Mocha',
      '240₺',
      Icons.ac_unit_rounded,
      desc: 'Buzlu çikolatalı mocha',
      tags: ['Soğuk', 'Tatlı'],
      imagePath: 'assets/menu/icemocha.jpg',
    ),
    _MenuItem(
      'Ice Oreo Latte',
      '235₺',
      Icons.ac_unit_rounded,
      desc: 'Oreo parçalı buzlu latte',
      tags: ['Soğuk', 'Tatlı'],
      imagePath: 'assets/menu/oreolatteice.jpeg',
    ),
    _MenuItem(
      'Ice Sütlü Filtre Kahve',
      '190₺',
      Icons.ac_unit_rounded,
      desc: 'Buzlu sütlü filtre',
      imagePath: 'assets/menu/icesutlufiltrekahve.jpg',
    ),
    _MenuItem(
      'Ice White Mocha',
      '240₺',
      Icons.ac_unit_rounded,
      desc: 'Buzlu beyaz mocha',
      imagePath: 'assets/menu/icewhitemocha.jpg',
    ),
  ],
  'LUUQ Kokteyl': [
    _MenuItem(
      'Beach of Luuq',
      '260₺',
      Icons.local_bar_rounded,
      desc: 'Tropikal meyveli serinletici kokteyl',
      tags: ['Yazın İyisi', 'Special'],
    ),
    _MenuItem(
      'Butterfly Effect',
      '270₺',
      Icons.local_bar_rounded,
      desc: 'Renk değiştiren büyüleyici kokteyl',
      tags: ['Special'],
      imagePath: 'assets/menu/buttferflyeffect.jpg',
    ),
    _MenuItem(
      'Caramel Affogato',
      '280₺',
      Icons.local_bar_rounded,
      desc: 'Karamelli affogato yorumu',
      tags: ['Tatlı'],
      imagePath: 'assets/menu/caramelaffogato.jpg',
    ),
    _MenuItem(
      'Casablanca',
      '260₺',
      Icons.local_bar_rounded,
      desc: 'Egzotik meyve karışımı',
      tags: ['Special'],
    ),
    _MenuItem(
      'Cool Lime',
      '260₺',
      Icons.local_bar_rounded,
      desc: 'Ferahlatıcı misket limonu',
      tags: ['Yazın İyisi'],
      imagePath: 'assets/menu/coollime.jpg',
    ),
    _MenuItem(
      'Ginger Dragon',
      '270₺',
      Icons.local_bar_rounded,
      desc: 'Zencefilli ejderha meyveli',
      tags: ['Special'],
    ),
    _MenuItem(
      'Guava Bomb',
      '270₺',
      Icons.local_bar_rounded,
      desc: 'Guava patlaması',
    ),
    _MenuItem(
      'Ice Matcha Latte',
      '240₺',
      Icons.local_bar_rounded,
      desc: 'Buzlu matcha sütlü',
      tags: ['Soğuk', 'Popüler'],
    ),
    _MenuItem(
      'Ice Pistachio Dream',
      '270₺',
      Icons.local_bar_rounded,
      desc: 'Antep fıstıklı rüya',
      tags: ['Tatlı'],
      imagePath: 'assets/menu/pistachiodream.jpg',
    ),
    _MenuItem(
      'Luuq Kuzu Kulağı Kokteyl',
      '270₺',
      Icons.local_bar_rounded,
      desc: 'Kuzu kulağı otlu özel tarif',
      tags: ['Special'],
      imagePath: 'assets/menu/kuzukulagi.jpg',
    ),
    _MenuItem(
      'Matcha Mix',
      '270₺',
      Icons.local_bar_rounded,
      desc: 'Matcha karışım kokteyl',
      imagePath: 'assets/menu/matchamix.jpg',
    ),
    _MenuItem(
      'Mazagran',
      '250₺',
      Icons.local_bar_rounded,
      desc: 'Limonlu soğuk kahve',
    ),
    _MenuItem(
      'Rubiqa Mocha',
      '270₺',
      Icons.local_bar_rounded,
      desc: 'Rubika özel mocha',
      tags: ['Special'],
      imagePath: 'assets/menu/rubycamocha.jpeg',
    ),
    _MenuItem(
      'Savaya',
      '270₺',
      Icons.local_bar_rounded,
      desc: 'Tropikal lezzet',
      tags: ['Special'],
    ),
    _MenuItem(
      'Strawberry Cool Lime',
      '260₺',
      Icons.local_bar_rounded,
      desc: 'Çilekli misket limonu',
      tags: ['Yazın İyisi'],
      imagePath: 'assets/menu/strawberrycoollime.jpg',
    ),
    _MenuItem(
      'Sweet & Sour Mix',
      '260₺',
      Icons.local_bar_rounded,
      desc: 'Tatlı ekşi karışım',
    ),
    _MenuItem(
      'Turkish Dream',
      '240₺',
      Icons.local_bar_rounded,
      desc: 'Türk kahveli özel kokteyl',
      tags: ['Special'],
    ),
    _MenuItem(
      'Waffle Juice',
      '260₺',
      Icons.local_bar_rounded,
      desc: 'Waffle aromalı taze sıkım',
      tags: ['Yeni'],
    ),
  ],
  'Bitki Çayları': [
    _MenuItem(
      'Ahududu Limon',
      '220₺',
      Icons.eco_rounded,
      desc: 'Ahududu ve taze limonun canlandırıcı uyumu',
      imagePath: 'assets/menu/bitkicayi.jpeg',
    ),
    _MenuItem(
      'Green Carnaval',
      '220₺',
      Icons.eco_rounded,
      desc: 'Egzotik yeşil çay ve meyve harmonisi',
      imagePath: 'assets/menu/bitkicayi.jpeg',
    ),
    _MenuItem(
      'Gripsavar',
      '220₺',
      Icons.eco_rounded,
      desc: 'Bağışıklık destekleyici zencefil, limon ve bal kürü',
      imagePath: 'assets/menu/bitkicayi.jpeg',
    ),
    _MenuItem(
      'Limon Zencefil',
      '220₺',
      Icons.eco_rounded,
      desc: 'Ferahlatıcı limon ve canlandırıcı zencefil',
      imagePath: 'assets/menu/bitkicayi.jpeg',
    ),
    _MenuItem(
      'Madagascar',
      '220₺',
      Icons.eco_rounded,
      desc: 'Özel baharatlar ve Madagaskar vanilyası harmanı',
      imagePath: 'assets/menu/bitkicayi.jpeg',
    ),
    _MenuItem(
      'Magic Of Bali',
      '220₺',
      Icons.eco_rounded,
      desc: 'Uzak doğunun mistik bitkisel lezzeti',
      imagePath: 'assets/menu/bitkicayi.jpeg',
    ),
    _MenuItem(
      'Relax',
      '220₺',
      Icons.eco_rounded,
      desc: 'Günün stresini alan rahatlatıcı papatya ve melisa',
      imagePath: 'assets/menu/bitkicayi.jpeg',
    ),
  ],
  'Frozen': [
    _MenuItem(
      'Frozen Ananas & Portakal & Limon',
      '265₺',
      Icons.severe_cold_rounded,
      desc: 'Ananas, portakal ve limonun ferah tropikal buluşması.',
      tags: ['Soğuk'],
      imagePath: 'assets/menu/frozenananasportakallimon.jpg',
    ),
    _MenuItem(
      'Frozen Karpuz & Çilek',
      '265₺',
      Icons.severe_cold_rounded,
      desc: 'Karpuzun serinliği, çileğin tatlı aromasıyla birleşir.',
      tags: ['Yazın İyisi', 'Soğuk'],
      imagePath: 'assets/menu/frozenkarpuzcilek.jpg',
    ),
    _MenuItem(
      'Frozen Mango',
      '265₺',
      Icons.severe_cold_rounded,
      desc: 'Yoğun mango aromasıyla egzotik ve ferah bir frozen.',
      tags: ['Soğuk'],
      imagePath: 'assets/menu/frozenmango.jpg',
    ),
    _MenuItem(
      'Frozen Orman Meyveleri',
      '265₺',
      Icons.severe_cold_rounded,
      desc: 'Orman meyvelerinin tatlı-ekşi ferahlığıyla hazırlanır.',
      tags: ['Soğuk', 'Popüler'],
      imagePath: 'assets/menu/frozenormanmeyveleri.jpg',
    ),
    _MenuItem(
      'Frozen Yuzu & Şeftali',
      '265₺',
      Icons.severe_cold_rounded,
      desc: 'Yuzu ferahlığı ve şeftali tatlılığı bir arada.',
      tags: ['Soğuk', 'Yeni'],
      imagePath: 'assets/menu/frozenyuzuseftali.jpg',
    ),
  ],
  'Bubble Tea': [
    _MenuItem(
      'Çilekli Limonata',
      '230₺',
      Icons.bubble_chart_rounded,
      desc: 'Çilek aromasıyla canlanan ferah ve serin limonata.',
      tags: ['Soğuk'],
    ),
    _MenuItem(
      'Fresh Bubble Tea',
      '250₺',
      Icons.bubble_chart_rounded,
      desc: 'Taptaze meyveler ve boba incileriyle ferah bir bubble tea.',
      tags: ['Soğuk'],
      imagePath: 'assets/menu/freshbubble.jpg',
    ),
    _MenuItem(
      'Jungle Bubble Tea',
      '250₺',
      Icons.bubble_chart_rounded,
      desc: 'Tropik meyveler ve yeşil elma boba ile canlı bir içim.',
      tags: ['Yeni', 'Soğuk'],
      imagePath: 'assets/menu/junglebubletea.jpg',
    ),
    _MenuItem(
      'Mango Bubble Tea',
      '250₺',
      Icons.bubble_chart_rounded,
      desc: 'Yoğun mango aroması ve boba incileriyle tropik lezzet.',
      tags: ['Soğuk'],
      imagePath: 'assets/menu/mangobubbletea.jpg',
    ),
    _MenuItem(
      'Naneli Limonata',
      '210₺',
      Icons.bubble_chart_rounded,
      desc: 'Nane ferahlığıyla zenginleşen serin limonata keyfi.',
      tags: ['Soğuk'],
    ),
    _MenuItem(
      'Strawberry Bubble Tea',
      '250₺',
      Icons.bubble_chart_rounded,
      desc: 'Çilek aroması ve boba incileriyle tatlı, eğlenceli bir içim.',
      tags: ['Popüler', 'Tatlı'],
      imagePath: 'assets/menu/strawberrybubbletea.jpg',
    ),
  ],
  'Milkshake': [
    _MenuItem(
      'Milkshake Beyaz Çikolata & Fındık',
      '265₺',
      Icons.icecream_rounded,
      desc: 'Kremamsı beyaz çikolata ve kavrulmuş fındık',
      tags: ['Tatlı'],
      imagePath: 'assets/menu/beyazcikolatafindik.jpg',
    ),
    _MenuItem(
      'Milkshake Bitter & Portakal',
      '265₺',
      Icons.icecream_rounded,
      desc: 'Yoğun bitter çikolata ve taze portakal aroması',
      tags: ['Tatlı'],
      imagePath: 'assets/menu/bitterportakal.jpg',
    ),
    _MenuItem(
      'Milkshake Cinderella',
      '265₺',
      Icons.icecream_rounded,
      desc: 'Çilek, vanilya ve sihirli süslemeler',
      tags: ['Special', 'Tatlı'],
      imagePath: 'assets/menu/cindirella.jpg',
    ),
    _MenuItem(
      'Milkshake Morocco',
      '265₺',
      Icons.icecream_rounded,
      desc: 'Egzotik baharatlı karamel rüyası',
      tags: ['Yeni'],
      imagePath: 'assets/menu/morocco.jpg',
    ),
    _MenuItem(
      'Milkshake Nutella',
      '265₺',
      Icons.icecream_rounded,
      desc: 'Orijinal Nutella ile hazırlanan yoğun lezzet',
      tags: ['Popüler', 'Tatlı'],
      imagePath: 'assets/menu/nutellamilshake.jpg',
    ),
    _MenuItem(
      'Milkshake Tahin & Karamel & Çilek',
      '265₺',
      Icons.icecream_rounded,
      desc: 'Geleneksel tahin, karamel ve çilek füzyonu',
      tags: ['Special'],
      imagePath: 'assets/menu/toffenutkaramelcilek.jpg',
    ),
  ],
  'Meşrubatlar': [
    _MenuItem(
      'Beyoğlu Klasik',
      '125₺',
      Icons.sports_bar_rounded,
      desc: 'Klasik Beyoğlu gazozu ferahlığı',
    ),
    _MenuItem(
      'Beyoğlu Reyhan',
      '125₺',
      Icons.sports_bar_rounded,
      desc: 'Reyhan aromalı efsanevi gazoz',
    ),
    _MenuItem(
      'Beyoğlu Zencefil',
      '125₺',
      Icons.sports_bar_rounded,
      desc: 'Zencefil aromalı serinletici gazoz',
    ),
    _MenuItem(
      'Redbull',
      '170₺',
      Icons.sports_bar_rounded,
      desc: 'Enerji veren klasik lezzet',
    ),
    _MenuItem(
      'Damla Soda (200 ml)',
      '90₺',
      Icons.sports_bar_rounded,
      desc: 'Doğal mineralli su',
    ),
    _MenuItem(
      'Damla Soda (330 ml)',
      '100₺',
      Icons.sports_bar_rounded,
      desc: 'Doğal mineralli su büyük boy',
    ),
    _MenuItem(
      'Damla Cam Su (330 ml)',
      '60₺',
      Icons.sports_bar_rounded,
      desc: 'Cam şişede doğal kaynak suyu',
    ),
    _MenuItem(
      'Uludağ Premium Soda',
      '100₺',
      Icons.sports_bar_rounded,
      desc: 'Özel cam şişede premium maden suyu',
    ),
  ],
  'Dondurmalar': [
    _MenuItem(
      'Vanilya',
      '100₺',
      Icons.icecream_outlined,
      desc: 'Klasik ve yoğun gerçek vanilya çekirdeği lezzeti.',
      tags: ['Yazın İyisi', 'Soğuk'],
    ),
    _MenuItem(
      'Kakao',
      '100₺',
      Icons.icecream_outlined,
      desc: 'Yoğun çikolata dolgulu geleneksel kakao keyfi.',
      tags: ['Yazın İyisi', 'Soğuk'],
    ),
    _MenuItem(
      'Karamel',
      '100₺',
      Icons.icecream_outlined,
      desc: 'Karamel soslu tatlı ve kremamsı dondurma.',
      tags: ['Yazın İyisi', 'Soğuk'],
    ),
    _MenuItem(
      'Antep Fıstığı',
      '100₺',
      Icons.icecream_outlined,
      desc: 'Taze Antep fıstığı parçacıklarıyla zenginleşen lezzet.',
      tags: ['Yazın İyisi', 'Soğuk'],
    ),
    _MenuItem(
      'Limon',
      '100₺',
      Icons.icecream_outlined,
      desc: 'Ekşi ve ferahlatıcı gerçek limon aroması.',
      tags: ['Yazın İyisi', 'Soğuk'],
    ),
    _MenuItem(
      'Kavun',
      '100₺',
      Icons.icecream_outlined,
      desc: 'Yaz kavununun tatlı ve sulu serinliği.',
      tags: ['Yazın İyisi', 'Soğuk'],
    ),
    _MenuItem(
      'Çilek',
      '100₺',
      Icons.icecream_outlined,
      desc: 'Taze yaz çilekleriyle hazırlanan meyveli dondurma.',
      tags: ['Yazın İyisi', 'Soğuk'],
    ),
    _MenuItem(
      'Karadut',
      '100₺',
      Icons.icecream_outlined,
      desc: 'Doğal karadut taneleriyle tatlı-ekşi ferahlık.',
      tags: ['Yazın İyisi', 'Soğuk'],
    ),
    _MenuItem(
      'Bal Badem',
      '100₺',
      Icons.icecream_outlined,
      desc: 'Süzme bal ve çıtır badem parçacıklarının uyumu.',
      tags: ['Yazın İyisi', 'Soğuk'],
    ),
    _MenuItem(
      'Bubble Gum',
      '100₺',
      Icons.icecream_outlined,
      desc: 'Eğlenceli sakız aromalı çocuksu tat.',
      tags: ['Yazın İyisi', 'Soğuk'],
    ),
    _MenuItem(
      'Blue Sky',
      '100₺',
      Icons.icecream_outlined,
      desc: 'Farklı ve özel aromasıyla gökyüzü mavisi lezzet.',
      tags: ['Yazın İyisi', 'Soğuk'],
    ),
    _MenuItem(
      'Meyve Şöleni',
      '100₺',
      Icons.icecream_outlined,
      desc: 'Karışık yaz meyvelerinin eşsiz uyumu.',
      tags: ['Yazın İyisi', 'Soğuk'],
    ),
    _MenuItem(
      'Oreo',
      '100₺',
      Icons.icecream_outlined,
      desc: 'Çıtır Oreo bisküvi parçacıklarıyla kremamsı dondurma.',
      tags: ['Yazın İyisi', 'Soğuk'],
    ),
  ],
  'Pasta & Tatlı': [
    _MenuItem(
      'Allgo Dom Pasta',
      '295₺',
      Icons.cake_rounded,
      desc: 'Özel kubbe tasarım çikolatalı pasta',
      tags: ['Special', 'Tatlı'],
    ),
    _MenuItem(
      'Ananas Badem Mono Pasta',
      '295₺',
      Icons.cake_rounded,
      desc: 'Ananas ve bademin hafif tatlı uyumu',
    ),
    _MenuItem(
      'Antep Dolgulu Cheesecake',
      '295₺',
      Icons.cake_rounded,
      desc: 'İçi bol fıstıklı çıtır cheesecake',
      tags: ['Popüler'],
      imagePath: 'assets/menu/antepcheesecake.jpeg',
    ),
    _MenuItem(
      'Antep Fıstıklı Tart',
      '305₺',
      Icons.cake_rounded,
      desc: 'Bol fıstıklı çıtır hamurlu Fransız tartı',
    ),
    _MenuItem(
      'Bademli Kruvasan',
      '295₺',
      Icons.cake_rounded,
      desc: 'Taze fırınlanmış badem kremalı kruvasan',
    ),
    _MenuItem(
      'Blondie Limon',
      '305₺',
      Icons.cake_rounded,
      desc: 'Limon ferahlığıyla beyaz çikolatalı blondie',
      tags: ['Yeni'],
    ),
    _MenuItem(
      'Cheesecake Patlayan Şeker',
      '285₺',
      Icons.cake_rounded,
      desc: 'Ağızda patlayan şekerli eğlenceli tatlı',
      tags: ['Special'],
    ),
    _MenuItem(
      'Cheesecake San Sebastian',
      '295₺',
      Icons.cake_rounded,
      desc: 'Yanık kabuklu, akışkan içiyle İspanyol klasiği',
      tags: ['Popüler', 'Klasik'],
      imagePath: 'assets/menu/sansebastian.jpeg',
    ),
    _MenuItem(
      'Çikolatalı Cookie Pie',
      '400₺',
      Icons.cake_rounded,
      desc: 'Dev çikolatalı kurabiye turtası',
      tags: ['Tatlı'],
    ),
    _MenuItem(
      'Çikolatalı Tırtıl Pasta',
      '285₺',
      Icons.cake_rounded,
      desc: 'Çocukların favorisi çikolatalı özel pasta',
    ),
    _MenuItem(
      'Elmalı Tart',
      '295₺',
      Icons.cake_rounded,
      desc: 'Tarçın ve karamelize elmalı çıtır tart',
      tags: ['Klasik'],
    ),
    _MenuItem(
      'Fındıklı Kruvasan',
      '295₺',
      Icons.cake_rounded,
      desc: 'Fındık kreması dolgulu sıcak kruvasan',
    ),
    _MenuItem(
      'Frambuaz & Antep Fıstıklı Kek',
      '295₺',
      Icons.cake_rounded,
      desc: 'Hafif ekşi frambuaz ve yeşil fıstık şöleni',
    ),
    _MenuItem(
      'Frambuazlı Mono Pasta',
      '295₺',
      Icons.cake_rounded,
      desc: 'Tek kişilik taze meyveli hafif pasta',
    ),
    _MenuItem(
      'Kesme Fındıklı Pasta',
      '435₺',
      Icons.cake_rounded,
      desc: 'Geleneksel kesme dondurma formunda pasta',
    ),
    _MenuItem(
      'Lime Ekler',
      '295₺',
      Icons.cake_rounded,
      desc: 'Misket limonu kremalı hafif ekler',
      tags: ['Yeni'],
    ),
    _MenuItem(
      'Limon & Frangipane Tart',
      '305₺',
      Icons.cake_rounded,
      desc: 'Badem kremalı limonlu zarif tart',
    ),
    _MenuItem(
      'Limon & Haşhaşlı Baton Kek',
      '155₺',
      Icons.cake_rounded,
      desc: 'Çıtır haşhaş ve taze limonlu kek dilimi',
    ),
    _MenuItem(
      'Lotus Mono Ekler',
      '295₺',
      Icons.cake_rounded,
      desc: 'Orijinal Lotus bisküvi kremalı porsiyonluk ekler',
      tags: ['Popüler'],
    ),
    _MenuItem(
      'Luuq Çikolatalı Mousse Pasta',
      '285₺',
      Icons.cake_rounded,
      desc: 'Köpüksü hafifliğiyle yoğun çikolata',
      tags: ['Special'],
    ),
    _MenuItem(
      'Mermer Baton Kek',
      '155₺',
      Icons.cake_rounded,
      desc: 'Vanilya ve kakaolu klasik mermer kek',
    ),
    _MenuItem(
      'Oreo Cheesecake',
      '305₺',
      Icons.cake_rounded,
      desc: 'Bol Oreo bisküvili klasik peynir tatlısı',
    ),
    _MenuItem(
      'Orman Meyveli Cup',
      '285₺',
      Icons.cake_rounded,
      desc: 'Bardakta taze meyveli kat kat lezzet',
    ),
    _MenuItem(
      'Orman Meyveli Elips Tart',
      '285₺',
      Icons.cake_rounded,
      desc: 'Özel şekliyle orman meyveli çıtır tart',
    ),
    _MenuItem(
      'Paris Breast',
      '295₺',
      Icons.cake_rounded,
      desc: 'Halka şeklinde badem kremalı Fransız tatlısı',
      tags: ['Special'],
    ),
    _MenuItem(
      'Passion & Çikolatalı Tart',
      '295₺',
      Icons.cake_rounded,
      desc: 'Çarkıfelek meyvesi ve çikolata buluşması',
    ),
    _MenuItem(
      'Smores Cup',
      '285₺',
      Icons.cake_rounded,
      desc: 'Kızarmış marshmallow ve çikolatalı kupa',
      tags: ['Yeni'],
    ),
    _MenuItem(
      'Tiramisu',
      '285₺',
      Icons.cake_rounded,
      desc: 'Espresso ile ıslatılmış mascarpone peynirli klasik',
      tags: ['Klasik'],
    ),
    _MenuItem(
      'Trio Chocolate Browni',
      '265₺',
      Icons.cake_rounded,
      desc: 'Üç çikolatalı yoğun brownie',
      tags: ['Popüler'],
      imagePath: 'assets/menu/brownie.jpeg',
    ),
    _MenuItem(
      'Üçgen Dilim Fıstıklı Cheesecake',
      '435₺',
      Icons.cake_rounded,
      desc: 'Yoğun fıstıklı dilimlenmiş dev cheesecake',
    ),
    _MenuItem(
      'Vişneli Tart',
      '305₺',
      Icons.cake_rounded,
      desc: 'Ekşi vişnelerle dengelenmiş tatlı tart',
    ),
    _MenuItem(
      'Vişneli Brownie',
      '275₺',
      Icons.cake_rounded,
      desc: 'İçi ıslak, vişne taneli brownie rüyası',
      imagePath: 'assets/menu/visnelibrownie.jpeg',
    ),
    _MenuItem(
      'White Cascada Dom Pasta',
      '285₺',
      Icons.cake_rounded,
      desc: 'Beyaz çikolatalı şelale tasarımlı pasta',
      imagePath: 'assets/menu/whitecascada.jpeg',
    ),
    _MenuItem(
      'Brownie Dream',
      '285₺',
      Icons.cake_rounded,
      desc: 'Özel krema dolgulu enfes brownie rüyası',
      imagePath: 'assets/menu/browniedream.jpeg',
    ),
    _MenuItem(
      'Çilek Limon Mono Pasta',
      '295₺',
      Icons.cake_rounded,
      desc: 'Çilek ve limon ferahlığıyla mono pasta',
      imagePath: 'assets/menu/cileklimonopasta.jpeg',
    ),
    _MenuItem(
      'Limonlu Pasta',
      '295₺',
      Icons.cake_rounded,
      desc: 'Limon soslu ve kremalı nefis pasta dilimi',
      imagePath: 'assets/menu/limonlupasta.jpeg',
    ),
    _MenuItem(
      'Yanık Cheesecake',
      '305₺',
      Icons.cake_rounded,
      desc: 'San Sebastian tarzı yanık üst kabuklu',
    ),
  ],
  'LUUQ Chocolate': [
    _MenuItem(
      'Luuq Chocolate Delight',
      '410₺',
      Icons.cookie_rounded,
      desc: 'Luuq ustalarından özel çikolata lokumu',
      tags: ['Special'],
      imagePath: 'assets/menu/luuqchocolatedelight.jpg',
    ),
    _MenuItem(
      'Luuq Chocolate Joy',
      '410₺',
      Icons.cookie_rounded,
      desc: 'Fındık ve fıstık dolgulu neşe küpleri',
      imagePath: 'assets/menu/luuqchocolatejoy.jpg',
    ),
    _MenuItem(
      'Luuq Cream Puff',
      '445₺',
      Icons.cookie_rounded,
      desc: 'İçi taze krema dolgulu çikolata topları',
      imagePath: 'assets/menu/luuqcreampuff.jpg',
    ),
    _MenuItem(
      'Luuq Crispy Dream',
      '445₺',
      Icons.cookie_rounded,
      desc: 'Çıtır gofret parçalı rüya gibi çikolata',
      imagePath: 'assets/menu/luuqcrispydream.jpg',
    ),
    _MenuItem(
      'Luuq Dubai Chocolate Cup',
      '445₺',
      Icons.cookie_rounded,
      desc: 'Künefe ve fıstık dolgulu meşhur Dubai çikolatası',
      tags: ['Popüler', 'Yeni'],
      imagePath: 'assets/menu/luuqdubaichocolatecup.jpg',
    ),
    _MenuItem(
      'Luuq White Chocolate Delight',
      '410₺',
      Icons.cookie_rounded,
      desc: 'Beyaz çikolata sevenlere özel spesiyal',
      imagePath: 'assets/menu/luuqwhitechocolatedelight.jpg',
    ),
  ],
  'Sandviç': [
    _MenuItem(
      'Dana Jambon',
      '275₺',
      Icons.lunch_dining_rounded,
      desc: 'Taze yeşilliklerle dana jambonlu sandviç',
    ),
    _MenuItem(
      'Haşhaşlı Cabata Sandviç',
      '275₺',
      Icons.lunch_dining_rounded,
      desc: 'Haşhaşlı taze ekmek içinde özel peynir',
    ),
    _MenuItem(
      'Ezine Peynirli Tahıllı Cabata Sandviç',
      '275₺',
      Icons.lunch_dining_rounded,
      desc: 'Tam tahıllı ekmek, ezine peyniri ve domates',
      tags: ['Klasik'],
    ),
    _MenuItem(
      'Haşhaşlı 4 Peynirli Bagel Sandviç',
      '265₺',
      Icons.lunch_dining_rounded,
      desc: 'Erimiş 4 peynirli doyurucu bagel',
    ),
    _MenuItem(
      'Haşhaşlı Cabata Hindi Füme Tahıllı',
      '275₺',
      Icons.lunch_dining_rounded,
      desc: 'Hindi füme ve yeşillikli hafif öğün',
    ),
    _MenuItem(
      'Cabata Sandviç',
      '275₺',
      Icons.lunch_dining_rounded,
      desc: 'Günlük taze cabata ekmeğine lezzetler',
    ),
    _MenuItem(
      'Pesto Soslu Tavuklu Sandviç',
      '295₺',
      Icons.lunch_dining_rounded,
      desc: 'İtalyan pesto soslu ızgara tavuk',
      tags: ['Popüler'],
    ),
    _MenuItem(
      'Tahıllı Üçgen Panini',
      '285₺',
      Icons.lunch_dining_rounded,
      desc: 'Tost makinesinde ısıtılmış kaşarlı panini',
    ),
    _MenuItem(
      'Yedi Foccacia Ezine Peynirli Sandviç',
      '295₺',
      Icons.lunch_dining_rounded,
      desc: 'Zeytinyağlı foccacia arası ezine',
    ),
    _MenuItem(
      'Yedi Foccacia Hindi Sandviç',
      '295₺',
      Icons.lunch_dining_rounded,
      desc: 'İtalyan ekmeğinde ince dilim hindi füme',
    ),
    _MenuItem(
      'Yedi Roast Beef Sandviç',
      '285₺',
      Icons.lunch_dining_rounded,
      desc: 'Közlenmiş biber ve roast beef eti',
      tags: ['Special'],
    ),
    _MenuItem(
      'Yulaflı Cabata',
      '250₺',
      Icons.lunch_dining_rounded,
      desc: 'Yulaf ezmeli sağlıklı sandviç seçeneği',
    ),
  ],
  'Termos & Seramik': [
    _MenuItem(
      'Seramik Demlik',
      '1750₺',
      Icons.coffee_rounded,
      desc: 'El yapımı özel seramik çay demliği',
    ),
    _MenuItem(
      'Seramik Double Türk Kahvesi Seti',
      '1200₺',
      Icons.coffee_rounded,
      desc: 'İki kişilik şık Türk kahvesi fincan takımı',
    ),
    _MenuItem(
      'Seramik Kupa - Altlık',
      '1200₺',
      Icons.coffee_rounded,
      desc: 'Tabağıyla birlikte el yapımı kahve kupası',
    ),
    _MenuItem(
      'Seramik Pasta Tabağı',
      '1200₺',
      Icons.coffee_rounded,
      desc: 'Tatlı sunumları için özel tasarım tabak',
    ),
    _MenuItem(
      'Seramik Türk Kahvesi Seti',
      '1200₺',
      Icons.coffee_rounded,
      desc: 'Tek kişilik özel tasarım kahve seti',
    ),
    _MenuItem(
      'Trm04s Rose 400 ml Termos',
      '995₺',
      Icons.coffee_rounded,
      desc: 'Rose gold renkli şık çelik termos',
    ),
    _MenuItem(
      'Trm094 Beyaz Ofset 350 ml Çelik Termos',
      '720₺',
      Icons.coffee_rounded,
      desc: 'Minimal beyaz tasarımlı kompakt termos',
    ),
    _MenuItem(
      'Trm094 K.rengi Ofset 350 ml Çelik Termos',
      '720₺',
      Icons.coffee_rounded,
      desc: 'Kahverengi tonlarında sızdırmaz termos',
    ),
    _MenuItem(
      'Trm119 Siyah 500 ml Çelik Mug Termos',
      '995₺',
      Icons.coffee_rounded,
      desc: 'Mat siyah geniş hacimli mug termos',
    ),
    _MenuItem(
      'Trm159 Haki 350 ml Çelik Termos',
      '995₺',
      Icons.coffee_rounded,
      desc: 'Haki yeşili dayanıklı çelik termos',
    ),
    _MenuItem(
      'Trm159 Krem 350 ml Çelik Termos',
      '995₺',
      Icons.coffee_rounded,
      desc: 'Krem renkli zarif çelik termos',
    ),
    _MenuItem(
      'Trm175 Siyah 500 ml Çelik Termos',
      '995₺',
      Icons.coffee_rounded,
      desc: 'Isı yalıtımlı mat siyah çelik termos',
    ),
    _MenuItem(
      'Trm173 Yeşil 350 ml Çelik Termos',
      '995₺',
      Icons.coffee_rounded,
      desc: 'Doğa yeşili tonlarında şık termos',
    ),
    _MenuItem(
      'Trm185-B 380 ml Beyaz Termos',
      '995₺',
      Icons.coffee_rounded,
      desc: 'Ergonomik beyaz renkli pratik termos',
    ),
    _MenuItem(
      'Trm185-G 380 ml Gri Termos',
      '995₺',
      Icons.coffee_rounded,
      desc: 'Modern gri tasarımlı günlük termos',
    ),
  ],
  'Ekstralar': [
    _MenuItem(
      'Bademli Süt',
      '50₺',
      Icons.add_circle_outline_rounded,
      desc: 'İçeceğinize vegan badem sütü alternatifi',
    ),
    _MenuItem(
      'Bubble',
      '50₺',
      Icons.add_circle_outline_rounded,
      desc: 'İçeceğinize ekstra patlayan meyve incileri',
    ),
    _MenuItem(
      'Balparmak (7 gr)',
      '100₺',
      Icons.add_circle_outline_rounded,
      desc: 'Tek kullanımlık doğal süzme bal',
    ),
    _MenuItem(
      'Calebaut',
      '80₺',
      Icons.add_circle_outline_rounded,
      desc: 'Gerçek Belçika çikolatası ilavesi',
    ),
    _MenuItem(
      'Dondurma',
      '75₺',
      Icons.add_circle_outline_rounded,
      desc: 'İçeceğinizin veya tatlınızın yanına bir top dondurma',
    ),
    _MenuItem(
      'Ekstra Çilek (Meyve)',
      '80₺',
      Icons.add_circle_outline_rounded,
      desc: 'Taze çilek dilimleri ilavesi',
    ),
    _MenuItem(
      'Ekstra Muz (Meyve)',
      '60₺',
      Icons.add_circle_outline_rounded,
      desc: 'Taze muz dilimleri ilavesi',
    ),
    _MenuItem(
      'Laktozsuz Süt',
      '50₺',
      Icons.add_circle_outline_rounded,
      desc: 'Hassas mideler için laktozsuz süt alternatifi',
    ),
    _MenuItem(
      'Fındık Süt',
      '50₺',
      Icons.add_circle_outline_rounded,
      desc: 'İçeceğinize fındık aromalı bitkisel süt',
    ),
    _MenuItem(
      'Krema',
      '30₺',
      Icons.add_circle_outline_rounded,
      desc: 'İçeceğinizin üzerine taze krem şanti',
    ),
    _MenuItem(
      'Püre',
      '30₺',
      Icons.add_circle_outline_rounded,
      desc: 'İçecekler için ekstra meyve püresi',
    ),
    _MenuItem(
      'Shot',
      '50₺',
      Icons.add_circle_outline_rounded,
      desc: 'Kahvenize ekstra bir shot espresso',
    ),
    _MenuItem(
      'Sos',
      '50₺',
      Icons.add_circle_outline_rounded,
      desc: 'Tatlınıza veya içeceğinize ekstra çikolata/karamel sos',
    ),
    _MenuItem(
      'Şurup',
      '30₺',
      Icons.add_circle_outline_rounded,
      desc: 'Farklı aromalarda ekstra şurup ilavesi',
    ),
    _MenuItem(
      'Yulaf Süt',
      '50₺',
      Icons.add_circle_outline_rounded,
      desc: 'İçeceğinize vegan yulaf sütü alternatifi',
    ),
  ],
};

class _MenuDialog extends StatefulWidget {
  const _MenuDialog();

  @override
  State<_MenuDialog> createState() => _MenuDialogState();
}

class _MenuDialogState extends State<_MenuDialog> {
  String _selectedCategory = 'Espresso Kahveler';
  String _searchQuery = '';
  final ScrollController _categoryScrollController = ScrollController();
  final ScrollController _itemsScrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    AnalyticsService.instance.trackMenuOpen();
  }

  @override
  void dispose() {
    _categoryScrollController.dispose();
    _itemsScrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  List<_MenuItem> get _filteredItems {
    final items = _menuCategories[_selectedCategory] ?? [];
    if (_searchQuery.isEmpty) return items;
    final q = _searchQuery.toLowerCase();
    // Search across ALL categories
    final allItems = <_MenuItem>[];
    for (final entry in _menuCategories.entries) {
      for (final item in entry.value) {
        if (trMenu(item.name).toLowerCase().contains(q) ||
            trMenu(item.desc).toLowerCase().contains(q)) {
          allItems.add(item);
        }
      }
    }
    return allItems;
  }

  // Parse M/L pricing: "185₺ / 205₺" → two prices, "220₺" → single
  bool _hasDualPrice(String price) => price.contains('/');

  String _mPrice(String price) {
    final parts = price.split('/');
    return parts[0].trim();
  }

  String _lPrice(String price) {
    final parts = price.split('/');
    return parts.length > 1 ? parts[1].trim() : '';
  }

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final screenH = MediaQuery.of(context).size.height;
    final items = _filteredItems;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(
        horizontal: screenW * 0.10,
        vertical: screenH * 0.06,
      ),
      child: Container(
        width: screenW * 0.80,
        height: screenH * 0.88,
        decoration: BoxDecoration(
          color: const Color(0xFF1C1724), // Solid dark plum/charcoal
          borderRadius: BorderRadius.circular(40),
          border: Border.all(color: _gold.withValues(alpha: 0.2), width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.9),
              blurRadius: 80,
              spreadRadius: 20,
            ),
            BoxShadow(color: _gold.withValues(alpha: 0.08), blurRadius: 40),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(38),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset('assets/menuphoto1.jpg', fit: BoxFit.cover),
              // Premium Dark Overlay for Readability
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF14101A).withValues(alpha: 0.65),
                      const Color(0xFF1C1724).withValues(alpha: 0.80),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
              Column(
                children: [
                  // ─── TOP HEADER BAR ───
                  _buildMenuHeader(),
                  // ─── BODY: Sidebar + Items ───
                  Expanded(
                    child: Row(
                      children: [
                        // Left Sidebar
                        _buildCategorySidebar(),
                        // Vertical divider
                        Container(
                          width: 1,
                          color: Colors.white.withValues(alpha: 0.06),
                        ),
                        // Right Content
                        Expanded(child: _buildItemsPanel(items)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══ HEADER ═══
  Widget _buildMenuHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(40, 28, 28, 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1A1520).withValues(alpha: 0.5),
            const Color(0xFF241E2E).withValues(alpha: 0.5),
          ],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        border: Border(
          bottom: BorderSide(color: _gold.withValues(alpha: 0.12)),
        ),
      ),
      child: Row(
        children: [
          // Logo icon
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _gold.withValues(alpha: 0.25),
                  _caramel.withValues(alpha: 0.15),
                ],
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.restaurant_menu_rounded,
              color: _gold,
              size: 30,
            ),
          ),
          const SizedBox(width: 20),
          // Title + subtitle
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr('LUUQ MENÜ', 'LUUQ MENU'),
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 6,
                    foreground: Paint()
                      ..shader = const LinearGradient(
                        colors: [_cream, _gold],
                      ).createShader(const Rect.fromLTWH(0, 0, 250, 40)),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  tr(
                    'Kategoriyi seç, lezzetleri keşfet.',
                    'Choose a category, explore the flavors.',
                  ),
                  style: TextStyle(
                    fontSize: 15,
                    color: _muted,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
          // Close button
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: const Icon(
                Icons.close_rounded,
                color: Colors.white70,
                size: 26,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══ CATEGORY SIDEBAR ═══
  Widget _buildCategorySidebar() {
    final categories = _menuCategories.keys.toList();
    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: const Color(0xFF14101A).withValues(alpha: 0.5),
        border: Border(
          right: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
        ),
      ),
      child: ScrollbarTheme(
        data: ScrollbarThemeData(
          thumbColor: WidgetStateProperty.all(_gold.withValues(alpha: 0.3)),
          thickness: WidgetStateProperty.all(3),
          radius: const Radius.circular(10),
        ),
        child: Scrollbar(
          controller: _categoryScrollController,
          child: ListView.builder(
            controller: _categoryScrollController,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            itemCount: categories.length,
            itemBuilder: (context, index) {
              final category = categories[index];
              final isSelected =
                  category == _selectedCategory && _searchQuery.isEmpty;
              final icon = _categoryIcons[category] ?? Icons.circle;
              final itemCount = _menuCategories[category]?.length ?? 0;

              return Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedCategory = category;
                      _searchQuery = '';
                      _searchController.clear();
                    });
                    if (_itemsScrollController.hasClients) {
                      _itemsScrollController.jumpTo(0);
                    }
                    AnalyticsService.instance.trackCategoryClick(category);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutQuint,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? _caramel.withValues(alpha: 0.15)
                          : const Color(0xFF1C1724).withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSelected
                            ? _gold.withValues(alpha: 0.5)
                            : Colors.white.withValues(alpha: 0.03),
                        width: 1.5,
                      ),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: _gold.withValues(alpha: 0.1),
                                blurRadius: 15,
                                offset: const Offset(0, 4),
                              ),
                            ]
                          : [],
                    ),
                    child: Row(
                      children: [
                        // Icon
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? _gold
                                : Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            icon,
                            color: isSelected
                                ? _bgDark
                                : Colors.white.withValues(alpha: 0.8),
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Text & Badge
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                trMenu(category),
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: isSelected
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                  color: isSelected
                                      ? _cream
                                      : Colors.white.withValues(alpha: 0.85),
                                  letterSpacing: 0.5,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? _gold.withValues(alpha: 0.2)
                                      : Colors.white.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  tr('$itemCount Ürün', '$itemCount Items'),
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: isSelected
                                        ? _gold
                                        : Colors.white.withValues(alpha: 0.7),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (isSelected)
                          const Icon(
                            Icons.chevron_right_rounded,
                            color: _gold,
                            size: 20,
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  // ═══ ITEMS PANEL ═══
  Widget _buildItemsPanel(List<_MenuItem> items) {
    return Column(
      children: [
        // ─── SEARCH & HERO AREA ───
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 24, 32, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Search bar
              Container(
                height: 54,
                decoration: BoxDecoration(
                  color: const Color(0xFF14101A).withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: TextField(
                  controller: _searchController,
                  onChanged: (v) => setState(() => _searchQuery = v),
                  style: const TextStyle(color: _cream, fontSize: 16),
                  decoration: InputDecoration(
                    hintText: tr(
                      'Menüde lezzet veya kategori ara...',
                      'Search for a flavor or category...',
                    ),
                    hintStyle: TextStyle(
                      color: Colors.white.withValues(alpha: 0.3),
                      fontSize: 15,
                    ),
                    prefixIcon: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Icon(
                        Icons.search_rounded,
                        color: _gold.withValues(alpha: 0.8),
                        size: 24,
                      ),
                    ),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? GestureDetector(
                            onTap: () => setState(() {
                              _searchQuery = '';
                              _searchController.clear();
                            }),
                            child: const Icon(
                              Icons.close_rounded,
                              color: Colors.white54,
                              size: 22,
                            ),
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              // Category Hero
              if (_searchQuery.isEmpty)
                _buildCategoryHero(items)
              else
                _buildSearchHero(items),
            ],
          ),
        ),

        // ─── ITEMS GRID ───
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            switchInCurve: Curves.easeOutQuad,
            switchOutCurve: Curves.easeInQuad,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.05),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: GridView.builder(
              key: ValueKey(
                _searchQuery.isNotEmpty
                    ? 'search_$_searchQuery'
                    : _selectedCategory,
              ),
              controller: _itemsScrollController,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 3.5, // More compact cards as requested
              ),
              itemCount: items.length,
              itemBuilder: (context, index) => _buildMenuItemCard(items[index]),
            ), // end of GridView.builder
          ), // end of AnimatedSwitcher
        ), // end of Expanded
      ],
    );
  }

  // ═══ CATEGORY HERO ═══
  Widget _buildCategoryHero(List<_MenuItem> items) {
    final description = trMenu(
      _categoryDescriptions[_selectedCategory] ??
          tr(
            'Bu kategoride ${items.length} ürün bulunuyor.',
            'There are ${items.length} products in this category.',
          ),
    );
    final populars = items
        .where((i) => i.tags.contains('Popüler'))
        .take(3)
        .map((i) => i.name)
        .join(', ');

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF231E2D).withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _gold.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _gold.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _categoryIcons[_selectedCategory] ?? Icons.circle,
                  color: _gold,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  trMenu(_selectedCategory).toUpperCase(),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: _gold,
                    letterSpacing: 2,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.05),
                  ),
                ),
                child: Text(
                  tr('${items.length} Ürün', '${items.length} Items'),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.white70,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            description,
            style: const TextStyle(
              fontSize: 15,
              color: Colors.white70,
              height: 1.4,
            ),
          ),
          if (populars.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _gold.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _gold.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.star_rounded, color: _gold, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    tr('Popüler Favoriler: ', 'Popular Favorites: '),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: _gold,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      populars,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: _cream,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSearchHero(List<_MenuItem> items) {
    return Row(
      children: [
        const Icon(Icons.search_rounded, color: _gold, size: 24),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            tr('"$_searchQuery" için sonuçlar', 'Results for "$_searchQuery"'),
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: _gold,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: _gold.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            tr('${items.length} Bulundu', '${items.length} Found'),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: _gold,
            ),
          ),
        ),
      ],
    );
  }

  // ═══ PRODUCT DETAIL DIALOG ═══
  void _showProductDetailDialog(_MenuItem item) {
    if (!currentFeatureFlags.menu) {
      showFeatureLockedDialog(context, tr('Ürün Detayı', 'Product Detail'));
      return;
    }
    AnalyticsService.instance.trackProductDetailOpen(
      _generateSlug(item.name),
      item.name,
      _selectedCategory,
    );
    showDialog(
      context: context,
      builder: (context) =>
          _VirtualCanvasDialogWrapper(child: _ProductDetailDialog(item: item)),
    );
  }

  // ═══ MENU ITEM CARD ═══
  Widget _buildMenuItemCard(_MenuItem item) {
    final hasTags = item.tags.isNotEmpty;
    final isPopular = item.tags.contains('Popüler');
    final isSpecial = item.tags.contains('Special');
    final dual = _hasDualPrice(item.price);

    return BouncyButton(
      onTap: () {
        AnalyticsService.instance.trackProductClick(
          _generateSlug(item.name),
          item.name,
          _selectedCategory,
        );
        _showProductDetailDialog(item);
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF282136).withValues(alpha: 0.85),
              const Color(0xFF1B1624).withValues(alpha: 0.85),
            ],
          ),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: isSpecial
                ? _gold.withValues(alpha: 0.4)
                : Colors.white.withValues(alpha: 0.08),
            width: 1.5,
          ),
          boxShadow: [
            if (isSpecial)
              BoxShadow(
                color: _gold.withValues(alpha: 0.12),
                blurRadius: 18,
                spreadRadius: 1,
              ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // ─── THUMBNAIL AREA ───
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: const Color(0xFF16131D).withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                image: item.imagePath != null
                    ? DecorationImage(
                        image: ResizeImage(
                          AssetImage(item.imagePath!),
                          width: 176, // Essential for fast scrolling
                        ),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: item.imagePath == null
                  ? Center(
                      child: Icon(
                        item.icon,
                        color: _gold.withValues(alpha: 0.75),
                        size: 38,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 16),
            // ─── INFO AREA ───
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Name + Badges
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      Text(
                        trMenu(item.name),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: _gold,
                          height: 1.2,
                          letterSpacing: 0.3,
                        ),
                      ),
                      if (isPopular || isSpecial)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: (isSpecial ? const Color(0xFFE879A8) : _gold)
                                .withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color:
                                  (isSpecial ? const Color(0xFFE879A8) : _gold)
                                      .withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isSpecial
                                    ? Icons.star_rounded
                                    : Icons.star_rounded,
                                size: 14,
                                color: isSpecial
                                    ? const Color(0xFFE879A8)
                                    : _gold,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                isSpecial ? 'Special' : trMenu('Popüler'),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  color: isSpecial
                                      ? const Color(0xFFE879A8)
                                      : _gold,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  // Description
                  if (trMenu(item.desc).isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      trMenu(item.desc),
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: 0.75),
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  // Tags (filtered to avoid redundancy)
                  if (hasTags) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: item.tags
                          .where((tag) => tag != 'Popüler' && tag != 'Special')
                          .map((tag) {
                            final color =
                                _tagStyles[tag] ?? const Color(0xFFB2BEC3);
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: color.withValues(alpha: 0.4),
                                ),
                              ),
                              child: Text(
                                trMenu(tag),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: color,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            );
                          })
                          .toList(),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            // ─── PRICE AREA ───
            dual
                ? _buildDualPriceBadge(item.price)
                : _buildSinglePrice(item.price),
          ],
        ),
      ),
    );
  }

  // ═══ SINGLE PRICE ═══
  Widget _buildSinglePrice(String price) {
    return Container(
      width: 90,
      height: 46,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _gold.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _gold.withValues(alpha: 0.4)),
      ),
      child: Text(
        price,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w900,
          color: _gold,
        ),
      ),
    );
  }

  // ═══ DUAL PRICE BADGES (M / L) ═══
  Widget _buildDualPriceBadge(String price) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _priceBadge('M', _mPrice(price)),
        const SizedBox(height: 6),
        _priceBadge('L', _lPrice(price)),
      ],
    );
  }

  Widget _priceBadge(String label, String price) {
    return Container(
      padding: const EdgeInsets.only(right: 6),
      decoration: BoxDecoration(
        color: _gold.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _gold.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 32,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(vertical: 5),
            decoration: BoxDecoration(
              color: _gold.withValues(alpha: 0.2),
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(9),
                right: Radius.circular(4),
              ),
            ),
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: _gold,
              ),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 44,
            child: Text(
              price,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: _cream,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductDetailDialog extends StatelessWidget {
  final _MenuItem item;
  const _ProductDetailDialog({required this.item});

  bool _hasDualPrice(String price) => price.contains('/');

  String _mPrice(String price) {
    final parts = price.split('/');
    return parts.isNotEmpty ? parts[0].trim() : price;
  }

  String _lPrice(String price) {
    final parts = price.split('/');
    return parts.length > 1 ? parts[1].trim() : price;
  }

  Widget _priceBadge(String label, String price) {
    return Container(
      padding: const EdgeInsets.only(right: 6),
      decoration: BoxDecoration(
        color: _gold.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _gold.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 32,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(vertical: 5),
            decoration: BoxDecoration(
              color: _gold.withValues(alpha: 0.2),
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(9),
                right: Radius.circular(4),
              ),
            ),
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: _gold,
              ),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 44,
            child: Text(
              price,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: _cream,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSinglePrice(String price) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
      decoration: BoxDecoration(
        color: _gold.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _gold.withValues(alpha: 0.4), width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.payments_rounded, color: _gold, size: 22),
          const SizedBox(width: 10),
          Text(
            price,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: _cream,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasTags = item.tags.isNotEmpty;
    final isPopular = item.tags.contains('Popüler');
    final isSpecial = item.tags.contains('Special');
    final dual = _hasDualPrice(item.price);

    String? displayImagePath = item.imagePath;
    if (displayImagePath != null &&
        displayImagePath.contains('assets/menu/png/')) {
      displayImagePath = displayImagePath.replaceFirst(
        'assets/menu/png/',
        'assets/menu/',
      );
      if (displayImagePath.endsWith('cay.png')) {
        displayImagePath = displayImagePath.replaceAll('.png', '.jpeg');
      } else {
        displayImagePath = displayImagePath.replaceAll('.png', '.jpg');
      }
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        width: 460,
        padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 42),
        decoration: BoxDecoration(
          color: const Color(0xFF1F1A28),
          borderRadius: BorderRadius.circular(36),
          border: Border.all(color: _gold.withValues(alpha: 0.3), width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.6),
              blurRadius: 30,
              offset: const Offset(0, 15),
            ),
            if (isSpecial)
              BoxShadow(
                color: _gold.withValues(alpha: 0.15),
                blurRadius: 40,
                spreadRadius: 5,
              ),
          ],
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            SizedBox(
              width: double.infinity,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      color: const Color(0xFF14101A),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.1),
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: displayImagePath == null
                        ? Center(
                            child: Icon(
                              item.icon,
                              size: 90,
                              color: _gold.withValues(alpha: 0.7),
                            ),
                          )
                        : Image.asset(
                            displayImagePath,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Center(
                                child: Icon(
                                  item.icon,
                                  size: 90,
                                  color: _gold.withValues(alpha: 0.7),
                                ),
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    trMenu(item.name),
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                      color: _gold,
                      letterSpacing: 0.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  if (trMenu(item.desc).isNotEmpty) ...[
                    Text(
                      trMenu(item.desc),
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.white.withValues(alpha: 0.75),
                        height: 1.4,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                  ],
                  if (hasTags) ...[
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      alignment: WrapAlignment.center,
                      children: item.tags.map((tag) {
                        final color =
                            _tagStyles[tag] ?? const Color(0xFFB2BEC3);
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: color.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Text(
                            trMenu(tag),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: color,
                              letterSpacing: 0.5,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 28),
                  ],
                  dual
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _priceBadge('M', _mPrice(item.price)),
                            const SizedBox(width: 16),
                            _priceBadge('L', _lPrice(item.price)),
                          ],
                        )
                      : _buildSinglePrice(item.price),
                ],
              ),
            ),
            if (isPopular || isSpecial)
              Positioned(
                top: -22,
                left: -18,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: (isSpecial ? const Color(0xFFE879A8) : _gold)
                        .withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: (isSpecial ? const Color(0xFFE879A8) : _gold)
                          .withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.star_rounded,
                        size: 18,
                        color: (isSpecial ? const Color(0xFFE879A8) : _gold),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isSpecial ? 'Special' : trMenu('Popüler'),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: (isSpecial ? const Color(0xFFE879A8) : _gold),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Positioned(
              top: -24,
              right: -20,
              child: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.close_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrinkWheelPainter extends CustomPainter {
  const _DrinkWheelPainter({
    required this.drinks,
    this.selectedDrink,
    this.showResult = false,
  });

  final List<Drink> drinks;
  final Drink? selectedDrink;
  final bool showResult;

  @override
  void paint(Canvas canvas, Size size) {
    if (drinks.isEmpty) return;

    final center = size.center(Offset.zero);
    final radius =
        size.shortestSide / 2 - 8; // Prevent outer stroke from clipping
    final bounds = Rect.fromCircle(center: center, radius: radius);

    final sweep = 2 * pi / drinks.length;

    for (var i = 0; i < drinks.length; i++) {
      final drink = drinks[i];
      final start = -pi / 2 + i * sweep;
      final isSelected = showResult && drink == selectedDrink;

      // Dim non-selected segments slightly when showing result
      final baseColor = (showResult && !isSelected)
          ? drink.color.withValues(alpha: 0.4)
          : drink.color;

      final paint = Paint()
        ..style = PaintingStyle.fill
        ..color = isSelected
            ? Color.lerp(drink.color, Colors.white, 0.25)!
            : baseColor;

      canvas.drawArc(bounds, start, sweep, true, paint);

      if (isSelected) {
        // Bright inner border for selected segment
        final highlightPaint = Paint()
          ..style = PaintingStyle.stroke
          ..color = Colors.white.withValues(alpha: 0.8)
          ..strokeWidth = 6;
        canvas.drawArc(bounds, start, sweep, true, highlightPaint);
      }

      // Separator
      final lineEnd = Offset(
        center.dx + cos(start) * radius,
        center.dy + sin(start) * radius,
      );
      canvas.drawLine(
        center,
        lineEnd,
        Paint()
          ..color = _bgDark.withValues(alpha: 0.8)
          ..strokeWidth = 4,
      );

      // Text and images are now rendered via Flutter Stack in _buildCenterArea
    }

    // Outer border
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12
        ..color = _surface,
    );
    canvas.drawCircle(
      center,
      radius - 6,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = _gold.withValues(alpha: 0.5),
    );
  }

  @override
  bool shouldRepaint(covariant _DrinkWheelPainter oldDelegate) {
    return oldDelegate.drinks != drinks ||
        oldDelegate.selectedDrink != selectedDrink ||
        oldDelegate.showResult != showResult;
  }
}

class _PointerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

    // Rounded triangle path
    final path = Path();
    const double radius = 6.0;

    // Start from top left with rounding
    path.moveTo(radius, 0);
    path.lineTo(size.width - radius, 0);
    path.quadraticBezierTo(size.width, 0, size.width, radius);

    // Point down
    path.lineTo(size.width / 2 + 4, size.height - 4);
    path.quadraticBezierTo(
      size.width / 2,
      size.height,
      size.width / 2 - 4,
      size.height - 4,
    );

    // Back to top
    path.lineTo(0, radius);
    path.quadraticBezierTo(0, 0, radius, 0);
    path.close();

    // Shadow
    canvas.drawPath(path.shift(const Offset(0, 4)), shadowPaint);

    // Main pointer
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

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

      final response = await http
          .post(
            Uri.parse(LicenseConfig.verifyAdminPinUrl),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'device_id': deviceId,
              'device_fingerprint_hash': fingerprint,
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
        debugPrint('verifyAdminPin JSON decode error: $e. Body raw: $bodyStr');
      }

      if (data != null) {
        final dynamic successVal = data['success'];
        final bool success =
            successVal == true ||
            successVal == 'true' ||
            successVal == 1 ||
            successVal == '1';
        if (success) {
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
                    color: _errorMessage != null ? Colors.redAccent : _muted,
                    fontSize: 13,
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

enum _AdminSection {
  barista,
  wheel,
  clean,
  analytics,
  theme,
  volume,
  info,
  exit,
}

class _AdminHubDialog extends StatelessWidget {
  const _AdminHubDialog();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<LicenseStatus>(
      valueListenable: LicenseService.instance.statusNotifier,
      builder: (context, status, _) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            width: 520,
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: const Color(0xFF1C1724),
              borderRadius: BorderRadius.circular(34),
              border: Border.all(color: _gold.withValues(alpha: 0.24)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.65),
                  blurRadius: 56,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.admin_panel_settings_rounded,
                      color: _gold,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        tr('Admin Menüsü', 'Admin Menu'),
                        style: const TextStyle(
                          color: _cream,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                      color: _muted,
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _AdminSectionButton(
                  icon: Icons.auto_awesome_rounded,
                  title: tr('Barista Önerisi', "Barista's Pick"),
                  subtitle: tr(
                    'Ana ekrandaki tavsiye içecek ve tatlıyı değiştir.',
                    'Change the recommended drink and dessert on the main screen.',
                  ),
                  isLocked: !status.features.baristaRecommendation,
                  onTap: () {
                    if (!status.features.baristaRecommendation) {
                      showFeatureLockedDialog(
                        context,
                        tr('Barista Önerisi', "Barista's Pick"),
                        customMessage: tr(
                          'Bu özellik lisansınızda aktif değil.',
                          'This feature is not active in your license.',
                        ),
                        screen: 'admin_menu',
                        featureKey: 'barista_recommendation_updated',
                      );
                      return;
                    }
                    Navigator.of(context).pop(_AdminSection.barista);
                  },
                ),
                const SizedBox(height: 14),
                _AdminSectionButton(
                  icon: Icons.casino_rounded,
                  title: tr('Çark İçeriği', 'Wheel Items'),
                  subtitle: tr(
                    'Ana çarktaki 8 menü ürününü seç.',
                    'Select the 8 menu items on the wheel.',
                  ),
                  isLocked: !status.features.wheelContent,
                  onTap: () {
                    if (!status.features.wheelContent) {
                      showFeatureLockedDialog(
                        context,
                        tr('Çark İçeriği', 'Wheel Items'),
                        customMessage: tr(
                          'Bu özellik lisansınızda aktif değil.',
                          'This feature is not active in your license.',
                        ),
                        screen: 'admin_menu',
                        featureKey: 'wheel_content_updated',
                      );
                      return;
                    }
                    Navigator.of(context).pop(_AdminSection.wheel);
                  },
                ),
                const SizedBox(height: 14),
                _AdminSectionButton(
                  icon: Icons.cleaning_services_rounded,
                  title: tr('Ekran Temizleme Modu', 'Screen Cleaning Mode'),
                  subtitle: tr(
                    'Ekranı 30 saniyeliğine karartır ve dokunmatiği kilitler.',
                    'Dims screen for 30 seconds and locks touch.',
                  ),
                  customColor: Colors.lightBlueAccent,
                  isLocked: !status.features.cleaningMode,
                  onTap: () {
                    if (!status.features.cleaningMode) {
                      showFeatureLockedDialog(
                        context,
                        tr('Ekran Temizleme Modu', 'Screen Cleaning Mode'),
                        customMessage: tr(
                          'Bu özellik lisansınızda aktif değil.',
                          'This feature is not active in your license.',
                        ),
                        screen: 'admin_menu',
                        featureKey: 'cleaning_mode_started',
                      );
                      return;
                    }
                    Navigator.of(context).pop(_AdminSection.clean);
                  },
                ),
                const SizedBox(height: 14),
                _AdminSectionButton(
                  icon: Icons.bar_chart_rounded,
                  title: tr('Analizler', 'Analytics'),
                  subtitle: tr(
                    'Menü tıklamaları, çark çevrimleri ve hesap kimde istatistikleri.',
                    'Menu clicks, wheel spins, and who pays game statistics.',
                  ),
                  customColor: Colors.amberAccent,
                  isLocked: !status.features.analytics,
                  onTap: () {
                    if (!status.features.analytics) {
                      showFeatureLockedDialog(
                        context,
                        tr('Analizler', 'Analytics'),
                        customMessage: tr(
                          'Bu özellik lisansınızda aktif değil.',
                          'This feature is not active in your license.',
                        ),
                        screen: 'admin_menu',
                        featureKey: 'analytics_opened',
                      );
                      return;
                    }
                    Navigator.of(context).pop(_AdminSection.analytics);
                  },
                ),
                const SizedBox(height: 14),
                _AdminSectionButton(
                  icon: Icons.palette_rounded,
                  title: tr('Uygulama Teması', 'App Theme'),
                  subtitle: tr(
                    'Yaz, Kış, Bayram ve Yılbaşı temaları arasında geçiş yap.',
                    'Switch between Summer, Winter, Holiday, and New Year themes.',
                  ),
                  customColor: Colors.purpleAccent,
                  isLocked: !status.features.themes,
                  onTap: () {
                    if (!status.features.themes) {
                      showFeatureLockedDialog(
                        context,
                        tr('Uygulama Teması', 'App Theme'),
                        customMessage: tr(
                          'Bu özellik lisansınızda aktif değil.',
                          'This feature is not active in your license.',
                        ),
                        screen: 'admin_menu',
                        featureKey: 'theme_changed',
                      );
                      return;
                    }
                    Navigator.of(context).pop(_AdminSection.theme);
                  },
                ),
                const SizedBox(height: 14),
                _AdminSectionButton(
                  icon: Icons.volume_up_rounded,
                  title: tr('Ses Seviyesi', 'Volume Level'),
                  subtitle: tr(
                    'Kiosk ses seviyesini ayarla (%0, %25, %50, %75, %100).',
                    'Adjust kiosk volume level (0%, 25%, 50%, 75%, 100%).',
                  ),
                  customColor: Colors.pinkAccent,
                  isLocked: !status.features.volumeControl,
                  onTap: () {
                    if (!status.features.volumeControl) {
                      showFeatureLockedDialog(
                        context,
                        tr('Ses Seviyesi', 'Volume Level'),
                        customMessage: tr(
                          'Bu özellik lisansınızda aktif değil.',
                          'This feature is not active in your license.',
                        ),
                        screen: 'admin_menu',
                        featureKey: 'volume_changed',
                      );
                      return;
                    }
                    Navigator.of(context).pop(_AdminSection.volume);
                  },
                ),
                const SizedBox(height: 14),
                _AdminSectionButton(
                  icon: Icons.info_outline_rounded,
                  title: tr('Uygulama Bilgileri', 'App Information'),
                  subtitle: tr('Geliştirici Sekmesi', 'Developer Tab'),
                  customColor: Colors.tealAccent,
                  onTap: () => Navigator.of(context).pop(_AdminSection.info),
                ),
                const SizedBox(height: 14),
                _AdminSectionButton(
                  icon: Icons.power_settings_new_rounded,
                  title: tr('Uygulamadan Çık', 'Exit App'),
                  subtitle: tr(
                    'Kiosk modunu kapatır ve masaüstüne döner.',
                    'Close kiosk mode and return to desktop.',
                  ),
                  customColor: Colors.redAccent,
                  isLocked: !status.features.manualExit,
                  onTap: () {
                    if (!status.features.manualExit) {
                      showFeatureLockedDialog(
                        context,
                        tr('Uygulamadan Çık', 'Exit App'),
                        customMessage: tr(
                          'Bu özellik lisansınızda aktif değil.',
                          'This feature is not active in your license.',
                        ),
                        screen: 'admin_menu',
                        featureKey: 'manual_exit_clicked',
                      );
                      return;
                    }
                    Navigator.of(context).pop(_AdminSection.exit);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AdminSectionButton extends StatelessWidget {
  const _AdminSectionButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.customColor,
    this.isLocked = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color? customColor;
  final bool isLocked;

  @override
  Widget build(BuildContext context) {
    return BouncyButton(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: isLocked
              ? _bgDark.withValues(alpha: 0.3)
              : _bgDark.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: isLocked
                ? _gold.withValues(alpha: 0.15)
                : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Row(
          children: [
            Opacity(
              opacity: isLocked ? 0.5 : 1.0,
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: (customColor ?? _gold).withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: customColor ?? _gold),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Opacity(
                opacity: isLocked ? 0.5 : 1.0,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: customColor ?? _cream,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: _muted,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Icon(
              isLocked ? Icons.lock_rounded : Icons.chevron_right_rounded,
              color: isLocked ? _gold : _muted,
            ),
          ],
        ),
      ),
    );
  }
}

class _WheelContentAdminDialog extends StatefulWidget {
  const _WheelContentAdminDialog({
    required this.initialItems,
    required this.iceCoffeeOptions,
    required this.hotCoffeeOptions,
    required this.dessertOptions,
    required this.cocktailOptions,
    required this.herbalTeaOptions,
    required this.iceCreamOptions,
    required this.blockedItems,
    required this.onSave,
  });

  final List<_MenuItem> initialItems;
  final List<_MenuItem> iceCoffeeOptions;
  final List<_MenuItem> hotCoffeeOptions;
  final List<_MenuItem> dessertOptions;
  final List<_MenuItem> cocktailOptions;
  final List<_MenuItem> herbalTeaOptions;
  final List<_MenuItem> iceCreamOptions;
  final List<_MenuItem> blockedItems;
  final ValueChanged<List<_MenuItem>> onSave;

  @override
  State<_WheelContentAdminDialog> createState() =>
      _WheelContentAdminDialogState();
}

class _WheelContentAdminDialogState extends State<_WheelContentAdminDialog> {
  late final List<_MenuItem> _items = List<_MenuItem>.from(widget.initialItems);

  List<_WheelSlot> get _slots {
    final isSummer = appThemeNotifier.value == AppTheme.summer;
    return [
      _WheelSlot(
        tr('Ice kahve 1', 'Ice coffee 1'),
        widget.iceCoffeeOptions,
        tr('Ice kahve ara', 'Search ice coffee'),
      ),
      _WheelSlot(
        isSummer
            ? tr('Ice kahve 2', 'Ice coffee 2')
            : tr('Sıcak kahve', 'Hot coffee'),
        isSummer ? widget.iceCoffeeOptions : widget.hotCoffeeOptions,
        isSummer
            ? tr('Ice kahve ara', 'Search ice coffee')
            : tr('Sıcak kahve ara', 'Search hot coffee'),
      ),
      _WheelSlot(
        tr('Tatlı 1', 'Dessert 1'),
        widget.dessertOptions,
        tr('Tatlı ara', 'Search dessert'),
      ),
      _WheelSlot(
        tr('Tatlı 2', 'Dessert 2'),
        widget.dessertOptions,
        tr('Tatlı ara', 'Search dessert'),
      ),
      _WheelSlot(
        tr('Kokteyl 1', 'Cocktail 1'),
        widget.cocktailOptions,
        tr('Kokteyl ara', 'Search cocktail'),
      ),
      _WheelSlot(
        tr('Kokteyl 2', 'Cocktail 2'),
        widget.cocktailOptions,
        tr('Kokteyl ara', 'Search cocktail'),
      ),
      _WheelSlot(
        isSummer
            ? tr('Dondurma 1', 'Ice cream 1')
            : tr('Bitki çayı 1', 'Herbal tea 1'),
        isSummer ? widget.iceCreamOptions : widget.herbalTeaOptions,
        isSummer
            ? tr('Dondurma ara', 'Search ice cream')
            : tr('Bitki çayı ara', 'Search herbal tea'),
      ),
      _WheelSlot(
        isSummer
            ? tr('Dondurma 2', 'Ice cream 2')
            : tr('Bitki çayı 2', 'Herbal tea 2'),
        isSummer ? widget.iceCreamOptions : widget.herbalTeaOptions,
        isSummer
            ? tr('Dondurma ara', 'Search ice cream')
            : tr('Bitki çayı ara', 'Search herbal tea'),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        width: 620,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.88,
        ),
        padding: const EdgeInsets.all(26),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1724),
          borderRadius: BorderRadius.circular(34),
          border: Border.all(color: _gold.withValues(alpha: 0.24)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.65),
              blurRadius: 56,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.casino_rounded, color: _gold),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    tr('Çark içeriği', 'Wheel items'),
                    style: const TextStyle(
                      color: _cream,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                  color: _muted,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              tr(
                'Ana çark 8 üründen oluşur. Her slotu menüden seçebilirsin.',
                'The main wheel consists of 8 products. You can select each slot from the menu.',
              ),
              style: const TextStyle(
                color: _muted,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 18),
            Expanded(
              child: ListView.separated(
                itemCount: _slots.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final slot = _slots[index];
                  return _WheelSlotPicker(
                    label: slot.label,
                    item: _items[index],
                    onTap: () async {
                      final selected = await _showAdminPicker(
                        context: context,
                        title: slot.label,
                        searchHint: slot.searchHint,
                        items: slot.options,
                        selected: _items[index],
                      );
                      if (selected != null) {
                        setState(() => _items[index] = selected);
                      }
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 18),
            BouncyButton(
              onTap: () async {
                final duplicate = _firstDuplicateItem(_items);
                if (duplicate != null) {
                  await _showAdminError(
                    context,
                    '${tr('Bu ürün çarkta iki kez seçilemez', 'This product cannot be selected twice on the wheel')}: ${trMenu(duplicate.name)}',
                  );
                  return;
                }
                final conflict = _firstContained(_items, widget.blockedItems);
                if (conflict != null) {
                  await _showAdminError(
                    context,
                    '${tr('Bu ürün Barista önerisinde seçili', 'This product is selected in Barista recommendation')}: ${trMenu(conflict.name)}',
                  );
                  return;
                }
                widget.onSave(List<_MenuItem>.from(_items));
                Navigator.of(context).pop();
              },
              child: Container(
                height: 58,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _gold,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: _gold.withValues(alpha: 0.25),
                      blurRadius: 22,
                    ),
                  ],
                ),
                child: Text(
                  tr('KAYDET', 'SAVE'),
                  style: const TextStyle(
                    color: _bgDark,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WheelSlot {
  const _WheelSlot(this.label, this.options, this.searchHint);
  final String label;
  final List<_MenuItem> options;
  final String searchHint;
}

class _WheelSlotPicker extends StatelessWidget {
  const _WheelSlotPicker({
    required this.label,
    required this.item,
    required this.onTap,
  });

  final String label;
  final _MenuItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return BouncyButton(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _bgDark.withValues(alpha: 0.50),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(
          children: [
            _AdminPickerThumb(item: item),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: _gold,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    trMenu(item.name),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _cream,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.edit_rounded, color: _muted, size: 20),
          ],
        ),
      ),
    );
  }
}

_MenuItem? _firstDuplicateItem(List<_MenuItem> items) {
  final seen = <_MenuItem>{};
  for (final item in items) {
    if (!seen.add(item)) return item;
  }
  return null;
}

_MenuItem? _firstContained(
  Iterable<_MenuItem> items,
  Iterable<_MenuItem> blockedItems,
) {
  for (final item in items) {
    if (blockedItems.contains(item)) return item;
  }
  return null;
}

Future<void> _showAdminError(BuildContext context, String message) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (context) {
      return AlertDialog(
        backgroundColor: const Color(0xFF1C1724),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: _gold),
            const SizedBox(width: 10),
            Text(
              tr('Seçim çakışıyor', 'Selection Conflict'),
              style: const TextStyle(
                color: _cream,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        content: Text(
          message,
          style: const TextStyle(color: _muted, fontWeight: FontWeight.w600),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              tr('TAMAM', 'OK'),
              style: const TextStyle(color: _gold, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      );
    },
  );
}

class _BaristaAdminDialog extends StatefulWidget {
  const _BaristaAdminDialog({
    required this.drinkOptions,
    required this.dessertOptions,
    required this.selectedDrink,
    required this.selectedDessert,
    required this.blockedItems,
    required this.onSave,
  });

  final List<_MenuItem> drinkOptions;
  final List<_MenuItem> dessertOptions;
  final _MenuItem selectedDrink;
  final _MenuItem selectedDessert;
  final List<_MenuItem> blockedItems;
  final void Function(_MenuItem drink, _MenuItem dessert) onSave;

  @override
  State<_BaristaAdminDialog> createState() => _BaristaAdminDialogState();
}

class _BaristaAdminDialogState extends State<_BaristaAdminDialog> {
  late _MenuItem _drink = widget.selectedDrink;
  late _MenuItem _dessert = widget.selectedDessert;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 520,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1724),
          borderRadius: BorderRadius.circular(34),
          border: Border.all(color: _gold.withValues(alpha: 0.24)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.65),
              blurRadius: 56,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.admin_panel_settings_rounded, color: _gold),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    tr('Admin Menüsü', 'Admin Menu'),
                    style: const TextStyle(
                      color: _cream,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                  color: _muted,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              tr(
                'Baristanın tavsiye edeceği içecek ve tatlıyı seç.',
                'Choose the drink and dessert for barista recommendation.',
              ),
              style: TextStyle(
                color: _muted,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 24),
            _AdminPickerField(
              label: tr('Tavsiye içecek', 'Recommended drink'),
              value: _drink,
              onTap: () async {
                final selected = await _showAdminPicker(
                  context: context,
                  title: tr('Tavsiye içecek', 'Recommended drink'),
                  searchHint: tr('İçecek ara', 'Search drink'),
                  items: widget.drinkOptions,
                  selected: _drink,
                );
                if (selected != null) {
                  setState(() => _drink = selected);
                }
              },
            ),
            const SizedBox(height: 16),
            _AdminPickerField(
              label: tr('Tavsiye tatlı', 'Recommended dessert'),
              value: _dessert,
              onTap: () async {
                final selected = await _showAdminPicker(
                  context: context,
                  title: tr('Tavsiye tatlı', 'Recommended dessert'),
                  searchHint: tr('Tatlı ara', 'Search dessert'),
                  items: widget.dessertOptions,
                  selected: _dessert,
                );
                if (selected != null) {
                  setState(() => _dessert = selected);
                }
              },
            ),
            const SizedBox(height: 26),
            BouncyButton(
              onTap: () async {
                final conflict = _firstContained([
                  _drink,
                  _dessert,
                ], widget.blockedItems);
                if (conflict != null) {
                  await _showAdminError(
                    context,
                    '${tr('Bu ürün çark içeriğinde seçili', 'This product is selected in the wheel items')}: ${trMenu(conflict.name)}',
                  );
                  return;
                }
                widget.onSave(_drink, _dessert);
                Navigator.of(context).pop();
              },
              child: Container(
                height: 58,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _gold,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: _gold.withValues(alpha: 0.25),
                      blurRadius: 22,
                    ),
                  ],
                ),
                child: Text(
                  tr('KAYDET', 'SAVE'),
                  style: const TextStyle(
                    color: _bgDark,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminPickerField extends StatelessWidget {
  const _AdminPickerField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final _MenuItem value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return BouncyButton(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: _muted),
          filled: true,
          fillColor: _bgDark.withValues(alpha: 0.55),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: _gold),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                value.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _cream,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 12),
            const Icon(Icons.keyboard_arrow_down_rounded, color: _gold),
          ],
        ),
      ),
    );
  }
}

Future<_MenuItem?> _showAdminPicker({
  required BuildContext context,
  required String title,
  required String searchHint,
  required List<_MenuItem> items,
  required _MenuItem selected,
}) {
  return showDialog<_MenuItem>(
    context: context,
    barrierDismissible: true,
    builder: (context) => _AdminSearchPickerDialog(
      title: title,
      searchHint: searchHint,
      items: items,
      selected: selected,
    ),
  );
}

class _AdminSearchPickerDialog extends StatefulWidget {
  const _AdminSearchPickerDialog({
    required this.title,
    required this.searchHint,
    required this.items,
    required this.selected,
  });

  final String title;
  final String searchHint;
  final List<_MenuItem> items;
  final _MenuItem selected;

  @override
  State<_AdminSearchPickerDialog> createState() =>
      _AdminSearchPickerDialogState();
}

class _AdminSearchPickerDialogState extends State<_AdminSearchPickerDialog> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<_MenuItem> get _filteredItems {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return widget.items;
    return widget.items
        .where(
          (item) =>
              trMenu(item.name).toLowerCase().contains(query) ||
              trMenu(item.desc).toLowerCase().contains(query),
        )
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final filteredItems = _filteredItems;
    final screenHeight = MediaQuery.sizeOf(context).height;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        width: 560,
        constraints: BoxConstraints(maxHeight: screenHeight * 0.82),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1724),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: _gold.withValues(alpha: 0.24)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.65),
              blurRadius: 56,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: const TextStyle(
                      color: _cream,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                  color: _muted,
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _searchController,
              autofocus: false,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(
                color: _cream,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
              decoration: InputDecoration(
                hintText: widget.searchHint,
                hintStyle: const TextStyle(color: _muted),
                prefixIcon: const Icon(Icons.search_rounded, color: _gold),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _searchController.clear();
                          setState(() {});
                        },
                        icon: const Icon(Icons.close_rounded),
                        color: _muted,
                      ),
                filled: true,
                fillColor: _bgDark.withValues(alpha: 0.55),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: const BorderSide(color: _gold),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Flexible(
              child: filteredItems.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 34),
                        child: Text(
                          tr('Sonuç bulunamadı', 'No results found'),
                          style: const TextStyle(
                            color: _muted,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: filteredItems.length,
                      separatorBuilder: (context, index) => Divider(
                        color: Colors.white.withValues(alpha: 0.06),
                        height: 1,
                      ),
                      itemBuilder: (context, index) {
                        final item = filteredItems[index];
                        final isSelected = item == widget.selected;
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          leading: _AdminPickerThumb(item: item),
                          title: Text(
                            trMenu(item.name),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _cream,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          subtitle: trMenu(item.desc).isEmpty
                              ? null
                              : Text(
                                  trMenu(item.desc),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: _muted),
                                ),
                          trailing: isSelected
                              ? const Icon(
                                  Icons.check_circle_rounded,
                                  color: _mint,
                                )
                              : const Icon(
                                  Icons.chevron_right_rounded,
                                  color: _muted,
                                ),
                          onTap: () => Navigator.of(context).pop(item),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminPickerThumb extends StatelessWidget {
  const _AdminPickerThumb({required this.item});

  final _MenuItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: _bgDark.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      clipBehavior: Clip.antiAlias,
      child: item.imagePath == null
          ? Icon(item.icon, color: _gold, size: 22)
          : Image.asset(
              item.imagePath!,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Icon(item.icon, color: _gold, size: 22);
              },
            ),
    );
  }
}

List<_MenuItem> _defaultWheelMenuItems() {
  final iceCoffee = _expensiveItems(
    _menuItemsForCategoryIcons([
      Icons.ac_unit_rounded,
      Icons.severe_cold_rounded,
      Icons.sports_bar_rounded,
      Icons.bubble_chart_rounded,
      Icons.icecream_rounded,
    ]),
  );
  final hotCoffee = _expensiveItems(
    _menuItemsForCategoryIcons([
      Icons.local_cafe_rounded,
      Icons.coffee_maker_rounded,
      Icons.whatshot_rounded,
    ]),
  );
  final desserts = _expensiveItems([
    ...?_menuCategories['Pasta & Tatlı'],
    ...?_menuCategories['LUUQ Chocolate'],
  ]);
  final cocktails = _expensiveItems(
    _menuItemsForCategoryIcons([Icons.local_bar_rounded]),
  );
  final herbalTeas = _expensiveItems(
    _menuItemsForCategoryIcons([Icons.eco_rounded]),
  );
  final iceCreams = _menuCategories['Dondurmalar'] ?? const [];

  if (appThemeNotifier.value == AppTheme.summer) {
    return [
      ...iceCoffee.take(2),
      ...desserts.take(2),
      ...cocktails.take(2),
      ...iceCreams.take(2),
    ];
  }

  return [
    iceCoffee.first,
    hotCoffee.first,
    ...desserts.take(2),
    ...cocktails.take(2),
    ...herbalTeas.take(2),
  ];
}

List<_MenuItem> _menuItemsForCategoryIcons(List<IconData> icons) {
  final items = <_MenuItem>[];
  for (final entry in _categoryIcons.entries) {
    if (icons.contains(entry.value)) {
      items.addAll(_menuCategories[entry.key] ?? const []);
    }
  }
  return items;
}

List<_MenuItem> _expensiveItems(List<_MenuItem> items) {
  return List<_MenuItem>.from(items)
    ..sort((a, b) => _maxMenuPrice(b.price).compareTo(_maxMenuPrice(a.price)));
}

int _maxMenuPrice(String price) {
  final matches = RegExp(r'\d+').allMatches(price);
  var maxPrice = 0;
  for (final match in matches) {
    maxPrice = max(maxPrice, int.tryParse(match.group(0) ?? '') ?? 0);
  }
  return maxPrice;
}

Drink _drinkFromMenuItem(_MenuItem item) {
  final category = _categoryForMenuItem(item);
  return Drink(
    shortName: _wheelShortName(trMenu(item.name)),
    fullName: trMenu(item.name),
    description: trMenu(item.desc),
    icon: item.icon,
    color: _wheelColorForMenuItem(item, category),
    moods: _wheelMoodsForMenuItem(item, category),
    ingredients: const [],
    imagePath: item.imagePath,
  );
}

String _categoryForMenuItem(_MenuItem item) {
  for (final entry in _menuCategories.entries) {
    if (entry.value.contains(item)) return entry.key;
  }
  return '';
}

String _wheelShortName(String name) {
  return name
      .replaceAll('Ice ', '')
      .replaceAll('Iced ', '')
      .replaceAll('Luuq ', '')
      .trim();
}

Color _wheelColorForMenuItem(_MenuItem item, String category) {
  final icon = _categoryIcons[category];
  if (icon == Icons.ac_unit_rounded ||
      icon == Icons.severe_cold_rounded ||
      icon == Icons.sports_bar_rounded) {
    return const Color(0xFF5F7F90);
  }
  if (icon == Icons.local_cafe_rounded ||
      icon == Icons.coffee_maker_rounded ||
      icon == Icons.whatshot_rounded) {
    return const Color(0xFF8A5A37);
  }
  if (icon == Icons.cake_rounded ||
      icon == Icons.cookie_rounded ||
      icon == Icons.bubble_chart_rounded ||
      icon == Icons.icecream_rounded) {
    return const Color(0xFFC97892);
  }
  if (icon == Icons.local_bar_rounded) return const Color(0xFF789D78);
  if (icon == Icons.eco_rounded) return const Color(0xFF5F8E70);
  return Color.lerp(_surface, _gold, 0.35)!;
}

Set<DrinkMood> _wheelMoodsForMenuItem(_MenuItem item, String category) {
  final icon = _categoryIcons[category];
  final moods = <DrinkMood>{};
  if (icon == Icons.ac_unit_rounded ||
      icon == Icons.local_bar_rounded ||
      icon == Icons.severe_cold_rounded ||
      icon == Icons.bubble_chart_rounded ||
      icon == Icons.icecream_rounded ||
      icon == Icons.sports_bar_rounded) {
    moods.add(DrinkMood.cold);
    moods.add(DrinkMood.fresh);
  }
  if (icon == Icons.local_cafe_rounded ||
      icon == Icons.eco_rounded ||
      icon == Icons.coffee_maker_rounded ||
      icon == Icons.whatshot_rounded) {
    moods.add(DrinkMood.hot);
  }
  if (icon == Icons.cake_rounded ||
      icon == Icons.cookie_rounded ||
      icon == Icons.lunch_dining_rounded ||
      icon == Icons.icecream_rounded ||
      icon == Icons.bubble_chart_rounded) {
    moods.add(DrinkMood.sweet);
  }
  final lowerName = trMenu(item.name).toLowerCase();
  final lowerDesc = trMenu(item.desc).toLowerCase();
  if (lowerName.contains('latte') ||
      lowerName.contains('mocha') ||
      lowerDesc.contains('sÃ¼t') ||
      lowerDesc.contains('krem')) {
    moods.add(DrinkMood.milky);
  }
  if (lowerName.contains('espresso') ||
      lowerName.contains('americano') ||
      lowerDesc.contains('yoÄŸun')) {
    moods.add(DrinkMood.strong);
  }
  if (moods.isEmpty) moods.add(DrinkMood.fresh);
  return moods;
}

class Drink {
  const Drink({
    required this.shortName,
    required this.fullName,
    required this.description,
    required this.icon,
    required this.color,
    required this.moods,
    required this.ingredients,
    this.imagePath,
  });

  final String shortName;
  final String fullName;
  final String description;
  final IconData icon;
  final Color color;
  final Set<DrinkMood> moods;
  final List<String> ingredients;
  final String? imagePath;

  @override
  bool operator ==(Object other) {
    return other is Drink && other.fullName == fullName;
  }

  @override
  int get hashCode => fullName.hashCode;
}

enum DrinkMood {
  cold('Soğuk', 'Cold', Icons.ac_unit_rounded),
  hot('Sıcak', 'Hot', Icons.local_fire_department_rounded),
  sweet('Tatlı', 'Sweet', Icons.cake_rounded),
  milky('Sütlü', 'Milky', Icons.local_drink_rounded),
  strong('Sert', 'Strong', Icons.bolt_rounded),
  fresh('Ferah', 'Fresh', Icons.spa_rounded);

  const DrinkMood(this.trLabel, this.enLabel, this.icon);
  final String trLabel;
  final String enLabel;
  final IconData icon;

  String get label => tr(trLabel, enLabel);
}

const drinks = [
  Drink(
    shortName: 'Espresso',
    fullName: 'Double Espresso',
    description: 'İtalyan klasiği; yoğun, sert ve uyanış garantili.',
    icon: Icons.coffee_rounded,
    color: Color(0xFF4A3525),
    moods: {DrinkMood.hot, DrinkMood.strong},
    ingredients: ['Çift Shot Espresso'],
  ),
  Drink(
    shortName: 'Americano',
    fullName: 'Iced Americano',
    description: 'Buz gibi su ve yoğun espresso. Ferahlatıcı ve net.',
    icon: Icons.water_drop_rounded,
    color: Color(0xFF908073),
    moods: {DrinkMood.cold, DrinkMood.strong, DrinkMood.fresh},
    ingredients: ['Soğuk Su', 'Buz', 'Çift Shot Espresso'],
  ),
  Drink(
    shortName: 'Cappuccino',
    fullName: 'Cappuccino',
    description: 'Baskın espresso tadı ve bol köpüklü sıcak süt.',
    icon: Icons.local_cafe_rounded,
    color: Color(0xFFC49B76),
    moods: {DrinkMood.hot, DrinkMood.strong, DrinkMood.milky},
    ingredients: ['Espresso', 'Sıcak Süt', 'Bol Süt Köpüğü'],
  ),
  Drink(
    shortName: 'Latte',
    fullName: 'Caffe Latte',
    description: 'Yumuşak içimli sıcak süt ve dengeli espresso.',
    icon: Icons.emoji_food_beverage_rounded,
    color: Color(0xFFD4B499),
    moods: {DrinkMood.hot, DrinkMood.milky},
    ingredients: ['Espresso', 'Sıcak Süt', 'Süt Köpüğü'],
  ),
  Drink(
    shortName: 'Flat White',
    fullName: 'Flat White',
    description: 'İncecik süt köpüğü altında yoğun espresso deneyimi.',
    icon: Icons.coffee_maker_rounded,
    color: Color(0xFFB58E6D),
    moods: {DrinkMood.hot, DrinkMood.strong, DrinkMood.milky},
    ingredients: ['Çift Shot Espresso', 'Buharda Isıtılmış Süt'],
  ),
  Drink(
    shortName: 'Macchiato',
    fullName: 'Caramel Macchiato',
    description: 'Vanilya şurubu, sıcak süt, espresso ve nefis karamel.',
    icon: Icons.icecream_rounded,
    color: Color(0xFFDDA77B),
    moods: {DrinkMood.hot, DrinkMood.sweet, DrinkMood.milky},
    ingredients: ['Vanilya Şurubu', 'Süt', 'Espresso', 'Karamel Sos'],
  ),
  Drink(
    shortName: 'Mocha',
    fullName: 'Caffe Mocha',
    description: 'Tatlı çikolatanın sıcak kahveyle efsane uyumu.',
    icon: Icons.eco_rounded,
    color: Color(0xFF7B5E4A),
    moods: {DrinkMood.hot, DrinkMood.sweet, DrinkMood.milky},
    ingredients: ['Espresso', 'Çikolata Sosu', 'Sıcak Süt'],
  ),
  Drink(
    shortName: 'Cold Brew',
    fullName: 'Cold Brew',
    description:
        'Soğuk suda saatlerce demlenmiş, yumuşak içimli yüksek kafein.',
    icon: Icons.ac_unit_rounded,
    color: Color(0xFF506B7D),
    moods: {DrinkMood.cold, DrinkMood.strong},
    ingredients: ['Soğuk Su', 'Demlenmiş Kahve Özü', 'Buz'],
  ),
  Drink(
    shortName: 'Frappe',
    fullName: 'Caramel Frappe',
    description: 'Buzlu, karamelli ve sütlü tatlı kahve rüyası.',
    icon: Icons.severe_cold_rounded,
    color: Color(0xFFE5B581),
    moods: {DrinkMood.cold, DrinkMood.sweet, DrinkMood.milky},
    ingredients: ['Süt', 'Karamel', 'Buz', 'Kahve', 'Krema'],
  ),
  Drink(
    shortName: 'Matcha',
    fullName: 'Matcha Latte',
    description: 'Japon yeşil çayı ve sütün huzur veren lezzeti.',
    icon: Icons.spa_rounded,
    color: Color(0xFF86A373),
    moods: {DrinkMood.hot, DrinkMood.fresh, DrinkMood.milky},
    ingredients: ['Matcha Tozu', 'Sıcak Süt', 'Vanilya Şurubu'],
  ),
  Drink(
    shortName: 'Iced Tea',
    fullName: 'Peach Iced Tea',
    description: 'Buz gibi serinletici, şeftali aromalı tatlı siyah çay.',
    icon: Icons.yard_rounded,
    color: Color(0xFFD68A59),
    moods: {DrinkMood.cold, DrinkMood.fresh, DrinkMood.sweet},
    ingredients: ['Siyah Çay', 'Şeftali Şurubu', 'Buz', 'Su'],
  ),
  Drink(
    shortName: 'Hot Choco',
    fullName: 'Hot Chocolate',
    description:
        'Gerçek çikolata parçalarıyla hazırlanan sıcak, tatlı kış klasiği.',
    icon: Icons.fireplace_rounded,
    color: Color(0xFF6B4226),
    moods: {DrinkMood.hot, DrinkMood.sweet, DrinkMood.milky},
    ingredients: ['Sıcak Süt', 'Kakao', 'Eritilmiş Çikolata'],
  ),
];

class BouncyButton extends StatefulWidget {
  const BouncyButton({super.key, required this.child, required this.onTap});
  final Widget child;
  final VoidCallback? onTap;

  @override
  State<BouncyButton> createState() => _BouncyButtonState();
}

class _BouncyButtonState extends State<BouncyButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 160),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOut,
        reverseCurve: Curves.easeOutBack,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) {
        if (widget.onTap != null) {
          _controller.forward();
        }
      },
      onPointerUp: (_) {
        if (widget.onTap != null) {
          _controller.reverse();
        }
      },
      onPointerCancel: (_) {
        if (widget.onTap != null) {
          _controller.reverse();
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: ScaleTransition(scale: _scaleAnimation, child: widget.child),
      ),
    );
  }
}

class _CurvedArrowsPainter extends CustomPainter {
  final double animationValue;
  _CurvedArrowsPainter({required this.animationValue});

  @override
  void paint(Canvas canvas, Size size) {
    // Synchronize opacity and a subtle radial pulse for a true 'breathing' feel
    final double baseRadius = size.width * 0.48;
    final double radius =
        baseRadius + (animationValue * 4.0); // Subtle expansion pulse

    final center = Offset(size.width / 2, size.height / 2);
    final Rect arcRect = Rect.fromCircle(center: center, radius: radius);

    // Opacity pulse - kept subtle so arrows don't dominate
    final color = Colors.white.withValues(
      alpha: 0.10 + (animationValue * 0.30),
    );

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.butt;

    final arrowHeadPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // 1. Left-side curved arrow (around 9-10 o'clock)
    const double startAngle1 = -pi * 0.60;
    const double sweepAngle1 = -pi * 0.22;
    canvas.drawArc(arcRect, startAngle1, sweepAngle1, false, paint);

    // 2. Right-side curved arrow (around 4-5 o'clock)
    const double startAngle2 = pi * 0.42;
    const double sweepAngle2 = -pi * 0.22;
    canvas.drawArc(arcRect, startAngle2, sweepAngle2, false, paint);

    // Function to draw arrow head at the end of an arc
    void drawHead(double endAngle) {
      final double x = center.dx + radius * cos(endAngle);
      final double y = center.dy + radius * sin(endAngle);

      canvas.save();
      canvas.translate(x, y);

      final double tangentAngle = atan2(-cos(endAngle), sin(endAngle));
      canvas.rotate(tangentAngle - pi / 2);

      final headPath = Path()
        ..moveTo(-8, -14)
        ..lineTo(8, -14)
        ..lineTo(0, 0)
        ..close();
      canvas.drawPath(headPath, arrowHeadPaint);
      canvas.restore();
    }

    // Draw heads at the end of each arc
    drawHead(startAngle1 + sweepAngle1);
    drawHead(startAngle2 + sweepAngle2);
  }

  @override
  bool shouldRepaint(covariant _CurvedArrowsPainter oldDelegate) =>
      oldDelegate.animationValue != animationValue;
}

class _RotatingIcon extends StatefulWidget {
  final IconData icon;
  final Color color;
  final double size;
  const _RotatingIcon({
    required this.icon,
    required this.color,
    required this.size,
  });

  @override
  State<_RotatingIcon> createState() => _RotatingIconState();
}

class _RotatingIconState extends State<_RotatingIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _controller,
      child: Icon(widget.icon, color: widget.color, size: widget.size),
    );
  }
}

class _CocktailShowcaseCard extends StatefulWidget {
  final List<_MenuItem> cocktails;
  final ValueChanged<_MenuItem> onTap;
  final bool isSpinning;

  const _CocktailShowcaseCard({
    required this.cocktails,
    required this.onTap,
    required this.isSpinning,
  });

  @override
  State<_CocktailShowcaseCard> createState() => _CocktailShowcaseCardState();
}

class _CocktailShowcaseCardState extends State<_CocktailShowcaseCard>
    with WidgetsBindingObserver {
  int _currentIndex = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startTimer();
  }

  @override
  void didUpdateWidget(covariant _CocktailShowcaseCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSpinning != oldWidget.isSpinning) {
      if (widget.isSpinning) {
        _stopTimer();
      } else {
        _startTimer();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopTimer();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !widget.isSpinning) {
      _startTimer();
    } else {
      _stopTimer();
    }
  }

  void _startTimer() {
    _stopTimer();
    final lifecycleState = WidgetsBinding.instance.lifecycleState;
    if (widget.cocktails.isEmpty ||
        (lifecycleState != null &&
            lifecycleState != AppLifecycleState.resumed)) {
      return;
    }
    _timer = Timer.periodic(const Duration(milliseconds: 4500), (timer) {
      if (mounted) {
        setState(() {
          _currentIndex = (_currentIndex + 1) % widget.cocktails.length;
        });
      }
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.cocktails.isEmpty) return const SizedBox.shrink();

    final isCompact = MediaQuery.sizeOf(context).width < 700;
    final item = widget.cocktails[_currentIndex];

    // Vibrant gradient lists for fallback cocktail placeholder
    final gradients = [
      [
        const Color(0xFFF9AB3E),
        const Color(0xFFE879A8),
      ], // sunset orange to pink
      [
        const Color(0xFF4ECDC4),
        const Color(0xFF45AAF2),
      ], // turquoise to ocean blue
      [
        const Color(0xFFFF7675),
        const Color(0xFFFDA7DF),
      ], // soft red to lavender
      [const Color(0xFF74B9FF), const Color(0xFFA29BFE)], // blue to violet
      [const Color(0xFF55EFC4), const Color(0xFF4ECDC4)], // mint to teal
    ];
    final activeGradient = gradients[_currentIndex % gradients.length];

    final theme = appThemeNotifier.value;
    final Color themeColor;
    final IconData themeIcon;
    final String themeTitle;
    final Color badgeColor;
    final String badgeText;

    if (theme == AppTheme.winter) {
      themeColor = Colors.lightBlueAccent;
      themeIcon = Icons.ac_unit_rounded;
      themeTitle = tr('KIŞIN NE GİDER ?', 'WINTER FAVS ?');
      badgeColor = const Color(0xFF74B9FF);
      badgeText = tr('SICAK KAHVE', 'HOT DRINK');
    } else if (theme == AppTheme.normal) {
      themeColor = Colors.tealAccent;
      themeIcon = Icons.coffee_rounded;
      themeTitle = tr('BUGÜN NE İÇSEK?', 'WHAT TO DRINK TODAY?');
      badgeColor = Colors.tealAccent;
      badgeText = tr('İÇECEK', 'DRINK');
    } else if (theme == AppTheme.newYear) {
      themeColor = Colors.redAccent;
      themeIcon = Icons.forest_rounded;
      themeTitle = tr('YENİ YILDA NE GİDER ?', 'NEW YEAR FAVS ?');
      badgeColor = Colors.redAccent;
      badgeText = tr('YENİ YIL', 'NEW YEAR');
    } else if (theme == AppTheme.feast) {
      themeColor = Colors.greenAccent;
      themeIcon = Icons.celebration_rounded;
      themeTitle = tr('BAYRAM ŞEKERLERİ', 'BAYRAM SWEETS');
      badgeColor = Colors.greenAccent;
      badgeText = tr('TATLI', 'SWEET');
    } else {
      // Default / Summer
      themeColor = _gold;
      themeIcon = Icons.wb_sunny_rounded;
      themeTitle = tr('YAZIN NE GİDER ?', 'SUMMER FAVS ?');
      badgeColor = const Color(0xFF4ECDC4);
      badgeText = tr('KOKTEYL', 'COCKTAIL');
    }

    return BouncyButton(
      onTap: () => widget.onTap(item),
      child: Container(
        width: double.infinity,
        height: double.infinity,
        padding: EdgeInsets.all(isCompact ? 16 : 22),
        decoration: BoxDecoration(
          color: _surface.withValues(alpha: 0.27),
          borderRadius: BorderRadius.circular(isCompact ? 24 : 32),
          border: Border.all(
            color: themeColor.withValues(alpha: 0.25),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 24,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Slot (Summer/Winter dynamic)
            Row(
              children: [
                _RotatingIcon(icon: themeIcon, color: themeColor, size: 26),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    themeTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: themeColor,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                // Glowing badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: badgeColor.withValues(alpha: 0.5),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    badgeText,
                    style: TextStyle(
                      color: badgeColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Carousel Showcase
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 600),
                switchInCurve: Curves.easeInOutCubic,
                switchOutCurve: Curves.easeInOutCubic,
                transitionBuilder: (Widget child, Animation<double> animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position:
                          Tween<Offset>(
                            begin: child.key == ValueKey(_currentIndex)
                                ? const Offset(0.18, 0.0)
                                : const Offset(-0.18, 0.0),
                            end: Offset.zero,
                          ).animate(
                            CurvedAnimation(
                              parent: animation,
                              curve: Curves.easeInOutCubic,
                            ),
                          ),
                      child: child,
                    ),
                  );
                },
                child: KeyedSubtree(
                  key: ValueKey(_currentIndex),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Showcase Image
                      Expanded(
                        child: Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.08),
                              width: 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.2),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              // Vibrant background summer gradient pool
                              Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: activeGradient,
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                ),
                              ),

                              if (item.imagePath != null)
                                Padding(
                                  padding: const EdgeInsets.all(12.0),
                                  child: Image.asset(
                                    item.imagePath!,
                                    fit: BoxFit.contain,
                                    errorBuilder: (context, error, stackTrace) {
                                      return const Center(
                                        child: Icon(
                                          Icons.local_bar_rounded,
                                          color: Colors.white70,
                                          size: 64,
                                        ),
                                      );
                                    },
                                  ),
                                )
                              else
                                const Center(
                                  child: Icon(
                                    Icons.local_bar_rounded,
                                    color: Colors.white70,
                                    size: 64,
                                  ),
                                ),

                              // Dark vignette overlay at bottom of image
                              Positioned.fill(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        Colors.black.withValues(alpha: 0.0),
                                        Colors.black.withValues(alpha: 0.35),
                                      ],
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Details Area
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Cocktail Name
                                ShaderMask(
                                  shaderCallback: (bounds) => LinearGradient(
                                    colors: [_cream, activeGradient.first],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ).createShader(bounds),
                                  child: Text(
                                    trMenu(item.name),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.white,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                // Description
                                Text(
                                  trMenu(item.desc),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: _cream.withValues(alpha: 0.7),
                                    height: 1.3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Price Badge
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: _gold.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: _gold.withValues(alpha: 0.35),
                                width: 1.2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: _gold.withValues(alpha: 0.05),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  item.price,
                                  style: const TextStyle(
                                    color: _gold,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(
                                  Icons.arrow_forward_ios_rounded,
                                  color: _gold,
                                  size: 10,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      // Secondary details: Tag pills row
                      if (item.tags.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: item.tags.map((tag) {
                            final color =
                                _tagStyles[tag] ?? const Color(0xFFB2BEC3);
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: color.withValues(alpha: 0.4),
                                ),
                              ),
                              child: Text(
                                trMenu(tag),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: color,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VirtualCanvasDialogWrapper extends StatelessWidget {
  final Widget child;
  const _VirtualCanvasDialogWrapper({required this.child});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenAspectRatio = constraints.maxWidth / constraints.maxHeight;
        final virtualWidth = max(1920.0, 1080.0 * screenAspectRatio);

        return Center(
          child: FittedBox(
            fit: BoxFit.contain,
            child: MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(size: Size(virtualWidth, 1080.0)),
              child: SizedBox(
                width: virtualWidth,
                height: 1080.0,
                child: Center(child: child),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CleaningModeDialog extends StatefulWidget {
  const _CleaningModeDialog();

  @override
  State<_CleaningModeDialog> createState() => _CleaningModeDialogState();
}

class _CleaningModeDialogState extends State<_CleaningModeDialog> {
  int _secondsLeft = 30;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    AnalyticsService.instance.trackCleaningModeStarted();
    // Hide all system overlays (status bar and navigation bar) completely
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: []);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _secondsLeft--;
          if (_secondsLeft <= 0) {
            _timer?.cancel();
            Navigator.of(context).pop();
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    // Restore the standard immersive sticky kiosk UI mode
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AbsorbPointer(
        absorbing:
            true, // Completely disable and consume all touch inputs in Flutter
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.cleaning_services_rounded,
                  color: Colors.lightBlueAccent,
                  size: 80,
                ),
                const SizedBox(height: 24),
                Text(
                  tr('EKRAN TEMİZLEME MODU', 'SCREEN CLEANING MODE'),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  tr(
                    'Ekranı şimdi silebilirsiniz. Dokunmatik kilitli.',
                    'You can now wipe the screen. Touch is locked.',
                  ),
                  style: TextStyle(color: Colors.white70, fontSize: 20),
                ),
                const SizedBox(height: 48),
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.lightBlueAccent, width: 4),
                  ),
                  child: Center(
                    child: Text(
                      '$_secondsLeft',
                      style: const TextStyle(
                        color: Colors.lightBlueAccent,
                        fontSize: 48,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
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

class _LanguageSwitcher extends StatelessWidget {
  const _LanguageSwitcher();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: appLanguageNotifier,
      builder: (context, language, _) {
        final isTr = language == AppLanguage.tr;
        return BouncyButton(
          onTap: () {
            if (isTr && !currentFeatureFlags.english) {
              showFeatureLockedDialog(
                context,
                tr('İngilizce Dil Desteği', 'English Language Support'),
              );
              return;
            }
            appLanguageNotifier.value = isTr ? AppLanguage.en : AppLanguage.tr;
          },
          child: Container(
            decoration: BoxDecoration(
              color: _bgDark.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'TR',
                  style: TextStyle(
                    color: isTr ? _gold : _muted,
                    fontWeight: isTr ? FontWeight.bold : FontWeight.normal,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 1,
                  height: 16,
                  color: Colors.white.withValues(alpha: 0.2),
                ),
                const SizedBox(width: 8),
                Text(
                  'EN',
                  style: TextStyle(
                    color: !isTr ? _gold : _muted,
                    fontWeight: !isTr ? FontWeight.bold : FontWeight.normal,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ===== LUUQ KULLANIM ANALİZLERİ VE VERİ SERVİSİ =====

class _LuuqAnalytics {
  _LuuqAnalytics._();
  static final instance = _LuuqAnalytics._();

  int menuClicks = 0;
  int wheelSpins = 0;
  int whoPaysPlays = 0;

  Future<File> _resolvedFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/luuq_analytics.json');
  }

  Future<void> load() async {
    try {
      final file = await _resolvedFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        final data = json.decode(content) as Map<String, dynamic>;
        menuClicks = data['menuClicks'] ?? 0;
        wheelSpins = data['wheelSpins'] ?? 0;
        whoPaysPlays = data['whoPaysPlays'] ?? 0;
      }
    } catch (e) {
      // ignore
    }
  }

  Future<void> save() async {
    try {
      final data = {
        'menuClicks': menuClicks,
        'wheelSpins': wheelSpins,
        'whoPaysPlays': whoPaysPlays,
      };
      final file = await _resolvedFile();
      await file.writeAsString(json.encode(data));
    } catch (e) {
      // ignore
    }
  }

  Future<void> incrementMenuClicks() async {
    menuClicks++;
    await save();
  }

  Future<void> incrementWheelSpins() async {
    wheelSpins++;
    await save();
  }

  Future<void> incrementWhoPaysPlays() async {
    whoPaysPlays++;
    await save();
  }

  Future<void> reset() async {
    menuClicks = 0;
    wheelSpins = 0;
    whoPaysPlays = 0;
    await save();
  }
}

// ===== ANALİZLER ADMİN DİYALOGU =====

class _AnalyticsAdminDialog extends StatefulWidget {
  const _AnalyticsAdminDialog();

  @override
  State<_AnalyticsAdminDialog> createState() => _AnalyticsAdminDialogState();
}

class _AnalyticsAdminDialogState extends State<_AnalyticsAdminDialog> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    await _LuuqAnalytics.instance.load();
    if (mounted) {
      setState(() {
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 680,
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
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: _gold))
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header
                  Row(
                    children: [
                      const Icon(
                        Icons.analytics_rounded,
                        color: _gold,
                        size: 28,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          tr('Kullanım Analizleri', 'Usage Analytics'),
                          style: const TextStyle(
                            color: _cream,
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                          ),
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

                  // Cards Grid
                  Row(
                    children: [
                      Expanded(
                        child: _buildStatCard(
                          icon: Icons.menu_book_rounded,
                          title: tr('Menü Tıklama', 'Menu Clicks'),
                          value: _LuuqAnalytics.instance.menuClicks,
                          color: _mint,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildStatCard(
                          icon: Icons.casino_rounded,
                          title: tr('Çark Çevirme', 'Wheel Spins'),
                          value: _LuuqAnalytics.instance.wheelSpins,
                          color: _gold,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildStatCard(
                          icon: Icons.payments_rounded,
                          title: tr('Hesap Kimde', 'Who Pays'),
                          value: _LuuqAnalytics.instance.whoPaysPlays,
                          color: const Color(0xFF74B9FF),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),

                  // Footer Actions
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Reset Button
                      TextButton.icon(
                        onPressed: _showResetConfirmDialog,
                        icon: const Icon(
                          Icons.refresh_rounded,
                          color: Colors.redAccent,
                          size: 20,
                        ),
                        label: Text(
                          tr('Verileri Sıfırla', 'Reset Data'),
                          style: const TextStyle(
                            color: Colors.redAccent,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(
                              color: Colors.redAccent.withValues(alpha: 0.3),
                            ),
                          ),
                        ),
                      ),

                      // Close Button
                      ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _gold,
                          foregroundColor: _bgDark,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 32,
                            vertical: 16,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 8,
                          shadowColor: _gold.withValues(alpha: 0.3),
                        ),
                        child: Text(
                          tr('Kapat', 'Close'),
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String title,
    required int value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withValues(alpha: 0.15), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              color: _muted,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$value',
            style: TextStyle(
              color: _cream,
              fontSize: 36,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showResetConfirmDialog() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1C1724),
        title: Text(
          tr('Verileri Sıfırla', 'Reset Data'),
          style: const TextStyle(color: _cream),
        ),
        content: Text(
          tr(
            'Tüm analiz verilerini sıfırlamak istediğinize emin misiniz? Bu işlem geri alınamaz.',
            'Are you sure you want to reset all analytics data? This action cannot be undone.',
          ),
          style: const TextStyle(color: _muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              tr('Hayır', 'No'),
              style: const TextStyle(color: _muted),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              tr('Evet, Sıfırla', 'Yes, Reset'),
              style: const TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _LuuqAnalytics.instance.reset();
      setState(() {});
    }
  }
}

// ===== UYGULAMA TEMASI SEÇİM DİYALOGU =====

class _ThemeSelectionDialog extends StatefulWidget {
  const _ThemeSelectionDialog();

  @override
  State<_ThemeSelectionDialog> createState() => _ThemeSelectionDialogState();
}

class _ThemeSelectionDialogState extends State<_ThemeSelectionDialog> {
  AppTheme _selectedTheme = AppTheme.summer;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _selectedTheme = appThemeNotifier.value;
  }

  Future<void> _onThemeSelected(AppTheme theme) async {
    if (_isSaving || theme == _selectedTheme) return;

    final previousTheme = _selectedTheme;
    final oldThemeName = appThemeNotifier.value.name;
    setState(() {
      _isSaving = true;
      _selectedTheme = theme;
    });

    final saved = await _saveAppTheme(theme);
    if (!mounted) return;

    setState(() {
      _isSaving = false;
      if (!saved) {
        _selectedTheme = previousTheme;
      }
    });

    if (!saved) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(
              'Tema kaydedilemedi. Önceki tema kullanılmaya devam edecek.',
              'Theme could not be saved. The previous theme will remain active.',
            ),
            style: const TextStyle(color: _cream, fontWeight: FontWeight.bold),
          ),
          backgroundColor: const Color(0xFF231E2D),
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    AnalyticsService.instance.trackThemeChanged(oldThemeName, theme.name);

    final String themeName = theme == AppTheme.summer
        ? tr('Yaz Modu', 'Summer Mode')
        : theme == AppTheme.winter
        ? tr('Kış Modu', 'Winter Mode')
        : theme == AppTheme.feast
        ? tr('Bayram Modu', 'Bayram Mode')
        : theme == AppTheme.newYear
        ? tr('Yılbaşı Modu', 'New Year Mode')
        : tr('Normal Mod', 'Normal Mode');

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          tr('$themeName aktif edildi!', '$themeName has been activated!'),
          style: const TextStyle(color: _cream, fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF231E2D),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 680,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1724),
          borderRadius: BorderRadius.circular(36),
          border: Border.all(
            color: Colors.purpleAccent.withValues(alpha: 0.24),
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
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.purpleAccent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.palette_rounded,
                    color: Colors.purpleAccent,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr('UYGULAMA TEMASI', 'APPLICATION THEME'),
                        style: const TextStyle(
                          color: _cream,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        tr(
                          'Kiosk Görünüm Modunu Değiştirin',
                          'Change Kiosk Visual Mode',
                        ),
                        style: const TextStyle(
                          color: _muted,
                          fontSize: 13,
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
            const SizedBox(height: 28),

            // Grid of Themes
            GridView.count(
              shrinkWrap: true,
              crossAxisCount: 2,
              crossAxisSpacing: 20,
              mainAxisSpacing: 20,
              childAspectRatio: 1.6,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildThemeCard(
                  theme: AppTheme.normal,
                  title: tr('Normal Mod', 'Normal Mode'),
                  subtitle: tr(
                    'Sade görünüm, içecek önerileriyle',
                    'Simple appearance with drink suggestions',
                  ),
                  icon: Icons.coffee_rounded,
                  color: Colors.tealAccent,
                ),
                _buildThemeCard(
                  theme: AppTheme.summer,
                  title: tr('Yaz Modu', 'Summer Mode'),
                  subtitle: tr(
                    'Canlı sarı ve sıcak koyu tonlar',
                    'Vibrant gold & warm dark tones',
                  ),
                  icon: Icons.wb_sunny_rounded,
                  color: _gold,
                ),
                _buildThemeCard(
                  theme: AppTheme.winter,
                  title: tr('Kış Modu', 'Winter Mode'),
                  subtitle: tr(
                    'Soğuk mavi tonlar ve kar animasyonları',
                    'Cool blue tones & snow animations',
                  ),
                  icon: Icons.ac_unit_rounded,
                  color: Colors.lightBlueAccent,
                ),
                _buildThemeCard(
                  theme: AppTheme.feast,
                  title: tr('Bayram Modu', 'Holiday Mode'),
                  subtitle: tr(
                    'Geleneksel motifler ve kutlama detayları',
                    'Traditional motifs & celebration details',
                  ),
                  icon: Icons.celebration_rounded,
                  color: Colors.greenAccent,
                ),
                _buildThemeCard(
                  theme: AppTheme.newYear,
                  title: tr('Yılbaşı Modu', 'New Year Mode'),
                  subtitle: tr(
                    'Kırmızı, yeşil tonlar ve yeni yıl coşkusu',
                    'Red, green tones & new year spirit',
                  ),
                  icon: Icons.forest_rounded,
                  color: Colors.redAccent,
                ),
              ],
            ),
            const SizedBox(height: 32),

            // Footer close button
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
                    color: Colors.purpleAccent,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.purpleAccent.withValues(alpha: 0.25),
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
    );
  }

  Widget _buildThemeCard({
    required AppTheme theme,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    bool isDevelopment = false,
  }) {
    final isSelected = _selectedTheme == theme;
    final isLocked = !currentFeatureFlags.themes && !isSelected;

    return BouncyButton(
      onTap: _isSaving
          ? null
          : () {
              if (isLocked) {
                showFeatureLockedDialog(
                  context,
                  tr('Tema Seçimi', 'Theme Selection'),
                );
                return;
              }
              _onThemeSelected(theme);
            },
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.08)
              : _surface.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isSelected ? color : Colors.white.withValues(alpha: 0.08),
            width: isSelected ? 2.5 : 1.5,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.15),
                    blurRadius: 12,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                if (isSelected)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      tr('Aktif', 'Active'),
                      style: const TextStyle(
                        color: _bgDark,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  )
                else if (isLocked)
                  const Icon(Icons.lock_rounded, color: _gold, size: 18)
                else if (isDevelopment)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.1),
                      ),
                    ),
                    child: Text(
                      tr('Yakında', 'Soon'),
                      style: TextStyle(
                        color: _muted.withValues(alpha: 0.8),
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            const Spacer(),
            Text(
              title,
              style: TextStyle(
                color: isSelected ? _cream : _cream.withValues(alpha: 0.9),
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _muted,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===== SES SEVİYESİ SEÇİM DİYALOGU =====

class _VolumeSelectionDialog extends StatefulWidget {
  const _VolumeSelectionDialog();

  @override
  State<_VolumeSelectionDialog> createState() => _VolumeSelectionDialogState();
}

class _VolumeSelectionDialogState extends State<_VolumeSelectionDialog> {
  double _selectedVolume = 1.0;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _selectedVolume = appVolumeNotifier.value;
  }

  Future<void> _onVolumeSelected(double vol) async {
    if (_isSaving || (_selectedVolume - vol).abs() < 0.001) return;

    final previousVolume = _selectedVolume;
    final int oldVolume = (appVolumeNotifier.value * 100).round();
    final int newVolume = (vol * 100).round();
    setState(() {
      _isSaving = true;
      _selectedVolume = vol;
    });

    final saved = await _saveAppVolume(vol);
    if (!mounted) return;

    setState(() {
      _isSaving = false;
      if (!saved) {
        _selectedVolume = previousVolume;
      }
    });

    if (!saved) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(
              'Ses seviyesi kaydedilemedi. Önceki değer kullanılmaya devam edecek.',
              'Volume could not be saved. The previous value will remain active.',
            ),
            style: const TextStyle(color: _cream, fontWeight: FontWeight.bold),
          ),
          backgroundColor: const Color(0xFF231E2D),
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    AnalyticsService.instance.trackVolumeChanged(oldVolume, newVolume);

    // Play a preview tick sound so user can hear the new volume
    _SpinTickSound().playTick();

    final int percentage = (vol * 100).round();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          tr(
            'Ses seviyesi %$percentage olarak ayarlandı!',
            'Volume level set to $percentage%!',
          ),
          style: const TextStyle(color: _cream, fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF231E2D),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double virtualWidth = 540.0;

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: virtualWidth,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1724),
          borderRadius: BorderRadius.circular(34),
          border: Border.all(color: Colors.pinkAccent.withValues(alpha: 0.24)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.75),
              blurRadius: 64,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.pinkAccent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.volume_up_rounded,
                    color: Colors.pinkAccent,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr('SES SEVİYESİ', 'VOLUME LEVEL'),
                        style: const TextStyle(
                          color: _cream,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        tr(
                          'Kiosk Ses Seviyesini Değiştirin',
                          'Change Kiosk Volume Level',
                        ),
                        style: const TextStyle(
                          color: _muted,
                          fontSize: 13,
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
            const SizedBox(height: 28),

            // Horizontal Row of 5 Volume options
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildVolumeCard(0.0, '0%', Icons.volume_off_rounded),
                _buildVolumeCard(0.25, '25%', Icons.volume_mute_rounded),
                _buildVolumeCard(0.50, '50%', Icons.volume_down_rounded),
                _buildVolumeCard(0.75, '75%', Icons.volume_down_rounded),
                _buildVolumeCard(1.00, '100%', Icons.volume_up_rounded),
              ],
            ),
            const SizedBox(height: 28),

            // Footer Close Button
            Align(
              alignment: Alignment.centerRight,
              child: BouncyButton(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.pinkAccent,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.pinkAccent.withValues(alpha: 0.25),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Text(
                    tr('Kapat', 'Close'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVolumeCard(double value, String label, IconData icon) {
    final bool isSelected = (_selectedVolume - value).abs() < 0.05;

    return BouncyButton(
      onTap: _isSaving ? null : () => _onVolumeSelected(value),
      child: Container(
        width: 82,
        height: 104,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.pinkAccent.withValues(alpha: 0.12)
              : Colors.white.withValues(alpha: 0.02),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected
                ? Colors.pinkAccent
                : Colors.white.withValues(alpha: 0.08),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.pinkAccent.withValues(alpha: 0.15),
                    blurRadius: 12,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.pinkAccent : _muted,
              size: 28,
            ),
            const SizedBox(height: 10),
            Text(
              label,
              style: TextStyle(
                color: isSelected
                    ? Colors.white
                    : _cream.withValues(alpha: 0.7),
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
      final result = await InternetAddress.lookup(
        'google.com',
      ).timeout(const Duration(seconds: 2));
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
              color: isEnabled ? _cream : _muted,
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
                            color: _muted,
                            fontSize: 13,
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
                                              color: _muted,
                                              fontSize: 13,
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
                                                fontSize: 12,
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
                                            Navigator.of(
                                              context,
                                            ).pop(); // close AppInfo dialog
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
                                              fontSize: 13,
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
                color: _muted,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? _cream,
              fontSize: 13,
              fontWeight: FontWeight.w900,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}

// ===== BAYRAM MODU ŞEKER YAĞMURU WIDGETI VE PAINTERI =====

class _FeastThemeCandyRain extends StatefulWidget {
  final int count;
  const _FeastThemeCandyRain({this.count = 40});

  @override
  State<_FeastThemeCandyRain> createState() => _FeastThemeCandyRainState();
}

class _FeastThemeCandyRainState extends State<_FeastThemeCandyRain>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  final List<_CandyParticle> _particles = [];
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();

    // Initialize particles
    for (int i = 0; i < widget.count; i++) {
      _particles.add(_generateParticle(initial: true));
    }

    _controller.addListener(_updateParticles);
  }

  @override
  void dispose() {
    _controller.removeListener(_updateParticles);
    _controller.dispose();
    super.dispose();
  }

  _CandyParticle _generateParticle({bool initial = false}) {
    final scale = 0.5 + _random.nextDouble() * 0.7;
    return _CandyParticle(
      x: _random.nextDouble(),
      y: initial ? _random.nextDouble() * 1.2 - 0.2 : -0.1,
      speed: 0.03 + _random.nextDouble() * 0.05,
      rotation: _random.nextDouble() * pi * 2,
      rotationSpeed:
          (0.2 + _random.nextDouble() * 0.6) * (_random.nextBool() ? 1 : -1),
      scale: scale,
      color: [
        const Color(0xFFFF74B1), // Candy Pink
        const Color(0xFFFFB100), // Orange
        const Color(0xFF48C9B0), // Mint
        const Color(0xFFFF7D7D), // Soft Red
        const Color(0xFFA55EEA), // Purple
        const Color(0xFF2D98DA), // Blue
      ][_random.nextInt(6)],
      type: _random.nextInt(
        3,
      ), // 0: Wrapped Hard Candy, 1: Lollipop, 2: Round Swirl
    );
  }

  void _updateParticles() {
    if (!mounted) return;
    setState(() {
      for (int i = 0; i < _particles.length; i++) {
        final p = _particles[i];
        p.y += p.speed * 0.05; // Fall speed
        p.rotation += p.rotationSpeed * 0.05; // Spin speed

        // Horizontal sway
        p.x += sin(_controller.value * pi * 2 + i) * 0.001;

        // Reset if it goes off bottom
        if (p.y > 1.1) {
          _particles[i] = _generateParticle();
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(painter: _CandyRainPainter(particles: _particles)),
      ),
    );
  }
}

class _CandyParticle {
  double x; // 0.0 to 1.0
  double y; // 0.0 to 1.0
  final double speed;
  double rotation;
  final double rotationSpeed;
  final double scale;
  final Color color;
  final int type; // 0: wrapped candy, 1: lollipop, 2: round swirl

  _CandyParticle({
    required this.x,
    required this.y,
    required this.speed,
    required this.rotation,
    required this.rotationSpeed,
    required this.scale,
    required this.color,
    required this.type,
  });
}

class _CandyRainPainter extends CustomPainter {
  final List<_CandyParticle> particles;
  _CandyRainPainter({required this.particles});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    for (final p in particles) {
      final px = p.x * size.width;
      final py = p.y * size.height;
      final radius = 16.0 * p.scale;

      canvas.save();
      canvas.translate(px, py);
      canvas.rotate(p.rotation);

      if (p.type == 0) {
        // Draw Wrapped Hard Candy
        // Left twist end
        final pathLeft = Path()
          ..moveTo(-radius, 0)
          ..lineTo(-radius * 1.6, -radius * 0.6)
          ..lineTo(-radius * 1.6, radius * 0.6)
          ..close();
        paint.color = p.color.withValues(alpha: 0.7);
        canvas.drawPath(pathLeft, paint);

        // Right twist end
        final pathRight = Path()
          ..moveTo(radius, 0)
          ..lineTo(radius * 1.6, -radius * 0.6)
          ..lineTo(radius * 1.6, radius * 0.6)
          ..close();
        canvas.drawPath(pathRight, paint);

        // Central candy body
        paint.color = p.color;
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset.zero,
            width: radius * 2,
            height: radius * 1.3,
          ),
          paint,
        );

        // Swirl line/details
        final detailPaint = Paint()
          ..color = Colors.white.withValues(alpha: 0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0 * p.scale;
        canvas.drawArc(
          Rect.fromCenter(
            center: Offset.zero,
            width: radius * 1.2,
            height: radius * 0.8,
          ),
          0,
          pi,
          false,
          detailPaint,
        );
      } else if (p.type == 1) {
        // Draw Lollipop
        // Stick
        final stickPaint = Paint()
          ..color = Colors.white.withValues(alpha: 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.0 * p.scale
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(Offset.zero, Offset(0, radius * 1.8), stickPaint);

        // Lollipop head
        paint.color = p.color;
        canvas.drawCircle(Offset.zero, radius, paint);

        // Swirl detail
        final swirlPaint = Paint()
          ..color = Colors.white.withValues(alpha: 0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0 * p.scale;

        final swirlPath = Path();
        for (double theta = 0; theta < pi * 3; theta += 0.1) {
          final r = radius * 0.8 * (theta / (pi * 3));
          final dx = r * cos(theta);
          final dy = r * sin(theta);
          if (theta == 0) {
            swirlPath.moveTo(dx, dy);
          } else {
            swirlPath.lineTo(dx, dy);
          }
        }
        canvas.drawPath(swirlPath, swirlPaint);
      } else {
        // Draw Round Swirl Candy
        paint.color = p.color;
        canvas.drawCircle(Offset.zero, radius, paint);

        // Stripes details
        final stripePaint = Paint()
          ..color = Colors.white.withValues(alpha: 0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5 * p.scale;

        canvas.drawArc(
          Rect.fromCircle(center: Offset.zero, radius: radius * 0.7),
          0,
          pi * 0.5,
          false,
          stripePaint,
        );
        canvas.drawArc(
          Rect.fromCircle(center: Offset.zero, radius: radius * 0.7),
          pi,
          pi * 0.5,
          false,
          stripePaint,
        );
        canvas.drawArc(
          Rect.fromCircle(center: Offset.zero, radius: radius * 0.4),
          pi * 0.5,
          pi * 0.5,
          false,
          stripePaint,
        );
        canvas.drawArc(
          Rect.fromCircle(center: Offset.zero, radius: radius * 0.4),
          pi * 1.5,
          pi * 0.5,
          false,
          stripePaint,
        );
      }

      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _CandyRainPainter oldDelegate) => true;
}

// ===== YILBAŞI MODU KAR YAĞMURU WIDGETI VE PAINTERI =====

class _NewYearThemeSnowRain extends StatefulWidget {
  const _NewYearThemeSnowRain();

  @override
  State<_NewYearThemeSnowRain> createState() => _NewYearThemeSnowRainState();
}

class _NewYearThemeSnowRainState extends State<_NewYearThemeSnowRain>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  final List<_SnowParticle> _particles = [];
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();

    // Initialize particles
    for (int i = 0; i < 50; i++) {
      _particles.add(_generateParticle(initial: true));
    }

    _controller.addListener(_updateParticles);
  }

  @override
  void dispose() {
    _controller.removeListener(_updateParticles);
    _controller.dispose();
    super.dispose();
  }

  _SnowParticle _generateParticle({bool initial = false}) {
    final scale = 0.4 + _random.nextDouble() * 0.8;
    return _SnowParticle(
      x: _random.nextDouble(),
      y: initial ? _random.nextDouble() * 1.2 - 0.2 : -0.1,
      speed: 0.03 + _random.nextDouble() * 0.05, // Same speed as candy rain
      rotation: _random.nextDouble() * pi * 2,
      rotationSpeed:
          (0.1 + _random.nextDouble() * 0.3) * (_random.nextBool() ? 1 : -1),
      scale: scale,
      opacity: 0.3 + _random.nextDouble() * 0.5,
      type: _random.nextInt(
        3,
      ), // 0: soft circle, 1: asterisk, 2: complex crystal
    );
  }

  void _updateParticles() {
    if (!mounted) return;
    setState(() {
      for (int i = 0; i < _particles.length; i++) {
        final p = _particles[i];
        p.y += p.speed * 0.05; // Same fall speed factor as candy rain
        p.rotation += p.rotationSpeed * 0.05; // Spin speed

        // Sway sideways slightly like real snow
        p.x += sin(_controller.value * pi * 2 + i) * 0.0012;

        // Reset if it goes off bottom
        if (p.y > 1.1) {
          _particles[i] = _generateParticle();
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(painter: _SnowRainPainter(particles: _particles)),
      ),
    );
  }
}

class _SnowParticle {
  double x; // 0.0 to 1.0
  double y; // 0.0 to 1.0
  final double speed;
  double rotation;
  final double rotationSpeed;
  final double scale;
  final double opacity;
  final int type; // 0: soft circle, 1: asterisk, 2: complex crystal

  _SnowParticle({
    required this.x,
    required this.y,
    required this.speed,
    required this.rotation,
    required this.rotationSpeed,
    required this.scale,
    required this.opacity,
    required this.type,
  });
}

class _SnowRainPainter extends CustomPainter {
  final List<_SnowParticle> particles;
  _SnowRainPainter({required this.particles});

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      final px = p.x * size.width;
      final py = p.y * size.height;
      final radius = 12.0 * p.scale;

      canvas.save();
      canvas.translate(px, py);
      canvas.rotate(p.rotation);

      if (p.type == 0) {
        // Draw Soft Circle
        final paint = Paint()
          ..color = Colors.white.withValues(alpha: p.opacity)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(Offset.zero, radius * 0.7, paint);
      } else if (p.type == 1) {
        // Draw 6-pointed asterisk
        final paint = Paint()
          ..color = Colors.white.withValues(alpha: p.opacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0 * p.scale
          ..strokeCap = StrokeCap.round;

        for (int i = 0; i < 3; i++) {
          final angle = i * pi / 3;
          canvas.drawLine(
            Offset(-radius * cos(angle), -radius * sin(angle)),
            Offset(radius * cos(angle), radius * sin(angle)),
            paint,
          );
        }
      } else {
        // Draw complex branched snow crystal
        final paint = Paint()
          ..color = Colors.white.withValues(alpha: p.opacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8 * p.scale
          ..strokeCap = StrokeCap.round;

        for (int i = 0; i < 6; i++) {
          final angle = i * pi / 3;
          final endX = radius * cos(angle);
          final endY = radius * sin(angle);
          canvas.drawLine(Offset.zero, Offset(endX, endY), paint);

          // Branches
          final branchLength = radius * 0.35;
          final branchAngle = pi / 4.5; // ~40 degrees

          // Branches at 50% length
          final bx1 = endX * 0.5;
          final by1 = endY * 0.5;
          canvas.drawLine(
            Offset(bx1, by1),
            Offset(
              bx1 + branchLength * cos(angle + branchAngle),
              by1 + branchLength * sin(angle + branchAngle),
            ),
            paint,
          );
          canvas.drawLine(
            Offset(bx1, by1),
            Offset(
              bx1 + branchLength * cos(angle - branchAngle),
              by1 + branchLength * sin(angle - branchAngle),
            ),
            paint,
          );

          // Small tips at 80% length
          final bx2 = endX * 0.8;
          final by2 = endY * 0.8;
          final smallTipLength = branchLength * 0.6;
          canvas.drawLine(
            Offset(bx2, by2),
            Offset(
              bx2 + smallTipLength * cos(angle + branchAngle),
              by2 + smallTipLength * sin(angle + branchAngle),
            ),
            paint,
          );
          canvas.drawLine(
            Offset(bx2, by2),
            Offset(
              bx2 + smallTipLength * cos(angle - branchAngle),
              by2 + smallTipLength * sin(angle - branchAngle),
            ),
            paint,
          );
        }
      }

      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _SnowRainPainter oldDelegate) => true;
}

// ===== YILBAŞI MODU NOEL ŞAPKASI PAINTERI =====

class _SantaHatPainter extends CustomPainter {
  const _SantaHatPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Draw red cap body (curved cone/triangle)
    final redPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          const Color(0xFFC0392B), // Deep crimson red
          const Color(0xFFE74C3C), // Bright festive red
        ],
        begin: Alignment.bottomLeft,
        end: Alignment.topRight,
      ).createShader(Rect.fromLTWH(0, 0, w, h))
      ..style = PaintingStyle.fill;

    // Curved red hat path
    final hatPath = Path();
    // Start at bottom-left of the red part
    hatPath.moveTo(w * 0.15, h * 0.7);
    // Control point for the top curve of the hat
    hatPath.quadraticBezierTo(w * 0.35, h * 0.12, w * 0.72, h * 0.18);
    // Tip of the hat dropping down slightly
    hatPath.quadraticBezierTo(w * 0.95, h * 0.22, w * 0.82, h * 0.52);
    // Inner fold curve back to bottom-right
    hatPath.quadraticBezierTo(w * 0.74, h * 0.44, w * 0.78, h * 0.7);
    hatPath.close();

    // Draw shadow under the hat body
    canvas.drawPath(
      hatPath,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.15)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0),
    );

    canvas.drawPath(hatPath, redPaint);

    // Draw white fluffy brim at the bottom
    final whiteBrimPaint = Paint()
      ..shader = LinearGradient(
        colors: [Colors.white, const Color(0xFFECF0F1)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, h * 0.62, w, h * 0.2))
      ..style = PaintingStyle.fill;

    // Brim as a soft curved path
    final brimPath = Path();
    brimPath.moveTo(w * 0.1, h * 0.7);
    brimPath.quadraticBezierTo(w * 0.45, h * 0.62, w * 0.8, h * 0.7);
    brimPath.quadraticBezierTo(w * 0.85, h * 0.78, w * 0.8, h * 0.84);
    brimPath.quadraticBezierTo(w * 0.45, h * 0.76, w * 0.1, h * 0.84);
    brimPath.quadraticBezierTo(w * 0.05, h * 0.76, w * 0.1, h * 0.7);
    brimPath.close();

    // Brim shadow
    canvas.drawPath(
      brimPath,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.15)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0),
    );
    canvas.drawPath(brimPath, whiteBrimPaint);

    // Draw small circles/bumps along the brim for fluffy details
    final fluffPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    for (int i = 0; i <= 6; i++) {
      final t = i / 6.0;
      // Interpolate along the curve of the brim
      final bx = w * 0.1 + (w * 0.7) * t;
      final by = h * 0.77 + sin(t * pi) * (-h * 0.08); // follow curve
      canvas.drawCircle(Offset(bx, by), w * 0.06, fluffPaint);
    }

    // Draw pom-pom at the tip
    final pomPomCenter = Offset(w * 0.82, h * 0.54);
    final pomPomRadius = w * 0.11;
    // Pom-pom shadow
    canvas.drawCircle(
      pomPomCenter,
      pomPomRadius,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.1)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0),
    );
    // Draw pom-pom base
    canvas.drawCircle(pomPomCenter, pomPomRadius, fluffPaint);

    // Draw smaller overlay circles for pom-pom fluffiness
    canvas.drawCircle(
      pomPomCenter + Offset(-w * 0.02, -h * 0.02),
      pomPomRadius * 0.8,
      Paint()..color = const Color(0xFFFBFBFC),
    );
    canvas.drawCircle(
      pomPomCenter + Offset(w * 0.02, h * 0.02),
      pomPomRadius * 0.8,
      Paint()..color = const Color(0xFFECEFF1),
    );
  }

  @override
  bool shouldRepaint(covariant oldDelegate) => false;
}

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
      final apkVersionCode = apkInfo['versionCode'] as int?;

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

      // This install remains part of the PIN-authorized download action.
      await _runInstallFlow(file.path);
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
                              color: _muted,
                              fontSize: 13,
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
                              color: _muted,
                              fontSize: 13,
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
                              color: _muted,
                              fontSize: 13,
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
                    color: _muted,
                    fontSize: 13,
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
                        fontSize: 13,
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

class GlobalDialogTracker {
  static bool isUpdateDialogOpen = false;
  static bool isUpdateDownloading = false;
  static bool isUpdateVerifying = false;
  static bool isUpdateReadyToInstall = false;
  static bool isUpdateOpeningInstaller = false;
  static bool isAdminPinDialogOpen = false;

  static bool shouldPauseIdleTimer() {
    return isUpdateDialogOpen ||
        isUpdateDownloading ||
        isUpdateVerifying ||
        isUpdateReadyToInstall ||
        isUpdateOpeningInstaller ||
        isAdminPinDialogOpen;
  }
}
