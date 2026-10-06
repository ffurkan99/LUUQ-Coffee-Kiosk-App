part of '../../main.dart';

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
  List<String>? wheelItemIds;
  String? baristaDrinkId;
  String? baristaDessertId;

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
        baristaDrinkId = jsonMap['baristaDrinkId'] as String?;
        baristaDessertId = jsonMap['baristaDessertId'] as String?;

        final list = jsonMap['wheelItems'] as List<dynamic>?;
        if (list != null) {
          wheelItems = list.cast<String>();
        }
        final ids = jsonMap['wheelItemIds'] as List<dynamic>?;
        if (ids != null) wheelItemIds = ids.cast<String>();
      }
    } catch (_) {}
  }

  /// Saves run one after another; each writes the values current at its turn.
  Future<bool> _saveChain = Future<bool>.value(true);

  Future<bool> save() {
    final next = _saveChain.then((_) => _saveNow(), onError: (_) => _saveNow());
    _saveChain = next;
    return next;
  }

  Future<bool> _saveNow() async {
    try {
      final file = await _getFile();
      final jsonMap = {
        'theme': theme.name,
        'volume': volume,
        'baristaDrink': baristaDrink,
        'baristaDessert': baristaDessert,
        'wheelItems': wheelItems,
        'baristaDrinkId': baristaDrinkId,
        'baristaDessertId': baristaDessertId,
        'wheelItemIds': wheelItemIds,
      };
      // Write a temp file and rename it over the old one: a power cut during
      // the write leaves the previous settings intact instead of a cut file.
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(json.encode(jsonMap), flush: true);
      await temp.rename(file.path);
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
