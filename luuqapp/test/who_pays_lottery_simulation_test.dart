import 'dart:math' as math;

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

          var target = simulation.timelineSeconds;
          Offset? preFinalWinnerPosition;
          while (target < simulation.durationSeconds) {
            final nextTarget = math.min(
              target + 1 / 60,
              simulation.durationSeconds,
            );
            final isFinalFrame = nextTarget >= simulation.durationSeconds;
            target = nextTarget;
            simulation.advanceTo(target);
            if (!isFinalFrame) {
              preFinalWinnerPosition = simulation.renderPositions[winnerIndex];
            }
          }

          // The end-of-timeline seat guarantee must be a safety net for
          // resume jumps, not part of normal playback.
          expect(
            (preFinalWinnerPosition! - const Offset(0, 209)).distance,
            lessThanOrEqualTo(24),
            reason:
                'winner $personCount/$seed was not physically seated before '
                'the final frame',
          );

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
          // Rotor-active phases: a full-speed blade strike can legitimately
          // move a ball ~25 px in one frame — not a teleport. After the rotor
          // stops (settling onward: capture, funnel, drop), constraint
          // projection is the only jump source, so the tight bound applies.
          final bound =
              target < simulation.settlingEndSeconds ? 32.0 : 24.0;
          for (var index = 0; index < simulation.personCount; index++) {
            final jump =
                (simulation.renderPositions[index] - previous[index]).distance;
            expect(
              jump,
              lessThanOrEqualTo(bound),
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
