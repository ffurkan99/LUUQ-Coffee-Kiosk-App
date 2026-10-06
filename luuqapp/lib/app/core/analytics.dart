part of '../../main.dart';

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
