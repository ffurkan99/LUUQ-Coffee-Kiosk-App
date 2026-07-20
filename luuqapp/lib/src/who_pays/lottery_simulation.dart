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
  static const double _guaranteeWindow = 0.30;

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
  // Winner-only drag while still in the chamber during capture. Lower than
  // settleDragRate so the suction pull (below) isn't fighting heavy viscous
  // damping while working the winner around chamber geometry toward the
  // mouth. Losers keep settleDragRate.
  static const double winnerCaptureDragRate = 0.6;

  // Capture suction toward the tube mouth.
  static const Offset mouthTarget = Offset(0, 126);
  static const double suctionSpringRate = 90.0;
  static const double suctionDampingRate = 2.5;
  static const double suctionRampMax = 3200.0;
  static const double suctionGuaranteeMax = 8000.0;

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

    // A background/resume jump is deliberately not fully simulated. If the
    // controller has already completed, guarantee a valid in-app result rather
    // than leaving the selected ball suspended in the glass.
    if (target >= durationSeconds) {
      balls[winnerIndex]
        ..position = const Offset(0, winnerSeatY)
        ..velocity = Offset.zero;
      if (droppedCatchUp) {
        _settleLosersToFloor();
      }
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
          dragRate = winnerCaptureDragRate;
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
    for (var pass = 0; pass < collisionPasses; pass++) {
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
      // From capture onward the winner is exempt from rotor contact: the
      // suction must be able to pull it across the stationary rotor's
      // territory to the mouth. The rotor is drawn behind the balls and
      // mostly transparent, so the pass-through is not visible.
      if (ballIndex == winnerIndex && drawTime >= _settlingEnd) {
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
