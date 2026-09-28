import 'dart:ui';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/data/constants.dart';
import 'package:flutter_app/data/notifiers.dart';
import 'package:flutter_app/firebase_options.dart';
import 'package:flutter_app/services/error_log_service.dart';
import 'package:flutter_app/views/pages/others/auth_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

final AppRouteObserver routeObserver = AppRouteObserver();

void main() async {
  // 1. Ensure Flutter framework is fully bootstrapped
  WidgetsFlutterBinding.ensureInitialized();

  // 2. Initialize Firebase with platform-specific options
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

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
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: isDarkModeNotifier,
      builder: (BuildContext context, bool isDarkMode, Widget? child) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.lightBlue, brightness: isDarkMode ? Brightness.dark : Brightness.light),
          ),
          navigatorObservers: [routeObserver],
          home: AuthPage(),
        );
      },
    );
  }
}
