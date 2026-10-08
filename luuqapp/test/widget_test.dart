import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:luuqapp/main.dart';
import 'package:luuqapp/licensing/feature_flags.dart';
import 'package:luuqapp/licensing/feature_sync_service.dart';
import 'package:luuqapp/licensing/license_gate.dart';
import 'package:luuqapp/licensing/license_service.dart';
import 'package:luuqapp/licensing/license_status.dart';
import 'package:luuqapp/menu/menu_models.dart';
import 'package:luuqapp/menu/menu_service.dart';
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

/// Çekiliş sonucu sabit bir süreye değil, topun yuvaya fiziksel olarak
/// oturmasına bağlıdır; bazı tohumlarda nominal süreyi ~1 sn aşar. Önce
/// nominal süreyi oynatır, sonra sonuç düğmesi görünene kadar sınırlı bekler
/// (simülasyonun üst sınırı maxPostDurationWaitSeconds = 8 sn).
Future<void> _pumpUntilDrawResult(WidgetTester tester) async {
  await _pumpFrames(
    tester,
    Duration(
      milliseconds: WhoPaysLotterySimulation.idleDurationMilliseconds + 200,
    ),
  );
  final result = find.byKey(const ValueKey('who_pays_redraw_button'));
  for (var attempt = 0; attempt < 90 && result.evaluate().isEmpty; attempt++) {
    await _pumpFrames(tester, const Duration(milliseconds: 100));
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

    await _pumpUntilDrawResult(tester);
    await _pumpFrames(tester);

    expect(
      find.textContaining(RegExp(r'^Hesap [1-6]\. kişide! 🎉$')),
      findsOneWidget,
    );
    expect(find.text('Tekrar Çek'), findsOneWidget);
    expect(find.byKey(const ValueKey('who_pays_close_button')), findsOneWidget);
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
    expect(redrawRect.left, winnerRect.left);
    expect(redrawRect.right, winnerRect.right);
    expect(redrawRect.top, greaterThanOrEqualTo(winnerRect.bottom));
    expect(closeRect.bottom, lessThan(winnerRect.top));
    expect(redrawRect.top - winnerRect.bottom, 8);
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
          find
              .byKey(const ValueKey('who_pays_redraw_button'))
              .evaluate()
              .isEmpty;
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

  testWidgets('a lost connection covers the kiosk until it is back', (
    WidgetTester tester,
  ) async {
    _enableLicensedKiosk();
    await _pumpKioskAtSize(tester, const Size(1920, 1080));
    // Leave the loading/idle screens first, as a customer tap would.
    for (
      var i = 0;
      i < 60 && find.text('Mini Çarkı Aç').evaluate().isEmpty;
      i++
    ) {
      await tester.tapAt(const Offset(960, 540));
      await _pumpFrames(tester, const Duration(milliseconds: 100));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
    expect(find.text('İnternet Bağlantısı Yok'), findsNothing);

    FeatureSyncService.instance.connectionLost.value = true;
    await _pumpFrames(tester);
    expect(find.text('İnternet Bağlantısı Yok'), findsOneWidget);

    FeatureSyncService.instance.connectionLost.value = false;
    await _pumpFrames(tester);
    expect(find.text('İnternet Bağlantısı Yok'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    // Let the deferred menu precache loop see the disposed screen and stop.
    await _pumpFrames(tester, const Duration(milliseconds: 300));
    _disableLicensedKiosk();
  });

  testWidgets('an abandoned menu returns to the idle screen after 60 s', (
    WidgetTester tester,
  ) async {
    _enableLicensedKiosk();
    await _pumpKioskAtSize(tester, const Size(1920, 1080));
    for (
      var i = 0;
      i < 60 && find.text('TÜM MENÜYÜ İNCELE').evaluate().isEmpty;
      i++
    ) {
      await tester.tapAt(const Offset(960, 540));
      await _pumpFrames(tester, const Duration(milliseconds: 100));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
    await tester.tap(find.text('TÜM MENÜYÜ İNCELE'));
    await _pumpFrames(tester, const Duration(milliseconds: 400));
    expect(find.byType(Dialog), findsOneWidget);

    // Longer than the 15 s main-screen timeout: the open menu stays.
    for (var s = 0; s < 30; s++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(find.byType(Dialog), findsOneWidget);

    // Past 60 s without a touch the menu closes and the kiosk goes idle.
    for (var s = 0; s < 32; s++) {
      await tester.pump(const Duration(seconds: 1));
    }
    await _pumpFrames(tester, const Duration(milliseconds: 400));
    expect(find.byType(Dialog), findsNothing);
    expect(GlobalDialogTracker.isCustomerDialogOpen, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpFrames(tester, const Duration(milliseconds: 300));
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

    await _pumpUntilDrawResult(tester);
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
    expect(find.byKey(const ValueKey('who_pays_close_button')), findsOneWidget);
    expect(find.bySemanticsLabel('Close Who Pays'), findsOneWidget);

    await tester.tap(find.text('MIX & DRAW!'));
    await _pumpFrames(tester);
    await _pumpUntilDrawResult(tester);
    await _pumpFrames(tester, const Duration(milliseconds: 350));

    expect(
      find.textContaining(RegExp(r'^Person [1-6] pays the bill! 🎉$')),
      findsOneWidget,
    );
    expect(find.text('Draw Again'), findsOneWidget);
    expect(find.byKey(const ValueKey('who_pays_close_button')), findsOneWidget);
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
            find
                .byKey(const ValueKey('who_pays_redraw_button'))
                .evaluate()
                .isEmpty;
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
      expect(redrawRect.top, greaterThanOrEqualTo(winnerRect.bottom));
      expect(closeRect.bottom, lessThan(winnerRect.top));
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

    await _pumpUntilDrawResult(tester);
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
    expect(find.byKey(const ValueKey('who_pays_close_button')), findsOneWidget);
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
    expect(closeRect.bottom, lessThan(winnerRect.top));
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

  group('customer dialogs', () {
    Future<void> openMenu(WidgetTester tester) async {
      for (
        var i = 0;
        i < 60 && find.text('TÜM MENÜYÜ İNCELE').evaluate().isEmpty;
        i++
      ) {
        await tester.tapAt(const Offset(960, 540));
        await _pumpFrames(tester, const Duration(milliseconds: 100));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
      }
      await tester.tap(find.text('TÜM MENÜYÜ İNCELE'));
      await _pumpFrames(tester, const Duration(milliseconds: 500));
      expect(find.byType(Dialog), findsOneWidget);
    }

    tearDown(_disableLicensedKiosk);

    testWidgets('the menu opens over a blurred scrim and closes outside', (
      tester,
    ) async {
      _enableLicensedKiosk();
      await _pumpKioskAtSize(tester, const Size(1920, 1080));
      await openMenu(tester);
      expect(find.byType(BackdropFilter), findsWidgets);

      // A tap inside the menu keeps it open, one outside closes it.
      await tester.tap(find.text('LUUQ MENÜ'));
      await _pumpFrames(tester, const Duration(milliseconds: 300));
      expect(find.byType(Dialog), findsOneWidget);
      await tester.tapAt(const Offset(4, 4));
      await _pumpFrames(tester, const Duration(milliseconds: 300));
      expect(find.byType(Dialog), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpFrames(tester, const Duration(milliseconds: 300));
    });

    testWidgets('a product photo flies into the detail, the X closes it', (
      tester,
    ) async {
      _enableLicensedKiosk();
      await _pumpKioskAtSize(tester, const Size(1920, 1080));
      await openMenu(tester);

      final cardPhoto = find.descendant(
        of: find.byType(Dialog),
        matching: find.byType(Hero),
      );
      expect(cardPhoto, findsWidgets);
      final tag = tester.widget<Hero>(cardPhoto.first).tag;
      await tester.tap(cardPhoto.first);
      await _pumpFrames(tester, const Duration(milliseconds: 500));

      // The detail photo carries the tapped card's tag.
      final sameTag = find.byWidgetPredicate((w) => w is Hero && w.tag == tag);
      expect(sameTag, findsNWidgets(2));
      expect(find.byType(Dialog), findsNWidgets(2));

      await tester.tap(find.byIcon(Icons.close_rounded).last);
      await _pumpFrames(tester, const Duration(milliseconds: 400));
      expect(find.byType(Dialog), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpFrames(tester, const Duration(milliseconds: 300));
    });

    testWidgets('a search without results offers products and categories', (
      tester,
    ) async {
      _enableLicensedKiosk();
      await _pumpKioskAtSize(tester, const Size(1920, 1080));
      await openMenu(tester);

      await tester.enterText(find.byType(TextField), 'qqqzzz');
      await _pumpFrames(tester, const Duration(milliseconds: 400));
      expect(find.text('Sonuç bulunamadı'), findsOneWidget);
      expect(find.text('Şunlara göz atabilirsiniz:'), findsOneWidget);

      // A category chip clears the search and opens that category.
      final chip = find.descendant(
        of: find.byKey(const ValueKey('no_results_qqqzzz')),
        matching: find.byType(BouncyButton),
      );
      expect(chip, findsWidgets);
      await tester.tap(chip.last);
      await _pumpFrames(tester, const Duration(milliseconds: 400));
      expect(find.text('Sonuç bulunamadı'), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpFrames(tester, const Duration(milliseconds: 300));
    });

    testWidgets('with animations off a dialog is fully open at once', (
      tester,
    ) async {
      _enableLicensedKiosk();
      await _pumpKioskAtSize(
        tester,
        const Size(1920, 1080),
        disableAnimations: true,
      );
      for (
        var i = 0;
        i < 60 && find.text('TÜM MENÜYÜ İNCELE').evaluate().isEmpty;
        i++
      ) {
        await tester.tapAt(const Offset(960, 540));
        await _pumpFrames(tester, const Duration(milliseconds: 100));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
      }
      await tester.tap(find.text('TÜM MENÜYÜ İNCELE'));
      await tester.pump();
      await tester.pump();
      final route = ModalRoute.of(tester.element(find.byType(Dialog)))!;
      expect(route.animation!.value, 1);

      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpFrames(tester, const Duration(milliseconds: 300));
    });
  });

  group('small fixes', () {
    // A test that ends with a dialog open leaves this set; a new menu would
    // then wait for the dialog to close.
    setUp(() => GlobalDialogTracker.isCustomerDialogOpen = false);
    tearDown(_disableLicensedKiosk);

    testWidgets('the result card flashes once and its content stays put', (
      tester,
    ) async {
      _enableLicensedKiosk();
      await _pumpKioskAtSize(
        tester,
        const Size(1920, 1080),
        disableAnimations: true,
      );
      await _wakeKiosk(tester, 'ÇARKI ÇEVİR');
      await tester.tap(find.text('ÇARKI ÇEVİR'));
      await tester.pump();
      await tester.pump();

      final resultArea = find.byWidgetPredicate(
        (w) =>
            w is TweenAnimationBuilder<double> &&
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('result_'),
      );
      expect(resultArea, findsOneWidget);
      final card = find
          .descendant(of: resultArea, matching: find.byType(Container))
          .first;
      final label = find.text('BUGÜNKÜ SEÇİMİN');

      double flashAlpha() {
        final decoration =
            tester.widget<Container>(card).foregroundDecoration
                as BoxDecoration?;
        return decoration?.border?.top.color.a ?? 0;
      }

      // Relative to the card's size: the whole card may pulse in scale.
      Offset labelOffset() {
        final cardRect = tester.getRect(card);
        final offset = tester.getTopLeft(label) - cardRect.topLeft;
        return Offset(
          (offset.dx / cardRect.width * 1000).roundToDouble(),
          (offset.dy / cardRect.height * 1000).roundToDouble(),
        );
      }

      final firstOffset = labelOffset();
      var previous = flashAlpha();
      expect(previous, greaterThan(0));
      for (var frame = 0; frame < 80; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        final alpha = flashAlpha();
        expect(alpha, lessThanOrEqualTo(previous + 1e-9));
        expect(labelOffset(), firstOffset);
        previous = alpha;
      }
      expect(previous, 0);

      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpFrames(tester, const Duration(milliseconds: 300));
    });

    testWidgets('the product detail X closes from its outer corner too', (
      tester,
    ) async {
      _enableLicensedKiosk();
      await _pumpKioskAtSize(tester, const Size(1920, 1080));
      await _openMenu(tester);
      await tester.tap(
        find
            .descendant(of: find.byType(Dialog), matching: find.byType(Hero))
            .first,
      );
      await _pumpFrames(tester, const Duration(milliseconds: 500));
      expect(find.byType(Dialog), findsNWidgets(2));

      final close = find
          .ancestor(
            of: find.descendant(
              of: find.byType(Dialog).last,
              matching: find.byIcon(Icons.close_rounded),
            ),
            matching: find.byType(BouncyButton),
          )
          .first;
      expect(close, findsOneWidget);
      final rect = tester.getRect(close);
      expect(rect.height, greaterThanOrEqualTo(44));
      // Near the top-right edge, where the old button took no taps.
      await tester.tapAt(rect.topRight + const Offset(-10, 10));
      await _pumpFrames(tester, const Duration(milliseconds: 400));
      expect(find.byType(Dialog), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpFrames(tester, const Duration(milliseconds: 300));
    });

    testWidgets('long prices stay on one line in their badges', (tester) async {
      _enableLicensedKiosk();
      addTearDown(() => MenuService.instance.catalogNotifier.value = null);
      final (overflows, restore) = _collectOverflows();
      addTearDown(restore);
      await _pumpKioskAtSize(tester, const Size(1920, 1080));
      await _setMenuCatalog(
        tester,
        _layoutCatalog([
          (name: 'Latte', price: '185₺ / 205₺', tags: [], description: ''),
          (
            name: 'Büyük Latte',
            price: '1.250₺ / 1.450₺',
            tags: [],
            description: '',
          ),
          (name: 'Pasta', price: '12.500₺', tags: [], description: ''),
        ]),
      );
      await _openMenu(tester);

      // A four-digit price is as tall as a short one: not wrapped, and
      // (with the wider badge) not shrunk either.
      final short = tester.getSize(_inDialog(find.text('185₺')));
      final long = tester.getSize(_inDialog(find.text('1.250₺')));
      expect(long.height, short.height);
      expect(long.width, lessThanOrEqualTo(60));
      final single = tester.getSize(_inDialog(find.text('12.500₺')));
      expect(single.width, lessThanOrEqualTo(90 - 16));

      for (final name in ['Büyük Latte', 'Pasta']) {
        await tester.tap(_inDialog(find.text(name)));
        await _pumpFrames(tester, const Duration(milliseconds: 500));
        expect(find.byType(Dialog), findsNWidgets(2));
        await tester.tap(
          _inDialog(find.byIcon(Icons.close_rounded), last: true),
        );
        await _pumpFrames(tester, const Duration(milliseconds: 400));
      }
      expect(overflows, isEmpty);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpFrames(tester, const Duration(milliseconds: 300));
    });

    for (final language in AppLanguage.values) {
      testWidgets('a long name and many tags fit the menu card ($language)', (
        tester,
      ) async {
        _enableLicensedKiosk();
        appLanguageNotifier.value = language;
        addTearDown(() => MenuService.instance.catalogNotifier.value = null);
        final (overflows, restore) = _collectOverflows();
        addTearDown(restore);
        await _pumpKioskAtSize(tester, const Size(1920, 1080));
        const longName =
            'Beyaz Çikolatalı Karamelli Fındıklı Tarçınlı Vanilyalı Buzlu '
            'Latte Grande Special Edition';
        await _setMenuCatalog(
          tester,
          _layoutCatalog([
            (
              name: longName,
              price: '1.250₺ / 1.450₺',
              tags: ['Popüler', 'Soğuk', 'Sütlü', 'Tatlı', 'Kafeinli', 'Yeni'],
              description:
                  'Espresso, beyaz çikolata, karamel ve fındık şurubu, süt ve '
                  'bol buz ile hazırlanan, üzeri krema ile süslenen bir içecek.',
            ),
            (name: 'Latte', price: '185₺ / 205₺', tags: [], description: ''),
          ]),
        );
        await _wakeKiosk(
          tester,
          language == AppLanguage.tr ? 'TÜM MENÜYÜ İNCELE' : 'BROWSE FULL MENU',
        );
        await tester.tap(
          find.text(
            language == AppLanguage.tr
                ? 'TÜM MENÜYÜ İNCELE'
                : 'BROWSE FULL MENU',
          ),
        );
        await _pumpFrames(tester, const Duration(milliseconds: 500));

        // Cut to two lines with an ellipsis; the badge is still there.
        final name = _inDialog(find.textContaining('…', findRichText: true));
        expect(name, findsOneWidget);
        expect(
          _inDialog(
            find.text(language == AppLanguage.tr ? 'Popüler' : 'Popular'),
          ),
          findsWidgets,
        );
        expect(overflows, isEmpty);
        expect(tester.takeException(), isNull);

        // The detail still shows the whole name.
        await tester.tap(name);
        await _pumpFrames(tester, const Duration(milliseconds: 500));
        expect(find.byType(Dialog), findsNWidgets(2));
        expect(overflows, isEmpty);
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await _pumpFrames(tester, const Duration(milliseconds: 300));
      });
    }

    for (final (language, textScale) in [
      (AppLanguage.en, 1.0),
      (AppLanguage.tr, 1.0),
      (AppLanguage.tr, 1.2),
    ]) {
      testWidgets('six players and the colour palette fit Who Pays '
          '($language, text x$textScale)', (tester) async {
        _enableLicensedKiosk();
        appLanguageNotifier.value = language;
        final (overflows, restore) = _collectOverflows();
        addTearDown(restore);
        await _pumpKioskAtSize(
          tester,
          const Size(1920, 1080),
          textScale: textScale,
        );
        await _openWhoPaysDialog(tester, language: language);
        String player(int i) =>
            language == AppLanguage.tr ? '$i. Kişi' : 'Person $i';

        await tester.tap(find.text('6').first);
        await _pumpFrames(tester, const Duration(milliseconds: 300));
        await tester.tap(find.text(player(1)));
        await _pumpFrames(tester, const Duration(milliseconds: 300));
        expect(find.text(player(6)), findsOneWidget);
        expect(
          find.bySemanticsLabel(RegExp('Oyuncu rengi|Player color')),
          findsWidgets,
        );

        // Two rows of three (the selected chip's thicker border moves its
        // text by a pixel).
        final tops = [
          for (var i = 1; i <= 6; i++)
            tester.getCenter(find.text(player(i))).dy,
        ]..sort();
        var rows = 1;
        for (var i = 1; i < tops.length; i++) {
          if (tops[i] - tops[i - 1] > 8) rows++;
        }
        expect(rows, 2);
        final card = tester.getRect(
          find.byKey(const ValueKey('who_pays_card')),
        );
        expect(card.top, greaterThanOrEqualTo(0));
        expect(card.bottom, lessThanOrEqualTo(1080));
        expect(overflows, isEmpty);
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await _pumpFrames(tester, const Duration(milliseconds: 300));
      });
    }
  });

  group('performance', () {
    setUp(() => GlobalDialogTracker.isCustomerDialogOpen = false);
    tearDown(_disableLicensedKiosk);

    // The center area only composites its children's layers each pulse
    // frame; what it holds is drawn in these boundaries.
    const areas = [
      'kiosk_left_column',
      'kiosk_right_column',
      'kiosk_wheel_face',
    ];

    int paints(WidgetTester tester, String key) {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(ValueKey(key)),
      );
      return boundary.debugSymmetricPaintCount +
          boundary.debugAsymmetricPaintCount;
    }

    testWidgets('the pulse repaints only its own layers', (tester) async {
      _enableLicensedKiosk();
      await _pumpKioskAtSize(tester, const Size(1920, 1080));
      await _wakeKiosk(tester, 'ÇARKI ÇEVİR');
      await _pumpFrames(tester, const Duration(seconds: 2));

      final before = {for (final key in areas) key: paints(tester, key)};
      await _pumpFrames(tester, const Duration(milliseconds: 500));
      for (final key in areas) {
        expect(paints(tester, key), before[key], reason: key);
      }

      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpFrames(tester, const Duration(milliseconds: 300));
    });

    testWidgets('the pulse rests while the wheel spins', (tester) async {
      _enableLicensedKiosk();
      await _pumpKioskAtSize(tester, const Size(1920, 1080));
      await _wakeKiosk(tester, 'ÇARKI ÇEVİR');
      await _pumpFrames(tester, const Duration(milliseconds: 1500));
      expect(debugKioskPulseAnimating(), isTrue);

      await tester.tap(find.text('ÇARKI ÇEVİR'));
      await _pumpFrames(tester, const Duration(milliseconds: 200));
      expect(find.text('SEÇİLİYOR...'), findsOneWidget);
      expect(debugKioskPulseAnimating(), isFalse);

      await _pumpFrames(tester, const Duration(seconds: 6));
      expect(find.text('BUGÜNKÜ SEÇİMİN'), findsOneWidget);
      expect(debugKioskPulseAnimating(), isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpFrames(tester, const Duration(milliseconds: 300));
    });
  });
}

/// A one-category server menu of [items] (name, price, tags), for layout
/// tests with long content.
MenuCatalog _layoutCatalog(
  List<({String name, String price, List<String> tags, String description})>
  items,
) {
  return MenuCatalog.fromApiJson({
    'schema_version': 2,
    'menu_version': 1,
    'catalog_revision': 1,
    'effective_revision': 'layout-test',
    'catalog': {
      'categories': [
        {
          'id': 'cat-0',
          'name_tr': 'Kahveler',
          'icon_key': 'local_cafe_rounded',
          'items': [
            for (final item in items)
              {
                'id': item.name,
                'category_id': 'cat-0',
                'name_tr': item.name,
                'description_tr': item.description,
                'price_text': item.price,
                'tags': item.tags,
                'icon_key': 'local_cafe_rounded',
              },
          ],
        },
      ],
    },
    'wheel_item_ids': const <String>[],
  });
}

Future<void> _setMenuCatalog(WidgetTester tester, MenuCatalog? catalog) async {
  MenuService.instance.catalogNotifier.value = catalog;
  await _pumpFrames(tester, const Duration(milliseconds: 200));
}

/// Collects layout overflow errors until the returned callback restores the
/// previous error handler.
(List<String>, void Function()) _collectOverflows() {
  final overflows = <String>[];
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    final message = details.exceptionAsString();
    if (message.toLowerCase().contains('overflow')) overflows.add(message);
    previous?.call(details);
  };
  return (overflows, () => FlutterError.onError = previous);
}

Finder _inDialog(Finder finder, {bool last = false}) => find.descendant(
  of: last ? find.byType(Dialog).last : find.byType(Dialog).first,
  matching: finder,
);

Future<void> _openMenu(WidgetTester tester) async {
  await _wakeKiosk(tester, 'TÜM MENÜYÜ İNCELE');
  await tester.tap(find.text('TÜM MENÜYÜ İNCELE'));
  await _pumpFrames(tester, const Duration(milliseconds: 500));
  expect(find.byType(Dialog), findsOneWidget);
}

/// Taps the idle kiosk awake until [label] is on screen.
Future<void> _wakeKiosk(WidgetTester tester, String label) async {
  for (var i = 0; i < 60 && find.text(label).evaluate().isEmpty; i++) {
    await tester.tapAt(const Offset(960, 540));
    await _pumpFrames(tester, const Duration(milliseconds: 100));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
  }
  expect(find.text(label), findsOneWidget);
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
