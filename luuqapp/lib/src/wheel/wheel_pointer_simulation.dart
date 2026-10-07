import 'dart:math';

/// The pointer at the top of the wheel, simulated as a spring-loaded flapper
/// that catches on the pegs at the segment borders.
///
/// A peg pushes the tip aside until the tip slips over it; the spring then
/// snaps the pointer back, it overshoots a little and settles. The ringing has
/// a fixed frequency, so the motion looks the same at any wheel speed, and
/// the pointer keeps settling after the wheel stops.
///
/// Coordinates are pixels with the hinge at the origin and y pointing down.
/// The tip is at `(-length * sin(angle), length * cos(angle))`, which matches
/// `Transform.rotate(angle: angle, alignment: Alignment.topCenter)`.
class WheelPointerSimulation {
  /// Hinge to tip, the height of the painted pointer.
  static const double length = 44;

  /// Radius of the pegs the wheel painter draws on the rim.
  static const double pegRadius = 5;

  /// Rounding of the pointer tip.
  static const double tipRadius = 2;

  /// How far the resting tip reaches into the peg row.
  static const double overlap = 3;

  /// Gap between the resting tip and the top of the rim (the centre line of
  /// the pegs); the widget places the pointer with it.
  static const double restTipGap = pegRadius + tipRadius - overlap;

  /// Hard stop of the flapper (about 26 degrees).
  static const double maxAngle = 0.45;

  static const double _frequencyHz = 9;
  static const double _dampingRatio = 0.25;
  static const double _stopRestitution = 0.2;
  static const double _maxCarriedSpeed = 8;
  static const double _step = 1 / 2000;
  static const double _maxFrameSeconds = 0.04;
  static const double _contactSlop = 0.5;

  static final double _omega = 2 * pi * _frequencyHz;
  static final double _stiffness = _omega * _omega;
  static final double _damping = 2 * _dampingRatio * _omega;

  double _angle = 0;
  double _velocity = 0;
  double? _turns;
  bool _touching = false;
  bool _settled = true;

  /// The pointer angle in radians; positive turns the tip to the left.
  double get angle => _angle;

  /// True when the pointer is at rest (straight down, or leaning on a peg of
  /// a wheel that does not move). Nothing changes until the wheel moves.
  bool get isSettled => _settled;

  /// Moves the wheel to [turns] (the wheel controller's value; one turn is a
  /// full clockwise revolution) over [seconds] and returns how many times the
  /// tip slipped off a peg, one tick sound each.
  ///
  /// [rimRadius] is the radius of the peg centres. A jump of more than half a
  /// turn in one frame (an instant spin) is applied without sweeping the pegs.
  int advance({
    required double turns,
    required int pegCount,
    required double rimRadius,
    required double seconds,
  }) {
    if (!turns.isFinite) return 0;
    var from = _turns ?? turns;
    _turns = turns;
    if ((turns - from).abs() > 0.5) from = turns;

    final frame = seconds.isFinite
        ? seconds.clamp(0.0, _maxFrameSeconds).toDouble()
        : 0.0;
    if (frame == 0) return 0;
    final steps = max(1, (frame / _step).ceil());
    final h = frame / steps;
    final pegs = rimRadius > 0 ? pegCount : 0;
    final centerY = length + restTipGap + rimRadius;
    final reach = pegRadius + tipRadius;
    final wheelMoved = turns != from;

    var releases = 0;
    for (var s = 1; s <= steps; s++) {
      final previousTurns = from + (turns - from) * (s - 1) / steps;
      final currentTurns = from + (turns - from) * s / steps;
      final previousAngle = _angle;

      // Spring (semi-implicit Euler).
      _velocity += (-_stiffness * _angle - _damping * _velocity) * h;
      _angle += _velocity * h;

      var pushed = false;
      var touching = false;
      if (pegs > 0) {
        final sweep = 2 * pi / pegs;
        final rotation = currentTurns * 2 * pi;
        final previousRotation = previousTurns * 2 * pi;
        for (var i = 0; i < pegs; i++) {
          final a = -pi / 2 + i * sweep + rotation;
          final px = rimRadius * cos(a);
          final py = centerY + rimRadius * sin(a);
          // Only the pegs near the top can reach the tip.
          if (py > length + reach + 1 || px.abs() > length + reach) continue;

          final tipX = -length * sin(_angle);
          final tipY = length * cos(_angle);
          final distance = sqrt(
            (tipX - px) * (tipX - px) + (tipY - py) * (tipY - py),
          );
          if (distance < reach) {
            // Keep the tip on the side of the peg it was on.
            final previousPegX =
                rimRadius * cos(-pi / 2 + i * sweep + previousRotation);
            final previousTipX = -length * sin(previousAngle);
            final resolved = _contactAngle(
              px,
              py,
              reach,
              keepRight: previousTipX >= previousPegX,
            );
            if (resolved != null) {
              _angle = resolved;
              pushed = true;
            }
          }
          if (distance < reach + _contactSlop) touching = true;
        }
      }

      // A pushed tip moves with the peg, but keeps no more speed than the
      // spring could give it; a fast peg shoves it aside instead of flinging
      // it across.
      if (pushed) {
        _velocity = ((_angle - previousAngle) / h).clamp(
          -_maxCarriedSpeed,
          _maxCarriedSpeed,
        );
      }

      // The stop bounces a free swing back; a tip a peg is still pressing
      // against the stop just rests there.
      if (_angle.abs() > maxAngle) {
        _angle = _angle.sign * maxAngle;
        if (_velocity.sign == _angle.sign) {
          _velocity = pushed ? 0 : -_velocity * _stopRestitution;
        }
      }

      if (_touching && !touching) releases++;
      _touching = touching;
    }

    final resting =
        !wheelMoved &&
        _velocity.abs() < 0.02 &&
        (_touching || _angle.abs() < 0.001);
    if (resting && !_touching) {
      _angle = 0;
      _velocity = 0;
    }
    _settled = resting;
    return releases;
  }

  /// The pointer angle that puts the tip on the edge of the peg at
  /// ([px], [py]): the intersection of the tip's arc with the peg's circle,
  /// on the right or the left side of the peg.
  static double? _contactAngle(
    double px,
    double py,
    double reach, {
    required bool keepRight,
  }) {
    final d = sqrt(px * px + py * py);
    if (d == 0) return null;
    final a = (length * length - reach * reach + d * d) / (2 * d);
    final h2 = length * length - a * a;
    if (h2 < 0) return null;
    final h = sqrt(h2);
    final bx = px * a / d;
    final by = py * a / d;
    final x1 = bx - h * py / d;
    final y1 = by + h * px / d;
    final x2 = bx + h * py / d;
    final y2 = by - h * px / d;
    final pickFirst = keepRight ? x1 >= x2 : x1 < x2;
    return pickFirst ? atan2(-x1, y1) : atan2(-x2, y2);
  }
}
