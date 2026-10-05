import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:luuqapp/main.dart';
import 'package:luuqapp/licensing/feature_flags.dart';
import 'package:luuqapp/licensing/license_gate.dart';
import 'package:luuqapp/licensing/license_service.dart';
import 'package:luuqapp/licensing/license_status.dart';
import 'package:luuqapp/src/who_pays/lottery_simulation.dart';
import 'package:luuqapp/src/who_pays/lottery_machine_view.dart';

Future<void> _pumpFrames(WidgetTester tester, [Duration? duration]) async {
  if (duration == null) {
    await tester.pump();
    return;
  }
  var remaining = duration.inMicroseconds;
  while (remaining > 0) {
    final step = remaining > 16667 ? 16667 : remaining;
    await tester.pump(Duration(microseconds: step));
    remaining -= step;
  }
}

void main() {
  testWidgets('app clamps system text enlargement to 120 percent', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(const LuuqApp());
    expect(
      MediaQuery.textScalerOf(tester.element(find.byType(LicenseGate)))
          .scale(20),
      24,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
  for (final language in AppLanguage.values) {
    testWidgets('enlarged text and reduced motion work in kiosk $language', (
      tester,
    ) async {
      _enableLicensedKiosk();
      appLanguageNotifier.value = language;
      final oldTheme = appThemeNotifier.value;
      addTearDown(() {
        appThemeNotifier.value = oldTheme;
        _disableLicensedKiosk();
      });
      appThemeNotifier.value = AppTheme.newYear;
      await _pumpKioskAtSize(
        tester,
        const Size(1920, 1080),
        textScale: 1.2,
        disableAnimations: true,
      );
      await _openWhoPaysDialog(tester, language: language);
      expect(tester.takeException(), isNull);
      final draw = language == AppLanguage.tr
          ? 'KARIŞTIR & ÇEK!'
          : 'MIX & DRAW!';
      await tester.tap(find.text(draw));
      await _pumpFrames(tester, const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
      final machine = tester.widget<WhoPaysLotteryMachineView>(
        find.byType(WhoPaysLotteryMachineView),
      );
      final completedWithWinner = language == AppLanguage.tr
          ? find
                .textContaining(RegExp(r'^Hesap [1-6]\. kişide! 🎉$'))
                .evaluate()
                .isNotEmpty
          : find
                .textContaining(RegExp(r'^Person [1-6] pays the bill! 🎉$'))
                .evaluate()
                .isNotEmpty;
      final completedWithFailure = language == AppLanguage.tr
          ? find
                .text('Top deliğe ulaşamadı. Lütfen tekrar deneyin.')
                .evaluate()
                .isNotEmpty
          : find
                .text('The balls did not reach the opening. Please try again.')
                .evaluate()
                .isNotEmpty;
      expect(completedWithWinner || completedWithFailure, isTrue);
      if (completedWithWinner) {
        expect(machine.simulation.phase, WhoPaysLotteryPhase.seated);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  for (final size in [const Size(1920, 1080), const Size(1024, 600)]) {
    testWidgets('result physics survives lifecycle and redraw at $size', (
      tester,
    ) async {
      _enableLicensedKiosk();
      await _pumpKioskAtSize(tester, size);
      await _openWhoPaysDialog(tester);
      await tester.tap(find.text('KARIŞTIR & ÇEK!'));
      await _pumpFrames(tester, const Duration(seconds: 4));
      final view = tester.widget<WhoPaysLotteryMachineView>(
        find.byType(WhoPaysLotteryMachineView),
      );
      final sim = view.simulation;
      final winner = sim.capturedBallIndex!;
      final loser = (winner + 1) % sim.personCount;
      sim.balls[loser].position = const Offset(0, -85);
      sim.balls[loser].velocity = Offset.zero;
      sim.wake();
      await _pumpFrames(tester, const Duration(milliseconds: 100));
      expect(sim.balls[loser].position.dy, greaterThan(-85));
      final time = sim.timelineSeconds;
      final position = sim.balls[loser].position;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 20));
      expect(sim.timelineSeconds, time);
      expect(sim.balls[loser].position, position);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _pumpFrames(tester, const Duration(milliseconds: 150));
      expect(sim.timelineSeconds, greaterThan(time));
      expect(sim.timelineSeconds, lessThan(time + 0.2));
      expect(sim.capturedBallIndex, winner);
      expect(find.text('Tekrar Çek'), findsOneWidget);
      if (const bool.fromEnvironment('LOTTERY_QA_CAPTURE')) {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find
              .ancestor(
                of: find.byType(Dialog),
                matching: find.byType(RepaintBoundary),
              )
              .first,
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ImageByteFormat.png);
          final output = File(
            'build/lottery-qa/result-${size.width.toInt()}.png',
          );
          await output.parent.create(recursive: true);
          await output.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.tap(find.text('Tekrar Çek'));
      await tester.pump();
      final next = tester
          .widget<WhoPaysLotteryMachineView>(
            find.byType(WhoPaysLotteryMachineView),
          )
          .simulation;
      expect(next, isNot(same(sim)));
      expect(next.balls[loser].position, sim.balls[loser].position);
      expect(next.balls[loser].velocity, sim.balls[loser].velocity);
      await _pumpFrames(tester, const Duration(seconds: 5));
      expect(find.text('Tekrar Çek'), findsOneWidget);
      // Keep the existing kiosk idle timeout from closing the test dialog.
      for (var i = 0; i < 5; i++) {
        await tester.tap(
          find.descendant(
            of: find.byKey(const ValueKey('who_pays_card')),
            matching: find.text('HESAP KİMDE?'),
          ),
        );
        await _pumpFrames(tester, const Duration(seconds: 5));
      }
      expect(next.isSleeping, isTrue);
      final sleepingTime = next.timelineSeconds;
      await _pumpFrames(tester, const Duration(seconds: 1));
      expect(
        next.timelineSeconds,
        sleepingTime,
        reason: 'UI ticker should stop at rest',
      );
      await tester.tap(find.text('Tekrar Çek'));
      await _pumpFrames(tester, const Duration(milliseconds: 150));
      final awake = tester
          .widget<WhoPaysLotteryMachineView>(
            find.byType(WhoPaysLotteryMachineView),
          )
          .simulation;
      expect(awake.isSleeping, isFalse);
      expect(awake.timelineSeconds, greaterThan(0));
      await tester.tap(find.byKey(const ValueKey('who_pays_close_button')));
      await _pumpFrames(tester, const Duration(milliseconds: 400));
      expect(find.byType(WhoPaysLotteryMachineView), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      _disableLicensedKiosk();
    });
  }
  setUpAll(_loadRobotoForWidgetTests);

  tearDown(() {
    final binding = TestWidgetsFlutterBinding.instance;
    binding.platformDispatcher.views.single.resetPhysicalSize();
    binding.platformDispatcher.views.single.resetDevicePixelRatio();
  });

  testWidgets('builds the application and shows license gate', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const LuuqApp());

    expect(find.byType(LuuqApp), findsOneWidget);
    expect(find.byType(LicenseGate), findsOneWidget);

    await _pumpFrames(tester, const Duration(milliseconds: 350));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('builds the kiosk screen directly', (WidgetTester tester) async {
    await _pumpKioskAtSize(tester, const Size(1920, 1080));
    expect(find.byType(CafeKioskScreen), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('lays out on phone and kiosk screens', (
    WidgetTester tester,
  ) async {
    await _pumpKioskAtSize(tester, const Size(390, 844));
    expect(tester.takeException(), isNull);

    await _pumpKioskAtSize(tester, const Size(1920, 1080));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('who pays draw keeps a visible winning ball and result', (
    WidgetTester tester,
  ) async {
    _enableLicensedKiosk();
    await _pumpKioskAtSize(tester, const Size(1920, 1080));
    await _openWhoPaysDialog(tester);

    expect(find.text('KARIŞTIR & ÇEK!'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('KARIŞTIR & ÇEK!')).textAlign,
      TextAlign.center,
    );
    final initialCloseButton = find.byKey(
      const ValueKey('who_pays_close_button'),
    );
    expect(initialCloseButton, findsOneWidget);
    expect(tester.getSize(initialCloseButton).height, greaterThanOrEqualTo(44));
    expect(find.bySemanticsLabel('Hesap Kimde ekranını kapat'), findsOneWidget);
    await tester.tapAt(const Offset(8, 8));
    await _pumpFrames(tester, const Duration(milliseconds: 300));
    expect(find.text('KARIŞTIR & ÇEK!'), findsOneWidget);

    // Dokunma geri bildirimi standardı: diyalogdaki basılabilir öğeler
    // (kişi sayısı çipleri, oyuncu kartları, ana buton, Kapat) BouncyButton
    // ile sarılı olmalı.
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.byType(BouncyButton),
      ),
      findsAtLeastNWidgets(8),
    );

    await tester.tap(find.text('KARIŞTIR & ÇEK!'));
    await _pumpFrames(tester);
    expect(find.text('KARILIYOR...'), findsOneWidget);

    await _pumpFrames(
      tester,
      Duration(
        milliseconds: WhoPaysLotterySimulation.idleDurationMilliseconds + 200,
      ),
    );
    await _pumpFrames(tester);

    expect(
      find.textContaining(RegExp(r'^Hesap [1-6]\. kişide! 🎉$')),
      findsOneWidget,
    );
    expect(find.text('Tekrar Çek'), findsOneWidget);
    expect(find.text('Kapat'), findsOneWidget);
    expect(
      tester
          .widget<Text>(
            find.textContaining(RegExp(r'^Hesap [1-6]\. kişide! 🎉$')),
          )
          .textAlign,
      TextAlign.center,
    );
    final winnerRect = tester.getRect(
      find.byKey(const ValueKey('who_pays_winner_message')),
    );
    final redrawRect = tester.getRect(
      find.byKey(const ValueKey('who_pays_redraw_button')),
    );
    final closeRect = tester.getRect(
      find.byKey(const ValueKey('who_pays_close_button')),
    );
    expect(redrawRect.width, winnerRect.width);
    expect(closeRect.width, winnerRect.width);
    expect(redrawRect.left, winnerRect.left);
    expect(closeRect.left, winnerRect.left);
    expect(redrawRect.right, winnerRect.right);
    expect(closeRect.right, winnerRect.right);
    expect(redrawRect.top, greaterThanOrEqualTo(winnerRect.bottom));
    expect(closeRect.top, greaterThan(redrawRect.bottom));
    expect(redrawRect.top - winnerRect.bottom, 8);
    expect(closeRect.top - redrawRect.bottom, 8);
    expect(winnerRect.height, greaterThanOrEqualTo(44));
    expect(redrawRect.height, greaterThanOrEqualTo(44));
    expect(closeRect.height, greaterThanOrEqualTo(44));
    expect(
      find.bySemanticsLabel(RegExp(r'Kazanan top çıkışta: [1-6]\. kişi')),
      findsOneWidget,
    );

    // Yeniden çekiliş: sonuç topu geri emilir, yeni çekiliş tam süre oynar.
    await tester.tap(find.text('Tekrar Çek'));
    await _pumpFrames(tester);
    expect(find.text('KARILIYOR...'), findsOneWidget);

    // Redraw sonucu sabit nominal süreye değil, topun fiziksel olarak
    // yuvaya oturmasına bağlıdır. Bu nedenle test sonucu sabit bir karede
    // değil, sonuç aksiyonu görünene kadar sınırlı biçimde bekler.
    for (
      var attempt = 0;
      attempt < 120 &&
          find.byKey(const ValueKey('who_pays_redraw_button')).evaluate().isEmpty;
      attempt++
    ) {
      await _pumpFrames(tester, const Duration(milliseconds: 100));
    }
    expect(
      find.textContaining(RegExp(r'^Hesap [1-6]\. kişide! 🎉$')),
      findsOneWidget,
    );
    expect(find.text('Tekrar Çek'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    _disableLicensedKiosk();
  });

  testWidgets('who pays dialog keeps one size across draw states', (
    WidgetTester tester,
  ) async {
    _enableLicensedKiosk();
    await _pumpKioskAtSize(tester, const Size(1920, 1080));
    await _openWhoPaysDialog(tester);

    // Alt bölge (buton/sonuç) durumlar arasında farklı içerik gösterir;
    // kartın yüksekliği yine de sabit kalmalı — sonuç açıklanınca kart
    // büyüyüp görsel kayma yaratamaz.
    final card = find.byKey(const ValueKey('who_pays_card'));
    final idleSize = tester.getSize(card);
    final idleCloseRect = tester.getRect(
      find.byKey(const ValueKey('who_pays_close_button')),
    );
    expect(idleCloseRect.height, greaterThanOrEqualTo(44));

    await tester.tap(find.text('KARIŞTIR & ÇEK!'));
    await _pumpFrames(tester, const Duration(milliseconds: 350));
    expect(find.text('KARILIYOR...'), findsOneWidget);
    expect(tester.getSize(card), idleSize);
    expect(
      tester.getRect(find.byKey(const ValueKey('who_pays_close_button'))),
      idleCloseRect,
    );

    await _pumpFrames(
      tester,
      Duration(
        milliseconds: WhoPaysLotterySimulation.idleDurationMilliseconds + 200,
      ),
    );
    await _pumpFrames(tester, const Duration(milliseconds: 150));
    expect(tester.takeException(), isNull);
    await _pumpFrames(tester, const Duration(milliseconds: 200));
    expect(find.text('Tekrar Çek'), findsOneWidget);
    expect(tester.getSize(card), idleSize);
    expect(
      tester.getRect(find.byKey(const ValueKey('who_pays_close_button'))),
      idleCloseRect,
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    _disableLicensedKiosk();
  });

  testWidgets('who pays result actions fit in English', (
    WidgetTester tester,
  ) async {
    _enableLicensedKiosk();
    appLanguageNotifier.value = AppLanguage.en;
    await _pumpKioskAtSize(tester, const Size(1920, 1080));
    await _openWhoPaysDialog(tester, language: AppLanguage.en);

    expect(find.text('MIX & DRAW!'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
    expect(find.bySemanticsLabel('Close Who Pays'), findsOneWidget);

    await tester.tap(find.text('MIX & DRAW!'));
    await _pumpFrames(tester);
    await _pumpFrames(
      tester,
      Duration(
        milliseconds: WhoPaysLotterySimulation.idleDurationMilliseconds + 200,
      ),
    );
    await _pumpFrames(tester, const Duration(milliseconds: 350));

    expect(
      find.textContaining(RegExp(r'^Person [1-6] pays the bill! 🎉$')),
      findsOneWidget,
    );
    expect(find.text('Draw Again'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    _disableLicensedKiosk();
  });
  testWidgets('who pays result grid fits on a narrow landscape kiosk', (
    WidgetTester tester,
  ) async {
    _enableLicensedKiosk();
    await _pumpKioskAtSize(tester, const Size(1280, 720));

    final overflowErrors = <String>[];
    final previousOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      final message = details.exceptionAsString();
      if (message.toLowerCase().contains('overflow')) {
        overflowErrors.add(message);
      }
      previousOnError?.call(details);
    };

    try {
      await _openWhoPaysDialog(tester);
      await tester.tap(find.text('KARIŞTIR & ÇEK!'));
      await _pumpFrames(tester);
      await _pumpFrames(
        tester,
        Duration(
          milliseconds: WhoPaysLotterySimulation.idleDurationMilliseconds + 50,
        ),
      );
      await _pumpFrames(tester, const Duration(milliseconds: 150));

      // Fiziksel capture sonucu nominal sürede değil, top gerçekten yuvaya
      // oturduğunda bildirilir. Dar görünüm testi bu fiziksel sonucu sabit bir
      // kareye bağlamamalı; sonuç aksiyonu görünene kadar sınırlı biçimde
      // ilerlemelidir.
      for (
        var attempt = 0;
        attempt < 120 &&
            find.byKey(const ValueKey('who_pays_redraw_button')).evaluate().isEmpty;
        attempt++
      ) {
        await _pumpFrames(tester, const Duration(milliseconds: 100));
      }

      expect(find.textContaining('Hesap '), findsOneWidget);
      final winnerRect = tester.getRect(
        find.byKey(const ValueKey('who_pays_winner_message')),
      );
      final redrawRect = tester.getRect(
        find.byKey(const ValueKey('who_pays_redraw_button')),
      );
      final closeRect = tester.getRect(
        find.byKey(const ValueKey('who_pays_close_button')),
      );
      expect(redrawRect.width, winnerRect.width);
      expect(closeRect.width, winnerRect.width);
      expect(closeRect.left, winnerRect.left);
      expect(closeRect.right, winnerRect.right);
      expect(redrawRect.top, greaterThanOrEqualTo(winnerRect.bottom));
      expect(closeRect.top, greaterThan(redrawRect.bottom));
      expect(overflowErrors, isEmpty);
      expect(tester.takeException(), isNull);
    } finally {
      FlutterError.onError = previousOnError;
      await tester.pumpWidget(const SizedBox.shrink());
      _disableLicensedKiosk();
    }
  });
  testWidgets('who pays locks controls and supports six-player redraw', (
    WidgetTester tester,
  ) async {
    _enableLicensedKiosk();
    await _pumpKioskAtSize(tester, const Size(1920, 1080));
    await _openWhoPaysDialog(tester);

    await tester.tap(find.text('6').first);
    await _pumpFrames(tester);
    expect(find.text('6. Kişi'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('KARIŞTIR & ÇEK!'));
    await _pumpFrames(tester);
    expect(find.text('KARILIYOR...'), findsOneWidget);

    await tester.tap(find.text('KARILIYOR...'));
    await _pumpFrames(tester, const Duration(milliseconds: 100));
    expect(find.text('KARILIYOR...'), findsOneWidget);
    expect(find.text('KARIŞTIR & ÇEK!'), findsNothing);
    expect(tester.takeException(), isNull);

    await _pumpFrames(
      tester,
      Duration(
        milliseconds: WhoPaysLotterySimulation.idleDurationMilliseconds + 200,
      ),
    );
    await _pumpFrames(tester);
    expect(find.text('Tekrar Çek'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    _disableLicensedKiosk();
  });

  testWidgets('who pays reduced motion skips the chaotic movement', (
    WidgetTester tester,
  ) async {
    _enableLicensedKiosk();
    await _pumpKioskAtSize(
      tester,
      const Size(1920, 1080),
      disableAnimations: true,
    );
    await _openWhoPaysDialog(tester);

    await tester.tap(find.text('KARIŞTIR & ÇEK!'));
    await _pumpFrames(tester);
    expect(find.text('KARILIYOR...'), findsOneWidget);

    await _pumpFrames(tester, const Duration(milliseconds: 200));
    await _pumpFrames(tester);
    expect(find.text('Tekrar Çek'), findsOneWidget);
    expect(find.text('Kapat'), findsOneWidget);
    final winnerRect = tester.getRect(
      find.byKey(const ValueKey('who_pays_winner_message')),
    );
    final redrawRect = tester.getRect(
      find.byKey(const ValueKey('who_pays_redraw_button')),
    );
    final closeRect = tester.getRect(
      find.byKey(const ValueKey('who_pays_close_button')),
    );
    expect(redrawRect.top, greaterThanOrEqualTo(winnerRect.bottom));
    expect(closeRect.top, greaterThan(redrawRect.bottom));
    expect(winnerRect.height, greaterThanOrEqualTo(44));
    expect(redrawRect.height, greaterThanOrEqualTo(44));
    expect(closeRect.height, greaterThanOrEqualTo(44));
    expect(
      find.bySemanticsLabel(RegExp(r'Kazanan top çıkışta: [1-6]\. kişi')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    _disableLicensedKiosk();
  });
}

Future<void> _pumpKioskAtSize(
  WidgetTester tester,
  Size size, {
  bool disableAnimations = false,
  double textScale = 1.0,
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;

  // Replicate LuuqApp's MaterialApp themes/builders for CafeKioskScreen
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: disableAnimations,
          ),
          child: child!,
        );
      },
      scrollBehavior: const MaterialScrollBehavior().copyWith(
        dragDevices: {
          PointerDeviceKind.mouse,
          PointerDeviceKind.touch,
          PointerDeviceKind.stylus,
          PointerDeviceKind.unknown,
        },
      ),
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF16131D),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFD88E2B),
          brightness: Brightness.dark,
          surface: const Color(0xFF231E2D),
        ),
        textTheme: ThemeData.dark().textTheme.apply(
          bodyColor: const Color(0xFFFFF7EC),
          displayColor: const Color(0xFFFFF7EC),
          fontFamily: 'Roboto',
        ),
      ),
      home: const CafeKioskScreen(),
    ),
  );
  await _pumpFrames(tester, const Duration(milliseconds: 350));
}

Future<void> _openWhoPaysDialog(
  WidgetTester tester, {
  AppLanguage language = AppLanguage.tr,
}) async {
  final launchLabel = language == AppLanguage.tr
      ? 'Mini Çarkı Aç'
      : 'Open Mini Wheel';
  final drawLabel = language == AppLanguage.tr
      ? 'KARIŞTIR & ÇEK!'
      : 'MIX & DRAW!';

  final viewportSize = tester.view.physicalSize / tester.view.devicePixelRatio;
  final viewportCenter = Offset(
    viewportSize.width / 2,
    viewportSize.height / 2,
  );
  for (var i = 0; i < 60 && find.text(launchLabel).evaluate().isEmpty; i++) {
    await tester.tapAt(viewportCenter);
    await _pumpFrames(tester, const Duration(milliseconds: 100));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
  }
  expect(find.text(launchLabel), findsOneWidget);
  await tester.tap(find.text(launchLabel));
  await _pumpFrames(tester, const Duration(milliseconds: 300));
  await _pumpFrames(tester, const Duration(milliseconds: 300));
  expect(find.text(drawLabel), findsOneWidget);
  expect(find.byKey(const ValueKey('who_pays_machine')), findsOneWidget);
}

void _enableLicensedKiosk() {
  appLanguageNotifier.value = AppLanguage.tr;
  LicenseService.instance.statusNotifier.value = const LicenseStatus(
    active: true,
    mode: LicenseMode.licensed,
    features: FeatureFlags.proDefault,
  );
}

void _disableLicensedKiosk() {
  LicenseService.instance.statusNotifier.value = const LicenseStatus(
    active: false,
    mode: LicenseMode.none,
    features: FeatureFlags.lockedAll,
  );
}

Future<void> _loadRobotoForWidgetTests() async {
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot == null) {
    throw StateError(
      'FLUTTER_ROOT is required for deterministic widget tests.',
    );
  }
  final bytes = await File(
    '$flutterRoot/bin/cache/artifacts/material_fonts/roboto-regular.ttf',
  ).readAsBytes();
  final loader = FontLoader('Roboto')
    ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
  await loader.load();
}
