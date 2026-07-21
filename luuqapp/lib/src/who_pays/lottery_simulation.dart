import 'dart:math';
import 'dart:ui';

enum WhoPaysLotteryPhase {
  idle,
  intake,
  spinUp,
  mixing,
  settling,
  capture,
  dropping,
  seated,
}

class WhoPaysBallState {
  WhoPaysBallState({required this.position, this.velocity = Offset.zero});

  Offset position;
  Offset velocity;
}

class WhoPaysStepReport {
  const WhoPaysStepReport({
    required this.physicsSteps,
    required this.droppedCatchUp,
    required this.maxImpactSpeed,
  });

  final int physicsSteps;
  final bool droppedCatchUp;
  final double maxImpactSpeed;
}

/// Package-internal simulation for the Hesap Kimde lottery machine.
///
/// Physics-first: the winner is NOT supplied by the caller. When the gate
/// opens, whichever ball genuinely falls through the mouth becomes
/// [capturedBallIndex]; the UI reads the result from the simulation. No
/// index-conditioned force may run before capture assignment
/// ([targetedForceApplications] proves it).
class WhoPaysLotterySimulation {
  WhoPaysLotterySimulation({
    required this.personCount,
    required this.seed,
    WhoPaysInitialState? initialState,
    @Deprecated('Physics decides the winner; this argument is ignored.')
    int? winnerIndex,
  }) : assert(personCount >= 2 && personCount <= 6),
       assert(
         initialState == null ||
             initialState.chamberPositions.length == personCount,
       ),
       _random = Random(seed),
       _initialState = initialState,
       _intakeBallIndex = initialState?.seatedBallIndex,
       _phaseShift = initialState?.seatedBallIndex != null
           ? intakeDurationSeconds
           : 0 {
    if (initialState != null) {
      for (var index = 0; index < personCount; index++) {
        final position = index == initialState.seatedBallIndex
            ? const Offset(0, winnerSeatY)
            : initialState.chamberPositions[index];
        balls.add(WhoPaysBallState(position: position));
      }
      _reducedMotionStartPositions.addAll(balls.map((ball) => ball.position));
    } else {
      _initializeBalls();
    }
    _updatePresentation();
  }

  // Draw-relative timeline offsets. _phaseShift carries the intake prologue
  // for continue-starts (intakeDurationSeconds when seeded from a previous
  // draw's exportState, 0 for a fresh draw).
  static const double _spinUpEnd = 0.18;
  static const double _mixingEnd = 2.05;
  static const double _settlingEnd = 2.55;
  static const double _captureEnd = 3.00;
  static const double _droppingEnd = 3.32;
  static const double _idleDuration = 3.40;
  static const double _gateOpenLength = 0.15;
  // Kapanış kazanan-farkındalıklıdır: en erken _gateCloseStart'ta VE kazanan
  // çubuğun süpürme bandını (dy < gateSweepClearY) geçtikten sonra başlar —
  // kapak, tüpten inen topun üstünden kapanamaz.
  static const double _gateCloseStart = 3.10;
  static const double _gateCloseLength = 0.14;
  static const double gateSweepClearY = 158.0;
  // Son-çare penceresi: fizik son 100 ms'ye dek hiçbir topu ağızdan
  // düşürememişse, ağza O ANDA en yakın top atanır ve düz yayla alınır —
  // kural yine "en yakın kazanır", endeks önseli yoktur.
  static const double _guaranteeWindow = 0.10;

  /// Çökme fazında yerçekimi çarpanı — kapak açılmadan topların tabana
  /// inmesine yardım eder (tüm toplara eşit uygulanır).
  static const double settleAssistGravityFactor = 1.3;

  static const int idleDurationMilliseconds = 3400;

  static const double intakeDurationSeconds = 0.45;
  static const int redrawDurationMilliseconds = 3850;
  static const double _intakeSuction = 3400.0;
  static const double _intakePullStart = 0.06;
  static const double _intakeGateOpenEnd = 0.12;
  static const double _intakeGateCloseStart = 0.34;
  static const double _intakeReleaseY = 95.0;

  static const double fixedStepSeconds = 1 / 120;
  static const int maxStepsPerFrame = 8;
  static const double ballRadius = 21.0;
  static const double cageRadius = 128.0;
  static const double maxBallCenterRadius = cageRadius - ballRadius;

  static const double gravity = 520.0;
  static const double chuteGravity = 1320.0;
  static const double maxRotorRadiansPerSecond = 6 * pi;
  static const double ballRestitution = 0.68;
  // Raised from the legacy 0.58: with maxBallSpeed and mixingDragRate held
  // at their spec-pinned values, balls need to keep most of their energy on
  // a wall bounce so they rebound back toward the rotor instead of resting
  // pinned against the glass.
  static const double wallRestitution = 0.93;
  static const double bladeRestitution = 0.46;
  static const double bladeFriction = 0.15;
  // Spec-pinned: must stay 760.0.
  static const double maxBallSpeed = 760.0;
  // Raised from the legacy 3 iterations so deep multi-ball contacts (common
  // once the winner is no longer staged out of the mix) fully separate
  // within one physics step instead of leaving residual overlap.
  static const int collisionPasses = 8;

  // Spec-pinned: must stay 0.22 ("mixing'de 0.22 kalır").
  static const double mixingDragRate = 0.22;
  static const double settleDragRate = 2.0;
  static const double tubeDragRate = 0.20;
  // Drag on the captured ball while it is still in the chamber (last-resort
  // transit only). Lower than settleDragRate so the guarantee spring isn't
  // fighting heavy viscous damping. Losers keep settleDragRate.
  static const double capturedTransitDragRate = 0.6;

  // Tube mouth reference point and the last-resort guarantee spring.
  static const Offset mouthTarget = Offset(0, 126);
  static const double suctionSpringRate = 90.0;
  static const double suctionDampingRate = 2.5;
  static const double suctionGuaranteeMax = 8000.0;

  /// Nötr drenaj: kapak açıkken ve henüz atama yokken TÜM toplara eşit,
  /// ağza yönlü, rampalanan kuvvet. Ağzın üstü boşsa yığını ağza kaydırır —
  /// yine deliğe en yakın top düşer (endeks önseli yok).
  static const double drainRampMax = 900.0;

  /// Ağzın top kabul etmesi için gereken kapak açıklığı. Tam açılmaya yakın
  /// eşik: top, kapak neredeyse tamamen açılmadan deliğe giremez.
  static const double gateOpenForCapture = 0.85;

  // Outward air cushion that clears losers away from the open mouth.
  static const double cushionRadius = 85.0;
  static const double cushionMax = 1400.0;

  /// Yakalama pulluğunun kaybedene aktarabileceği en yüksek hız (px/s) —
  /// üstü kırpılır ki itilen toplar duvara fırlamasın.
  static const double plowKickCap = 320.0;

  /// Karışım sonrası düşey terminal hız (px/s). Fanus yüksekliğinden serbest
  /// düşüş ~494 px/s üretir; üstü "roket düşüş" gibi okunur.
  static const double postMixTerminalFallSpeed = 560.0;

  /// Kazananın yakalama/iniş boyunca sinematik hız tavanı (px/s).
  static const double winnerCaptureMaxSpeed = 540.0;

  /// Yuvadan önce ağır sönümleme uygulanan bant (px) ve sönümleme oranı —
  /// yumuşak konma için.
  static const double seatCushionZone = 36.0;
  static const double seatCushionDragRate = 11.0;

  /// Ağız keepout bölgesi: yakalama ATANDIKTAN sonra, kapak anlamlı açıkken
  /// (ikinci top sızmasın diye) yakalanan dışındaki toplar bu banttan
  /// geometrik tahliyeyle yana süpürülür. Atama öncesi bölge serbesttir —
  /// ağzın üstünde top olması artık istenen durumdur.
  static const double gateRidgeTopY = 84.0;
  static const double mouthKeepoutHalfWidth = 34.0;

  /// Karışım sonrası çakışma ayrıştırmasının kare başına konum itmesi
  /// tavanı (px) — derin binmelerde tek karelik "zıplama" görüntüsünü
  /// birkaç kareye yayar.
  static const double postMixSeparationCap = 5.0;

  static const int rotorBladeCount = 3;
  static const double rotorHubRadius = 15.0;
  static const double rotorBladeInnerRadius = 15.0;
  static const double rotorBladeMiddleRadius = 50.0;
  static const double rotorBladeOuterRadius = 80.0;
  static const double rotorBladeInnerAngleOffset = 0.06;
  static const double rotorBladeMiddleAngleOffset = 0.27;
  static const double rotorBladeOuterAngleOffset = 0.40;
  static const double rotorBladeInnerHalfWidth = 8.0;
  static const double rotorBladeOuterHalfWidth = 6.0;

  // Vertical band where the winner leaves the chamber for the tube. The hard
  // center clamp below it is temporary and is replaced by the funnel task.
  static const double tubeEntryY = 100.0;
  static const double funnelBottomY = 133.0;
  static const double funnelTopHalfWidth = 38.0;
  static const double tubeHalfWidth = 4.0;
  static const double winnerSeatY = 209.0;

  /// Resting slot angles on the floor arc (radians, π/2 = bottom center).
  /// 0.42 rad ≈ 45 px of arc at r=107, wider than a 42 px ball, so relocated
  /// balls can never overlap each other.
  static const List<double> floorSlotAngles = <double>[
    pi / 2,
    pi / 2 + 0.42,
    pi / 2 - 0.42,
    pi / 2 + 0.84,
    pi / 2 - 0.84,
  ];

  final int personCount;
  final int seed;
  final Random _random;
  final double _phaseShift;
  final WhoPaysInitialState? _initialState;
  final int? _intakeBallIndex;
  bool _intakeReleased = false;

  // Fiziğin yakaladığı top. İki yoldan atanır: (a) doğal — kapak açıkken
  // bir topun merkezi huni bandına girdiği an; (b) son çare — garanti
  // penceresi dolduğunda ağza en yakın top. Bir kez atanınca değişmez.
  int? _capturedBallIndex;

  // Reduced-motion gölge çözümünün önbelleği (canlı fizik koşulmadığında
  // kazanan, aynı seed'li gölge kopyanın sona koşulmasıyla öğrenilir).
  int? _reducedMotionCaptured;

  /// Fiziğin ağızdan düşürdüğü topun endeksi. Canlı koşumda atama anından
  /// itibaren, reduced-motion'da gölge çözümden gelir. `phase == seated`
  /// olan bir çekilişte null olamaz.
  int? get capturedBallIndex => _capturedBallIndex ?? _reducedMotionCaptured;

  // Yakalanan top huniden tüpe bir kez girdi mi? Girince ağız temizleme
  // yastığı görevini tamamlar ve kaybedenler dondurulmadan önce tabana
  // inebilsin diye iniş yardımı devralır.
  bool _capturedReachedTube = false;

  // Kapanışın başladığı mutlak an (sn). Kazanan süpürme bandını geçince
  // (en erken _gateCloseStart'ta) atanır; zaman çizelgesi sonunda hâlâ
  // atanmadıysa son-kare garantisi kapatır.
  double? _gateCloseBeganAt;

  final List<WhoPaysBallState> balls = <WhoPaysBallState>[];
  final List<Offset> renderPositions = <Offset>[];
  final List<Offset> _reducedMotionStartPositions = <Offset>[];

  double timelineSeconds = 0;
  double rotorAngle = 0;
  double rotorSpeed = 0;
  double gateProgress = 0;
  double contentOpacity = 1;
  WhoPaysLotteryPhase phase = WhoPaysLotteryPhase.idle;

  double _accumulator = 0;
  late final List<double> _ridgeShiftBudget = List<double>.filled(
    personCount,
    0,
  );

  /// Cumulative physical blade/hub impacts. Used by focused tests and local
  /// diagnostics to prove that mixing energy comes from rotor contact.
  int bladeCollisionCount = 0;

  /// Incremented every physics step that applies an index-conditioned
  /// capture force (the captured ball's tube/transit handling). Tests assert
  /// this stays 0 while [capturedBallIndex] is null — the winner is chosen
  /// by geometry, never steered by a targeted force. (The redraw intake
  /// prologue is presentation continuity and does not count.)
  int targetedForceApplications = 0;

  double get durationSeconds => _phaseShift + _idleDuration;
  int get durationMilliseconds =>
      _phaseShift > 0 ? redrawDurationMilliseconds : idleDurationMilliseconds;
  double get spinUpEndSeconds => _phaseShift + _spinUpEnd;
  double get mixingEndSeconds => _phaseShift + _mixingEnd;
  double get settlingEndSeconds => _phaseShift + _settlingEnd;
  double get captureEndSeconds => _phaseShift + _captureEnd;
  double get droppingEndSeconds => _phaseShift + _droppingEnd;

  double get fanPower =>
      (rotorSpeed / maxRotorRadiansPerSecond).clamp(0.0, 1.0);

  /// Allowed center half-width for a ball travelling the mouth funnel. Wide at
  /// the chamber floor, narrowing linearly to the tube so per-step wall
  /// projections stay tiny and no visible teleport can occur.
  static double funnelHalfWidthAt(double dy) {
    if (dy >= funnelBottomY) return tubeHalfWidth;
    if (dy <= tubeEntryY) return funnelTopHalfWidth;
    final t = (dy - tubeEntryY) / (funnelBottomY - tubeEntryY);
    return funnelTopHalfWidth + (tubeHalfWidth - funnelTopHalfWidth) * t;
  }

  static List<Offset> bladeSpinePoints(double angle, int bladeIndex) {
    final baseAngle = angle + bladeIndex * 2 * pi / rotorBladeCount;
    return <Offset>[
      Offset.fromDirection(
        baseAngle + rotorBladeInnerAngleOffset,
        rotorBladeInnerRadius,
      ),
      Offset.fromDirection(
        baseAngle + rotorBladeMiddleAngleOffset,
        rotorBladeMiddleRadius,
      ),
      Offset.fromDirection(
        baseAngle + rotorBladeOuterAngleOffset,
        rotorBladeOuterRadius,
      ),
    ];
  }

  WhoPaysStepReport advanceTo(double targetSeconds) {
    final target = targetSeconds.clamp(0.0, durationSeconds);
    if (target <= timelineSeconds) {
      return const WhoPaysStepReport(
        physicsSteps: 0,
        droppedCatchUp: false,
        maxImpactSpeed: 0,
      );
    }

    final rawDelta = target - timelineSeconds;
    final maxFrameDelta = fixedStepSeconds * maxStepsPerFrame;
    final simulatedDelta = min(rawDelta, maxFrameDelta);
    final droppedCatchUp = rawDelta > maxFrameDelta;
    timelineSeconds = target;
    phase = _phaseFor(target);
    rotorSpeed = _rotorSpeedAt(target);
    rotorAngle = _rotorAngleAt(target);
    gateProgress = _gateProgressAt(target);
    contentOpacity = 1;

    var maxImpactSpeed = 0.0;
    var physicsSteps = 0;
    _accumulator += simulatedDelta;
    while (_accumulator + 1e-9 >= fixedStepSeconds &&
        physicsSteps < maxStepsPerFrame) {
      final stepTime = target - _accumulator + fixedStepSeconds;
      maxImpactSpeed = max(
        maxImpactSpeed,
        _stepPhysics(fixedStepSeconds, stepTime),
      );
      _accumulator -= fixedStepSeconds;
      physicsSteps++;
    }

    // Kazanan-farkındalıklı kapanış tetiği: en erken _gateCloseStart'ta VE
    // yakalanan top çubuğun süpürme bandını geçtikten sonra.
    final captured = _capturedBallIndex;
    if (_gateCloseBeganAt == null &&
        target - _phaseShift >= _gateCloseStart &&
        captured != null &&
        balls[captured].position.dy >= gateSweepClearY) {
      _gateCloseBeganAt = timelineSeconds;
    }

    // A background/resume jump is deliberately not fully simulated. If the
    // controller has already completed, guarantee a valid in-app result
    // rather than leaving the draw unresolved: the ball nearest the mouth is
    // the winner (same closest-wins rule, applied at the freeze frame).
    if (target >= durationSeconds) {
      final seatedIndex = _capturedBallIndex ??= _nearestToMouth();
      balls[seatedIndex]
        ..position = const Offset(0, winnerSeatY)
        ..velocity = Offset.zero;
      // Donma karesi kapalı kapak gösterir: kapanış hiç başlamadıysa veya
      // (geç varışta) bitmeye vakti kalmadıysa son karede tamamlanmış
      // sayılır.
      final latestCloseStart = timelineSeconds - _gateCloseLength;
      final closeBeganAt = _gateCloseBeganAt;
      if (closeBeganAt == null || closeBeganAt > latestCloseStart) {
        _gateCloseBeganAt = latestCloseStart;
      }
      if (droppedCatchUp) {
        _settleLosersToFloor();
      }
    }
    gateProgress = _gateProgressAt(target);

    _updatePresentation();
    return WhoPaysStepReport(
      physicsSteps: physicsSteps,
      droppedCatchUp: droppedCatchUp,
      maxImpactSpeed: maxImpactSpeed,
    );
  }

  /// Snapshot of the current ball layout, used to seed the next draw's
  /// continuity.
  ///
  /// Note: advanceReducedMotion never mutates [balls], so a reduced-motion
  /// draw exports its construction-time layout — which is exactly what
  /// reduced motion rendered for the losers. Keep it that way: mutating
  /// balls there would desynchronize redraw continuity.
  WhoPaysInitialState exportState() {
    return WhoPaysInitialState(
      chamberPositions: List<Offset>.unmodifiable(
        balls.map((ball) => ball.position),
      ),
      seatedBallIndex: phase == WhoPaysLotteryPhase.seated
          ? capturedBallIndex
          : null,
    );
  }

  void advanceReducedMotion(double progress) {
    final value = progress.clamp(0.0, 1.0);
    timelineSeconds = value * durationSeconds;
    rotorSpeed = 0;
    rotorAngle = 0;
    gateProgress = 0;
    phase = value >= 1
        ? WhoPaysLotteryPhase.seated
        : WhoPaysLotteryPhase.capture;
    contentOpacity = (2 * value - 1).abs().clamp(0.0, 1.0);

    renderPositions
      ..clear()
      ..addAll(
        value < 0.5
            ? _reducedMotionStartPositions
            : _reducedMotionEndPositions(),
      );
  }

  /// Reduced-motion'da kazanan, aynı seed ve başlangıç durumuyla kurulan
  /// gölge kopyanın sona kadar koşulmasıyla öğrenilir. Gölge burada
  /// güvenlidir: reduced motion fizik koşumu render etmez, ayrışabileceği
  /// bir görsel koşum yoktur. Ana örneğin [balls] listesi mutasyona uğramaz.
  int _resolveReducedMotionCaptured() {
    final live = _capturedBallIndex;
    if (live != null) return live;
    final cached = _reducedMotionCaptured;
    if (cached != null) return cached;
    final shadow = WhoPaysLotterySimulation(
      personCount: personCount,
      seed: seed,
      initialState: _initialState,
    );
    var target = 0.0;
    while (target < shadow.durationSeconds - 1e-9) {
      target = min(target + 1 / 60, shadow.durationSeconds);
      shadow.advanceTo(target);
    }
    return _reducedMotionCaptured = shadow._capturedBallIndex!;
  }

  List<Offset> _reducedMotionEndPositions() {
    final positions = List<Offset>.from(_reducedMotionStartPositions);
    final winnerIndex = _resolveReducedMotionCaptured();
    positions[winnerIndex] = const Offset(0, winnerSeatY);
    final intakeBallIndex = _intakeBallIndex;
    if (intakeBallIndex != null && intakeBallIndex != winnerIndex) {
      // Önceki kazanan fanusa döner: diğer görünen toplarla çakışmayan ilk
      // taban slotu.
      for (final angle in floorSlotAngles) {
        final candidate = Offset.fromDirection(angle, maxBallCenterRadius);
        final overlaps = positions.asMap().entries.any(
          (entry) =>
              entry.key != intakeBallIndex &&
              (entry.value - candidate).distance < ballRadius * 2,
        );
        if (!overlaps) {
          positions[intakeBallIndex] = candidate;
          break;
        }
      }
    }
    return positions;
  }

  void _initializeBalls() {
    balls.clear();
    renderPositions.clear();
    _reducedMotionStartPositions.clear();
    bladeCollisionCount = 0;
    targetedForceApplications = 0;

    const minimumDistance = ballRadius * 2 + 4;
    for (var index = 0; index < personCount; index++) {
      Offset? position;
      for (var attempt = 0; attempt < 1200; attempt++) {
        final angle = _random.nextDouble() * 2 * pi;
        final minimumRadiusSquared = 48.0 * 48.0;
        final maximumRadiusSquared = 104.0 * 104.0;
        final radius = sqrt(
          minimumRadiusSquared +
              _random.nextDouble() *
                  (maximumRadiusSquared - minimumRadiusSquared),
        );
        final candidate = Offset.fromDirection(angle, radius);
        if (_isSafeInitialPosition(candidate, minimumDistance)) {
          position = candidate;
          break;
        }
      }

      if (position == null) {
        final phaseOffset = (seed % 360) * pi / 180;
        for (final radius in const <double>[104, 78, 54]) {
          for (var slot = 0; slot < 72; slot++) {
            final candidate = Offset.fromDirection(
              phaseOffset + slot * 2 * pi / 72,
              radius,
            );
            if (_isSafeInitialPosition(candidate, minimumDistance)) {
              position = candidate;
              break;
            }
          }
          if (position != null) break;
        }
      }

      if (position == null) {
        throw StateError('Could not place Hesap Kimde ball $index safely.');
      }
      balls.add(WhoPaysBallState(position: position));
    }

    _reducedMotionStartPositions.addAll(balls.map((ball) => ball.position));
  }

  bool _isSafeInitialPosition(Offset candidate, double minimumDistance) {
    if (candidate.distance > maxBallCenterRadius - 1) return false;
    if (balls.any(
      (ball) => (candidate - ball.position).distance < minimumDistance,
    )) {
      return false;
    }
    return !_overlapsRotor(candidate, 0, clearance: 2);
  }

  double _stepPhysics(double dt, double stepTime) {
    final drawTime = stepTime - _phaseShift;
    final stepRotorSpeed = _rotorSpeedAt(stepTime);
    final stepRotorAngle = _rotorAngleAt(stepTime);
    final stepGateProgress = _gateProgressAt(stepTime);
    final settling = drawTime >= _mixingEnd;
    final capturing = drawTime >= _settlingEnd;

    // Son çare: garanti penceresi açıldı ve fizik hâlâ hiçbir topu ağızdan
    // düşürmediyse, ağza O ANDA en yakın top atanır — endeks önseli yok.
    if (_capturedBallIndex == null &&
        capturing &&
        drawTime >= _captureEnd - _guaranteeWindow) {
      _capturedBallIndex = _nearestToMouth();
    }

    for (var index = 0; index < balls.length; index++) {
      final ball = balls[index];
      final isCaptured = index == _capturedBallIndex;
      final capturedInTube = isCaptured && ball.position.dy >= tubeEntryY;
      if (capturedInTube) _capturedReachedTube = true;
      final intakeActive =
          _phaseShift > 0 &&
          stepTime < _phaseShift &&
          index == _intakeBallIndex &&
          !_intakeReleased;

      Offset acceleration;
      double dragRate;

      if (intakeActive) {
        acceleration = stepTime >= _intakePullStart
            ? const Offset(0, -_intakeSuction)
            : Offset.zero;
        dragRate = 0.3;
      } else if (capturedInTube) {
        final centering = _clampMagnitude(
          Offset(-ball.position.dx * 260 - ball.velocity.dx * 26, 0),
          2600,
        );
        acceleration = centering + const Offset(0, chuteGravity);
        // İniş yastığı: yuvanın son bandında ağır sönümleme — top ~550 px/s
        // ile çakılıp tek karede durmak yerine yavaşlayıp yumuşak konar
        // (sekme yok, iniş monotonluğu korunur).
        dragRate = ball.position.dy >= winnerSeatY - seatCushionZone
            ? seatCushionDragRate
            : tubeDragRate;
        targetedForceApplications++;
      } else {
        // Çökme fazında iniş yardımı: toplar kapak açılmadan tabana insin
        // diye yerçekimi geçici olarak güçlenir (tüm toplara eşit —
        // tarafsızlık bozulmaz).
        final inSettleWindow =
            drawTime >= _mixingEnd && drawTime < _settlingEnd;
        // Yakalanan top tüpe geçtikten sonra kaybedenler de aynı yardımla
        // tabana iner — son kare donmadan önce havada top kalmasın.
        final loserHomeStretch =
            capturing && !isCaptured && _capturedReachedTube;
        acceleration = Offset(
          0,
          (inSettleWindow || loserHomeStretch)
              ? gravity * settleAssistGravityFactor
              : gravity,
        );
        dragRate = settling ? settleDragRate : mixingDragRate;

        // Nötr drenaj: kapak neredeyse tam açık ve atama henüz yokken TÜM
        // toplara eşit, ağza yönlü, rampalanan kuvvet. Ağzın üstü boşsa
        // yığını ağza kaydırır — yine deliğe en yakın top düşer.
        if (capturing &&
            _capturedBallIndex == null &&
            stepGateProgress > gateOpenForCapture) {
          final ramp =
              ((drawTime - _settlingEnd) / (_captureEnd - _settlingEnd)).clamp(
                0.0,
                1.0,
              );
          final toMouth = mouthTarget - ball.position;
          final distance = toMouth.distance;
          if (distance > 1) {
            acceleration += toMouth / distance * (drainRampMax * ramp);
          }
        }

        if (isCaptured) {
          // Son-çare transiti: atanmış top henüz tüpte değil — garanti yayı
          // onu ağza taşır. (Doğal yakalamada top atandığı anda zaten huni
          // bandındadır; bu dal yalnız son-çare atamasında çalışır.)
          dragRate = capturedTransitDragRate;
          final pull =
              (mouthTarget - ball.position) * suctionSpringRate -
              ball.velocity * suctionDampingRate;
          acceleration += _clampMagnitude(pull, suctionGuaranteeMax);
          targetedForceApplications++;
        } else if (_capturedBallIndex != null &&
            capturing &&
            // Yastık, yakalanan top tüpe girene dek açık kalır; girer girmez
            // söner ki kaybedenler kare donmadan önce tabana inebilsin.
            !_capturedReachedTube &&
            drawTime < _droppingEnd &&
            stepGateProgress > 0.5) {
          final delta = ball.position - mouthTarget;
          final distance = delta.distance;
          if (distance < cushionRadius && distance > 0.001) {
            // Süpürücü: radyal üfleme topları dikine fırlatıp son karede
            // havada bırakıyordu. Yana (hafif aşağı basımlı) itiş, ağzı
            // boşaltırken kaybedenleri taban boyunca iki yana ayırır.
            final sideways = ball.position.dx.abs() > 0.5
                ? ball.position.dx.sign
                : (index.isEven ? 1.0 : -1.0);
            final strength = cushionMax * (1 - distance / cushionRadius);
            acceleration += Offset(sideways * strength, strength * 0.15);
          }
        }
      }

      ball.velocity += acceleration * dt;
      ball.velocity *= exp(-dragRate * dt);
      ball.position += ball.velocity * dt;

      if (index == _intakeBallIndex &&
          !_intakeReleased &&
          ball.position.dy < _intakeReleaseY) {
        _intakeReleased = true;
      }

      if (_intakeBallIndex != null &&
          !_intakeReleased &&
          stepTime >= _phaseShift) {
        // Time-bound: the intake exemptions must never outlive the prologue,
        // even if a retuned suction fails to lift the ball past the release
        // line.
        _intakeReleased = true;
      }
    }

    // Kapak sırtı tahliye bütçesi: her top adım başına en fazla
    // postMixSeparationCap kadar yana kaydırılabilir; bütçe pass'ler
    // arasında paylaşılır ki tahliye 8 pass'te katlanmasın ama yarattığı
    // çakışmalar aynı adımın kalan pass'lerinde çözülebilsin.
    for (var i = 0; i < _ridgeShiftBudget.length; i++) {
      _ridgeShiftBudget[i] = postMixSeparationCap;
    }

    var maxImpactSpeed = 0.0;
    for (var pass = 0; pass < collisionPasses; pass++) {
      maxImpactSpeed = max(maxImpactSpeed, _resolveBallCollisions(drawTime));
      maxImpactSpeed = max(
        maxImpactSpeed,
        _resolveRotorCollisions(stepRotorAngle, stepRotorSpeed, drawTime),
      );
      maxImpactSpeed = max(
        maxImpactSpeed,
        _resolveBoundaries(drawTime, stepGateProgress),
      );
    }

    _assignCaptureIfEntered(drawTime, stepGateProgress);

    final postMix = drawTime >= _mixingEnd;
    for (var index = 0; index < balls.length; index++) {
      final ball = balls[index];
      final speed = ball.velocity.distance;
      if (speed > maxBallSpeed) {
        ball.velocity = ball.velocity / speed * maxBallSpeed;
      }
      // Karışım bittikten sonra sunum sakinleşir: düşüşler serbest düşüş
      // tavanını aşamaz (tüm toplara eşit — tarafsızlık korunur) ve
      // yakalanan top sinematik hız tavanına uyar. Roket düşüş / fırlamış
      // kayış görüntüsünün önüne geçer.
      if (postMix && ball.velocity.dy > postMixTerminalFallSpeed) {
        ball.velocity = Offset(ball.velocity.dx, postMixTerminalFallSpeed);
      }
      if (index == _capturedBallIndex) {
        final capturedSpeed = ball.velocity.distance;
        if (capturedSpeed > winnerCaptureMaxSpeed) {
          ball.velocity =
              ball.velocity / capturedSpeed * winnerCaptureMaxSpeed;
        }
      }
    }
    return maxImpactSpeed;
  }

  /// Doğal yakalama ataması: kapak yeterince açıkken huni bandına girmiş
  /// toplar arasından ağza en yakın olan seçilir. Endeks yalnız eşitlik
  /// kırıcı bile değildir — ölçüt tamamen geometriktir.
  void _assignCaptureIfEntered(double drawTime, double stepGateProgress) {
    if (_capturedBallIndex != null) return;
    if (drawTime < _settlingEnd || stepGateProgress <= gateOpenForCapture) {
      return;
    }
    int? best;
    var bestDistance = double.infinity;
    for (var index = 0; index < balls.length; index++) {
      final position = balls[index].position;
      if (position.dy < tubeEntryY ||
          position.dx.abs() > funnelHalfWidthAt(position.dy)) {
        continue;
      }
      final distance = (position - mouthTarget).distance;
      if (distance < bestDistance) {
        bestDistance = distance;
        best = index;
      }
    }
    if (best != null) {
      _capturedBallIndex = best;
    }
  }

  /// Ağza (mouthTarget'a) en yakın topun endeksi — son-çare ve donma-karesi
  /// garantilerinin ortak "en yakın kazanır" kuralı.
  int _nearestToMouth() {
    var best = 0;
    var bestDistance = double.infinity;
    for (var index = 0; index < balls.length; index++) {
      final distance = (balls[index].position - mouthTarget).distance;
      if (distance < bestDistance) {
        bestDistance = distance;
        best = index;
      }
    }
    return best;
  }

  double _resolveBallCollisions(double drawTime) {
    var maxImpactSpeed = 0.0;
    const minimumDistance = ballRadius * 2;
    final restitution = drawTime < _mixingEnd ? ballRestitution : 0.16;

    for (var firstIndex = 0; firstIndex < balls.length; firstIndex++) {
      for (
        var secondIndex = firstIndex + 1;
        secondIndex < balls.length;
        secondIndex++
      ) {
        final first = balls[firstIndex];
        final second = balls[secondIndex];
        final delta = second.position - first.position;
        final distance = delta.distance;
        if (distance >= minimumDistance) continue;

        final normal = distance > 0.001
            ? delta / distance
            : Offset.fromDirection((firstIndex + secondIndex) * 0.9);
        final overlap = minimumDistance - distance;

        // Atamadan itibaren yakalanan top "ağır top" gibi davranır: temasta
        // diğeri kenara itilir, yakalanan momentumunu korur. Böylece taban
        // yığını yakalananı ağzın dışında kilitleyemez; itilme fiziksel
        // (gerçek çarpışma) göründüğü için süzülme hissi doğmaz.
        final firstIsCaptureWinner = firstIndex == _capturedBallIndex;
        final secondIsCaptureWinner = secondIndex == _capturedBallIndex;

        // Karışım sonrası ayrıştırma itmesi kare başına sınırlanır: derin
        // binmelerde topu tek karede fırlatmak yerine birkaç kareye yayar
        // (collisionPasses döngüsü toplam ayrışmayı yine tamamlar).
        final postMixCollision = drawTime >= _mixingEnd;
        final fullPush = overlap;
        final halfPush = overlap * 0.5;
        final cappedFull = postMixCollision
            ? min(fullPush, postMixSeparationCap)
            : fullPush;
        final cappedHalf = postMixCollision
            ? min(halfPush, postMixSeparationCap)
            : halfPush;

        if (firstIsCaptureWinner) {
          second.position += normal * cappedFull;
        } else if (secondIsCaptureWinner) {
          first.position -= normal * cappedFull;
        } else {
          first.position -= normal * cappedHalf;
          second.position += normal * cappedHalf;
        }

        final relativeVelocity = second.velocity - first.velocity;
        final normalSpeed = _dot(relativeVelocity, normal);
        if (normalSpeed >= 0) continue;

        maxImpactSpeed = max(maxImpactSpeed, -normalSpeed);
        if (firstIsCaptureWinner) {
          // Pulluk tekmesi tavanlı: yolu asıl açan konumsal itme; sınırsız
          // impuls kaybedenleri duvara fırlatıp son karede havada
          // bırakıyordu.
          final kick = ((1 + restitution) * normalSpeed).clamp(
            -plowKickCap,
            0.0,
          );
          second.velocity -= normal * kick;
        } else if (secondIsCaptureWinner) {
          final kick = ((1 + restitution) * normalSpeed).clamp(
            -plowKickCap,
            0.0,
          );
          first.velocity += normal * kick;
        } else {
          final impulseMagnitude = -(1 + restitution) * normalSpeed / 2;
          final impulse = normal * impulseMagnitude;
          first.velocity -= impulse;
          second.velocity += impulse;
        }
      }
    }
    return maxImpactSpeed;
  }

  double _resolveRotorCollisions(
    double angle,
    double angularVelocity,
    double drawTime,
  ) {
    var maxImpactSpeed = 0.0;
    for (var ballIndex = 0; ballIndex < balls.length; ballIndex++) {
      // From assignment onward the captured ball is exempt from rotor
      // contact: the last-resort spring must be able to pull it across the
      // stationary rotor's territory to the mouth. The rotor is drawn
      // behind the balls and mostly transparent, so the pass-through is not
      // visible.
      if (ballIndex == _capturedBallIndex) {
        continue;
      }

      final ball = balls[ballIndex];
      final skipAsIntakeBall =
          ballIndex == _intakeBallIndex &&
          !_intakeReleased &&
          _phaseShift > 0 &&
          ball.position.dy >= tubeEntryY;
      if (skipAsIntakeBall) continue;

      final contact = _deepestRotorContact(ball.position, angle, ballIndex);
      if (contact == null) continue;

      // Karışım sonrası (rotor yavaşlarken) kanat penetrasyon itmesi de kare
      // başına sınırlanır — yavaşlayan kanadın topu tek karede savurması
      // "ani düşme/itilme" olarak görünüyordu.
      final rotorPush = drawTime >= _mixingEnd
          ? min(contact.penetration, postMixSeparationCap)
          : contact.penetration;
      ball.position += contact.normal * (rotorPush + 0.05);
      final surfaceVelocity = Offset(
        -contact.point.dy * angularVelocity,
        contact.point.dx * angularVelocity,
      );
      final relativeVelocity = ball.velocity - surfaceVelocity;
      final approachSpeed = _dot(relativeVelocity, contact.normal);
      if (approachSpeed >= 0) continue;

      final normalImpulse = -(1 + bladeRestitution) * approachSpeed;
      ball.velocity += contact.normal * normalImpulse;

      final tangent = Offset(-contact.normal.dy, contact.normal.dx);
      final tangentSpeed = _dot(ball.velocity - surfaceVelocity, tangent);
      final maximumFrictionImpulse = bladeFriction * normalImpulse;
      final frictionImpulse = (-tangentSpeed).clamp(
        -maximumFrictionImpulse,
        maximumFrictionImpulse,
      );
      ball.velocity += tangent * frictionImpulse;

      if (angularVelocity.abs() > 0.001 && -approachSpeed >= 12) {
        bladeCollisionCount++;
      }
      maxImpactSpeed = max(maxImpactSpeed, -approachSpeed);
    }
    return maxImpactSpeed;
  }

  _RotorContact? _deepestRotorContact(
    Offset position,
    double angle,
    int ballIndex,
  ) {
    _RotorContact? deepest;

    final hubDistance = position.distance;
    final hubLimit = ballRadius + rotorHubRadius;
    if (hubDistance < hubLimit) {
      final normal = hubDistance > 0.001
          ? position / hubDistance
          : Offset.fromDirection(ballIndex * 1.7 + angle);
      deepest = _RotorContact(
        point: normal * rotorHubRadius,
        normal: normal,
        penetration: hubLimit - hubDistance,
      );
    }

    for (var bladeIndex = 0; bladeIndex < rotorBladeCount; bladeIndex++) {
      final points = bladeSpinePoints(angle, bladeIndex);
      for (var segmentIndex = 0; segmentIndex < 2; segmentIndex++) {
        final start = points[segmentIndex];
        final end = points[segmentIndex + 1];
        final halfWidth = segmentIndex == 0
            ? rotorBladeInnerHalfWidth
            : rotorBladeOuterHalfWidth;
        final closest = _closestPointOnSegment(position, start, end);
        final delta = position - closest;
        final distance = delta.distance;
        final limit = ballRadius + halfWidth;
        if (distance >= limit) continue;

        final segment = end - start;
        var normal = distance > 0.001
            ? delta / distance
            : Offset(-segment.dy, segment.dx) / segment.distance;
        if (_dot(normal, position) < 0 && distance <= 0.001) {
          normal = -normal;
        }
        final candidate = _RotorContact(
          point: closest,
          normal: normal,
          penetration: limit - distance,
        );
        if (deepest == null || candidate.penetration > deepest.penetration) {
          deepest = candidate;
        }
      }
    }
    return deepest;
  }

  double _resolveBoundaries(double drawTime, double stepGateProgress) {
    var maxImpactSpeed = 0.0;
    final capturing = drawTime >= _settlingEnd;
    // Ağız deliği: kapak neredeyse tam açık ve atama yokken huni bandı
    // HERKESE açıktır — ağzın üstündeki top gerçekten düşer ve atanır.
    // Atamadan sonra delik yalnız yakalanan topa (ve intake topuna) açıktır.
    final mouthOpenForEntry =
        capturing &&
        _capturedBallIndex == null &&
        stepGateProgress > gateOpenForCapture;

    for (var index = 0; index < balls.length; index++) {
      final ball = balls[index];
      final inFunnelBand =
          ball.position.dy >= tubeEntryY &&
          ball.position.dx.abs() <= funnelHalfWidthAt(ball.position.dy);
      final capturedInTube =
          index == _capturedBallIndex && ball.position.dy >= tubeEntryY;
      final intakeInTube =
          index == _intakeBallIndex &&
          !_intakeReleased &&
          _phaseShift > 0 &&
          ball.position.dy >= tubeEntryY;

      if (capturedInTube || intakeInTube || (mouthOpenForEntry && inFunnelBand)) {
        final halfWidth = funnelHalfWidthAt(ball.position.dy);
        if (ball.position.dx.abs() > halfWidth) {
          final normal = Offset(ball.position.dx.sign, 0);
          ball.position = Offset(normal.dx * halfWidth, ball.position.dy);
          final normalSpeed = _dot(ball.velocity, normal);
          if (normalSpeed > 0) {
            maxImpactSpeed = max(maxImpactSpeed, normalSpeed);
            ball.velocity -= normal * (1.12 * normalSpeed);
          }
        }
        if (ball.position.dy >= winnerSeatY) {
          maxImpactSpeed = max(maxImpactSpeed, max(0, ball.velocity.dy));
          ball
            ..position = const Offset(0, winnerSeatY)
            ..velocity = Offset.zero;
        }
        continue;
      }

      // Ağız koridoru keepout'u: kapak anlamlı açıkken bant, o an tüpte
      // seyahat hakkı olan topa aittir — diğerleri adım-bütçesi dahilinde
      // yana tahliye edilir. İki dönem: (1) intake prologu — dönen topun
      // koridoru, üstünde dinlenen top tarafından tıkanmasın; (2) yakalama
      // ATANDIKTAN sonra — ikinci top sızamaz. Atama öncesi ve kapak
      // kapandıktan sonra bölge serbesttir (kapalı kapağın üstünde
      // dinlenmek doğaldır; yığının ağzın üstünde durması istenen durumdur).
      // Pass döngüsü içinde çalıştığı için yarattığı çakışmalar aynı adımda
      // çözülür.
      final inPrologue = _phaseShift > 0 && drawTime < 0;
      final keepoutActive =
          stepGateProgress > 0.15 &&
          (inPrologue
              ? index != _intakeBallIndex
              : _capturedBallIndex != null && index != _capturedBallIndex);
      if (keepoutActive &&
          _ridgeShiftBudget[index] > 0 &&
          ball.position.dy > gateRidgeTopY &&
          ball.position.dx.abs() < mouthKeepoutHalfWidth) {
        final side = ball.position.dx.abs() > 0.5
            ? ball.position.dx.sign
            : (index.isEven ? 1.0 : -1.0);
        final needed = mouthKeepoutHalfWidth - ball.position.dx.abs();
        final shift = min(_ridgeShiftBudget[index], needed);
        _ridgeShiftBudget[index] -= shift;
        ball.position = Offset(
          ball.position.dx + side * shift,
          ball.position.dy,
        );
        if (ball.velocity.dx.sign != side) {
          ball.velocity = Offset(ball.velocity.dx * 0.3, ball.velocity.dy);
        }
      }

      final distance = ball.position.distance;
      if (distance <= maxBallCenterRadius) continue;

      final normal = distance > 0.001
          ? ball.position / distance
          : const Offset(0, 1);
      ball.position = normal * maxBallCenterRadius;
      final normalSpeed = _dot(ball.velocity, normal);
      if (normalSpeed <= 0) continue;

      maxImpactSpeed = max(maxImpactSpeed, normalSpeed);
      final restitution = drawTime < _mixingEnd ? wallRestitution : 0.12;
      ball.velocity -= normal * ((1 + restitution) * normalSpeed);
    }
    return maxImpactSpeed;
  }

  bool _overlapsRotor(Offset position, double angle, {double clearance = 0}) {
    if (position.distance < ballRadius + rotorHubRadius + clearance) {
      return true;
    }
    for (var bladeIndex = 0; bladeIndex < rotorBladeCount; bladeIndex++) {
      final points = bladeSpinePoints(angle, bladeIndex);
      for (var segmentIndex = 0; segmentIndex < 2; segmentIndex++) {
        final halfWidth = segmentIndex == 0
            ? rotorBladeInnerHalfWidth
            : rotorBladeOuterHalfWidth;
        final closest = _closestPointOnSegment(
          position,
          points[segmentIndex],
          points[segmentIndex + 1],
        );
        if ((position - closest).distance <
            ballRadius + halfWidth + clearance) {
          return true;
        }
      }
    }
    return false;
  }

  void _updatePresentation() {
    renderPositions
      ..clear()
      ..addAll(balls.map((ball) => ball.position));
  }

  /// Deterministically parks every loser on the floor arc. Used only when the
  /// timeline finishes via a resume/background jump, so the last frame never
  /// shows balls frozen mid-air.
  void _settleLosersToFloor() {
    assert(
      balls.length - 1 <= floorSlotAngles.length,
      'floor slots must cover every loser',
    );
    final used = List<bool>.filled(floorSlotAngles.length, false);
    for (var index = 0; index < balls.length; index++) {
      if (index == _capturedBallIndex) continue;
      final currentAngle = balls[index].position.direction;
      var best = 0;
      var bestDifference = double.infinity;
      for (var slot = 0; slot < floorSlotAngles.length; slot++) {
        if (used[slot]) continue;
        final raw = floorSlotAngles[slot] - currentAngle;
        final difference = atan2(sin(raw), cos(raw)).abs();
        if (difference < bestDifference) {
          bestDifference = difference;
          best = slot;
        }
      }
      used[best] = true;
      balls[index]
        ..position = Offset.fromDirection(
          floorSlotAngles[best],
          maxBallCenterRadius,
        )
        ..velocity = Offset.zero;
    }
  }

  WhoPaysLotteryPhase _phaseFor(double seconds) {
    if (seconds <= 0) return WhoPaysLotteryPhase.idle;
    if (seconds < _phaseShift) return WhoPaysLotteryPhase.intake;
    final t = seconds - _phaseShift;
    if (t < _spinUpEnd) return WhoPaysLotteryPhase.spinUp;
    if (t < _mixingEnd) return WhoPaysLotteryPhase.mixing;
    if (t < _settlingEnd) return WhoPaysLotteryPhase.settling;
    if (t < _captureEnd) return WhoPaysLotteryPhase.capture;
    if (t < _droppingEnd) return WhoPaysLotteryPhase.dropping;
    return WhoPaysLotteryPhase.seated;
  }

  double _rotorSpeedAt(double seconds) {
    final t = seconds - _phaseShift;
    if (t <= 0 || t >= _settlingEnd) return 0;
    if (t < _spinUpEnd) {
      return maxRotorRadiansPerSecond * _smoothStep(t / _spinUpEnd);
    }
    if (t < _mixingEnd) return maxRotorRadiansPerSecond;
    final progress = (t - _mixingEnd) / (_settlingEnd - _mixingEnd);
    return maxRotorRadiansPerSecond * (1 - _smoothStep(progress));
  }

  double _rotorAngleAt(double seconds) {
    final clamped = (seconds - _phaseShift).clamp(0.0, _settlingEnd);
    if (clamped <= _spinUpEnd) {
      final progress = clamped / _spinUpEnd;
      return maxRotorRadiansPerSecond *
          _spinUpEnd *
          (pow(progress, 3) - 0.5 * pow(progress, 4));
    }

    var angle = maxRotorRadiansPerSecond * _spinUpEnd * 0.5;
    final constantEnd = min(clamped, _mixingEnd);
    angle += maxRotorRadiansPerSecond * max(0.0, constantEnd - _spinUpEnd);
    if (clamped <= _mixingEnd) return angle;

    final progress = (clamped - _mixingEnd) / (_settlingEnd - _mixingEnd);
    angle +=
        maxRotorRadiansPerSecond *
        (_settlingEnd - _mixingEnd) *
        (progress - pow(progress, 3) + 0.5 * pow(progress, 4));
    return angle;
  }

  double _gateProgressAt(double seconds) {
    if (_phaseShift > 0 && seconds < _phaseShift) {
      if (seconds < _intakeGateOpenEnd) {
        return _smoothStep(seconds / _intakeGateOpenEnd);
      }
      if (seconds < _intakeGateCloseStart) return 1;
      return 1 -
          _smoothStep(
            (seconds - _intakeGateCloseStart) /
                (_phaseShift - _intakeGateCloseStart),
          );
    }
    final t = seconds - _phaseShift;
    if (t <= _settlingEnd) return 0;
    if (t < _settlingEnd + _gateOpenLength) {
      return _smoothStep((t - _settlingEnd) / _gateOpenLength);
    }
    final closeBeganAt = _gateCloseBeganAt;
    if (closeBeganAt == null) return 1;
    final closeProgress = (seconds - closeBeganAt) / _gateCloseLength;
    if (closeProgress <= 0) return 1;
    if (closeProgress >= 1) return 0;
    return 1 - _smoothStep(closeProgress);
  }

  static Offset _closestPointOnSegment(Offset point, Offset start, Offset end) {
    final segment = end - start;
    final lengthSquared = _dot(segment, segment);
    if (lengthSquared <= 1e-9) return start;
    final progress = (_dot(point - start, segment) / lengthSquared).clamp(
      0.0,
      1.0,
    );
    return start + segment * progress;
  }

  static Offset _clampMagnitude(Offset value, double maximum) {
    final length = value.distance;
    if (length <= maximum || length <= 1e-9) return value;
    return value / length * maximum;
  }

  static double _smoothStep(double value) {
    final clamped = value.clamp(0.0, 1.0);
    return clamped * clamped * (3 - 2 * clamped);
  }

  static double _dot(Offset first, Offset second) {
    return first.dx * second.dx + first.dy * second.dy;
  }
}

class _RotorContact {
  const _RotorContact({
    required this.point,
    required this.normal,
    required this.penetration,
  });

  final Offset point;
  final Offset normal;
  final double penetration;
}

/// Snapshot of a finished draw used to seed the next one, so the machine
/// animates continuously instead of teleporting to a fresh layout.
class WhoPaysInitialState {
  const WhoPaysInitialState({
    required this.chamberPositions,
    this.seatedBallIndex,
  });

  final List<Offset> chamberPositions;
  final int? seatedBallIndex;
}
