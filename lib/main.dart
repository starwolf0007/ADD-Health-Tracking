// lib/main.dart
//
// Entry point. Initializes the two Platform services that need explicit
// startup work (notifications, background jobs) before the widget tree
// builds, then hands off to TodayScreen via ProviderScope.
//
// First-launch seed: a ProviderContainer is created before runApp so
// routine/habit defaults can be inserted before the widget tree builds.
// The same container is handed to ProviderScope via `parent:` so no
// second DB connection is opened.
//
// (This file was previously truncated mid-comment; the bootstrap below
// completes what its own header described.)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/providers.dart';
import 'data/habit_seeds.dart';
import 'data/routine_seeds.dart';
import 'platform/background/background_scheduler.dart';
import 'platform/daily_reset.dart';
import 'platform/notifications/notification_service.dart';
import 'presentation/theme.dart';
import 'presentation/app_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // One-time async platform setup — intentionally NOT inside providers so
  // provider construction stays synchronous (see lib/app/providers.dart).
  await NotificationService().init();
  await BackgroundScheduler().init();
  await BackgroundScheduler().registerPeriodicJobs();

  // Bootstrap the container before runApp for first-launch seeding and the
  // new-day routine reset.
  final container = ProviderContainer();
  await seedDefaultRoutines(container.read(routineRepositoryProvider));
  await seedDefaultHabits(container.read(habitRepositoryProvider));
  await resetRoutinesIfNewDay(container);

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const NeuroFlowApp(),
    ),
  );
}

class NeuroFlowApp extends StatelessWidget {
  const NeuroFlowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NeuroFlow',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: const AppShell(),
    );
  }
}
