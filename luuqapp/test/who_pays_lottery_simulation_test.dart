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

      _advanceUntilOutcome(first);
      _advanceUntilOutcome(second);
      expect(first.capturedBallIndex, second.capturedBallIndex);
      expect(first.isPhysicallySeated, second.isPhysicallySeated);
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
        final simulation = WhoPaysLotterySimulation(personCount: 6, seed: seed);

        var target = 0.0;
        final limit =
            simulation.durationSeconds +
            WhoPaysLotterySimulation.maxPostDurationWaitSeconds;
        while (target < limit - 1e-9 &&
            !simulation.isPhysicallySeated &&
            !simulation.isStalled) {
          target = math.min(target + 1 / 60, limit);
          simulation.advanceTo(target);
          if (simulation.capturedBallIndex == null) {
            expect(
              simulation.targetedForceApplications,
              0,
              reason: 'neutrality broken at ${target.toStringAsFixed(2)}s',
            );
          }
        }
        expect(simulation.isPhysicallySeated || simulation.isStalled, isTrue);
      });
    }

    test('nominal capture time never chooses a ball by proximity', () {
      final simulation = WhoPaysLotterySimulation(
        personCount: 2,
        seed: 20260915,
      );

      // Keep both balls safely above and outside the funnel as the nominal
      // capture window opens. The old guarantee fallback selected the nearest
      // ball here even though neither ball had entered the opening.
      _advanceInFrames(simulation, 2.88);
      simulation.balls[0]
        ..position = const Offset(-72, -18)
        ..velocity = Offset.zero;
      simulation.balls[1]
        ..position = const Offset(72, -18)
        ..velocity = Offset.zero;
      simulation.wake();

      _advanceInFrames(simulation, 2.90);
      expect(simulation.capturedBallIndex, isNull);
      expect(simulation.targetedForceApplications, 0);
      _advanceInFrames(simulation, simulation.durationSeconds);
      expect(simulation.capturedBallIndex, isNull);
      expect(
        simulation.balls.every((ball) => ball.position != const Offset(0, 209)),
        isTrue,
        reason: 'nominal duration must not seat a non-captured ball',
      );
    });

    test(
      'a post-duration funnel entry travels through the tube before seating',
      () {
        final simulation = WhoPaysLotterySimulation(
          personCount: 2,
          seed: 20260916,
        );

        _advanceInFrames(simulation, 2.88);
        simulation.balls[0]
          ..position = const Offset(-72, -18)
          ..velocity = Offset.zero;
        simulation.balls[1]
          ..position = const Offset(72, -18)
          ..velocity = Offset.zero;
        simulation.wake();
        _advanceInFrames(simulation, simulation.durationSeconds);
        expect(simulation.capturedBallIndex, isNull);

        simulation.balls[1]
          ..position = const Offset(0, 99)
          ..velocity = const Offset(0, 80);
        simulation.wake();
        simulation.advanceTo(simulation.timelineSeconds + 1 / 60);

        final captured = simulation.capturedBallIndex;
        expect(captured, 1);
        expect(simulation.isPhysicallySeated, isFalse);
        expect(
          simulation.renderPositions[captured!].dy,
          lessThan(WhoPaysLotterySimulation.winnerSeatY),
        );

        _advanceUntilOutcome(simulation);
        expect(simulation.isPhysicallySeated, isTrue);
        expect(simulation.capturedBallIndex, captured);
        expect(simulation.renderPositions[captured], const Offset(0, 209));
      },
    );

    test('a physically supported no-capture draw becomes stalled', () {
      final simulation = WhoPaysLotterySimulation(
        personCount: 2,
        seed: 20260917,
      );

      // Jump to the nominal end with a deliberately delayed frame. The
      // watchdog must still report a no-capture stall rather than assigning a
      // winner while it closes the draw.
      simulation.advanceTo(simulation.durationSeconds);
      simulation.balls[0]
        ..position = const Offset(-100, 40)
        ..velocity = Offset.zero;
      simulation.balls[1]
        ..position = const Offset(100, 40)
        ..velocity = Offset.zero;
      simulation.wake();

      simulation.advanceTo(
        simulation.durationSeconds +
            WhoPaysLotterySimulation.maxPostDurationWaitSeconds,
      );

      expect(simulation.capturedBallIndex, isNull);
      expect(simulation.isPhysicallySeated, isFalse);
      expect(simulation.isStalled, isTrue);
      expect(simulation.isSleeping, isTrue);
    });

    test('the gate opens during capture and is closed at the end', () {
      final simulation = WhoPaysLotterySimulation(personCount: 3, seed: 42);

      _advanceInFrames(simulation, 2.50);
      expect(simulation.gateProgress, 0);
      _advanceInFrames(simulation, 2.72);
      expect(simulation.gateProgress, 1);
      _advanceUntilOutcome(simulation);
      if (simulation.isPhysicallySeated) {
        _advanceAfterPhysicalOutcome(simulation);
        expect(simulation.gateProgress, 0);
      } else {
        expect(simulation.isStalled, isTrue);
        expect(simulation.capturedBallIndex, isNull);
      }
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
        test(
          'draw $personCount/$seed captures exactly one ball and seats it',
          () {
            final simulation = WhoPaysLotterySimulation(
              personCount: personCount,
              seed: seed,
            );

            final crossedThroat = <int>{};
            List<Offset>? preFinalPositions;
            var target = simulation.timelineSeconds;
            final limit =
                simulation.durationSeconds +
                WhoPaysLotterySimulation.maxPostDurationWaitSeconds;
            while (target < limit &&
                !simulation.isPhysicallySeated &&
                !simulation.isStalled) {
              final nextTarget = math.min(target + 1 / 60, limit);
              target = nextTarget;
              simulation.advanceTo(target);
              for (var i = 0; i < personCount; i++) {
                if (simulation.renderPositions[i].dy >=
                    WhoPaysLotterySimulation.funnelBottomY) {
                  crossedThroat.add(i);
                }
              }
              if (!simulation.isPhysicallySeated && !simulation.isStalled) {
                preFinalPositions = List<Offset>.from(
                  simulation.renderPositions,
                );
              }
            }

            final captured = simulation.capturedBallIndex;
            expect(
              simulation.isPhysicallySeated,
              isTrue,
              reason: 'draw stalled without a physical capture',
            );
            expect(captured, isNotNull, reason: 'no ball was captured');
            final seatedIndex = captured!;
            expect(crossedThroat, {
              seatedIndex,
            }, reason: 'only the captured ball may pass the tube throat');

            // Physical seating must happen during playback, not by a
            // timeline-end position assignment.
            if (preFinalPositions != null) {
              expect(
                (preFinalPositions[seatedIndex] - const Offset(0, 209))
                    .distance,
                greaterThan(0),
                reason: 'winner was already snapped before physical seating',
              );
            }

            expect(simulation.phase, WhoPaysLotteryPhase.seated);
            _advanceAfterPhysicalOutcome(simulation);
            expect(simulation.gateProgress, 0);
            expect(
              simulation.renderPositions[seatedIndex].dx,
              closeTo(0, 0.001),
            );
            expect(
              simulation.renderPositions[seatedIndex].dy,
              closeTo(209, 0.001),
            );
            for (var index = 0; index < simulation.personCount; index++) {
              if (index == seatedIndex) continue;
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
          },
        );
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
        test('gate never closes through the captured ball ($personCount/$seed)', () {
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
        _advanceUntilOutcome(live);

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

    test('results continue falling without changing the winner', () {
      final sim = WhoPaysLotterySimulation(personCount: 6, seed: 8080);
      _advanceUntilOutcome(sim);
      final winner = sim.capturedBallIndex!;
      final loser = (winner + 1) % 6;
      sim.balls[loser].position = const Offset(0, -85);
      sim.balls[loser].velocity = Offset.zero;
      sim.wake();
      sim.advanceTo(sim.timelineSeconds + 0.1);
      expect(sim.balls[loser].position.dy, greaterThan(-85));
      expect(sim.capturedBallIndex, winner);
      expect(sim.balls[winner].position, const Offset(0, 209));
      final state = sim.exportState();
      final redraw = WhoPaysLotterySimulation(
        personCount: 6,
        seed: 42,
        initialState: state,
      );
      expect(redraw.balls[loser].velocity, sim.balls[loser].velocity);
      expect(redraw.balls[loser].position, sim.balls[loser].position);
    });

    for (final fps in [30, 60, 120]) {
      test('30-second result stability at $fps fps', () {
        for (var count = 2; count <= 6; count++) {
          for (final seed in [8, 97, 8080]) {
            final sim = WhoPaysLotterySimulation(
              personCount: count,
              seed: seed,
            );
            _advanceUntilOutcome(sim);
            final winner = sim.capturedBallIndex;
            if (winner == null) {
              expect(sim.isStalled, isTrue);
              continue;
            }
            _advanceAfterPhysicalOutcome(sim);
            final end = sim.durationSeconds + 30;
            while (sim.timelineSeconds < end) {
              sim.advanceTo(math.min(end, sim.timelineSeconds + 1 / fps));
              expect(sim.capturedBallIndex, winner);
              expect(sim.gateProgress, 0);
              for (var i = 0; i < count; i++) {
                final ball = sim.balls[i];
                expect(
                  ball.position.dx.isFinite && ball.position.dy.isFinite,
                  isTrue,
                );
                expect(ball.velocity.distance.isFinite, isTrue);
                if (i != winner) {
                  expect(ball.position.distance, lessThanOrEqualTo(107.001));
                }
              }
            }
            for (var i = 0; i < count; i++) {
              expect(
                sim.balls[i].velocity.distance,
                lessThan(8),
                reason: '$count/$seed/$fps ball $i keeps moving',
              );
            }
            _expectNoOverlap(sim, minimumDistance: 41);
            expect(
              sim.isSleeping,
              isTrue,
              reason: 'did not sleep: $count/$seed/$fps',
            );
            final before = List<Offset>.from(sim.renderPositions);
            final report = sim.advanceTo(end + 5);
            expect(report.physicsSteps, 0);
            expect(sim.renderPositions, before);
          }
        }
      });
    }

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
      _advanceUntilOutcome(first);

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
      _advanceUntilOutcome(first);
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
          _advanceUntilOutcome(first);

          final second = WhoPaysLotterySimulation(
            personCount: personCount,
            seed: seed * 31,
            initialState: first.exportState(),
          );

          var previous = List<Offset>.from(second.renderPositions);
          var target = 0.0;
          final limit =
              second.durationSeconds +
              WhoPaysLotterySimulation.maxPostDurationWaitSeconds;
          while (target < limit &&
              !second.isPhysicallySeated &&
              !second.isStalled) {
            target = math.min(target + 1 / 60, limit);
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

          expect(second.isPhysicallySeated || second.isStalled, isTrue);
          if (!second.isStalled) {
            expect(second.phase, WhoPaysLotteryPhase.seated);
            _advanceAfterPhysicalOutcome(second);
            expect(second.gateProgress, 0);
            final captured = second.capturedBallIndex;
            expect(captured, isNotNull);
            expect(second.renderPositions[captured!], const Offset(0, 209));
          }
        });
      }
    }

    test('neutrality also holds during a redraw intake', () {
      final first = WhoPaysLotterySimulation(personCount: 5, seed: 640);
      _advanceUntilOutcome(first);

      final second = WhoPaysLotterySimulation(
        personCount: 5,
        seed: 641,
        initialState: first.exportState(),
      );
      _advanceInFrames(second, second.settlingEndSeconds - 0.001);
      expect(second.capturedBallIndex, isNull);
      expect(second.targetedForceApplications, 0);
      _advanceUntilOutcome(second);
      final captured = second.capturedBallIndex;
      expect(captured, isNotNull);
      expect(second.renderPositions[captured!], const Offset(0, 209));
    });

    // Adalet: kazanan artık seed + kaotik karışımın fonksiyonu. Sabit seed
    // listesiyle deterministik; bant gevşektir (gerçek tekdüzelikte ~4σ) ki
    // test flaky olmasın. 2026-07-22 taraması (600×{2,3,4,6}): tüm paylar
    // 1/n'in 0.85-1.13 katı bandındaydı.
    test('capture outcomes are distributed fairly across players', () {
      for (final personCount in [2, 6]) {
        final wins = List<int>.filled(personCount, 0);
        for (var seed = 1; seed <= 240; seed++) {
          final simulation = WhoPaysLotterySimulation(
            personCount: personCount,
            seed: seed,
          );
          _advanceUntilOutcome(simulation);
          final captured = simulation.capturedBallIndex;
          if (captured != null) {
            wins[captured]++;
          }
        }
        final expected = 240 / personCount;
        for (var index = 0; index < personCount; index++) {
          expect(
            wins[index],
            greaterThan((expected * 0.45).floor()),
            reason: 'player $index wins too rarely for n=$personCount: $wins',
          );
          expect(
            wins[index],
            lessThan((expected * 1.75).ceil()),
            reason: 'player $index wins too often for n=$personCount: $wins',
          );
        }
      }
    }, timeout: const Timeout(Duration(minutes: 5)));

    test('reduced motion honours the initial state', () {
      final first = WhoPaysLotterySimulation(personCount: 4, seed: 12321);
      _advanceUntilOutcome(first);
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

void _advanceUntilOutcome(
  WhoPaysLotterySimulation simulation, {
  double frameSeconds = 1 / 60,
}) {
  var target = simulation.timelineSeconds;
  final limit =
      simulation.durationSeconds +
      WhoPaysLotterySimulation.maxPostDurationWaitSeconds;
  while (target < limit &&
      !simulation.isPhysicallySeated &&
      !simulation.isStalled) {
    target = math.min(target + frameSeconds, limit);
    simulation.advanceTo(target);
  }
}

void _advanceAfterPhysicalOutcome(WhoPaysLotterySimulation simulation) {
  if (simulation.isPhysicallySeated) {
    _advanceInFrames(simulation, simulation.timelineSeconds + 0.25);
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
