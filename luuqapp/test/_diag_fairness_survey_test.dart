import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:luuqapp/src/who_pays/lottery_simulation.dart';

// GEÇİCİ TANI DOSYASI — merge öncesi silinir.
// Fizik-öncelikli kazanan seçiminin adalet dağılımını ölçer.

void main() {
  test('fairness survey: fresh draws', () {
    for (final personCount in [2, 3, 4, 6]) {
      final wins = List<int>.filled(personCount, 0);
      var lateAssignments = 0; // atama >= 2.895 (son-çare bölgesi)
      final assignTimes = <double>[];
      for (var seed = 1; seed <= 600; seed++) {
        final sim = WhoPaysLotterySimulation(
          personCount: personCount,
          seed: seed,
        );
        double? assignedAt;
        var t = 0.0;
        while (t < sim.durationSeconds - 1e-9) {
          t = math.min(t + 1 / 60, sim.durationSeconds);
          sim.advanceTo(t);
          if (assignedAt == null && sim.capturedBallIndex != null) {
            assignedAt = t;
          }
        }
        wins[sim.capturedBallIndex!]++;
        assignTimes.add(assignedAt!);
        if (assignedAt >= 2.895) lateAssignments++;
      }
      assignTimes.sort();
      final p50 = assignTimes[assignTimes.length ~/ 2];
      final p90 = assignTimes[(assignTimes.length * 9) ~/ 10];
      // ignore: avoid_print
      print(
        'FRESH n=$personCount wins=$wins '
        'lastResortish=$lateAssignments/600 '
        'assignT p50=${p50.toStringAsFixed(2)} p90=${p90.toStringAsFixed(2)}',
      );
    }
  }, timeout: const Timeout(Duration(minutes: 10)));

  test('fairness survey: redraws', () {
    for (final personCount in [2, 6]) {
      final wins = List<int>.filled(personCount, 0);
      var lateAssignments = 0;
      for (var seed = 1; seed <= 300; seed++) {
        final first = WhoPaysLotterySimulation(
          personCount: personCount,
          seed: seed,
        );
        var t = 0.0;
        while (t < first.durationSeconds - 1e-9) {
          t = math.min(t + 1 / 60, first.durationSeconds);
          first.advanceTo(t);
        }
        final second = WhoPaysLotterySimulation(
          personCount: personCount,
          seed: seed * 131 + 7,
          initialState: first.exportState(),
        );
        double? assignedAt;
        t = 0.0;
        while (t < second.durationSeconds - 1e-9) {
          t = math.min(t + 1 / 60, second.durationSeconds);
          second.advanceTo(t);
          if (assignedAt == null && second.capturedBallIndex != null) {
            assignedAt = t;
          }
        }
        wins[second.capturedBallIndex!]++;
        if (assignedAt! - 0.45 >= 2.895) lateAssignments++;
      }
      // ignore: avoid_print
      print(
        'REDRAW n=$personCount wins=$wins lastResortish=$lateAssignments/300',
      );
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}
