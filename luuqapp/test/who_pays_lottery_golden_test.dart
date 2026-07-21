import 'dart:math' as math;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luuqapp/src/who_pays/lottery_machine_view.dart';
import 'package:luuqapp/src/who_pays/lottery_simulation.dart';

const _playerColors = <Color>[
  Color(0xFFE8B445),
  Color(0xFF48C9B0),
  Color(0xFFFF7675),
  Color(0xFF74B9FF),
  Color(0xFFA29BFE),
  Color(0xFF55EFC4),
];

void main() {
  setUpAll(_loadRobotoForGoldens);

  testWidgets('lottery machine idle appearance', (tester) async {
    await _expectMachineGolden(
      tester,
      seconds: 0,
      goldenName: 'who_pays_idle.png',
    );
  });

  testWidgets('lottery machine mixing appearance', (tester) async {
    await _expectMachineGolden(
      tester,
      seconds: 1.5,
      goldenName: 'who_pays_mixing.png',
    );
  });

  testWidgets('lottery machine capture appearance', (tester) async {
    await _expectMachineGolden(
      tester,
      seconds: 2.80,
      goldenName: 'who_pays_capture.png',
    );
  });

  testWidgets('lottery machine result appearance', (tester) async {
    await _expectMachineGolden(
      tester,
      seconds: 3.40,
      goldenName: 'who_pays_result.png',
    );
  });
}

Future<void> _loadRobotoForGoldens() async {
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot == null) {
    throw StateError('FLUTTER_ROOT is required for deterministic goldens.');
  }
  final bytes = await File(
    '$flutterRoot/bin/cache/artifacts/material_fonts/roboto-regular.ttf',
  ).readAsBytes();
  final loader = FontLoader('Roboto')
    ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
  await loader.load();
}

Future<void> _expectMachineGolden(
  WidgetTester tester, {
  required double seconds,
  required String goldenName,
}) async {
  final simulation = WhoPaysLotterySimulation(
    personCount: 6,
    seed: 20260720,
  );
  _advanceInFrames(simulation, seconds);

  final repaint = ValueNotifier<int>(0);
  addTearDown(repaint.dispose);
  const boundaryKey = ValueKey('lottery_golden_boundary');

  tester.view
    ..physicalSize = const Size(440, 440)
    ..devicePixelRatio = 1;
  addTearDown(() {
    tester.view
      ..resetPhysicalSize()
      ..resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF231E2D),
        body: Center(
          child: RepaintBoundary(
            key: boundaryKey,
            child: WhoPaysLotteryMachineView(
              simulation: simulation,
              playerColors: _playerColors,
              repaint: repaint,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();

  await expectLater(
    find.byKey(boundaryKey),
    matchesGoldenFile('goldens/$goldenName'),
  );
}

void _advanceInFrames(WhoPaysLotterySimulation simulation, double endSeconds) {
  var target = simulation.timelineSeconds;
  while (target < endSeconds) {
    target = math.min(target + 1 / 60, endSeconds);
    simulation.advanceTo(target);
  }
}
