import 'dart:math';
import 'dart:ui';

enum WhoPaysLotteryPhase {
  idle,
  spinUp,
  mixing,
  settling,
  gateOpening,
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
/// it never selects or changes the result.
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

  // The shorter presentation restores the pace of the original game while
  // leaving enough time to see the physical mix and the selected-ball drop.
  static const int durationMilliseconds = 3400;
  static const double durationSeconds = durationMilliseconds / 1000;
  static const double spinUpEndSeconds = 0.18;
  static const double mixingEndSeconds = 2.20;
  static const double settlingEndSeconds = 2.72;
  static const double gateOpeningEndSeconds = 2.92;
  static const double droppingEndSeconds = 3.32;

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

  static const Offset winnerStagingPosition = Offset(0, 103);
  static const double chuteCenterHalfWidth = 3.5;
  static const double winnerSeatY = 209.0;

  final int personCount;
  final int winnerIndex;
  final int seed;
  final Random _random;

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
  bool _winnerLatched = false;

  /// Cumulative physical blade/hub impacts. Used by focused tests and local
  /// diagnostics to prove that mixing energy comes from rotor contact.
  int bladeCollisionCount = 0;

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
      final winner = balls[winnerIndex];
      winner
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
    gateProgress = _smoothStep(value);
    phase = value >= 1
        ? WhoPaysLotteryPhase.seated
        : WhoPaysLotteryPhase.gateOpening;
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
    _winnerLatched = false;
    bladeCollisionCount = 0;

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
    final stepRotorSpeed = _rotorSpeedAt(stepTime);
    final stepRotorAngle = _rotorAngleAt(stepTime);
    final selecting = stepTime >= mixingEndSeconds;
    final gateIsOpening = stepTime >= settlingEndSeconds;
    final winnerReleased = stepTime >= gateOpeningEndSeconds;

    for (var index = 0; index < balls.length; index++) {
      final ball = balls[index];
      Offset acceleration;
      double dragRate;

      if (index == winnerIndex && winnerReleased) {
        acceleration = Offset(
          -ball.position.dx * 260 - ball.velocity.dx * 26,
          chuteGravity,
        );
        dragRate = 0.20;
      } else {
        acceleration = const Offset(0, gravity);
        dragRate = selecting ? 5.2 : 0.22;

        if (index == winnerIndex && selecting) {
          final captureProgress = gateIsOpening
              ? 1.0
              : _smoothStep(
                  (stepTime - mixingEndSeconds) /
                      (settlingEndSeconds - mixingEndSeconds),
                );
          final guide =
              (winnerStagingPosition - ball.position) * 86 -
              ball.velocity * 17;
          acceleration +=
              _clampMagnitude(guide, 5200) * captureProgress;
        }
      }

      if (_winnerLatched && index == winnerIndex && !winnerReleased) {
        ball
          ..position = winnerStagingPosition
          ..velocity = Offset.zero;
        continue;
      }

      ball.velocity += acceleration * dt;
      ball.velocity *= exp(-dragRate * dt);
      ball.position += ball.velocity * dt;
    }

    var maxImpactSpeed = 0.0;
    for (var pass = 0; pass < 3; pass++) {
      maxImpactSpeed = max(
        maxImpactSpeed,
        _resolveBallCollisions(stepTime),
      );
      maxImpactSpeed = max(
        maxImpactSpeed,
        _resolveRotorCollisions(stepRotorAngle, stepRotorSpeed),
      );
      maxImpactSpeed = max(
        maxImpactSpeed,
        _resolveBoundaries(stepTime),
      );
    }

    if (selecting && !winnerReleased && !_winnerLatched) {
      final winner = balls[winnerIndex];
      if ((winner.position - winnerStagingPosition).distance <= 3.0 &&
          winner.velocity.distance <= 90) {
        _winnerLatched = true;
        winner
          ..position = winnerStagingPosition
          ..velocity = Offset.zero;
      }
    }

    if (_winnerLatched && !winnerReleased) {
      balls[winnerIndex]
        ..position = winnerStagingPosition
        ..velocity = Offset.zero;
    }

    for (final ball in balls) {
      final speed = ball.velocity.distance;
      if (speed > maxBallSpeed) {
        ball.velocity = ball.velocity / speed * maxBallSpeed;
      }
    }
    return maxImpactSpeed;
  }

  double _resolveBallCollisions(double stepTime) {
    var maxImpactSpeed = 0.0;
    const minimumDistance = ballRadius * 2;
    final restitution = stepTime < mixingEndSeconds
        ? ballRestitution
        : 0.16;

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
        final firstIsLatched = _winnerLatched &&
            firstIndex == winnerIndex &&
            stepTime < gateOpeningEndSeconds;
        final secondIsLatched = _winnerLatched &&
            secondIndex == winnerIndex &&
            stepTime < gateOpeningEndSeconds;

        if (firstIsLatched) {
          second.position += normal * overlap;
        } else if (secondIsLatched) {
          first.position -= normal * overlap;
        } else {
          first.position -= normal * (overlap * 0.5);
          second.position += normal * (overlap * 0.5);
        }

        final relativeVelocity = second.velocity - first.velocity;
        final normalSpeed = _dot(relativeVelocity, normal);
        if (normalSpeed >= 0) continue;

        maxImpactSpeed = max(maxImpactSpeed, -normalSpeed);
        if (firstIsLatched) {
          second.velocity -= normal * ((1 + restitution) * normalSpeed);
        } else if (secondIsLatched) {
          first.velocity += normal * ((1 + restitution) * normalSpeed);
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

  double _resolveRotorCollisions(double angle, double angularVelocity) {
    var maxImpactSpeed = 0.0;
    for (var ballIndex = 0; ballIndex < balls.length; ballIndex++) {
      if (ballIndex == winnerIndex &&
          timelineSeconds >= gateOpeningEndSeconds &&
          balls[ballIndex].position.dy > winnerStagingPosition.dy) {
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

  double _resolveBoundaries(double stepTime) {
    var maxImpactSpeed = 0.0;
    final winnerReleased = stepTime >= gateOpeningEndSeconds;

    for (var index = 0; index < balls.length; index++) {
      final ball = balls[index];
      final inWinnerChute = index == winnerIndex &&
          winnerReleased &&
          ball.position.dy >= winnerStagingPosition.dy - 8;

      if (inWinnerChute) {
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
      final restitution = stepTime < mixingEndSeconds
          ? wallRestitution
          : 0.12;
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

  static WhoPaysLotteryPhase _phaseFor(double seconds) {
    if (seconds <= 0) return WhoPaysLotteryPhase.idle;
    if (seconds < spinUpEndSeconds) return WhoPaysLotteryPhase.spinUp;
    if (seconds < mixingEndSeconds) return WhoPaysLotteryPhase.mixing;
    if (seconds < settlingEndSeconds) return WhoPaysLotteryPhase.settling;
    if (seconds < gateOpeningEndSeconds) {
      return WhoPaysLotteryPhase.gateOpening;
    }
    if (seconds < droppingEndSeconds) return WhoPaysLotteryPhase.dropping;
    return WhoPaysLotteryPhase.seated;
  }

  static double _rotorSpeedAt(double seconds) {
    if (seconds <= 0 || seconds >= settlingEndSeconds) return 0;
    if (seconds < spinUpEndSeconds) {
      return maxRotorRadiansPerSecond * _smoothStep(seconds / spinUpEndSeconds);
    }
    if (seconds < mixingEndSeconds) return maxRotorRadiansPerSecond;
    final progress =
        (seconds - mixingEndSeconds) / (settlingEndSeconds - mixingEndSeconds);
    return maxRotorRadiansPerSecond * (1 - _smoothStep(progress));
  }

  static double _rotorAngleAt(double seconds) {
    final clamped = seconds.clamp(0.0, settlingEndSeconds);
    if (clamped <= spinUpEndSeconds) {
      final progress = clamped / spinUpEndSeconds;
      return maxRotorRadiansPerSecond *
          spinUpEndSeconds *
          (pow(progress, 3) - 0.5 * pow(progress, 4));
    }

    var angle = maxRotorRadiansPerSecond * spinUpEndSeconds * 0.5;
    final constantEnd = min(clamped, mixingEndSeconds);
    angle +=
        maxRotorRadiansPerSecond * max(0.0, constantEnd - spinUpEndSeconds);
    if (clamped <= mixingEndSeconds) return angle;

    final progress =
        (clamped - mixingEndSeconds) / (settlingEndSeconds - mixingEndSeconds);
    angle +=
        maxRotorRadiansPerSecond *
        (settlingEndSeconds - mixingEndSeconds) *
        (progress - pow(progress, 3) + 0.5 * pow(progress, 4));
    return angle;
  }

  static double _gateProgressAt(double seconds) {
    if (seconds <= settlingEndSeconds) return 0;
    if (seconds >= gateOpeningEndSeconds) return 1;
    return _smoothStep(
      (seconds - settlingEndSeconds) /
          (gateOpeningEndSeconds - settlingEndSeconds),
    );
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
