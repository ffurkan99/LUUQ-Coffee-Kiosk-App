import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';

import 'package:luuqapp/main.dart';

void main() {
  test('renders only an initialized video with valid dimensions', () {
    const ready = VideoPlayerValue(
      duration: Duration(seconds: 1),
      size: Size(1920, 1080),
      isInitialized: true,
    );

    expect(isVideoReadyForRender(ready, unavailable: false), isTrue);
    expect(isVideoReadyForRender(ready, unavailable: true), isFalse);
  });

  test('rejects errored, uninitialized, and zero-sized video states', () {
    const base = VideoPlayerValue(
      duration: Duration(seconds: 1),
      size: Size(1920, 1080),
      isInitialized: true,
    );

    expect(
      isVideoReadyForRender(
        base.copyWith(errorDescription: 'decode failed'),
        unavailable: false,
      ),
      isFalse,
    );
    expect(
      isVideoReadyForRender(
        base.copyWith(isInitialized: false),
        unavailable: false,
      ),
      isFalse,
    );
    expect(
      isVideoReadyForRender(
        base.copyWith(size: Size.zero),
        unavailable: false,
      ),
      isFalse,
    );
  });
}
