import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:luuqapp/src/wheel/wheel_pointer_simulation.dart';

const _rim = 340.0;
const _frame = 1 / 60;

class _Run {
  final angles = <double>[];
  var releases = 0;
}

/// Drives [sim] at 60 fps for [seconds] with the wheel at [turnsAt].
_Run _drive(
  WheelPointerSimulation sim,
  double seconds,
  double Function(double t) turnsAt, {
  int pegs = 8,
}) {
  final run = _Run();
  final frames = (seconds / _frame).round();
  for (var f = 0; f <= frames; f++) {
    run.releases += sim.advance(
      turns: turnsAt(f * _frame),
      pegCount: pegs,
      rimRadius: _rim,
      seconds: _frame,
    );
    run.angles.add(sim.angle);
  }
  return run;
}

void main() {
  test('a still wheel leaves the pointer straight and settled', () {
    final sim = WheelPointerSimulation();
    final run = _drive(sim, 1, (_) => 0.0625);
    expect(run.angles.every((a) => a == 0), isTrue);
    expect(run.releases, 0);
    expect(sim.isSettled, isTrue);
  });

  test('a slow peg lifts the tip, slips off with one tick and the '
      'pointer rings back and settles', () {
    final sim = WheelPointerSimulation();
    // One peg passes the top at 0.1 turns per second (clockwise).
    final pass = _drive(sim, 1.2, (t) => -0.06 + 0.1 * t);
    expect(pass.releases, 1);

    final lowest = pass.angles.reduce(min);
    expect(lowest, lessThan(-0.2)); // pushed to the right
    expect(lowest, greaterThanOrEqualTo(-WheelPointerSimulation.maxAngle));
    final afterLowest = pass.angles.sublist(pass.angles.indexOf(lowest));
    expect(afterLowest.reduce(max), greaterThan(0.02)); // overshoot

    final rest = _drive(sim, 0.6, (_) => 0.06);
    expect(rest.angles.last.abs(), lessThan(0.5 * pi / 180));
    expect(sim.isSettled, isTrue);
    expect(sim.angle, 0);
  });

  test('turning the other way deflects the other way', () {
    final sim = WheelPointerSimulation();
    final pass = _drive(sim, 1.2, (t) => 0.06 - 0.1 * t);
    expect(pass.releases, 1);
    expect(pass.angles.reduce(max), greaterThan(0.2));
  });

  test('a fast spin never skips a peg and stays within the stop', () {
    final sim = WheelPointerSimulation();
    // 3 turns per second for 2 s with 8 pegs: 48 pegs pass.
    final run = _drive(sim, 2, (t) => 0.03 + 3 * t);
    expect(run.releases, inInclusiveRange(46, 48));
    expect(
      run.angles.every((a) => a.abs() <= WheelPointerSimulation.maxAngle),
      isTrue,
    );
    // The pegs come faster than the spring returns: the pointer rides them,
    // lifted to the right, instead of swinging across.
    final riding = run.angles.skip(10);
    expect(riding.every((a) => a < 0), isTrue);
    expect(sim.isSettled, isFalse);
  });

  test('a long frame stall is capped and stays finite', () {
    final sim = WheelPointerSimulation();
    _drive(sim, 0.3, (t) => -0.03 + 0.2 * t);
    sim.advance(turns: 0.04, pegCount: 8, rimRadius: _rim, seconds: 0.5);
    expect(sim.angle.isFinite, isTrue);
    expect(sim.angle.abs(), lessThanOrEqualTo(WheelPointerSimulation.maxAngle));
  });

  test('an instant spin (animations off) jumps without ticks', () {
    final sim = WheelPointerSimulation();
    sim.advance(turns: 0.03, pegCount: 8, rimRadius: _rim, seconds: _frame);
    final ticks = sim.advance(
      turns: 4.53,
      pegCount: 8,
      rimRadius: _rim,
      seconds: _frame,
    );
    expect(ticks, 0);
  });

  test('a changing or empty peg count during a spin is safe', () {
    final sim = WheelPointerSimulation();
    var t = 0.0;
    for (final pegs in [8, 5, 0, 1, 12]) {
      final start = t;
      final run = _drive(sim, 0.4, (x) => start + 0.5 * x, pegs: pegs);
      t = start + 0.2;
      expect(run.angles.every((a) => a.isFinite), isTrue);
    }
  });

  test(
    'a wheel stopped with a peg under the tip leaves it leaning, settled',
    () {
      final sim = WheelPointerSimulation();
      // Creep until the peg presses the tip, then hold the wheel.
      _drive(sim, 0.38, (t) => -0.02 + 0.05 * t);
      final held = -0.02 + 0.05 * 0.38;
      _drive(sim, 0.5, (_) => held);
      expect(sim.angle, lessThan(-0.01));
      expect(sim.isSettled, isTrue);
    },
  );
}
