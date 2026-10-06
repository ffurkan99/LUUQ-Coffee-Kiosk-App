part of '../../main.dart';

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

  late List<Color> _playerColors;
  int? _editingPlayerIndex;

  bool _isAnimating = false;
  bool _physicsStalled = false;

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

    // Kazanan burada seçilmez: fizik, kapak açıldığında ağızdan gerçekten
    // düşen topu belirler; sonuç onComplete ile simülasyondan gelir.
    setState(() {
      _result = null; // Hide previous result
      _physicsStalled = false;
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

  Widget _buildHesapKimdeActionButton({
    required String keyName,
    required String label,
    required String semanticLabel,
    required VoidCallback? onTap,
    required Color backgroundColor,
    required Color foregroundColor,
    required Color borderColor,
    bool emphasize = false,
  }) {
    return Semantics(
      container: true,
      excludeSemantics: true,
      button: true,
      enabled: onTap != null,
      label: semanticLabel,
      child: BouncyButton(
        onTap: onTap,
        child: SizedBox(
          width: double.infinity,
          height: 48,
          child: Container(
            key: ValueKey(keyName),
            padding: const EdgeInsets.symmetric(horizontal: 24),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor, width: 1.5),
              boxShadow: emphasize
                  ? [
                      BoxShadow(
                        color: _mint.withValues(alpha: 0.34),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ]
                  : null,
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: foregroundColor,
                fontSize: 16,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        key: const ValueKey('who_pays_card'),
        width: 480,
        padding: EdgeInsets.symmetric(
          horizontal: 40,
          vertical: MediaQuery.textScalerOf(context).scale(28) > 28 ? 16 : 40,
        ),
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
                color: _mutedText,
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
                  child: BouncyButton(
                    onTap: _isAnimating
                        ? null
                        : () {
                            setState(() {
                              _personCount = count;
                              _result = null;
                              _physicsStalled = false;
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
                  child: BouncyButton(
                    onTap: _isAnimating
                        ? null
                        : () {
                            setState(() {
                              _editingPlayerIndex = isEditing ? null : index;
                              _result = null;
                              _physicsStalled = false;
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
                      child: BouncyButton(
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
              isAnimating: _isAnimating,
              showResult: _result != null,
              showFailure: _physicsStalled,
              onComplete: (winner) {
                if (!mounted) return;
                setState(() {
                  _result = winner + 1;
                  _physicsStalled = false;
                  _isAnimating = false;
                });
              },
              onStalled: () {
                if (!mounted) return;
                setState(() {
                  _result = null;
                  _physicsStalled = true;
                  _isAnimating = false;
                });
              },
            ),

            const SizedBox(height: 32),

            // Spin button & Result. Sabit yükseklik: sonuç durumu (kutu +
            // "Tekrar Çek") en uzun içeriktir; bölge her durumda onun
            // boyunda kalır ki kart, durumlar arasında büyüyüp görsel kayma
            // yaratmasın.
            SizedBox(
              height: MediaQuery.textScalerOf(context).scale(28) > 28
                  ? 142 + MediaQuery.textScalerOf(context).scale(48)
                  : 142,
              child: Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: ((_result != null || _physicsStalled) && !_isAnimating)
                      ? Align(
                          key: ValueKey(
                            _physicsStalled
                                ? 'who_pays_physics_stalled'
                                : 'who_pays_result_$_result',
                          ),
                          alignment: Alignment.bottomCenter,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 32,
                                  vertical: 16,
                                ),
                                key: const ValueKey('who_pays_winner_message'),
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
                                child: _physicsStalled
                                    ? Text(
                                        tr(
                                          'Top deliğe ulaşamadı. Lütfen tekrar deneyin.',
                                          'The balls did not reach the opening. Please try again.',
                                        ),
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.w800,
                                          color: _gold,
                                        ),
                                      )
                                    : Text(
                                        tr(
                                          'Hesap $_result. kişide! 🎉',
                                          'Person $_result pays the bill! 🎉',
                                        ),
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 28,
                                          fontWeight: FontWeight.w900,
                                          color: _playerColors[_result! - 1],
                                        ),
                                      ),
                              ),
                              const SizedBox(height: 8),
                              _buildHesapKimdeActionButton(
                                keyName: 'who_pays_redraw_button',
                                label: tr('Tekrar Çek', 'Draw Again'),
                                semanticLabel: tr(
                                  'Yeni bir sonuç çek',
                                  'Draw again',
                                ),
                                onTap: _spin,
                                backgroundColor: _mint,
                                foregroundColor: _bgDark,
                                borderColor: _mint,
                                emphasize: true,
                              ),
                            ],
                          ),
                        )
                      : Semantics(
                          key: const ValueKey('spin_btn'),
                          button: true,
                          enabled: !_isAnimating,
                          label: tr(
                            'Topları karıştır ve sonucu seç',
                            'Mix balls and draw',
                          ),
                          child: BouncyButton(
                            onTap: _isAnimating ? null : _spin,
                            child: Container(
                              width: double.infinity,
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
                                textAlign: TextAlign.center,
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
              ),
            ),
            const SizedBox(height: 8),

            // Close button
            _buildHesapKimdeActionButton(
              keyName: 'who_pays_close_button',
              label: tr('Kapat', 'Close'),
              semanticLabel: tr('Hesap Kimde ekranını kapat', 'Close Who Pays'),
              onTap: () => Navigator.of(context).pop(),
              backgroundColor: _bgDark,
              foregroundColor: _mutedText,
              borderColor: Colors.white.withValues(alpha: 0.16),
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
  final bool isAnimating;
  final bool showResult;
  final bool showFailure;

  /// Çekiliş bittiğinde fiziğin ağızdan düşürdüğü topun endeksiyle çağrılır.
  final ValueChanged<int> onComplete;
  final VoidCallback onStalled;

  const _LotteryMachine({
    required this.personCount,
    required this.playerColors,
    required this.isAnimating,
    required this.showResult,
    required this.showFailure,
    required this.onComplete,
    required this.onStalled,
  });

  @override
  State<_LotteryMachine> createState() => _LotteryMachineState();
}

class _LotteryMachineState extends State<_LotteryMachine>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final Ticker _ticker;
  final ValueNotifier<int> _controller = ValueNotifier<int>(0);
  late WhoPaysLotterySimulation _simulation;
  final _spinSound = _SpinTickSound();
  final _seedRandom = Random();
  DateTime? _lastImpactSoundAt;
  Duration? _lastElapsed;
  double _drawElapsed = 0;
  bool _reduceMotion = false;
  bool _completed = false;
  bool _running = false;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _simulation = _createSimulation(seed: widget.personCount * 997);
    _ticker = createTicker(_handleTick);
  }

  WhoPaysLotterySimulation _createSimulation({required int seed}) =>
      WhoPaysLotterySimulation(personCount: widget.personCount, seed: seed);

  void _handleTick(Duration elapsed) {
    final previous = _lastElapsed;
    _lastElapsed = elapsed;
    if (!_running || !_foreground || previous == null) return;
    // Discard suspended wall time; never fast-forward the draw on resume.
    final dt = min(
      (elapsed - previous).inMicroseconds / 1000000,
      WhoPaysLotterySimulation.fixedStepSeconds *
          WhoPaysLotterySimulation.maxStepsPerFrame,
    );
    _drawElapsed += dt;
    if (_reduceMotion) {
      _simulation.advanceReducedMotion((_drawElapsed / 0.18).clamp(0.0, 1.0));
    } else {
      final report = _simulation.advanceTo(_drawElapsed);
      if (!_completed && report.maxImpactSpeed >= 90) {
        final now = DateTime.now();
        if (_lastImpactSoundAt == null ||
            now.difference(_lastImpactSoundAt!) >=
                const Duration(milliseconds: 60)) {
          _lastImpactSoundAt = now;
          _spinSound.playTick();
        }
      }
    }
    _controller.value++;
    if (!_completed && _simulation.isPhysicallySeated) {
      _completed = true;
      _spinSound.playResult();
      final captured = _simulation.capturedBallIndex;
      assert(captured != null);
      if (captured != null) widget.onComplete(captured);
    } else if (!_completed && _simulation.isStalled) {
      _completed = true;
      widget.onStalled();
    }
    if (_completed && (_reduceMotion || _simulation.isSleeping)) _ticker.stop();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _lastElapsed = null;
    if (!_foreground) {
      _ticker.stop();
    } else if (_running &&
        !(_completed && (_reduceMotion || _simulation.isSleeping)) &&
        !_ticker.isActive) {
      _ticker.start();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Apply accessibility changes between draws, never swap physics mid-flight.
    if (!_running) _reduceMotion = MediaQuery.disableAnimationsOf(context);
  }

  @override
  void didUpdateWidget(covariant _LotteryMachine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isAnimating && !oldWidget.isAnimating) {
      _lastImpactSoundAt = null;
      final previous = _simulation;
      _simulation = WhoPaysLotterySimulation(
        personCount: widget.personCount,
        seed: _seedRandom.nextInt(0x7fffffff),
        initialState:
            previous.personCount == widget.personCount &&
                previous.phase == WhoPaysLotteryPhase.seated
            ? previous.exportState()
            : null,
      );
      _reduceMotion = MediaQuery.disableAnimationsOf(context);
      _drawElapsed = 0;
      _lastElapsed = null;
      _completed = false;
      _running = true;
      if (_foreground && !_ticker.isActive) _ticker.start();
    } else if ((!widget.showResult &&
            !widget.showFailure &&
            (oldWidget.showResult || oldWidget.showFailure)) ||
        widget.personCount != oldWidget.personCount) {
      _ticker.stop();
      _running = false;
      _lastElapsed = null;
      _simulation = _createSimulation(seed: widget.personCount * 997);
      _controller.value++;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final seatedWinner = _simulation.isPhysicallySeated
        ? _simulation.capturedBallIndex
        : null;
    return Semantics(
      liveRegion:
          (widget.showResult && seatedWinner != null) || widget.showFailure,
      label: widget.showFailure
          ? tr(
              'Toplar deliğe ulaşamadı. Tekrar deneyin.',
              'The balls did not reach the opening. Try again.',
            )
          : widget.showResult && seatedWinner != null
          ? tr(
              'Kazanan top çıkışta: ${seatedWinner + 1}. kişi',
              'Winning ball in chute: person ${seatedWinner + 1}',
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
