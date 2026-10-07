import 'package:flutter_test/flutter_test.dart';
import 'package:luuqapp/main.dart' show effectFrameFactor;

void main() {
  test('one 60 Hz frame moves particles one step', () {
    expect(
      effectFrameFactor(Duration.zero, const Duration(microseconds: 16667)),
      closeTo(1, 0.01),
    );
  });

  test('a 120 Hz frame moves them half a step', () {
    expect(
      effectFrameFactor(Duration.zero, const Duration(microseconds: 8333)),
      closeTo(0.5, 0.01),
    );
  });

  test('a long stall is capped at 0.1 s', () {
    expect(
      effectFrameFactor(const Duration(seconds: 1), const Duration(seconds: 3)),
      closeTo(6, 0.001),
    );
  });

  test('the first tick and a restarted controller count as one frame', () {
    expect(effectFrameFactor(null, const Duration(seconds: 1)), 1);
    expect(
      effectFrameFactor(const Duration(seconds: 2), const Duration(seconds: 1)),
      1,
    );
  });
}
