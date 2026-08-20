// lib/main.dart
//
// Entry point. Initializes Firebase diagnostics, services, and seed data via
// AppBootstrap before launching the widget tree.

import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:neuroflow/app/bootstrap.dart';
import 'package:neuroflow/presentation/app_shell.dart';
import 'package:neuroflow/presentation/theme.dart';
import 'package:neuroflow/presentation/widgets/achievement_toast.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase config is intentionally optional for offline/local builds. CI and
  // distributed test builds restore google-services.json before compilation.
  final crashReportingReady = await _initFirebaseCrashReporting();

  // Create the shared container for early-initialization.
  final container = ProviderContainer();

  // Run all startup work (platform init, seeding, maintenance). Record startup
  // failures explicitly so crashes before runApp() are visible in Crashlytics.
  try {
    await AppBootstrap.init(container);
  } catch (error, stack) {
    if (crashReportingReady) {
      await FirebaseCrashlytics.instance.recordError(
        error,
        stack,
        fatal: true,
        reason: 'AppBootstrap.init failed during startup',
      );
    }
    rethrow;
  }

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const NeuroFlowApp(),
    ),
  );
}

Future<bool> _initFirebaseCrashReporting() async {
  try {
    await Firebase.initializeApp();

    // Capture uncaught Flutter framework errors.
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;

    // Capture uncaught asynchronous errors outside the Flutter framework.
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };

    return true;
  } catch (error) {
    // Keep local/offline-capable builds usable when Firebase config is absent.
    debugPrint('Firebase crash reporting unavailable: $error');
    return false;
  }
}

class NeuroFlowApp extends StatelessWidget {
  const NeuroFlowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NeuroFlow',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.dark, // calm-functional is dark-only by design (§13)
      home: const AchievementToastHost(child: AppShell()),
    );
  }
}
