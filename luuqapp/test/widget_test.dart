import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:luuqapp/main.dart';
import 'package:luuqapp/licensing/feature_flags.dart';
import 'package:luuqapp/licensing/license_gate.dart';
import 'package:luuqapp/licensing/license_service.dart';
import 'package:luuqapp/licensing/license_status.dart';
import 'package:luuqapp/src/who_pays/lottery_simulation.dart';

void main() {
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

    await tester.pump(const Duration(milliseconds: 350));
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
    await tester.tapAt(const Offset(8, 8));
    await tester.pump(const Duration(milliseconds: 300));
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
    await tester.pump();
    expect(find.text('KARILIYOR...'), findsOneWidget);

    await tester.pump(
      Duration(
        milliseconds: WhoPaysLotterySimulation.idleDurationMilliseconds + 200,
      ),
    );
    await tester.pump();

    expect(
      find.textContaining(RegExp(r'^Hesap [1-6]\. kişide! 🎉$')),
      findsOneWidget,
    );
    expect(find.text('Tekrar Çek'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp(r'Kazanan top çıkışta: [1-6]\. kişi')),
      findsOneWidget,
    );

    // Yeniden çekiliş: sonuç topu geri emilir, yeni çekiliş tam süre oynar.
    await tester.tap(find.text('Tekrar Çek'));
    await tester.pump();
    expect(find.text('KARILIYOR...'), findsOneWidget);

    // Süreklilik kanıtı: yeniden çekiliş intake nedeniyle 3850 ms sürer —
    // idle süre + pay geçtikten sonra sonuç HENÜZ görünmemeli.
    //
    // Not: kontrol noktası idle süreden (3400 ms) sadece 200 ms sonraya
    // konursa kanıt yanlış pozitif verir: sonuç paneli ile "KARILIYOR..."
    // düğmesi arasında 300 ms'lik bir AnimatedSwitcher geçişi var, bu
    // yüzden bozuk/eski (initialState geçirilmemiş) 3400 ms'lik bir
    // simülasyon bile 3400+200=3600 ms'de "KARILIYOR..." widget'ını hâlâ
    // (geçiş animasyonunun kalıntısı olarak) ağaçta bırakır. Kontrol
    // noktasını, 300 ms'lik geçişi geride bırakacak ama gerçek 3850 ms'lik
    // yeniden çekilişin bitişinden (idle + 450 ms) önce kalacak şekilde
    // idle + 375 ms'ye taşıyoruz.
    const probeOffsetMs = 375;
    await tester.pump(
      const Duration(
        milliseconds:
            WhoPaysLotterySimulation.idleDurationMilliseconds + probeOffsetMs,
      ),
    );
    expect(find.text('KARILIYOR...'), findsOneWidget);
    expect(find.text('Tekrar Çek'), findsNothing);

    await tester.pump(
      Duration(
        milliseconds:
            WhoPaysLotterySimulation.redrawDurationMilliseconds +
            200 -
            WhoPaysLotterySimulation.idleDurationMilliseconds -
            probeOffsetMs,
      ),
    );
    await tester.pump();

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

    await tester.tap(find.text('KARIŞTIR & ÇEK!'));
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('KARILIYOR...'), findsOneWidget);
    expect(tester.getSize(card), idleSize);

    await tester.pump(
      Duration(
        milliseconds: WhoPaysLotterySimulation.idleDurationMilliseconds + 200,
      ),
    );
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('Tekrar Çek'), findsOneWidget);
    expect(tester.getSize(card), idleSize);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    _disableLicensedKiosk();
  });

  testWidgets('who pays locks controls and supports six-player redraw', (
    WidgetTester tester,
  ) async {
    _enableLicensedKiosk();
    await _pumpKioskAtSize(tester, const Size(1920, 1080));
    await _openWhoPaysDialog(tester);

    await tester.tap(find.text('6').first);
    await tester.pump();
    expect(find.text('6. Kişi'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('KARIŞTIR & ÇEK!'));
    await tester.pump();
    expect(find.text('KARILIYOR...'), findsOneWidget);

    await tester.tap(find.text('KARILIYOR...'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('KARILIYOR...'), findsOneWidget);
    expect(find.text('KARIŞTIR & ÇEK!'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pump(
      Duration(
        milliseconds: WhoPaysLotterySimulation.idleDurationMilliseconds + 200,
      ),
    );
    await tester.pump();
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
    await tester.pump();
    expect(find.text('KARILIYOR...'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    expect(find.text('Tekrar Çek'), findsOneWidget);
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
            textScaler: const TextScaler.linear(1.0),
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
  await tester.pump(const Duration(milliseconds: 350));
}

Future<void> _openWhoPaysDialog(WidgetTester tester) async {
  for (
    var i = 0;
    i < 60 && find.text('Mini Çarkı Aç').evaluate().isEmpty;
    i++
  ) {
    await tester.tapAt(const Offset(960, 540));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
  }
  expect(find.text('Mini Çarkı Aç'), findsOneWidget);
  await tester.tap(find.text('Mini Çarkı Aç'));
  await tester.pump(const Duration(milliseconds: 300));
  expect(find.text('KARIŞTIR & ÇEK!'), findsOneWidget);
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
