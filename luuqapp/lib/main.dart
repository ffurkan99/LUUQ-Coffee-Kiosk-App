import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:video_player/video_player.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

import 'licensing/license_gate.dart';
import 'licensing/license_service.dart';
import 'licensing/license_storage.dart';
import 'licensing/feature_flags.dart';
import 'licensing/device_identity_service.dart';
import 'licensing/license_status.dart';
import 'licensing/feature_sync_service.dart';
import 'licensing/license_activation_screen.dart';
import 'licensing/license_config.dart';
import 'licensing/update_service.dart';
import 'menu/menu_models.dart';
import 'menu/menu_service.dart';
import 'menu/menu_image_view.dart';
import 'analytics/analytics_service.dart';
import 'analytics/analytics_event.dart';
import 'src/who_pays/lottery_machine_view.dart';
import 'src/who_pays/lottery_simulation.dart';

part 'app/core/theme.dart';
part 'app/core/settings.dart';
part 'app/core/i18n.dart';
part 'app/core/analytics.dart';
part 'app/menu/menu_item.dart';
part 'app/menu/menu_catalog_data.dart';
part 'app/wheel/wheel.dart';
part 'app/widgets/common.dart';
part 'app/widgets/cocktail_showcase_card.dart';
part 'app/effects/feast_candy_rain.dart';
part 'app/effects/new_year_snow.dart';
part 'app/dialogs/feature_lock.dart';
part 'app/dialogs/who_pays_dialog.dart';
part 'app/dialogs/menu_dialog.dart';
part 'app/dialogs/product_detail_dialog.dart';
part 'app/admin/admin_pin_dialog.dart';
part 'app/admin/admin_hub.dart';
part 'app/admin/wheel_content_admin.dart';
part 'app/admin/barista_admin.dart';
part 'app/admin/admin_picker.dart';
part 'app/admin/cleaning_mode_dialog.dart';
part 'app/admin/analytics_admin.dart';
part 'app/admin/theme_dialog.dart';
part 'app/admin/volume_dialog.dart';
part 'app/admin/app_info_dialog.dart';
part 'app/update/update_dialog.dart';
part 'app/kiosk/kiosk_screen.dart';
part 'app/kiosk/kiosk_layout.dart';
part 'app/kiosk/kiosk_overlays.dart';

FeatureFlags get currentFeatureFlags =>
    LicenseService.instance.currentFeatureFlags;

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

late final DateTime _appStartTime;

void main() async {
  _appStartTime = DateTime.now();
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(UpdateService.cleanupOldUpdateApks());
  await _LuuqSettings.instance.load();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  await _loadAppTheme();
  await _loadAppVolume();
  runApp(const LuuqApp());
}

class LuuqApp extends StatelessWidget {
  const LuuqApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: appLanguageNotifier,
      builder: (context, language, child) {
        return MaterialApp(
          navigatorKey: navigatorKey,
          debugShowCheckedModeBanner: false,
          title: 'LUUQ Kiosk',
          builder: (context, child) {
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: MediaQuery.textScalerOf(context)
                    .clamp(minScaleFactor: 1.0, maxScaleFactor: 1.2),
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
            scaffoldBackgroundColor: _bgDark,
            colorScheme: ColorScheme.fromSeed(
              seedColor: _caramel,
              brightness: Brightness.dark,
              surface: _surface,
            ),
            textTheme: ThemeData.dark().textTheme.apply(
              bodyColor: _cream,
              displayColor: _cream,
              fontFamily: 'Roboto',
            ),
            pageTransitionsTheme: const PageTransitionsTheme(
              builders: {
                TargetPlatform.android: ZoomPageTransitionsBuilder(),
                TargetPlatform.iOS: ZoomPageTransitionsBuilder(),
                TargetPlatform.macOS: ZoomPageTransitionsBuilder(),
                TargetPlatform.windows: ZoomPageTransitionsBuilder(),
                TargetPlatform.linux: ZoomPageTransitionsBuilder(),
                TargetPlatform.fuchsia: ZoomPageTransitionsBuilder(),
              },
            ),
          ),
          home: const LicenseGate(),
        );
      },
    );
  }
}

bool isVideoReadyForRender(
  VideoPlayerValue value, {
  required bool unavailable,
}) {
  return !unavailable &&
      value.isInitialized &&
      !value.hasError &&
      value.size.width > 0 &&
      value.size.height > 0;
}

class GlobalDialogTracker {
  static bool isUpdateDialogOpen = false;
  static bool isUpdateDownloading = false;
  static bool isUpdateVerifying = false;
  static bool isUpdateReadyToInstall = false;
  static bool isUpdateOpeningInstaller = false;
  static bool isAdminPinDialogOpen = false;

  /// The admin hub loop is running. The idle timer keeps running with a longer
  /// timeout (taps inside admin dialogs reset it) so an abandoned admin
  /// session still closes, and remote menu changes wait until it ends.
  static bool isAdminSessionOpen = false;

  static bool shouldDeferMenuChanges() =>
      shouldPauseIdleTimer() || isAdminSessionOpen;

  static bool shouldPauseIdleTimer() {
    return isUpdateDialogOpen ||
        isUpdateDownloading ||
        isUpdateVerifying ||
        isUpdateReadyToInstall ||
        isUpdateOpeningInstaller ||
        isAdminPinDialogOpen;
  }
}
