# Hesap Kimde Mekanik Yenileme — Uygulama Planı

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Hesap Kimde çekiliş makinesine spec'teki yeni koreografiyi (tarafsız karışım, son anda yakalama, huni, kapak döngüsü, "Tekrar Çek" sürekliliği) uygulamak ve süre/robustluk buglarını kapatmak.

**Architecture:** Tek fizik sınıfı `WhoPaysLotterySimulation` evrimleştirilir: zaman modeli `_phaseShift`'li örnek getter'lara taşınır, staging/latch kaldırılıp capture emmesi + huni + intake eklenir. `main.dart` yalnızca bağlantı katmanıdır (controller süresi, exportState geçişi). Görünümde tek değişiklik kapak geometrisidir.

**Tech Stack:** Flutter/Dart, `flutter_test` (birim + golden testler), sabit adımlı (120 Hz) deterministik fizik.

**Spec:** `luuqapp/docs/superpowers/specs/2026-07-20-hesap-kimde-mechanics-design.md`

## Global Constraints

- Kazanan seçimi dialogda `Random.nextInt(personCount)` ile kalır; fizik sonucu asla etkilemez.
- Sabit adım `1/120` s, kare başına en çok 8 adım, top hız limiti 760 px/s — değişmez.
- Faz sınırları ve süreler sabittir (idle 3400 ms, devam 3850 ms); kuvvet sabitleri (yay, ramp, yastık) testleri geçirmek için ayarlanabilir.
- Capture başlamadan önce kazanana özel hiçbir kuvvet uygulanamaz (`winnerGuideApplications == 0` invaryantı).
- Tüm komutlar `C:\xampp\htdocs\LUUQ\luuqapp` dizininde çalıştırılır.
- Her görev sonunda `flutter analyze` temiz olmalı; commit mesajları `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>` ile biter.
- UI metinleri (TR/EN) değişmez.

---

### Task 1: Yuva hizası (209) + kapak görseli (50 px, menteşe kirişte)

**Files:**
- Modify: `lib/src/who_pays/lottery_simulation.dart` (yalnız `winnerSeatY` sabiti)
- Modify: `lib/src/who_pays/lottery_machine_view.dart` (`_paintGate`)
- Modify: `test/who_pays_lottery_simulation_test.dart` (205 → 209 beklentileri)
- Test: `test/who_pays_lottery_golden_test.dart` (golden yeniden üretimi)

**Interfaces:**
- Produces: `WhoPaysLotterySimulation.winnerSeatY == 209.0` (sonraki tüm görevler bu değeri kullanır).

- [ ] **Step 1: Testleri 209'a güncelle (başarısız hale gelirler)**

`test/who_pays_lottery_simulation_test.dart` içinde iki yeri değiştir:

```dart
      expect(simulation.renderPositions[winnerIndex].dy, closeTo(209, 0.001));
```

(`only the selected winner enters and remains in the chute` testindeki `closeTo(205, 0.001)` satırı) ve

```dart
      expect(simulation.renderPositions[1], const Offset(0, 209));
```

(`reduced motion skips rotation and ends at the result` testindeki `Offset(0, 205)` satırı).

- [ ] **Step 2: Testlerin başarısız olduğunu doğrula**

Run: `flutter test test/who_pays_lottery_simulation_test.dart`
Expected: FAIL — iki test 205 ≠ 209 nedeniyle düşer.

- [ ] **Step 3: Simülasyonda yuvayı düzelt**

`lib/src/who_pays/lottery_simulation.dart`:

```dart
  static const double winnerSeatY = 209.0;
```

(eski değer `205.0`).

- [ ] **Step 4: Kapak geometrisini düzelt**

`lib/src/who_pays/lottery_machine_view.dart` içindeki `_paintGate` tamamen şu olsun (yarı genişlik 21 → 25, menteşe y=128 → kiriş y≈132.7):

```dart
  void _paintGate(Canvas canvas, Offset center) {
    const gateHalfWidth = 25.0;
    // Kiriş: cam kürenin tüp duvarlarıyla kesiştiği omuz hattı.
    final chordY = center.dy + sqrt(135.0 * 135.0 - gateHalfWidth * gateHalfWidth);
    final hinge = Offset(center.dx - gateHalfWidth, chordY);
    final angle = pi * 0.5 * simulation.gateProgress;

    canvas.save();
    canvas.translate(hinge.dx, hinge.dy);
    canvas.rotate(angle);
    canvas.drawLine(
      Offset.zero,
      const Offset(gateHalfWidth * 2, 0),
      Paint()
        ..color = _machineBackground.withValues(alpha: 0.75)
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawLine(
      Offset.zero,
      const Offset(gateHalfWidth * 2, 0),
      Paint()
        ..color = _machineGold.withValues(alpha: 0.78)
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );
    canvas.restore();

    canvas.drawCircle(
      hinge,
      5,
      Paint()..color = _machineCaramel.withValues(alpha: 0.9),
    );
    canvas.drawCircle(
      hinge,
      5,
      Paint()
        ..color = _machineCream.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }
```

- [ ] **Step 5: Birim testler geçsin, golden'ları yeniden üret**

Run: `flutter test test/who_pays_lottery_simulation_test.dart`
Expected: PASS.

Run: `flutter test --update-goldens test/who_pays_lottery_golden_test.dart`
Expected: PASS (dört golden dosyası yenilenir).

Run: `flutter test`
Expected: tümü PASS.

- [ ] **Step 6: Commit**

```powershell
git -C C:\xampp\htdocs\LUUQ add -A
git -C C:\xampp\htdocs\LUUQ commit -m @'
fix(who_pays): seat the winning ball on the glass floor, widen the gate

Seat Y 205 -> 209 so the ball rests tangent to the bottom cap; the gate now
spans the full 50 px tube and hinges on the shoulder chord.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
'@
```

---

### Task 2: Çekirdek koreografi (idle mod) + süre senkronu

En büyük görev: staging/latch kalkar, yeni zaman modeli ve capture emmesi gelir, controller simülasyon süresini okur.

**Files:**
- Modify: `lib/src/who_pays/lottery_simulation.dart` (büyük yeniden yazım — tam kod aşağıda)
- Modify: `lib/main.dart:5112-5233` (`_LotteryMachineState`)
- Modify: `test/who_pays_lottery_simulation_test.dart` (tam yeni içerik aşağıda)
- Modify: `test/who_pays_lottery_golden_test.dart` (örnekleme anları)
- Modify: `test/widget_test.dart` (pompalama süreleri)

**Interfaces:**
- Consumes: Task 1'in `winnerSeatY = 209.0` değeri.
- Produces (sonraki görevler bunlara güvenir):
  - `enum WhoPaysLotteryPhase { idle, intake, spinUp, mixing, settling, capture, dropping, seated }`
  - Örnek getter'lar: `double durationSeconds`, `int durationMilliseconds`, `double spinUpEndSeconds`, `double mixingEndSeconds`, `double settlingEndSeconds`, `double captureEndSeconds`, `double droppingEndSeconds`
  - Statikler: `int idleDurationMilliseconds = 3400`, `double tubeEntryY = 100.0`, `Offset mouthTarget = Offset(0, 126)`
  - Alanlar: `int winnerGuideApplications` (capture emmesi her uygulandığında artar), `double _phaseShift` (bu görevde her zaman 0)
  - `advanceTo`/`advanceReducedMotion`/`WhoPaysStepReport` imzaları değişmez.

- [ ] **Step 1: Simülasyon testlerini yeni koreografiye göre yaz (başarısız olacaklar)**

`test/who_pays_lottery_simulation_test.dart` dosyasının TÜM içeriğini şununla değiştir:

```dart
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:luuqapp/src/who_pays/lottery_simulation.dart';

void main() {
  group('WhoPaysLotterySimulation', () {
    for (var personCount = 2; personCount <= 6; personCount++) {
      test('$personCount balls start inside the cage without overlap', () {
        final simulation = WhoPaysLotterySimulation(
          personCount: personCount,
          winnerIndex: 0,
          seed: 7000 + personCount,
        );

        for (final ball in simulation.balls) {
          expect(
            ball.position.distance,
            lessThanOrEqualTo(WhoPaysLotterySimulation.maxBallCenterRadius),
          );
        }
        _expectNoOverlap(simulation, minimumDistance: 46);
      });
    }

    test('the same seed produces the same simulation', () {
      final first = WhoPaysLotterySimulation(
        personCount: 6,
        winnerIndex: 3,
        seed: 1842,
      );
      final second = WhoPaysLotterySimulation(
        personCount: 6,
        winnerIndex: 3,
        seed: 1842,
      );

      _advanceInFrames(first, 2.5);
      _advanceInFrames(second, 2.5);

      expect(first.rotorAngle, second.rotorAngle);
      expect(first.renderPositions, second.renderPositions);
      expect(
        first.balls.map((ball) => ball.velocity).toList(),
        second.balls.map((ball) => ball.velocity).toList(),
      );
    });

    test('timeline phases follow the approved choreography', () {
      final simulation = WhoPaysLotterySimulation(
        personCount: 4,
        winnerIndex: 2,
        seed: 5,
      );

      expect(simulation.durationSeconds, closeTo(3.40, 1e-9));
      expect(simulation.durationMilliseconds, 3400);
      expect(simulation.spinUpEndSeconds, closeTo(0.18, 1e-9));
      expect(simulation.mixingEndSeconds, closeTo(2.05, 1e-9));
      expect(simulation.settlingEndSeconds, closeTo(2.55, 1e-9));
      expect(simulation.captureEndSeconds, closeTo(3.00, 1e-9));
      expect(simulation.droppingEndSeconds, closeTo(3.32, 1e-9));

      simulation.advanceTo(0.10);
      expect(simulation.phase, WhoPaysLotteryPhase.spinUp);
      simulation.advanceTo(1.00);
      expect(simulation.phase, WhoPaysLotteryPhase.mixing);
      simulation.advanceTo(2.30);
      expect(simulation.phase, WhoPaysLotteryPhase.settling);
      simulation.advanceTo(2.80);
      expect(simulation.phase, WhoPaysLotteryPhase.capture);
      simulation.advanceTo(3.10);
      expect(simulation.phase, WhoPaysLotteryPhase.dropping);
      simulation.advanceTo(3.40);
      expect(simulation.phase, WhoPaysLotteryPhase.seated);
    });

    test('no winner-specific force is applied before capture starts', () {
      final simulation = WhoPaysLotterySimulation(
        personCount: 6,
        winnerIndex: 1,
        seed: 314159,
      );

      _advanceInFrames(simulation, simulation.settlingEndSeconds - 0.001);
      expect(simulation.winnerGuideApplications, 0);

      _advanceInFrames(simulation, simulation.durationSeconds);
      expect(simulation.winnerGuideApplications, greaterThan(0));
    });

    test('the gate opens during capture and is closed at the end', () {
      final simulation = WhoPaysLotterySimulation(
        personCount: 3,
        winnerIndex: 0,
        seed: 42,
      );

      _advanceInFrames(simulation, 2.50);
      expect(simulation.gateProgress, 0);
      _advanceInFrames(simulation, 2.72);
      expect(simulation.gateProgress, 1);
      _advanceInFrames(simulation, simulation.durationSeconds);
      expect(simulation.gateProgress, 0);
    });

    test('balls remain finite, separated, and inside the glass', () {
      final simulation = WhoPaysLotterySimulation(
        personCount: 6,
        winnerIndex: 4,
        seed: 99173,
      );

      var target = 0.0;
      final end = simulation.settlingEndSeconds - 0.0001;
      while (target < end) {
        target = math.min(target + 1 / 60, end);
        simulation.advanceTo(target);

        for (final ball in simulation.balls) {
          expect(ball.position.dx.isFinite, isTrue);
          expect(ball.position.dy.isFinite, isTrue);
          expect(ball.velocity.dx.isFinite, isTrue);
          expect(ball.velocity.dy.isFinite, isTrue);
          expect(
            ball.position.distance,
            lessThanOrEqualTo(
              WhoPaysLotterySimulation.maxBallCenterRadius + 0.001,
            ),
          );
        }
        _expectNoOverlap(simulation, minimumDistance: 41.5);
      }
    });

    test('mixing does not pin most balls to one glass wall', () {
      final simulation = WhoPaysLotterySimulation(
        personCount: 6,
        winnerIndex: 2,
        seed: 20260720,
      );

      for (final sample in <double>[0.75, 1.4, 2.0]) {
        _advanceInFrames(simulation, sample);
        final ballsNearWall = simulation.balls
            .where((ball) => ball.position.distance > 96)
            .length;
        expect(
          ballsNearWall,
          lessThanOrEqualTo(4),
          reason: 'too many balls were pinned near the wall at $sample s',
        );
      }
    });

    test('a large frame gap is capped at eight physics steps', () {
      final simulation = WhoPaysLotterySimulation(
        personCount: 4,
        winnerIndex: 1,
        seed: 77,
      );

      final report = simulation.advanceTo(1.8);

      expect(report.droppedCatchUp, isTrue);
      expect(
        report.physicsSteps,
        lessThanOrEqualTo(WhoPaysLotterySimulation.maxStepsPerFrame),
      );
      for (final ball in simulation.balls) {
        expect(ball.position.dx.isFinite, isTrue);
        expect(ball.position.dy.isFinite, isTrue);
      }
    });

    test('fan power follows the rotor and reaches zero before capture', () {
      final simulation = WhoPaysLotterySimulation(
        personCount: 3,
        winnerIndex: 2,
        seed: 12,
      );

      expect(simulation.fanPower, 0);
      simulation.advanceTo(simulation.spinUpEndSeconds);
      expect(simulation.fanPower, closeTo(1, 0.0001));
      simulation.advanceTo(simulation.settlingEndSeconds);
      expect(simulation.fanPower, 0);
      expect(simulation.rotorSpeed, 0);
    });

    for (var personCount = 2; personCount <= 6; personCount++) {
      for (final seed in const <int>[1, 97, 5000, 977351]) {
        test('winner $personCount/$seed is seated with the gate closed', () {
          final winnerIndex = seed % personCount;
          final simulation = WhoPaysLotterySimulation(
            personCount: personCount,
            winnerIndex: winnerIndex,
            seed: seed,
          );

          _advanceInFrames(simulation, simulation.durationSeconds);

          expect(simulation.phase, WhoPaysLotteryPhase.seated);
          expect(simulation.gateProgress, 0);
          expect(
            simulation.renderPositions[winnerIndex].dx,
            closeTo(0, 0.001),
          );
          expect(
            simulation.renderPositions[winnerIndex].dy,
            closeTo(209, 0.001),
          );
          for (var index = 0; index < simulation.personCount; index++) {
            if (index == winnerIndex) continue;
            expect(
              simulation.renderPositions[index].distance,
              lessThanOrEqualTo(
                WhoPaysLotterySimulation.maxBallCenterRadius + 0.001,
              ),
            );
          }
        });
      }
    }

    test('the winner descends monotonically after capture ends', () {
      final simulation = WhoPaysLotterySimulation(
        personCount: 5,
        winnerIndex: 2,
        seed: 101,
      );
      _advanceInFrames(simulation, simulation.captureEndSeconds);

      var previousY = simulation.renderPositions[2].dy;
      var target = simulation.captureEndSeconds;
      while (target < simulation.droppingEndSeconds) {
        target = math.min(target + 1 / 120, simulation.droppingEndSeconds);
        simulation.advanceTo(target);
        final currentY = simulation.renderPositions[2].dy;
        expect(currentY + 0.001, greaterThanOrEqualTo(previousY));
        previousY = currentY;
      }
    });

    test('reduced motion keeps the gate closed and ends at the result', () {
      final simulation = WhoPaysLotterySimulation(
        personCount: 4,
        winnerIndex: 1,
        seed: 8,
      );

      simulation.advanceReducedMotion(0.5);
      expect(simulation.rotorAngle, 0);
      expect(simulation.rotorSpeed, 0);
      expect(simulation.gateProgress, 0);
      expect(simulation.contentOpacity, 0);

      simulation.advanceReducedMotion(1);
      expect(simulation.phase, WhoPaysLotteryPhase.seated);
      expect(simulation.gateProgress, 0);
      expect(simulation.renderPositions[1], const Offset(0, 209));
      expect(simulation.contentOpacity, 1);
    });
  });
}

void _advanceInFrames(WhoPaysLotterySimulation simulation, double endSeconds) {
  var target = simulation.timelineSeconds;
  while (target < endSeconds) {
    target = math.min(target + 1 / 60, endSeconds);
    simulation.advanceTo(target);
  }
}

void _expectNoOverlap(
  WhoPaysLotterySimulation simulation, {
  required double minimumDistance,
}) {
  for (var first = 0; first < simulation.balls.length; first++) {
    for (var second = first + 1; second < simulation.balls.length; second++) {
      expect(
        (simulation.balls[first].position - simulation.balls[second].position)
            .distance,
        greaterThanOrEqualTo(minimumDistance),
        reason: 'balls $first and $second overlap',
      );
    }
  }
}
```

Not: eski `only the selected winner enters...`, `the winner drop does not use an upward bounce` ve `_expectNoRenderOverlap` yardımcısı bu içerikte kaldırıldı/karşılıklarıyla değiştirildi. Sonda örtüşme kontrolü yok çünkü kaybedenler kapalı tabana serbest fizikle oturur (örtüşme zaten çarpışma çözücüyle engellenir).

- [ ] **Step 2: Testlerin başarısız olduğunu doğrula**

Run: `flutter test test/who_pays_lottery_simulation_test.dart`
Expected: FAIL — `intake`/`capture` enum değerleri ve örnek getter'lar yok (derleme hatası).

- [ ] **Step 3: Simülasyonu yeniden yaz**

`lib/src/who_pays/lottery_simulation.dart` dosyasının TÜM içeriğini şununla değiştir:

```dart
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
/// The winner is supplied by the caller. Physics only controls presentation;
/// it never selects or changes the result. No winner-specific force may run
/// before the capture phase starts ([winnerGuideApplications] proves it).
class WhoPaysLotterySimulation {
  WhoPaysLotterySimulation({
    required this.personCount,
    required this.winnerIndex,
    required this.seed,
  }) : assert(personCount >= 2 && personCount <= 6),
       assert(winnerIndex >= 0 && winnerIndex < personCount),
       _random = Random(seed) {
    _initializeBalls();
    _updatePresentation();
  }

  // Draw-relative timeline offsets. _phaseShift carries the intake prologue
  // for continue-starts (always 0 until that feature lands).
  static const double _spinUpEnd = 0.18;
  static const double _mixingEnd = 2.05;
  static const double _settlingEnd = 2.55;
  static const double _captureEnd = 3.00;
  static const double _droppingEnd = 3.32;
  static const double _idleDuration = 3.40;
  static const double _gateOpenLength = 0.15;
  static const double _gateCloseStart = 3.10;
  static const double _gateCloseEnd = 3.30;
  static const double _guaranteeWindow = 0.10;

  static const int idleDurationMilliseconds = 3400;

  static const double fixedStepSeconds = 1 / 120;
  static const int maxStepsPerFrame = 8;
  static const double ballRadius = 21.0;
  static const double cageRadius = 128.0;
  static const double maxBallCenterRadius = cageRadius - ballRadius;

  static const double gravity = 520.0;
  static const double chuteGravity = 1320.0;
  static const double maxRotorRadiansPerSecond = 6 * pi;
  static const double ballRestitution = 0.68;
  static const double wallRestitution = 0.58;
  static const double bladeRestitution = 0.46;
  static const double bladeFriction = 0.15;
  static const double maxBallSpeed = 760.0;

  static const double mixingDragRate = 0.22;
  static const double settleDragRate = 2.0;
  static const double tubeDragRate = 0.20;

  // Capture suction toward the tube mouth.
  static const Offset mouthTarget = Offset(0, 126);
  static const double suctionSpringRate = 60.0;
  static const double suctionDampingRate = 14.0;
  static const double suctionRampMax = 3200.0;
  static const double suctionGuaranteeMax = 5200.0;

  // Outward air cushion that clears losers away from the open mouth.
  static const double cushionRadius = 55.0;
  static const double cushionMax = 900.0;

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
  static const double chuteCenterHalfWidth = 3.5;
  static const double winnerSeatY = 209.0;

  final int personCount;
  final int winnerIndex;
  final int seed;
  final Random _random;
  final double _phaseShift = 0;

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

  /// Cumulative physical blade/hub impacts. Used by focused tests and local
  /// diagnostics to prove that mixing energy comes from rotor contact.
  int bladeCollisionCount = 0;

  /// Incremented every physics step that applies the capture suction (or its
  /// end-of-window guarantee) to the winner. Tests assert this stays 0 until
  /// the capture phase starts.
  int winnerGuideApplications = 0;

  double get durationSeconds => _phaseShift + _idleDuration;
  int get durationMilliseconds => idleDurationMilliseconds;
  double get spinUpEndSeconds => _phaseShift + _spinUpEnd;
  double get mixingEndSeconds => _phaseShift + _mixingEnd;
  double get settlingEndSeconds => _phaseShift + _settlingEnd;
  double get captureEndSeconds => _phaseShift + _captureEnd;
  double get droppingEndSeconds => _phaseShift + _droppingEnd;

  double get fanPower =>
      (rotorSpeed / maxRotorRadiansPerSecond).clamp(0.0, 1.0);

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

    // A background/resume jump is deliberately not fully simulated. If the
    // controller has already completed, guarantee a valid in-app result rather
    // than leaving the selected ball suspended in the glass.
    if (target >= durationSeconds) {
      balls[winnerIndex]
        ..position = const Offset(0, winnerSeatY)
        ..velocity = Offset.zero;
    }

    _updatePresentation();
    return WhoPaysStepReport(
      physicsSteps: physicsSteps,
      droppedCatchUp: droppedCatchUp,
      maxImpactSpeed: maxImpactSpeed,
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
            : List<Offset>.generate(personCount, (index) {
                if (index == winnerIndex) {
                  return const Offset(0, winnerSeatY);
                }
                return _reducedMotionStartPositions[index];
              }),
      );
  }

  void _initializeBalls() {
    balls.clear();
    renderPositions.clear();
    _reducedMotionStartPositions.clear();
    bladeCollisionCount = 0;
    winnerGuideApplications = 0;

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

    _reducedMotionStartPositions.addAll(
      balls.map((ball) => ball.position),
    );
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

    for (var index = 0; index < balls.length; index++) {
      final ball = balls[index];
      final isWinner = index == winnerIndex;
      final winnerInTube =
          isWinner && capturing && ball.position.dy >= tubeEntryY;

      Offset acceleration;
      double dragRate;

      if (winnerInTube) {
        final centering = _clampMagnitude(
          Offset(-ball.position.dx * 260 - ball.velocity.dx * 26, 0),
          2600,
        );
        acceleration = centering + const Offset(0, chuteGravity);
        dragRate = tubeDragRate;
      } else {
        acceleration = const Offset(0, gravity);
        dragRate = settling ? settleDragRate : mixingDragRate;

        if (isWinner && capturing) {
          final ramp =
              ((drawTime - _settlingEnd) / (_captureEnd - _settlingEnd))
                  .clamp(0.0, 1.0);
          final limit = drawTime >= _captureEnd - _guaranteeWindow
              ? suctionGuaranteeMax
              : suctionRampMax * ramp;
          final pull =
              (mouthTarget - ball.position) * suctionSpringRate -
              ball.velocity * suctionDampingRate;
          acceleration += _clampMagnitude(pull, limit);
          winnerGuideApplications++;
        } else if (!isWinner &&
            capturing &&
            drawTime < _captureEnd &&
            stepGateProgress > 0.5) {
          final delta = ball.position - mouthTarget;
          final distance = delta.distance;
          if (distance < cushionRadius && distance > 0.001) {
            acceleration +=
                delta /
                distance *
                (cushionMax * (1 - distance / cushionRadius));
          }
        }
      }

      ball.velocity += acceleration * dt;
      ball.velocity *= exp(-dragRate * dt);
      ball.position += ball.velocity * dt;
    }

    var maxImpactSpeed = 0.0;
    for (var pass = 0; pass < 3; pass++) {
      maxImpactSpeed = max(
        maxImpactSpeed,
        _resolveBallCollisions(drawTime),
      );
      maxImpactSpeed = max(
        maxImpactSpeed,
        _resolveRotorCollisions(stepRotorAngle, stepRotorSpeed, drawTime),
      );
      maxImpactSpeed = max(
        maxImpactSpeed,
        _resolveBoundaries(drawTime),
      );
    }

    for (final ball in balls) {
      final speed = ball.velocity.distance;
      if (speed > maxBallSpeed) {
        ball.velocity = ball.velocity / speed * maxBallSpeed;
      }
    }
    return maxImpactSpeed;
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
        first.position -= normal * (overlap * 0.5);
        second.position += normal * (overlap * 0.5);

        final relativeVelocity = second.velocity - first.velocity;
        final normalSpeed = _dot(relativeVelocity, normal);
        if (normalSpeed >= 0) continue;

        maxImpactSpeed = max(maxImpactSpeed, -normalSpeed);
        final impulseMagnitude = -(1 + restitution) * normalSpeed / 2;
        final impulse = normal * impulseMagnitude;
        first.velocity -= impulse;
        second.velocity += impulse;
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
      if (ballIndex == winnerIndex &&
          drawTime >= _settlingEnd &&
          balls[ballIndex].position.dy >= tubeEntryY) {
        continue;
      }

      final ball = balls[ballIndex];
      final contact = _deepestRotorContact(ball.position, angle, ballIndex);
      if (contact == null) continue;

      ball.position += contact.normal * (contact.penetration + 0.05);
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

  double _resolveBoundaries(double drawTime) {
    var maxImpactSpeed = 0.0;

    for (var index = 0; index < balls.length; index++) {
      final ball = balls[index];
      final winnerInTube = index == winnerIndex &&
          drawTime >= _settlingEnd &&
          ball.position.dy >= tubeEntryY;

      if (winnerInTube) {
        if (ball.position.dx.abs() > chuteCenterHalfWidth) {
          final normal = Offset(ball.position.dx.sign, 0);
          ball.position = Offset(
            normal.dx * chuteCenterHalfWidth,
            ball.position.dy,
          );
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

  bool _overlapsRotor(
    Offset position,
    double angle, {
    double clearance = 0,
  }) {
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
    final t = seconds - _phaseShift;
    if (t <= _settlingEnd) return 0;
    if (t < _settlingEnd + _gateOpenLength) {
      return _smoothStep((t - _settlingEnd) / _gateOpenLength);
    }
    if (t < _gateCloseStart) return 1;
    if (t < _gateCloseEnd) {
      return 1 -
          _smoothStep((t - _gateCloseStart) / (_gateCloseEnd - _gateCloseStart));
    }
    return 0;
  }

  static Offset _closestPointOnSegment(
    Offset point,
    Offset start,
    Offset end,
  ) {
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
```

- [ ] **Step 4: main.dart bağlantısını güncelle**

`lib/main.dart` içindeki `_LotteryMachineState`'te üç düzenleme:

(a) `initState` içindeki controller kurulumunu şu hale getir:

```dart
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: _simulation.durationMilliseconds),
    );
```

(b) `_handleAnimationTick` içindeki `advanceTo` çağrısı:

```dart
    final report = _simulation.advanceTo(
      _controller.value * _simulation.durationSeconds,
    );
```

(c) `didChangeDependencies` içindeki süre satırı:

```dart
    _controller.duration = Duration(
      milliseconds: reduceMotion ? 180 : _simulation.durationMilliseconds,
    );
```

- [ ] **Step 5: Golden testinin örnekleme anlarını yeni zaman çizelgesine taşı**

`test/who_pays_lottery_golden_test.dart` içindeki dört `testWidgets` bloğunu şununla değiştir (yardımcılar aynen kalır):

```dart
  testWidgets('lottery machine idle appearance', (tester) async {
    await _expectMachineGolden(
      tester,
      seconds: 0,
      goldenName: 'who_pays_idle.png',
    );
  });

  testWidgets('lottery machine mixing appearance', (tester) async {
    await _expectMachineGolden(
      tester,
      seconds: 1.5,
      goldenName: 'who_pays_mixing.png',
    );
  });

  testWidgets('lottery machine capture appearance', (tester) async {
    await _expectMachineGolden(
      tester,
      seconds: 2.80,
      goldenName: 'who_pays_capture.png',
    );
  });

  testWidgets('lottery machine result appearance', (tester) async {
    await _expectMachineGolden(
      tester,
      seconds: 3.40,
      goldenName: 'who_pays_result.png',
    );
  });
```

Eski `who_pays_gate_opening.png` dosyasını sil:

```powershell
Remove-Item C:\xampp\htdocs\LUUQ\luuqapp\test\goldens\who_pays_gate_opening.png -Confirm:$false
```

- [ ] **Step 6: widget testinin pompalama sürelerini sabitten türet**

`test/widget_test.dart` içinde `await tester.pump(const Duration(milliseconds: 4100));` satırını şununla değiştir:

```dart
    await tester.pump(
      Duration(
        milliseconds: WhoPaysLotterySimulation.idleDurationMilliseconds + 200,
      ),
    );
```

ve dosyanın import bloğuna ekle:

```dart
import 'package:luuqapp/src/who_pays/lottery_simulation.dart';
```

- [ ] **Step 7: Birim testler geçsin**

Run: `flutter test test/who_pays_lottery_simulation_test.dart`
Expected: PASS (kazanan-oturma taraması dahil). Kuvvet sabitleri yetmezse yalnızca `suctionSpringRate`/`suctionRampMax`/`cushionMax` ayarlanabilir; faz sınırları değişmez.

- [ ] **Step 8: Golden'ları yeniden üret ve tam suite çalıştır**

Run: `flutter test --update-goldens test/who_pays_lottery_golden_test.dart`
Expected: PASS.

Run: `flutter test`
Expected: tümü PASS.

Run: `flutter analyze`
Expected: `No issues found`.

- [ ] **Step 9: Commit**

```powershell
git -C C:\xampp\htdocs\LUUQ add -A
git -C C:\xampp\htdocs\LUUQ commit -m @'
feat(who_pays): late-capture choreography with a neutral mix

The winner is no longer staged early: all balls settle naturally, the gate
opens, a short suction pulls the winning ball through the mouth and the gate
closes behind it. The controller now reads the simulation duration, fixing
the 15% slow-motion mismatch.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
'@
```

---

### Task 3: Huni — teleportsuz tüp girişi

**Files:**
- Modify: `lib/src/who_pays/lottery_simulation.dart` (`chuteCenterHalfWidth` yerine huni)
- Test: `test/who_pays_lottery_simulation_test.dart` (yeni invaryant testleri)

**Interfaces:**
- Consumes: Task 2'nin `tubeEntryY`, `winnerSeatY`, `_resolveBoundaries(drawTime)` yapısı.
- Produces: `static double funnelHalfWidthAt(double dy)` (public, testler çağırır), statikler `tubeHalfWidth = 4.0`, `funnelBottomY = 133.0`, `funnelTopHalfWidth = 38.0`.

- [ ] **Step 1: Başarısız testleri yaz**

`test/who_pays_lottery_simulation_test.dart` içindeki `group('WhoPaysLotterySimulation', ...)` bloğunun sonuna (son testten sonra) ekle:

```dart
    test('funnel half-width narrows monotonically to the tube', () {
      expect(
        WhoPaysLotterySimulation.funnelHalfWidthAt(90),
        WhoPaysLotterySimulation.funnelTopHalfWidth,
      );
      expect(
        WhoPaysLotterySimulation.funnelHalfWidthAt(140),
        WhoPaysLotterySimulation.tubeHalfWidth,
      );
      var previous = WhoPaysLotterySimulation.funnelHalfWidthAt(100);
      for (var dy = 101.0; dy <= 133.0; dy += 1.0) {
        final current = WhoPaysLotterySimulation.funnelHalfWidthAt(dy);
        expect(current, lessThanOrEqualTo(previous));
        previous = current;
      }
    });

    for (final seed in const <int>[3, 811, 42424]) {
      test('no ball teleports at 60 fps playback (seed $seed)', () {
        final simulation = WhoPaysLotterySimulation(
          personCount: 6,
          winnerIndex: seed % 6,
          seed: seed,
        );

        var previous = List<Offset>.from(simulation.renderPositions);
        var target = 0.0;
        while (target < simulation.durationSeconds) {
          target = math.min(target + 1 / 60, simulation.durationSeconds);
          simulation.advanceTo(target);
          for (var index = 0; index < simulation.personCount; index++) {
            final jump =
                (simulation.renderPositions[index] - previous[index]).distance;
            expect(
              jump,
              lessThanOrEqualTo(24),
              reason: 'ball $index jumped ${jump.toStringAsFixed(1)} px '
                  'at ${target.toStringAsFixed(2)} s',
            );
          }
          previous = List<Offset>.from(simulation.renderPositions);
        }
      });
    }

    test('the winner respects the funnel walls on the way down', () {
      final simulation = WhoPaysLotterySimulation(
        personCount: 6,
        winnerIndex: 5,
        seed: 606,
      );

      var target = 0.0;
      while (target < simulation.durationSeconds) {
        target = math.min(target + 1 / 120, simulation.durationSeconds);
        simulation.advanceTo(target);
        final winner = simulation.renderPositions[5];
        if (winner.dy >= WhoPaysLotterySimulation.tubeEntryY) {
          expect(
            winner.dx.abs(),
            lessThanOrEqualTo(
              WhoPaysLotterySimulation.funnelHalfWidthAt(winner.dy) + 0.5,
            ),
          );
        }
      }
    });
```

Not: teleport testi kazananın son-kare garantisini de kapsar — 60 fps oynatımda garanti satırı topu zıplatıyorsa test yakalar.

- [ ] **Step 2: Başarısızlığı doğrula**

Run: `flutter test test/who_pays_lottery_simulation_test.dart`
Expected: FAIL — `funnelHalfWidthAt` tanımsız (derleme hatası).

- [ ] **Step 3: Huniyi uygula**

`lib/src/who_pays/lottery_simulation.dart` içinde:

(a) Sabit bloğundaki şu iki satırı:

```dart
  static const double tubeEntryY = 100.0;
  static const double chuteCenterHalfWidth = 3.5;
```

şununla değiştir:

```dart
  static const double tubeEntryY = 100.0;
  static const double funnelBottomY = 133.0;
  static const double funnelTopHalfWidth = 38.0;
  static const double tubeHalfWidth = 4.0;
```

(b) Sınıfın statik yardımcılarına (örneğin `bladeSpinePoints` yakınına) ekle:

```dart
  /// Allowed center half-width for a ball travelling the mouth funnel. Wide at
  /// the chamber floor, narrowing linearly to the tube so per-step wall
  /// projections stay tiny and no visible teleport can occur.
  static double funnelHalfWidthAt(double dy) {
    if (dy >= funnelBottomY) return tubeHalfWidth;
    if (dy <= tubeEntryY) return funnelTopHalfWidth;
    final t = (dy - tubeEntryY) / (funnelBottomY - tubeEntryY);
    return funnelTopHalfWidth + (tubeHalfWidth - funnelTopHalfWidth) * t;
  }
```

(c) `_resolveBoundaries` içindeki `winnerInTube` bloğunu şununla değiştir:

```dart
      if (winnerInTube) {
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
```

- [ ] **Step 4: Testler geçsin**

Run: `flutter test test/who_pays_lottery_simulation_test.dart`
Expected: PASS.

Run: `flutter test --update-goldens test/who_pays_lottery_golden_test.dart`
Expected: PASS (capture karesi değişebilir).

Run: `flutter test` ve `flutter analyze`
Expected: tümü PASS / `No issues found`.

- [ ] **Step 5: Commit**

```powershell
git -C C:\xampp\htdocs\LUUQ add -A
git -C C:\xampp\htdocs\LUUQ commit -m @'
fix(who_pays): funnel the tube mouth instead of hard-clamping x

Replaces the 3.5 px center clamp with a continuous funnel wall so the winning
ball can never teleport sideways at the chute entrance. Adds per-frame
displacement and funnel-adherence invariant tests.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
'@
```

---

### Task 4: Resume garantisi — kaybedenler tabana oturur

**Files:**
- Modify: `lib/src/who_pays/lottery_simulation.dart` (`advanceTo` son-jump bloğu + `_settleLosersToFloor`)
- Test: `test/who_pays_lottery_simulation_test.dart`

**Interfaces:**
- Consumes: Task 2/3'ün `advanceTo` yapısı, `maxBallCenterRadius`.
- Produces: `static const List<double> floorSlotAngles` (5 açı; Task 5 reduced-motion'da yeniden kullanır) ve `_settleLosersToFloor()` özel metodu.

- [ ] **Step 1: Başarısız testleri yaz**

Simülasyon test grubunun sonuna ekle:

```dart
    test('a resume jump leaves no loser suspended mid-air', () {
      final simulation = WhoPaysLotterySimulation(
        personCount: 6,
        winnerIndex: 2,
        seed: 8080,
      );

      _advanceInFrames(simulation, 1.2); // karışımın ortası
      simulation.advanceTo(simulation.durationSeconds); // arka plan sıçraması

      expect(simulation.phase, WhoPaysLotteryPhase.seated);
      expect(simulation.gateProgress, 0);
      expect(simulation.renderPositions[2], const Offset(0, 209));
      for (var index = 0; index < simulation.personCount; index++) {
        if (index == 2) continue;
        final position = simulation.renderPositions[index];
        expect(
          position.distance,
          closeTo(WhoPaysLotterySimulation.maxBallCenterRadius, 0.001),
          reason: 'loser $index is not resting on the floor arc',
        );
        expect(position.dy, greaterThan(30));
        expect(simulation.balls[index].velocity, Offset.zero);
      }
    });

    test('continuous playback does not snap losers on the final frame', () {
      final simulation = WhoPaysLotterySimulation(
        personCount: 6,
        winnerIndex: 0,
        seed: 121212,
      );

      _advanceInFrames(simulation, simulation.durationSeconds - 1 / 60);
      final before = List<Offset>.from(simulation.renderPositions);
      simulation.advanceTo(simulation.durationSeconds);

      for (var index = 1; index < simulation.personCount; index++) {
        expect(
          (simulation.renderPositions[index] - before[index]).distance,
          lessThanOrEqualTo(24),
          reason: 'loser $index snapped on the final frame',
        );
      }
    });
```

- [ ] **Step 2: Başarısızlığı doğrula**

Run: `flutter test test/who_pays_lottery_simulation_test.dart`
Expected: FAIL — ilk yeni test kaybedenleri havada bulur.

- [ ] **Step 3: Yerleştirmeyi uygula**

`lib/src/who_pays/lottery_simulation.dart`:

(a) Sabitlere ekle (`winnerSeatY` satırının altına):

```dart
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
```

(b) `advanceTo` içindeki son-jump garantisini şununla değiştir:

```dart
    if (target >= durationSeconds) {
      balls[winnerIndex]
        ..position = const Offset(0, winnerSeatY)
        ..velocity = Offset.zero;
      final losersUnsettled = droppedCatchUp ||
          balls.asMap().entries.any(
            (entry) =>
                entry.key != winnerIndex &&
                entry.value.velocity.distance > 150,
          );
      if (losersUnsettled) {
        _settleLosersToFloor();
      }
    }
```

(c) Sınıfa özel metodu ekle:

```dart
  /// Deterministically parks every loser on the floor arc. Used only when the
  /// timeline finishes via a resume/background jump, so the last frame never
  /// shows balls frozen mid-air.
  void _settleLosersToFloor() {
    final used = List<bool>.filled(floorSlotAngles.length, false);
    for (var index = 0; index < balls.length; index++) {
      if (index == winnerIndex) continue;
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
```

- [ ] **Step 4: Testler geçsin**

Run: `flutter test test/who_pays_lottery_simulation_test.dart`
Expected: PASS (ikinci test, sürekli oynatımda `losersUnsettled`'ın false kaldığını kanıtlar).

Run: `flutter test` ve `flutter analyze`
Expected: tümü PASS / `No issues found`.

- [ ] **Step 5: Commit**

```powershell
git -C C:\xampp\htdocs\LUUQ add -A
git -C C:\xampp\htdocs\LUUQ commit -m @'
fix(who_pays): settle losers onto the floor after a resume jump

A background/resume jump now parks every losing ball on a deterministic
floor-arc slot instead of leaving them frozen mid-air. Continuous playback is
untouched: the settle only triggers on a dropped catch-up or fast leftovers.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
'@
```

---

### Task 5: Süreklilik — WhoPaysInitialState, exportState, intake fazı

**Files:**
- Modify: `lib/src/who_pays/lottery_simulation.dart`
- Test: `test/who_pays_lottery_simulation_test.dart`

**Interfaces:**
- Consumes: Task 2–4'ün tamamı (`_phaseShift`, huni, `floorSlotAngles`).
- Produces (Task 6 bunları kullanır):
  - `class WhoPaysInitialState { const WhoPaysInitialState({required List<Offset> chamberPositions, int? seatedBallIndex}); }`
  - Yapıcı parametresi `WhoPaysInitialState? initialState`
  - `WhoPaysInitialState exportState()`
  - Statikler: `double intakeDurationSeconds = 0.45`, `int redrawDurationMilliseconds = 3850`
  - `durationMilliseconds` artık intake varsa 3850 döndürür.

- [ ] **Step 1: Başarısız testleri yaz**

Simülasyon test grubunun sonuna ekle:

```dart
    test('exportState captures seated results for the next draw', () {
      final first = WhoPaysLotterySimulation(
        personCount: 4,
        winnerIndex: 3,
        seed: 2024,
      );
      _advanceInFrames(first, first.durationSeconds);

      final state = first.exportState();
      expect(state.seatedBallIndex, 3);
      expect(state.chamberPositions.length, 4);

      final second = WhoPaysLotterySimulation(
        personCount: 4,
        winnerIndex: 1,
        seed: 9,
        initialState: state,
      );
      expect(second.durationMilliseconds,
          WhoPaysLotterySimulation.redrawDurationMilliseconds);
      expect(second.durationSeconds, closeTo(3.85, 1e-9));
      expect(second.renderPositions[3], const Offset(0, 209));
      for (var index = 0; index < 4; index++) {
        if (index == 3) continue;
        expect(second.renderPositions[index], state.chamberPositions[index]);
      }
    });

    test('the intake ball is pulled back into the chamber', () {
      final first = WhoPaysLotterySimulation(
        personCount: 6,
        winnerIndex: 0,
        seed: 31337,
      );
      _advanceInFrames(first, first.durationSeconds);

      final second = WhoPaysLotterySimulation(
        personCount: 6,
        winnerIndex: 4,
        seed: 555,
        initialState: first.exportState(),
      );

      _advanceInFrames(second, 0.10);
      expect(second.phase, WhoPaysLotteryPhase.intake);
      expect(second.gateProgress, greaterThan(0.5));

      _advanceInFrames(second, 0.40);
      expect(
        second.renderPositions[0].dy,
        lessThan(WhoPaysLotterySimulation.tubeEntryY),
        reason: 'intake ball should be back in the chamber',
      );

      _advanceInFrames(second, WhoPaysLotterySimulation.intakeDurationSeconds);
      expect(second.gateProgress, 0);
    });

    for (var personCount = 2; personCount <= 6; personCount++) {
      for (final seed in const <int>[11, 7302]) {
        test('redraw $personCount/$seed seats the new winner cleanly', () {
          final first = WhoPaysLotterySimulation(
            personCount: personCount,
            winnerIndex: seed % personCount,
            seed: seed,
          );
          _advanceInFrames(first, first.durationSeconds);

          final winnerIndex = (seed + 1) % personCount;
          final second = WhoPaysLotterySimulation(
            personCount: personCount,
            winnerIndex: winnerIndex,
            seed: seed * 31,
            initialState: first.exportState(),
          );

          var previous = List<Offset>.from(second.renderPositions);
          var target = 0.0;
          while (target < second.durationSeconds) {
            target = math.min(target + 1 / 60, second.durationSeconds);
            second.advanceTo(target);
            for (var index = 0; index < personCount; index++) {
              expect(
                (second.renderPositions[index] - previous[index]).distance,
                lessThanOrEqualTo(24),
                reason: 'redraw ball $index teleported at $target s',
              );
            }
            previous = List<Offset>.from(second.renderPositions);
          }

          expect(second.phase, WhoPaysLotteryPhase.seated);
          expect(second.gateProgress, 0);
          expect(second.renderPositions[winnerIndex], const Offset(0, 209));
        });
      }
    }

    test('winner neutrality also holds during a redraw intake', () {
      final first = WhoPaysLotterySimulation(
        personCount: 5,
        winnerIndex: 2,
        seed: 640,
      );
      _advanceInFrames(first, first.durationSeconds);

      final second = WhoPaysLotterySimulation(
        personCount: 5,
        winnerIndex: 2, // aynı top üst üste kazanabilir
        seed: 641,
        initialState: first.exportState(),
      );
      _advanceInFrames(second, second.settlingEndSeconds - 0.001);
      expect(second.winnerGuideApplications, 0);
      _advanceInFrames(second, second.durationSeconds);
      expect(second.renderPositions[2], const Offset(0, 209));
    });

    test('reduced motion honours the initial state', () {
      final first = WhoPaysLotterySimulation(
        personCount: 4,
        winnerIndex: 0,
        seed: 12321,
      );
      _advanceInFrames(first, first.durationSeconds);

      final second = WhoPaysLotterySimulation(
        personCount: 4,
        winnerIndex: 2,
        seed: 5,
        initialState: first.exportState(),
      );
      second.advanceReducedMotion(0);
      expect(second.renderPositions[0], const Offset(0, 209));

      second.advanceReducedMotion(1);
      expect(second.phase, WhoPaysLotteryPhase.seated);
      expect(second.gateProgress, 0);
      expect(second.renderPositions[2], const Offset(0, 209));
      expect(
        second.renderPositions[0].distance,
        lessThanOrEqualTo(WhoPaysLotterySimulation.maxBallCenterRadius + 0.001),
        reason: 'previous winner must end up back inside the chamber',
      );
    });
```

- [ ] **Step 2: Başarısızlığı doğrula**

Run: `flutter test test/who_pays_lottery_simulation_test.dart`
Expected: FAIL — `WhoPaysInitialState`/`exportState` tanımsız (derleme hatası).

- [ ] **Step 3: Süreklilik API'sini uygula**

`lib/src/who_pays/lottery_simulation.dart` düzenlemeleri:

(a) Dosyanın sonuna (sınıf dışına) ekle:

```dart
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
```

(b) Yapıcıyı şununla değiştir:

```dart
  WhoPaysLotterySimulation({
    required this.personCount,
    required this.winnerIndex,
    required this.seed,
    WhoPaysInitialState? initialState,
  }) : assert(personCount >= 2 && personCount <= 6),
       assert(winnerIndex >= 0 && winnerIndex < personCount),
       assert(
         initialState == null ||
             initialState.chamberPositions.length == personCount,
       ),
       _random = Random(seed),
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
```

(c) Alan ve sabit değişiklikleri:

```dart
  static const double intakeDurationSeconds = 0.45;
  static const int redrawDurationMilliseconds = 3850;
  static const double _intakeSuction = 3400.0;
  static const double _intakePullStart = 0.06;
  static const double _intakeGateOpenEnd = 0.12;
  static const double _intakeGateCloseStart = 0.34;
  static const double _intakeReleaseY = 95.0;
```

`final double _phaseShift = 0;` satırını sil (artık yapıcıda atanıyor) ve yerine alan bildirimlerini koy:

```dart
  final double _phaseShift;
  final int? _intakeBallIndex;
  bool _intakeReleased = false;
```

`durationMilliseconds` getter'ı:

```dart
  int get durationMilliseconds => _phaseShift > 0
      ? redrawDurationMilliseconds
      : idleDurationMilliseconds;
```

(d) `exportState` metodu (`advanceReducedMotion`'ın üstüne):

```dart
  WhoPaysInitialState exportState() {
    return WhoPaysInitialState(
      chamberPositions: List<Offset>.unmodifiable(
        balls.map((ball) => ball.position),
      ),
      seatedBallIndex:
          phase == WhoPaysLotteryPhase.seated ? winnerIndex : null,
    );
  }
```

(e) `_stepPhysics` içinde, top döngüsünün başındaki `final winnerInTube = ...` satırından önce intake dalını ekle ve kuvvet seçimini şu yapıya getir:

```dart
      final intakeActive = _phaseShift > 0 &&
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
      } else if (winnerInTube) {
```

(devamı mevcut `winnerInTube` gövdesi; `else {` dalı aynen kalır). Pozisyon güncellemesinden sonra (döngü içinde, `ball.position += ball.velocity * dt;` satırının hemen ardından) ekle:

```dart
      if (index == _intakeBallIndex &&
          !_intakeReleased &&
          ball.position.dy < _intakeReleaseY) {
        _intakeReleased = true;
      }
```

(f) `_resolveBoundaries` içindeki `winnerInTube` hesabını huni erişimini intake topuna da verecek şekilde genişlet:

```dart
      final winnerInTube = index == winnerIndex &&
          drawTime >= _settlingEnd &&
          ball.position.dy >= tubeEntryY;
      final intakeInTube = index == _intakeBallIndex &&
          !_intakeReleased &&
          _phaseShift > 0 &&
          ball.position.dy >= tubeEntryY;

      if (winnerInTube || intakeInTube) {
```

(yalnız koşul satırları değişir; blok gövdesi Task 3'teki huni kodudur. `ball.position.dy >= winnerSeatY` oturma clamp'i intake topu için de zararsızdır: top yukarı giderken tetiklenmez.)

(g) `_resolveRotorCollisions` içindeki atlama koşulunu genişlet:

```dart
      final ball = balls[ballIndex];
      final skipAsWinnerInTube = ballIndex == winnerIndex &&
          drawTime >= _settlingEnd &&
          ball.position.dy >= tubeEntryY;
      final skipAsIntakeBall = ballIndex == _intakeBallIndex &&
          !_intakeReleased &&
          _phaseShift > 0 &&
          ball.position.dy >= tubeEntryY;
      if (skipAsWinnerInTube || skipAsIntakeBall) continue;
```

(mevcut `if (ballIndex == winnerIndex && ...) continue;` bloğunun yerine; `final ball = ...` satırı yukarı taşınır.)

(h) `_gateProgressAt` başına intake penceresini ekle:

```dart
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
    ...
```

(kalanı mevcut gövde).

(i) `advanceReducedMotion` bitiş listesinde önceki kazananı fanusa yerleştir — metodu şununla değiştir:

```dart
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

  List<Offset> _reducedMotionEndPositions() {
    final positions = List<Offset>.from(_reducedMotionStartPositions);
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
```

(j) `_initializeBalls` içindeki `winnerGuideApplications = 0;` ve `_intakeReleased` sıfırlaması: `_initializeBalls` yalnız temiz başlangıçta çağrıldığından `_intakeReleased = false` alan başlangıç değeri yeterlidir; ek değişiklik gerekmez.

- [ ] **Step 4: Testler geçsin**

Run: `flutter test test/who_pays_lottery_simulation_test.dart`
Expected: PASS. (Intake topu 0.40'ta fanusa dönmüyorsa yalnız `_intakeSuction` artırılabilir.)

Run: `flutter test` ve `flutter analyze`
Expected: tümü PASS / `No issues found`.

- [ ] **Step 5: Commit**

```powershell
git -C C:\xampp\htdocs\LUUQ add -A
git -C C:\xampp\htdocs\LUUQ commit -m @'
feat(who_pays): continuous redraws via exportState/initialState

A finished draw can now seed the next one: the gate reopens, the seated ball
is sucked back up the tube, and mixing starts from the previous resting
layout. Redraw timeline is 3850 ms with a 450 ms intake prologue.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
'@
```

---

### Task 6: main.dart bağlantısı + widget testinde "Tekrar Çek" akışı

**Files:**
- Modify: `lib/main.dart:5183-5197` (`_LotteryMachineState.didUpdateWidget` ve süre yönetimi)
- Test: `test/widget_test.dart`

**Interfaces:**
- Consumes: Task 5'in `exportState()`, `initialState`, örnek `durationMilliseconds`.
- Produces: yok (son kablolama).

- [ ] **Step 1: Widget testine yeniden çekiliş akışını ekle (başarısız olacak — süre yetmez)**

`test/widget_test.dart` içindeki `who pays draw keeps a visible winning ball and result` testinde, `expect(find.text('Tekrar Çek'), findsOneWidget);` satırından sonra (ve `expect(tester.takeException(), isNull);` satırından önce) ekle:

```dart
    // Yeniden çekiliş: sonuç topu geri emilir, yeni çekiliş tam süre oynar.
    await tester.tap(find.text('Tekrar Çek'));
    await tester.pump();
    expect(find.text('KARILIYOR...'), findsOneWidget);

    await tester.pump(
      Duration(
        milliseconds:
            WhoPaysLotterySimulation.redrawDurationMilliseconds + 200,
      ),
    );
    await tester.pump();

    expect(
      find.textContaining(RegExp(r'^Hesap [1-6]\. kişide! 🎉$')),
      findsOneWidget,
    );
    expect(find.text('Tekrar Çek'), findsOneWidget);
```

- [ ] **Step 2: Başarısızlığı doğrula**

Run: `flutter test test/widget_test.dart`
Expected: FAIL — controller hâlâ 3400 ms tabanlı olduğundan yeniden çekiliş 3850 ms'lik simülasyonu erken keser ve/veya `initialState` geçilmediği için süre uyuşmazlığı oluşur. (Test tam süre dolmadan sonuç bulamayabilir; hangi assertion düştüğü fark etmez, kırmızı olması yeterli.)

- [ ] **Step 3: Bağlantıyı uygula**

`lib/main.dart` içindeki `_LotteryMachineState`'e özel yardımcı ekle (örneğin `_createSimulation`'ın altına):

```dart
  void _syncControllerDuration() {
    _controller.duration = Duration(
      milliseconds: _reduceMotion ? 180 : _simulation.durationMilliseconds,
    );
  }
```

`didUpdateWidget`'ı şununla değiştir:

```dart
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
        initialState: previous.personCount == widget.personCount &&
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
```

`didChangeDependencies` içindeki süre satırını da yardımcıya bağla:

```dart
    _reduceMotion = reduceMotion;
    _syncControllerDuration();
```

- [ ] **Step 4: Testler geçsin**

Run: `flutter test test/widget_test.dart`
Expected: PASS.

Run: `flutter test` ve `flutter analyze`
Expected: tümü PASS / `No issues found`.

- [ ] **Step 5: Commit**

```powershell
git -C C:\xampp\htdocs\LUUQ add -A
git -C C:\xampp\htdocs\LUUQ commit -m @'
feat(who_pays): wire redraw continuity into the dialog

Draw Again now hands the finished layout to the next simulation and the
controller reads the per-draw duration (3400 ms idle / 3850 ms redraw).

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
'@
```

---

### Task 7: Final doğrulama

**Files:**
- Modify: yok (yalnız doğrulama ve gerekiyorsa format düzeltmeleri)

**Interfaces:**
- Consumes: tüm önceki görevler.

- [ ] **Step 1: Format ve statik analiz**

Run: `dart format lib/src/who_pays/lottery_simulation.dart lib/src/who_pays/lottery_machine_view.dart lib/main.dart test/who_pays_lottery_simulation_test.dart test/who_pays_lottery_golden_test.dart test/widget_test.dart`
Expected: değişen dosya varsa formatlanır.

Run: `flutter analyze`
Expected: `No issues found`.

- [ ] **Step 2: Golden'ları son kez üret ve gözle doğrula**

Run: `flutter test --update-goldens test/who_pays_lottery_golden_test.dart`

`test/goldens/` altındaki dört PNG'yi aç ve kontrol et: idle karesinde kapak kapalı; mixing karesinde toplar dağınık; capture karesinde kapak açık ve kazanan ağza yakın; result karesinde kazanan yuvada cam tabana teğet, kapak kapalı, kaybedenler tabanda.

- [ ] **Step 3: Tam test paketi**

Run: `flutter test`
Expected: tüm testler PASS.

- [ ] **Step 4: Kabul kriterlerini spec'e karşı işaretle**

Spec'teki 5 kabul kriterini tek tek doğrula (1: analyze/test; 2: koreografi — golden + birim testler; 3: yeniden çekiliş — widget + simülasyon testleri; 4: süre senkronu — Task 2/6; 5: resume — Task 4). Uygulama içi manuel doğrulama (2 ve 6 kişiyle çekiliş + Tekrar Çek) kullanıcıya bırakılır; hazır olduğunu raporla.

- [ ] **Step 5: Format değişikliği olduysa commit**

```powershell
git -C C:\xampp\htdocs\LUUQ add -A
git -C C:\xampp\htdocs\LUUQ commit -m @'
chore(who_pays): final formatting pass for the mechanics rework

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
'@
```

(Değişiklik yoksa bu adım atlanır.)
