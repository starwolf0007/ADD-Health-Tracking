// lib/main.dart
//
// Entry point. Initializes the two Platform services that need explicit
// startup work (notifications, background jobs) before the widget tree
// builds, then hands off to TodayScreen via ProviderScope.
//
// First-launch seed: a ProviderContainer is created before runApp so
// routine defaults can be inserted into the database before the widget
// tree builds. The same container is handed to ProviderScope via
// `parent:` so no second DB connection is opened.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/habit_seeds.dart';
import 'data/routine_seeds.dart';
import 'platform/alarms/alarm_scheduler.dart';
import 'platform/background/background_scheduler.dart';
import 'platform/daily_reset.dart';
import 'platform/notifications/notification_service.dart';
import 'platform/sync/foreground_sync_observer.dart';
import 'platform/wear/wear_action_handler.dart';
import 'presentation/theme.dart';
import 'presentation/today_screen.dart';
import 'providers.dart'; // AdvisorTier, advisorTierProvider, settingsServiceProvider

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // These two are intentionally NOT Riverpod providers for their init() call
  // — provider construction stays synchronous (see lib/providers.dart), so
  // the one-time async setup happens here instead.
  await NotificationService().init();
  await BackgroundScheduler().init();
  await BackgroundScheduler().registerPeriodicJobs();

  // Bootstrap Riverpod container before runApp so we can seed the database
  // on first launch. Pass it to ProviderScope via `parent:` — this keeps
  // a single AppDatabase instance alive for the lifetime of the app.
  final container = ProviderContainer();
  await _seedOnFirstLaunch(container);
  await resetRoutinesIfNewDay(container); // resets step flags once per calendar day
  await _hydrateAdvisorTier(container);  // sync §14 AI tier from persisted prefs

  // Start listening for Complete/Snooze actions from the Pixel Watch 4.
  // No-ops gracefully if watch is unpaired or running on simulator.
  WearActionHandler(container).start();

  // Trigger a silent Google Tasks sync flush every time the app comes to the
  // foreground. Auth-gated — completely dormant until user connects Google
  // Tasks. Fixes the inbound lag problem: without this, a task added on
  // desktop wouldn't appear for up to 4h (the WorkManager interval).
  ForegroundSyncObserver(container).start();

  // Schedule the morning briefing as an exact alarm (AlarmManager) rather than
  // WorkManager, so it fires precisely on time for ADHD time-blindness.
  // WorkManager is kept only for the 4h sync flush where inexact is acceptable.
  final briefingEnabled =
      await container.read(settingsServiceProvider).getMorningBriefingEnabled();
  if (briefingEnabled) {
    await AlarmScheduler.scheduleMorning(); // defaults to 8:00 AM
  }

  runApp(ProviderScope(
    parent: container,
    child: const NeuroFlowApp(),
  ));
}

/// Reads the persisted Cloud Gemini setting and updates advisorTierProvider so
/// the correct PlanAdvisor is active immediately on launch — no Settings visit
/// required. Non-fatal: on failure the default (lexi) stays in place.
Future<void> _hydrateAdvisorTier(ProviderContainer container) async {
  try {
    final svc = container.read(settingsServiceProvider);
    final cloudEnabled = await svc.getCloudGeminiEnabled();
    if (cloudEnabled) {
      container.read(advisorTierProvider.notifier).state = AdvisorTier.cloud;
    }
    // lexi is already the default; no-op when cloudEnabled is false.
  } catch (_) {
    // Non-fatal — advisor stays at default lexi tier.
  }
}

/// Seeds default routines and habits when tables are empty (first launch).
/// Safe to call every startup — no-ops if data already exists.
Future<void> _seedOnFirstLaunch(ProviderContainer container) async {
  try {
    final routineRepo = container.read(routineRepositoryProvider);
    final existingRoutines = await routineRepo.watchActive().first;
    if (existingRoutines.isEmpty) {
      await seedDefaultRoutines(routineRepo);
    }

    final habitRepo = container.read(habitRepositoryProvider);
    final existingHabits = await habitRepo.watchActive().first;
    if (existingHabits.isEmpty) {
      await seedDefaultHabits(habitRepo);
    }
  } catch (_) {
    // Seed failure is non-fatal — app still launches without defaults.
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
      home: const TodayScreen(),
    );
  }
}
