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
        final data = json.decode(content);
        if (data is! Map) return;
        int count(Object? value) => value is num ? value.toInt() : 0;
        menuClicks = count(data['menuClicks']);
        wheelSpins = count(data['wheelSpins']);
        whoPaysPlays = count(data['whoPaysPlays']);
      }
    } catch (e) {
      // ignore
    }
  }

  /// Saves run one after another; each writes the values current at its turn.
  Future<void> _saveChain = Future<void>.value();

  Future<void> save() {
    final next = _saveChain.then((_) => _saveNow());
    _saveChain = next;
    return next;
  }

  Future<void> _saveNow() async {
    try {
      final data = {
        'menuClicks': menuClicks,
        'wheelSpins': wheelSpins,
        'whoPaysPlays': whoPaysPlays,
      };
      final file = await _resolvedFile();
      // Temp file + rename: a power cut mid-write keeps the previous counts
      // instead of a cut file that silently resets them to zero.
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(json.encode(data), flush: true);
      await temp.rename(file.path);
    } catch (e) {
      debugPrint('[ANALYTICS] Failed to save local counters: $e');
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
