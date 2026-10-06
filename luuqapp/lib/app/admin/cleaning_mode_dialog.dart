part of '../../main.dart';

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
