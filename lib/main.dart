import 'dart:async';
import 'dart:ui';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/data/notifiers.dart';
import 'package:selecta_ops/firebase_options.dart';
import 'package:selecta_ops/services/error_log_service.dart';
import 'package:selecta_ops/services/push_notification_service.dart';
import 'package:selecta_ops/theme/app_theme.dart';
import 'package:selecta_ops/views/pages/others/auth_page.dart';
import 'package:selecta_ops/views/widgets/offline_banner_widget.dart';
import 'package:selecta_ops/views/widgets/snackbar_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

final AppRouteObserver routeObserver = AppRouteObserver();

void main() async {
  // 1. Ensure Flutter framework is fully bootstrapped
  WidgetsFlutterBinding.ensureInitialized();

  // Configure GoogleFonts to permit runtime fetching with seamless system font fallback
  GoogleFonts.config.allowRuntimeFetching = true;

  // 2. Initialize Firebase with platform-specific options
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // 3. Initialize Push Notification Service (FCM) asynchronously without blocking startup
  unawaited(PushNotificationService().initialize().catchError((e, s) {
    debugPrint('PushNotificationService init error: $e');
  }));

  // 3. Register global error interceptors for unhandled exceptions
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    ErrorLogService.logError(
      action: 'Unhandled Flutter Framework Error',
      error: details.exceptionAsString(),
      stackTrace: details.stack,
      page: ErrorLogService.currentPage,
    );
  };

  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    ErrorLogService.logError(
      action: 'Unhandled Platform / Async Error',
      error: error.toString(),
      stackTrace: stack,
      page: ErrorLogService.currentPage,
    );
    return true; // Mark as handled to avoid crashing
  };

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    initThemeMode();
    super.initState();
  }

  void initThemeMode() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final bool? repeat = prefs.getBool(KConstants.themeModeKey);
    isDarkModeNotifier.value = repeat ?? false;

    final String? savedPreset = prefs.getString('app_theme_preset_key');
    if (savedPreset != null) {
      appThemePresetNotifier.value = AppThemePreset.fromString(savedPreset);
    }

    final double? savedFontScale = prefs.getDouble('app_font_scale_key');
    if (savedFontScale != null) {
      appFontScaleNotifier.value = savedFontScale;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([isDarkModeNotifier, appThemePresetNotifier, appFontScaleNotifier]),
      builder: (BuildContext context, Widget? child) {
        final isDarkMode = isDarkModeNotifier.value;
        final preset = appThemePresetNotifier.value;
        final fontScale = appFontScaleNotifier.value;

        return MaterialApp(
          scaffoldMessengerKey: rootScaffoldMessengerKey,
          title: 'Selecta Ops',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightThemeFor(preset),
          darkTheme: AppTheme.darkThemeFor(preset),
          themeMode: isDarkMode ? ThemeMode.dark : ThemeMode.light,
          navigatorObservers: [routeObserver],
          builder: (context, child) => OfflineBannerWrapper(
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(fontScale),
              ),
              child: child ?? const SizedBox.shrink(),
            ),
          ),
          home: const AuthPage(),
        );
      },
    );
  }
}
