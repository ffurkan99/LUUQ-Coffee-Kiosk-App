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

    test('balls remain finite, separated, and inside the glass', () {
      final simulation = WhoPaysLotterySimulation(
        personCount: 6,
        winnerIndex: 4,
        seed: 99173,
      );

      var target = 0.0;
      const end = WhoPaysLotterySimulation.settlingEndSeconds - 0.0001;
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

      for (final sample in <double>[0.75, 1.5, 2.25]) {
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

    test('fan power follows the rotor and reaches zero before the gate', () {
      final simulation = WhoPaysLotterySimulation(
        personCount: 3,
        winnerIndex: 2,
        seed: 12,
      );

      expect(simulation.fanPower, 0);
      simulation.advanceTo(WhoPaysLotterySimulation.spinUpEndSeconds);
      expect(simulation.fanPower, closeTo(1, 0.0001));
      simulation.advanceTo(WhoPaysLotterySimulation.settlingEndSeconds);
      expect(simulation.fanPower, 0);
      expect(simulation.rotorSpeed, 0);
    });

    test('only the selected winner enters and remains in the chute', () {
      const winnerIndex = 4;
      final simulation = WhoPaysLotterySimulation(
        personCount: 6,
        winnerIndex: winnerIndex,
        seed: 444,
      );

      _advanceInFrames(simulation, WhoPaysLotterySimulation.durationSeconds);

      expect(simulation.phase, WhoPaysLotteryPhase.seated);
      expect(simulation.gateProgress, 1);
      expect(simulation.renderPositions[winnerIndex].dx, closeTo(0, 0.001));
      expect(simulation.renderPositions[winnerIndex].dy, closeTo(209, 0.001));
      for (var index = 0; index < simulation.personCount; index++) {
        if (index == winnerIndex) continue;
        expect(
          simulation.renderPositions[index].distance,
          lessThanOrEqualTo(
            WhoPaysLotterySimulation.maxBallCenterRadius + 0.001,
          ),
        );
      }
      _expectNoRenderOverlap(simulation, minimumDistance: 42);
    });

    test('the winner drop does not use an upward bounce', () {
      final simulation = WhoPaysLotterySimulation(
        personCount: 5,
        winnerIndex: 2,
        seed: 101,
      );
      _advanceInFrames(
        simulation,
        WhoPaysLotterySimulation.gateOpeningEndSeconds,
      );

      var previousY = simulation.renderPositions[2].dy;
      var target = WhoPaysLotterySimulation.gateOpeningEndSeconds;
      while (target < WhoPaysLotterySimulation.droppingEndSeconds) {
        target = math.min(
          target + 1 / 120,
          WhoPaysLotterySimulation.droppingEndSeconds,
        );
        simulation.advanceTo(target);
        final currentY = simulation.renderPositions[2].dy;
        expect(currentY + 0.001, greaterThanOrEqualTo(previousY));
        previousY = currentY;
      }
    });

    test('reduced motion skips rotation and ends at the result', () {
      final simulation = WhoPaysLotterySimulation(
        personCount: 4,
        winnerIndex: 1,
        seed: 8,
      );

      simulation.advanceReducedMotion(0.5);
      expect(simulation.rotorAngle, 0);
      expect(simulation.rotorSpeed, 0);
      expect(simulation.contentOpacity, 0);

      simulation.advanceReducedMotion(1);
      expect(simulation.phase, WhoPaysLotteryPhase.seated);
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

void _expectNoRenderOverlap(
  WhoPaysLotterySimulation simulation, {
  required double minimumDistance,
}) {
  for (var first = 0; first < simulation.renderPositions.length; first++) {
    for (
      var second = first + 1;
      second < simulation.renderPositions.length;
      second++
    ) {
      expect(
        (simulation.renderPositions[first] - simulation.renderPositions[second])
            .distance,
        greaterThanOrEqualTo(minimumDistance),
        reason: 'rendered balls $first and $second overlap',
      );
    }
  }
}
