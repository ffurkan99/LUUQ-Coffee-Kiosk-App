import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:luuqapp/src/who_pays/lottery_simulation.dart';

void main() {
  group('WhoPaysLotterySimulation', () {
    for (var personCount = 2; personCount <= 6; personCount++) {
      test('$personCount balls start inside the cage without overlap', () {
        final simulation = WhoPaysLotterySimulation(
          personCount: personCount,
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

    test('the same seed produces the same simulation and the same winner', () {
      final first = WhoPaysLotterySimulation(personCount: 6, seed: 1842);
      final second = WhoPaysLotterySimulation(personCount: 6, seed: 1842);

      _advanceInFrames(first, 2.5);
      _advanceInFrames(second, 2.5);

      expect(first.rotorAngle, second.rotorAngle);
      expect(first.renderPositions, second.renderPositions);
      expect(
        first.balls.map((ball) => ball.velocity).toList(),
        second.balls.map((ball) => ball.velocity).toList(),
      );

      _advanceInFrames(first, first.durationSeconds);
      _advanceInFrames(second, second.durationSeconds);
      expect(first.capturedBallIndex, isNotNull);
      expect(first.capturedBallIndex, second.capturedBallIndex);
    });

    test('timeline phases follow the approved choreography', () {
      final simulation = WhoPaysLotterySimulation(personCount: 4, seed: 5);

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

    // Total tarafsızlık: yakalama ataması gerçekleşene kadar hiçbir topa
    // endekse-koşullu kuvvet uygulanamaz. Kazanan, kuvvetlerin değil
    // geometrinin sonucudur.
    for (final seed in const <int>[314159, 424242]) {
      test('no index-conditioned force fires before capture ($seed)', () {
        final simulation = WhoPaysLotterySimulation(
          personCount: 6,
          seed: seed,
        );

        var target = 0.0;
        while (target < simulation.durationSeconds - 1e-9) {
          target = math.min(target + 1 / 60, simulation.durationSeconds);
          simulation.advanceTo(target);
          if (simulation.capturedBallIndex == null) {
            expect(
              simulation.targetedForceApplications,
              0,
              reason: 'neutrality broken at ${target.toStringAsFixed(2)}s',
            );
          }
        }
        expect(simulation.capturedBallIndex, isNotNull);
      });
    }

    test('the gate opens during capture and is closed at the end', () {
      final simulation = WhoPaysLotterySimulation(personCount: 3, seed: 42);

      _advanceInFrames(simulation, 2.50);
      expect(simulation.gateProgress, 0);
      _advanceInFrames(simulation, 2.72);
      expect(simulation.gateProgress, 1);
      _advanceInFrames(simulation, simulation.durationSeconds);
      expect(simulation.gateProgress, 0);
    });

    test('balls remain finite, separated, and inside the glass', () {
      final simulation = WhoPaysLotterySimulation(personCount: 6, seed: 99173);

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
      final simulation = WhoPaysLotterySimulation(personCount: 4, seed: 77);

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
      final simulation = WhoPaysLotterySimulation(personCount: 3, seed: 12);

      expect(simulation.fanPower, 0);
      simulation.advanceTo(simulation.spinUpEndSeconds);
      expect(simulation.fanPower, closeTo(1, 0.0001));
      simulation.advanceTo(simulation.settlingEndSeconds);
      expect(simulation.fanPower, 0);
      expect(simulation.rotorSpeed, 0);
    });

    // Fizik-öncelikli çekirdek sözleşme: her çekilişte fizik tam bir top
    // yakalar, tüp boğazından yalnız o geçer ve donma karesinden önce
    // fiziksel olarak yuvaya varır.
    for (var personCount = 2; personCount <= 6; personCount++) {
      for (final seed in const <int>[1, 97, 5000, 977351]) {
        test('draw $personCount/$seed captures exactly one ball and seats it',
            () {
          final simulation = WhoPaysLotterySimulation(
            personCount: personCount,
            seed: seed,
          );

          final crossedThroat = <int>{};
          List<Offset>? preFinalPositions;
          var target = simulation.timelineSeconds;
          while (target < simulation.durationSeconds) {
            final nextTarget = math.min(
              target + 1 / 60,
              simulation.durationSeconds,
            );
            final isFinalFrame = nextTarget >= simulation.durationSeconds;
            target = nextTarget;
            simulation.advanceTo(target);
            for (var i = 0; i < personCount; i++) {
              if (simulation.renderPositions[i].dy >=
                  WhoPaysLotterySimulation.funnelBottomY) {
                crossedThroat.add(i);
              }
            }
            if (!isFinalFrame) {
              preFinalPositions = List<Offset>.from(simulation.renderPositions);
            }
          }

          final captured = simulation.capturedBallIndex;
          expect(captured, isNotNull, reason: 'no ball was captured');
          expect(
            crossedThroat,
            {captured},
            reason: 'only the captured ball may pass the tube throat',
          );

          // The end-of-timeline seat guarantee must be a safety net for
          // resume jumps, not part of normal playback.
          expect(
            (preFinalPositions![captured!] - const Offset(0, 209)).distance,
            lessThanOrEqualTo(24),
            reason:
                'captured ball $personCount/$seed was not physically seated '
                'before the final frame',
          );

          expect(simulation.phase, WhoPaysLotteryPhase.seated);
          expect(simulation.gateProgress, 0);
          expect(simulation.renderPositions[captured].dx, closeTo(0, 0.001));
          expect(simulation.renderPositions[captured].dy, closeTo(209, 0.001));
          for (var index = 0; index < simulation.personCount; index++) {
            if (index == captured) continue;
            expect(
              simulation.renderPositions[index].distance,
              lessThanOrEqualTo(
                WhoPaysLotterySimulation.maxBallCenterRadius + 0.001,
              ),
            );
          }

          for (var first = 0; first < simulation.personCount; first++) {
            if (first == captured) continue;
            for (
              var second = first + 1;
              second < simulation.personCount;
              second++
            ) {
              if (second == captured) continue;
              expect(
                (simulation.renderPositions[first] -
                        simulation.renderPositions[second])
                    .distance,
                greaterThanOrEqualTo(41),
                reason:
                    'losers $first and $second end-state overlap for '
                    'draw $personCount/$seed',
              );
            }
          }
        });
      }
    }

    // Ağız yalnız yakalanan topu kabul eder: atamadan sonra, kapak anlamlı
    // şekilde açıkken, başka hiçbir top huninin derinliğinde oyalanamaz
    // (keepout tahliyesi onu birkaç karede yana süpürmelidir).
    for (final seed in const <int>[1, 3, 97, 5000, 42424, 977351]) {
      for (final personCount in const <int>[4, 6]) {
        test('mouth admits only the captured ball ($personCount/$seed)', () {
          final simulation = WhoPaysLotterySimulation(
            personCount: personCount,
            seed: seed,
          );

          var target = 0.0;
          final consecutiveDeep = List<int>.filled(personCount, 0);
          while (target < simulation.durationSeconds) {
            target = math.min(target + 1 / 60, simulation.durationSeconds);
            simulation.advanceTo(target);
            final captured = simulation.capturedBallIndex;
            if (captured == null || simulation.gateProgress <= 0.15) {
              continue;
            }
            for (var i = 0; i < personCount; i++) {
              if (i == captured) continue;
              final ball = simulation.renderPositions[i];
              final deepInFunnel =
                  ball.dy >= WhoPaysLotterySimulation.tubeEntryY + 6 &&
                  ball.dx.abs() <= 24;
              consecutiveDeep[i] = deepInFunnel ? consecutiveDeep[i] + 1 : 0;
              expect(
                consecutiveDeep[i],
                lessThan(9),
                reason:
                    'ball $i lingers in the open funnel at '
                    '${target.toStringAsFixed(2)}s '
                    '(${ball.dx.toStringAsFixed(0)}, ${ball.dy.toStringAsFixed(0)})',
              );
            }
          }
        });
      }
    }

    // Kapak, tüpten inen topun üstünden kapanamaz: kapanış süpürmesi
    // sırasında yakalanan top çubuğun süpürme bandında (dy 112-154) olamaz.
    for (final seed in const <int>[1, 97, 5000, 977351]) {
      for (final personCount in const <int>[2, 4, 6]) {
        test('gate never closes through the captured ball ($personCount/$seed)',
            () {
          final simulation = WhoPaysLotterySimulation(
            personCount: personCount,
            seed: seed,
          );

          var target = 0.0;
          double? previousGate;
          while (target < simulation.durationSeconds) {
            target = math.min(target + 1 / 60, simulation.durationSeconds);
            simulation.advanceTo(target);
            final gate = simulation.gateProgress;
            final closing =
                previousGate != null && gate < previousGate && gate > 0;
            previousGate = gate;
            final captured = simulation.capturedBallIndex;
            if (!closing || captured == null) continue;
            final ball = simulation.renderPositions[captured];
            expect(
              ball.dy > 112 && ball.dy < 154,
              isFalse,
              reason:
                  'gate sweeps through the captured ball at '
                  '${target.toStringAsFixed(2)}s (dy=${ball.dy.toStringAsFixed(0)})',
            );
          }
        });
      }
    }

    test('the captured ball descends monotonically after capture ends', () {
      final simulation = WhoPaysLotterySimulation(personCount: 5, seed: 101);
      _advanceInFrames(simulation, simulation.captureEndSeconds);

      final captured = simulation.capturedBallIndex;
      expect(captured, isNotNull);
      var previousY = simulation.renderPositions[captured!].dy;
      var target = simulation.captureEndSeconds;
      while (target < simulation.droppingEndSeconds) {
        target = math.min(target + 1 / 120, simulation.droppingEndSeconds);
        simulation.advanceTo(target);
        final currentY = simulation.renderPositions[captured].dy;
        expect(currentY + 0.001, greaterThanOrEqualTo(previousY));
        previousY = currentY;
      }
    });

    test('reduced motion keeps the gate closed and ends at the result', () {
      final simulation = WhoPaysLotterySimulation(personCount: 4, seed: 8);

      simulation.advanceReducedMotion(0.5);
      expect(simulation.rotorAngle, 0);
      expect(simulation.rotorSpeed, 0);
      expect(simulation.gateProgress, 0);
      expect(simulation.contentOpacity, 0);

      simulation.advanceReducedMotion(1);
      expect(simulation.phase, WhoPaysLotteryPhase.seated);
      expect(simulation.gateProgress, 0);
      final captured = simulation.capturedBallIndex;
      expect(captured, isNotNull);
      expect(simulation.renderPositions[captured!], const Offset(0, 209));
      expect(simulation.contentOpacity, 1);
    });

    // Gölge-canlı eşdeğerliği: reduced-motion gölge çözümü, aynı seed'in
    // canlı koşumuyla aynı kazananı vermek zorundadır.
    for (final seed in const <int>[8, 977351]) {
      test('shadow resolution matches the live run (seed $seed)', () {
        final live = WhoPaysLotterySimulation(personCount: 5, seed: seed);
        _advanceInFrames(live, live.durationSeconds);

        final reduced = WhoPaysLotterySimulation(personCount: 5, seed: seed);
        reduced.advanceReducedMotion(1);

        expect(live.capturedBallIndex, isNotNull);
        expect(reduced.capturedBallIndex, live.capturedBallIndex);
      });
    }

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
        final simulation = WhoPaysLotterySimulation(personCount: 6, seed: seed);

        var previous = List<Offset>.from(simulation.renderPositions);
        var target = 0.0;
        while (target < simulation.durationSeconds) {
          target = math.min(target + 1 / 60, simulation.durationSeconds);
          simulation.advanceTo(target);
          // Rotor-active phases: a full-speed blade strike or a deep-overlap
          // resolution can legitimately move a ball ~25-33 px in one frame —
          // not a teleport. After the rotor stops (settling onward: capture,
          // funnel, drop), constraint projection is the only jump source, so
          // the tight bound applies.
          final bound = target < simulation.settlingEndSeconds ? 34.0 : 24.0;
          for (var index = 0; index < simulation.personCount; index++) {
            final jump =
                (simulation.renderPositions[index] - previous[index]).distance;
            expect(
              jump,
              lessThanOrEqualTo(bound),
              reason:
                  'ball $index jumped ${jump.toStringAsFixed(1)} px '
                  'at ${target.toStringAsFixed(2)} s',
            );
          }
          previous = List<Offset>.from(simulation.renderPositions);
        }
      });
    }

    test('the captured ball respects the funnel walls on the way down', () {
      final simulation = WhoPaysLotterySimulation(personCount: 6, seed: 606);

      var sawTube = false;
      var target = 0.0;
      while (target < simulation.durationSeconds) {
        target = math.min(target + 1 / 120, simulation.durationSeconds);
        simulation.advanceTo(target);
        final captured = simulation.capturedBallIndex;
        if (captured == null) continue;
        final ball = simulation.renderPositions[captured];
        if (ball.dy >= WhoPaysLotterySimulation.tubeEntryY) {
          sawTube = true;
          expect(
            ball.dx.abs(),
            lessThanOrEqualTo(
              WhoPaysLotterySimulation.funnelHalfWidthAt(ball.dy) + 0.5,
            ),
          );
        }
      }
      expect(
        sawTube,
        isTrue,
        reason: 'captured ball never entered the funnel — assertions vacuous',
      );
    });

    test('a resume jump leaves no loser suspended mid-air', () {
      final simulation = WhoPaysLotterySimulation(personCount: 6, seed: 8080);

      _advanceInFrames(simulation, 1.2); // karışımın ortası
      simulation.advanceTo(simulation.durationSeconds); // arka plan sıçraması

      expect(simulation.phase, WhoPaysLotteryPhase.seated);
      expect(simulation.gateProgress, 0);
      final captured = simulation.capturedBallIndex;
      expect(captured, isNotNull);
      expect(simulation.renderPositions[captured!], const Offset(0, 209));
      for (var index = 0; index < simulation.personCount; index++) {
        if (index == captured) continue;
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
      final simulation = WhoPaysLotterySimulation(personCount: 6, seed: 121212);

      _advanceInFrames(simulation, simulation.durationSeconds - 1 / 60);
      final before = List<Offset>.from(simulation.renderPositions);
      simulation.advanceTo(simulation.durationSeconds);

      final captured = simulation.capturedBallIndex;
      expect(captured, isNotNull);
      for (var index = 0; index < simulation.personCount; index++) {
        if (index == captured) continue;
        expect(
          (simulation.renderPositions[index] - before[index]).distance,
          lessThanOrEqualTo(24),
          reason: 'loser $index snapped on the final frame',
        );
      }
    });

    test('exportState captures seated results for the next draw', () {
      final first = WhoPaysLotterySimulation(personCount: 4, seed: 2024);
      _advanceInFrames(first, first.durationSeconds);

      final captured = first.capturedBallIndex;
      expect(captured, isNotNull);
      final state = first.exportState();
      expect(state.seatedBallIndex, captured);
      expect(state.chamberPositions.length, 4);

      final second = WhoPaysLotterySimulation(
        personCount: 4,
        seed: 9,
        initialState: state,
      );
      expect(
        second.durationMilliseconds,
        WhoPaysLotterySimulation.redrawDurationMilliseconds,
      );
      expect(second.durationSeconds, closeTo(3.85, 1e-9));
      expect(second.renderPositions[captured!], const Offset(0, 209));
      for (var index = 0; index < 4; index++) {
        if (index == captured) continue;
        expect(second.renderPositions[index], state.chamberPositions[index]);
      }
    });

    test('the intake ball is pulled back into the chamber', () {
      final first = WhoPaysLotterySimulation(personCount: 6, seed: 31337);
      _advanceInFrames(first, first.durationSeconds);
      final intakeIndex = first.capturedBallIndex!;

      final second = WhoPaysLotterySimulation(
        personCount: 6,
        seed: 555,
        initialState: first.exportState(),
      );

      _advanceInFrames(second, 0.10);
      expect(second.phase, WhoPaysLotteryPhase.intake);
      expect(second.gateProgress, greaterThan(0.5));

      _advanceInFrames(second, 0.40);
      expect(
        second.renderPositions[intakeIndex].dy,
        lessThan(WhoPaysLotterySimulation.tubeEntryY),
        reason: 'intake ball should be back in the chamber',
      );

      _advanceInFrames(second, WhoPaysLotterySimulation.intakeDurationSeconds);
      expect(second.gateProgress, 0);
    });

    for (var personCount = 2; personCount <= 6; personCount++) {
      for (final seed in const <int>[11, 7302]) {
        test('redraw $personCount/$seed captures and seats a ball cleanly', () {
          final first = WhoPaysLotterySimulation(
            personCount: personCount,
            seed: seed,
          );
          _advanceInFrames(first, first.durationSeconds);

          final second = WhoPaysLotterySimulation(
            personCount: personCount,
            seed: seed * 31,
            initialState: first.exportState(),
          );

          var previous = List<Offset>.from(second.renderPositions);
          var target = 0.0;
          while (target < second.durationSeconds) {
            target = math.min(target + 1 / 60, second.durationSeconds);
            second.advanceTo(target);
            // Rotor-active phases (intake + spin-up/mixing/settling): a
            // full-speed blade strike or a deep-overlap resolution can
            // legitimately move a ball ~25-33 px in one frame — not a
            // teleport. After the rotor stops, constraint projection is the
            // only jump source, so the tight bound applies.
            final bound = target < second.settlingEndSeconds ? 34.0 : 24.0;
            for (var index = 0; index < personCount; index++) {
              final jump =
                  (second.renderPositions[index] - previous[index]).distance;
              expect(
                jump,
                lessThanOrEqualTo(bound),
                reason:
                    'redraw ball $index jumped ${jump.toStringAsFixed(1)} '
                    'px at ${target.toStringAsFixed(2)} s',
              );
            }
            previous = List<Offset>.from(second.renderPositions);
          }

          expect(second.phase, WhoPaysLotteryPhase.seated);
          expect(second.gateProgress, 0);
          final captured = second.capturedBallIndex;
          expect(captured, isNotNull);
          expect(second.renderPositions[captured!], const Offset(0, 209));
        });
      }
    }

    test('neutrality also holds during a redraw intake', () {
      final first = WhoPaysLotterySimulation(personCount: 5, seed: 640);
      _advanceInFrames(first, first.durationSeconds);

      final second = WhoPaysLotterySimulation(
        personCount: 5,
        seed: 641,
        initialState: first.exportState(),
      );
      _advanceInFrames(second, second.settlingEndSeconds - 0.001);
      expect(second.capturedBallIndex, isNull);
      expect(second.targetedForceApplications, 0);
      _advanceInFrames(second, second.durationSeconds);
      final captured = second.capturedBallIndex;
      expect(captured, isNotNull);
      expect(second.renderPositions[captured!], const Offset(0, 209));
    });

    test('reduced motion honours the initial state', () {
      final first = WhoPaysLotterySimulation(personCount: 4, seed: 12321);
      _advanceInFrames(first, first.durationSeconds);
      final previousWinner = first.capturedBallIndex!;

      final second = WhoPaysLotterySimulation(
        personCount: 4,
        seed: 5,
        initialState: first.exportState(),
      );
      second.advanceReducedMotion(0);
      expect(second.renderPositions[previousWinner], const Offset(0, 209));

      second.advanceReducedMotion(1);
      expect(second.phase, WhoPaysLotteryPhase.seated);
      expect(second.gateProgress, 0);
      final captured = second.capturedBallIndex;
      expect(captured, isNotNull);
      expect(second.renderPositions[captured!], const Offset(0, 209));
      if (previousWinner != captured) {
        expect(
          second.renderPositions[previousWinner].distance,
          lessThanOrEqualTo(
            WhoPaysLotterySimulation.maxBallCenterRadius + 0.001,
          ),
          reason: 'previous winner must end up back inside the chamber',
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
