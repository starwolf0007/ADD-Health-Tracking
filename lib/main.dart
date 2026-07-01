// lib/main.dart
//
// Entry point. Initializes the two Platform services that need explicit
// startup work (notifications, background jobs) before the widget tree
// builds, then hands off to TodayScreen via ProviderScope.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'platform/background/background_scheduler.dart';
import 'platform/notifications/notification_service.dart';
import 'presentation/theme.dart';
import 'presentation/today_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // These two are intentionally NOT Riverpod providers for their init() call
  // — provider construction stays synchronous (see app/providers.dart), so
  // the one-time async setup happens here instead.
  await NotificationService().init();
  await BackgroundScheduler().init();
  await BackgroundScheduler().registerPeriodicJobs();

  runApp(const ProviderScope(child: NeuroFlowApp()));
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
      home: const TodayScreen(),
    );
  }
}
