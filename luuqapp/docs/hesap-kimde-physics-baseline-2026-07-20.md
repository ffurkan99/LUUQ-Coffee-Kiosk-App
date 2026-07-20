# Hesap Kimde fizik baseline — 20 Temmuz 2026

Bu belge, fanus fiziği iyileştirmesinden **önceki** Hesap Kimde uygulamasının geri dönüş kaydıdır. Repo kökünde Git geçmişi bulunmadığından aşağıdaki kod blokları geri kopyalanabilir kaynak kabul edilir.

## Baseline doğrulaması

- `flutter analyze`: başarılı — `No issues found`
- `flutter test`: başarılı — `82 test`
- Canlı API, gerçek installer veya fiziksel kiosk cihazı kullanılmadı.
- `lib/main.dart` SHA-256: `1b7b993a1975957990348e37ed3df7be0e7f70e3be5b1b7ada6e85e59b21122f`
- Aşağıdaki Hesap Kimde kod bloğunun LF-normalize SHA-256 değeri: `130d2a9b0acb63ea2d15815ecb5627833082368b6396fefcfcfc263b9836f232`
- `test/widget_test.dart` SHA-256: `77f8e25f8ceb3c3e66748565ee7afcb01fca6bc761c09d9ef8c6ec45b3164440`

## Mevcut davranış ve sabitler

| Alan | Baseline |
| --- | --- |
| Dialog | 480 px genişlik, 40 px padding, 40 px radius |
| Makine alanı | 400 × 400 px |
| Fanus | 135 px çizim yarıçapı, 128 px fizik yarıçapı |
| Top | 21 px yarıçap |
| Toplam animasyon | 4000 ms |
| Karıştırma | İlk %75 / 3000 ms |
| Reduced motion | 180 ms; doğrudan sonuç fazı |
| Yerçekimi | 520 |
| Swirl | 260 ± 60 |
| Alt üfleme | En fazla yaklaşık 1250 |
| Maksimum hız | 750 |
| Top restitution | 0.85 |
| Cam restitution | 0.75 |
| Sonuç hareketi | `Curves.easeOut` ve `Curves.bounceOut` |
| Kazanan seçimi | `Random.nextInt(personCount)` |

## Geri yükleme

1. `lib/main.dart` içindeki `const List<Color> _billPalette` satırından `class _MenuItem` satırının hemen önüne kadar olan bölümü aşağıdaki baseline koduyla değiştir.
2. `test/widget_test.dart` dosyasını aşağıdaki baseline test içeriğiyle değiştir.
3. Yeni sistemden geri dönülüyorsa şu ekleri kaldır:
   - `lib/src/who_pays/lottery_simulation.dart`
   - `test/who_pays_lottery_simulation_test.dart`
   - Hesap Kimde için eklenen golden dosyaları
4. `dart format lib/main.dart test/widget_test.dart`, `flutter analyze` ve `flutter test` çalıştır.
5. Hesap Kimde dialogunda 2 ve 6 oyuncuyla çekiliş yap; sonuç topunun çıkışta kaldığını doğrula.

## Baseline Hesap Kimde kaynak kodu

<!-- BASELINE_MAIN_START -->
```dart
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

class PhysicsBall {
  Offset position;
  Offset velocity;
  final double radius = 21.0;

  PhysicsBall({required this.position, required this.velocity});
}

class _LotteryMachineState extends State<_LotteryMachine>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final _spinSound = _SpinTickSound();

  // Mutable physics simulation state
  final List<PhysicsBall> _balls = [];
  double _lastSimTime = 0.0;
  bool _reduceMotion = false;

  // Handoff capture
  final List<Offset> _handoffPositions = [];
  bool _handoffCaptured = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4000),
    );

    _controller.addListener(() {
      if (!mounted) return;

      final t = _reduceMotion
          ? 0.75 + (_controller.value * 0.25)
          : _controller.value;
      if (widget.isAnimating) {
        if (t < 0.75) {
          // Physics Mixing Phase
          double targetTime =
              t * 4.0; // scale controller from 0.0 - 0.75 to 0.0 - 3.0 seconds
          if (targetTime > 3.0) targetTime = 3.0;

          const double dt = 0.016; // 16ms time steps
          while (_lastSimTime + dt <= targetTime) {
            _updatePhysicsStep(dt, _lastSimTime);
            _lastSimTime += dt;
          }
          setState(() {});
        } else {
          // Settle and Drop Phase
          if (!_handoffCaptured) {
            _handoffPositions.clear();
            for (final ball in _balls) {
              _handoffPositions.add(ball.position);
            }
            _handoffCaptured = true;
          }
          setState(() {});
        }
      }
    });

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        _spinSound.playResult();
        widget.onComplete();
      }
    });

    _initPhysics();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion == reduceMotion) return;
    _reduceMotion = reduceMotion;
    _controller.duration = Duration(milliseconds: reduceMotion ? 180 : 4000);
  }

  void _initPhysics() {
    _balls.clear();
    _handoffPositions.clear();
    _handoffCaptured = false;
    _lastSimTime = 0.0;

    final random = Random();
    const double ballRadius = 21.0;
    const double minDist =
        2 * ballRadius +
        6.0; // 48.0 pixels spacing to ensure absolutely no overlaps

    for (int i = 0; i < widget.personCount; i++) {
      Offset pos = Offset.zero;
      bool found = false;

      // Try up to 200 times to find a non-overlapping spot
      for (int attempt = 0; attempt < 200; attempt++) {
        // Generate random position within a safe inner radius of 85.0 to keep well inside the 135.0 radius chamber
        final double angle = random.nextDouble() * 2 * pi;
        final double r = random.nextDouble() * 85.0;
        final double rx = r * cos(angle);
        final double ry = r * sin(angle);
        final candidate = Offset(rx, ry);

        // Check distance to all existing balls
        bool overlap = false;
        for (final other in _balls) {
          if ((candidate - other.position).distance < minDist) {
            overlap = true;
            break;
          }
        }

        if (!overlap) {
          pos = candidate;
          found = true;
          break;
        }
      }

      // Safe fallback in case random search fails (extremely rare for <= 6 balls)
      if (!found) {
        final double angle = i * (2 * pi / widget.personCount);
        final double rx = 50.0 * cos(angle);
        final double ry = 50.0 * sin(angle);
        pos = Offset(rx, ry);
      }

      _balls.add(PhysicsBall(position: pos, velocity: Offset.zero));
    }
  }

  void _updatePhysicsStep(double dt, double simTime) {
    const double cageRadius =
        128.0; // Reduced to keep balls completely inside the neon border with buffer
    const double ballRadius = 21.0;
    const double maxR = cageRadius - ballRadius; // 107.0
    final cageCenter =
        Offset.zero; // Aligned perfectly concentric with visual sphere center

    // 1. Apply Forces (Gravity + Dynamic Swirl Vortex + Turbulent Air Blower)
    for (int i = 0; i < _balls.length; i++) {
      final ball = _balls[i];
      // Base gravity pulling down
      Offset force = const Offset(0, 520);

      // Dynamic Central Swirl Vortex
      final toCenter = ball.position - cageCenter;
      final distToCenter = toCenter.distance;
      if (distToCenter > 5.0) {
        final swirlDir = Offset(
          -toCenter.dy / distToCenter,
          toCenter.dx / distToCenter,
        );
        final dynamicSwirl = 260.0 + sin(simTime * 5.0) * 60.0;
        force += swirlDir * dynamicSwirl;
      }

      // Dynamic chaotic turbulent upward air blower with horizontal oscillation
      if (ball.position.dy > -20) {
        final double factor = (ball.position.dy + 40) / 150.0;
        final double noise = 1.0 + sin(simTime * 13.0 + i * 3.1) * 0.6;
        force += Offset(
          sin(simTime * 8.0 + i) * 150.0, // Horizontal sweeping turbulence
          -1250 * factor.clamp(0.0, 1.2) * noise, // Upward blower thrust
        );
      }

      ball.velocity += force * dt;

      // Impose terminal speed limit for numerical physics stability
      final double speed = ball.velocity.distance;
      if (speed > 750.0) {
        ball.velocity = (ball.velocity / speed) * 750.0;
      }
    }

    // 2. Update Positions
    for (final ball in _balls) {
      ball.position += ball.velocity * dt;
    }

    // 3. Resolve Ball-on-Ball Elastic Collisions (Impulse Model)
    for (int i = 0; i < _balls.length; i++) {
      for (int j = i + 1; j < _balls.length; j++) {
        final b1 = _balls[i];
        final b2 = _balls[j];
        final delta = b2.position - b1.position;
        final dist = delta.distance;
        final minDist = 2 * ballRadius;
        if (dist < minDist) {
          final overlap = minDist - dist;
          final normal = dist > 0.1 ? delta / dist : const Offset(1, 0);

          // Push apart to resolve overlay
          b1.position -= normal * (overlap * 0.5);
          b2.position += normal * (overlap * 0.5);

          // Swap relative velocities along normal vector
          final relVel = b2.velocity - b1.velocity;
          final velAlongNormal = relVel.dx * normal.dx + relVel.dy * normal.dy;

          if (velAlongNormal < 0) {
            final double e = 0.85; // high restitution for bouncy balls
            final impulseScalar = -(1.0 + e) * velAlongNormal / 2.0;
            final impulse = normal * impulseScalar;
            b1.velocity -= impulse;
            b2.velocity += impulse;

            // Cooldown-protected realistic sound trigger
            if (velAlongNormal < -30.0) {
              _spinSound.playTick();
            }
          }
        }
      }
    }

    // 4. Resolve Ball-vs-Wall Boundary Collisions
    for (final ball in _balls) {
      final toCenter = ball.position - cageCenter;
      final dist = toCenter.distance;
      if (dist > maxR) {
        final normal = toCenter / dist;
        ball.position = cageCenter + normal * maxR;

        final velAlongNormal =
            ball.velocity.dx * normal.dx + ball.velocity.dy * normal.dy;
        if (velAlongNormal > 0) {
          final double e = 0.75;
          ball.velocity -= normal * ((1.0 + e) * velAlongNormal);

          if (velAlongNormal > 30.0) {
            _spinSound.playTick();
          }
        }
      }
    }
  }

  @override
  void didUpdateWidget(covariant _LotteryMachine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isAnimating && !oldWidget.isAnimating) {
      _initPhysics();
      _controller.forward(from: 0);
    } else if (!widget.showResult && oldWidget.showResult) {
      _controller.reset();
      _initPhysics();
    } else if (widget.personCount != oldWidget.personCount) {
      _controller.reset();
      _initPhysics();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _lerp(double a, double b, double t) => a + (b - a) * t;

  @override
  Widget build(BuildContext context) {
    final t = _reduceMotion
        ? 0.75 + (_controller.value * 0.25)
        : _controller.value;
    final List<Offset> ballPositions = [];

    // Calculate dynamic stirrer rotation angle
    final double rotorAngle;
    if (_reduceMotion) {
      rotorAngle = 0;
    } else if (t < 0.75) {
      rotorAngle = t * 16 * pi; // spins 6 times during mixing
    } else {
      // Gracefully decelerate stirrer to a halt
      final double tDrop = (t - 0.75) / 0.25;
      rotorAngle = 12 * pi + (1.0 - (1.0 - tDrop) * (1.0 - tDrop)) * 2 * pi;
    }

    for (int i = 0; i < widget.personCount; i++) {
      double bx = 0;
      double by = 0;

      if (t < 0.75) {
        // Render exact current coordinates computed by real-time physics engine
        if (i < _balls.length) {
          bx = _balls[i].position.dx;
          by = _balls[i].position.dy;
        }
      } else {
        // Settle & Drop phase: interpolate smoothly using handoff coordinate
        final double tDrop = (t - 0.75) / 0.25;
        final double mixX = _handoffPositions.length > i
            ? _handoffPositions[i].dx
            : 0.0;
        final double mixY = _handoffPositions.length > i
            ? _handoffPositions[i].dy
            : 30.0;

        if (i == widget.winnerIndex) {
          // Winning ball slides down funnel with easeOut, and falls straight into U-slot at (0, 205) with bounceOut
          if (tDrop <= 0.4) {
            final double subT = tDrop / 0.4;
            bx = _lerp(mixX, 0.0, Curves.easeOut.transform(subT));
            by = _lerp(mixY, 80.0, Curves.easeOut.transform(subT));
          } else {
            final double subT = (tDrop - 0.4) / 0.6;
            bx = 0.0;
            by = _lerp(80.0, 205.0, Curves.bounceOut.transform(subT));
          }
        } else {
          // Losing balls slide smoothly into corners along sloped shoulders using easeOut
          final int idx = i < widget.winnerIndex ? i : i - 1;

          // Place balls along the inner boundary of the circular glass cage (R - ballRadius - 7px clearance)
          const double maxR = 135.0 - 21.0 - 7.0; // 107.0 px
          final double rx;
          final double ry;

          if (idx % 2 == 0) {
            // Left shoulder arc stack
            final double angle = 1.95 + (idx ~/ 2) * 0.32;
            rx = maxR * cos(angle);
            ry = maxR * sin(angle);
          } else {
            // Right shoulder arc stack
            final double angle = 1.19 - (idx ~/ 2) * 0.32;
            rx = maxR * cos(angle);
            ry = maxR * sin(angle);
          }
          bx = _lerp(mixX, rx, Curves.easeOut.transform(tDrop));
          by = _lerp(mixY, ry, Curves.easeOut.transform(tDrop));
        }
      }
      ballPositions.add(Offset(bx, by));
    }

    return Semantics(
      liveRegion: widget.showResult && t >= 0.999,
      label: widget.showResult && t >= 0.999
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
      child: SizedBox(
        width: 400,
        height: 400,
        child: CustomPaint(
          key: const ValueKey('who_pays_machine'),
          painter: _LotteryMachinePainter(
            personCount: widget.personCount,
            playerColors: widget.playerColors,
            ballPositions: ballPositions,
            rotorAngle: rotorAngle,
          ),
        ),
      ),
    );
  }
}

class _LotteryMachinePainter extends CustomPainter {
  final int personCount;
  final List<Color> playerColors;
  final List<Offset> ballPositions;
  final double rotorAngle;

  _LotteryMachinePainter({
    required this.personCount,
    required this.playerColors,
    required this.ballPositions,
    required this.rotorAngle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, 145);
    final double R = 135.0; // Enlarged sphere radius

    // Build a unified, beautifully symmetrical glass cage path extending straight down to a rounded bottom cap
    final path = Path();
    final double tubeHalfWidth = 25.0; // Half of 50.0 tube width
    final double thetaRight = acos(tubeHalfWidth / R);
    final double thetaLeft = pi - thetaRight;
    final double sweepAngle = pi + 2 * thetaRight;

    // Start at the left shoulder (where the circle meets the left tube wall)
    final double startX = center.dx - tubeHalfWidth;
    final double startY = center.dy + R * sin(thetaLeft);

    path.moveTo(startX, startY);

    // Large circle arch going clockwise from left shoulder to right shoulder
    path.arcTo(
      Rect.fromCircle(center: center, radius: R),
      thetaLeft,
      sweepAngle,
      false,
    );

    // Right vertical tube wall
    path.lineTo(center.dx + tubeHalfWidth, center.dy + 205.0);

    // Closed rounded bottom cap arc (perfectly U-shaped)
    path.arcTo(
      Rect.fromCircle(
        center: Offset(center.dx, center.dy + 205.0),
        radius: tubeHalfWidth,
      ),
      0,
      pi,
      false,
    );

    // Left vertical tube wall back up to left shoulder
    path.lineTo(startX, startY);
    path.close();

    // Fill glass cage with glassmorphic semi-transparent radial gradient
    final glassGradient = RadialGradient(
      colors: [
        Colors.white.withValues(alpha: 0.02),
        Colors.white.withValues(alpha: 0.08),
        Colors.white.withValues(alpha: 0.16),
      ],
      stops: const [0.0, 0.7, 1.0],
    );

    canvas.drawPath(
      path,
      Paint()
        ..shader = glassGradient.createShader(
          Rect.fromCircle(center: center, radius: R),
        )
        ..style = PaintingStyle.fill,
    );

    // Draw the neon border of the cage (mint green theme)
    final neonPaint = Paint()
      ..color = _mint.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    // Draw inner glow/shadow of border
    canvas.drawPath(
      path,
      Paint()
        ..color = _mint.withValues(alpha: 0.15)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawPath(path, neonPaint);

    // Draw glass highlight/reflection on top left
    canvas.drawArc(
      Rect.fromCircle(
        center: Offset(center.dx - 8, center.dy - 8),
        radius: R - 8,
      ),
      -pi * 0.75,
      pi * 0.4,
      false,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.15)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );

    // Draw the center stirrer/rotor (behind the balls but inside glass cage)
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotorAngle);

    final stirrerPaint = Paint()
      ..color = _gold.withValues(alpha: 0.20)
      ..style = PaintingStyle.fill;

    for (int j = 0; j < 3; j++) {
      final double angleOffset = j * 2.0 * pi / 3.0;
      final pProp = Path();
      pProp.moveTo(0, 0);
      pProp.cubicTo(
        20 * cos(angleOffset + 0.35),
        20 * sin(angleOffset + 0.35),
        55 * cos(angleOffset + 0.65),
        55 * sin(angleOffset + 0.65),
        85 * cos(angleOffset + 0.4),
        85 * sin(angleOffset + 0.4),
      );
      pProp.cubicTo(
        55 * cos(angleOffset + 0.1),
        55 * sin(angleOffset + 0.1),
        20 * cos(angleOffset - 0.1),
        20 * sin(angleOffset - 0.1),
        0,
        0,
      );
      canvas.drawPath(pProp, stirrerPaint);

      final highlightPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.12)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawPath(pProp, highlightPaint);
    }

    // Central brass spindle cap
    final capGradient = RadialGradient(
      colors: [_cream, _gold, _caramel],
      stops: const [0.0, 0.65, 1.0],
      center: const Alignment(-0.3, -0.3),
    );
    canvas.drawCircle(
      Offset.zero,
      15.0,
      Paint()
        ..shader = capGradient.createShader(
          Rect.fromCircle(center: Offset.zero, radius: 15.0),
        )
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      Offset.zero,
      15.0,
      Paint()
        ..color = _bgDark.withValues(alpha: 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );

    canvas.restore();

    // Draw the balls
    const double ballRadius = 21.0;

    for (int i = 0; i < ballPositions.length; i++) {
      final ballPos = ballPositions[i];
      final absolutePos = Offset(
        center.dx + ballPos.dx,
        center.dy + ballPos.dy,
      );
      final color = playerColors[i];

      // Premium 3D sphere gradient
      final ballGradient = RadialGradient(
        colors: [
          Color.lerp(color, Colors.white, 0.4)!,
          color,
          Color.lerp(color, Colors.black, 0.3)!,
        ],
        center: const Alignment(-0.35, -0.35),
        radius: 0.9,
      );

      // Ball shadow
      canvas.drawCircle(
        absolutePos + const Offset(2.5, 2.5),
        ballRadius,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.4)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.5),
      );

      // Ball body
      canvas.drawCircle(
        absolutePos,
        ballRadius,
        Paint()
          ..shader = ballGradient.createShader(
            Rect.fromCircle(center: absolutePos, radius: ballRadius),
          ),
      );

      // Highlight sheen
      canvas.drawCircle(
        absolutePos,
        ballRadius,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.05)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );

      // Draw the player number inside the ball
      final textSpan = TextSpan(
        text: '${i + 1}',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w900,
          shadows: [
            Shadow(
              color: Color(0xCC000000),
              blurRadius: 3,
              offset: Offset(0, 1),
            ),
          ],
        ),
      );

      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        absolutePos - Offset(textPainter.width / 2, textPainter.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LotteryMachinePainter oldDelegate) {
    return oldDelegate.ballPositions != ballPositions ||
        oldDelegate.playerColors != playerColors ||
        oldDelegate.rotorAngle != rotorAngle;
  }
}

// ===== MENÜ DIALOG (Veri Tabanlı) =====
```
<!-- BASELINE_MAIN_END -->

## Baseline widget test dosyası

<!-- BASELINE_TEST_START -->
```dart
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:luuqapp/main.dart';
import 'package:luuqapp/licensing/feature_flags.dart';
import 'package:luuqapp/licensing/license_gate.dart';
import 'package:luuqapp/licensing/license_service.dart';
import 'package:luuqapp/licensing/license_status.dart';

void main() {
  tearDown(() {
    final binding = TestWidgetsFlutterBinding.instance;
    binding.platformDispatcher.views.single.resetPhysicalSize();
    binding.platformDispatcher.views.single.resetDevicePixelRatio();
  });

  testWidgets('builds the application and shows license gate', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const LuuqApp());

    expect(find.byType(LuuqApp), findsOneWidget);
    expect(find.byType(LicenseGate), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('builds the kiosk screen directly', (WidgetTester tester) async {
    await _pumpKioskAtSize(tester, const Size(1920, 1080));
    expect(find.byType(CafeKioskScreen), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('lays out on phone and kiosk screens', (
    WidgetTester tester,
  ) async {
    await _pumpKioskAtSize(tester, const Size(390, 844));
    expect(tester.takeException(), isNull);

    await _pumpKioskAtSize(tester, const Size(1920, 1080));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('who pays draw keeps a visible winning ball and result', (
    WidgetTester tester,
  ) async {
    appLanguageNotifier.value = AppLanguage.tr;
    LicenseService.instance.statusNotifier.value = const LicenseStatus(
      active: true,
      mode: LicenseMode.licensed,
      features: FeatureFlags.proDefault,
    );

    await _pumpKioskAtSize(tester, const Size(1920, 1080));
    for (
      var i = 0;
      i < 60 && find.text('Mini Çarkı Aç').evaluate().isEmpty;
      i++
    ) {
      await tester.tapAt(const Offset(960, 540));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
    expect(find.text('Mini Çarkı Aç'), findsOneWidget);
    await tester.tap(find.text('Mini Çarkı Aç'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('KARIŞTIR & ÇEK!'), findsOneWidget);
    await tester.tapAt(const Offset(8, 8));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('KARIŞTIR & ÇEK!'), findsOneWidget);

    await tester.tap(find.text('KARIŞTIR & ÇEK!'));
    await tester.pump();
    expect(find.text('KARILIYOR...'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 4100));
    await tester.pump();

    expect(
      find.textContaining(RegExp(r'^Hesap [1-6]\. kişide! 🎉$')),
      findsOneWidget,
    );
    expect(find.text('Tekrar Çek'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp(r'Kazanan top çıkışta: [1-6]\. kişi')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    LicenseService.instance.statusNotifier.value = const LicenseStatus(
      active: false,
      mode: LicenseMode.none,
      features: FeatureFlags.lockedAll,
    );
  });
}

Future<void> _pumpKioskAtSize(WidgetTester tester, Size size) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;

  // Replicate LuuqApp's MaterialApp themes/builders for CafeKioskScreen
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
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
        scaffoldBackgroundColor: const Color(0xFF16131D),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFD88E2B),
          brightness: Brightness.dark,
          surface: const Color(0xFF231E2D),
        ),
        textTheme: ThemeData.dark().textTheme.apply(
          bodyColor: const Color(0xFFFFF7EC),
          displayColor: const Color(0xFFFFF7EC),
          fontFamily: 'Roboto',
        ),
      ),
      home: const CafeKioskScreen(),
    ),
  );
  await tester.pump(const Duration(milliseconds: 350));
}
```
<!-- BASELINE_TEST_END -->

