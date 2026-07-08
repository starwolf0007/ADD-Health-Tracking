// lib/app/bootstrap.dart
//
// App-wide initialization and seeding logic.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:neuroflow/data/habit_seeds.dart';
import 'package:neuroflow/data/routine_seeds.dart';
import 'package:neuroflow/platform/daily_reset.dart';
import 'package:neuroflow/platform/notifications/notification_service.dart';
import 'package:neuroflow/platform/background/background_scheduler.dart';
import 'package:neuroflow/platform/wear/wear_action_handler.dart';
import 'package:neuroflow/platform/sync/foreground_sync_observer.dart';
import 'package:neuroflow/platform/alarms/alarm_scheduler.dart';
import 'package:neuroflow/app/providers.dart';

class AppBootstrap {
  /// Run all startup initialization.
  static Future<void> init(ProviderContainer container) async {
    // 1. Platform services
    await NotificationService().init();
    await BackgroundScheduler().init();
    await BackgroundScheduler().registerPeriodicJobs();

    // 2. Data seeding (no-ops if already seeded)
    await _seedOnFirstLaunch(container);
    await _cleanupDuplicates(container);
    
    // 3. State maintenance
    await resetRoutinesIfNewDay(container);
    await _hydrateAdvisorTier(container);
    await container.read(googleServiceManagerProvider).restoreSession();

    // 4. Integrations
    WearActionHandler(container).start();
    ForegroundSyncObserver(container).start();

    // 5. Alarms
    final briefingEnabled = await container.read(settingsServiceProvider).getMorningBriefingEnabled();
    if (briefingEnabled) {
      await AlarmScheduler.scheduleMorning();
    }
  }

  static Future<void> _seedOnFirstLaunch(ProviderContainer container) async {
    final routineRepo = container.read(routineRepositoryProvider);
    await seedDefaultRoutines(routineRepo);

    final habitRepo = container.read(habitRepositoryProvider);
    await seedDefaultHabits(habitRepo);
  }

  static Future<void> _cleanupDuplicates(ProviderContainer container) async {
    final routineRepo = container.read(routineRepositoryProvider);
    final habitRepo = container.read(habitRepositoryProvider);

    final routines = await routineRepo.watchActive().first;
    final seenRoutines = <String>{};
    for (final routine in routines) {
      if (seenRoutines.contains(routine.name)) {
        await routineRepo.delete(routine.id);
      } else {
        seenRoutines.add(routine.name);
      }
    }

    final habits = await habitRepo.watchActive().first;
    final seenHabits = <String>{};
    for (final habit in habits) {
      if (seenHabits.contains(habit.name)) {
        await habitRepo.delete(habit.id);
      } else {
        seenHabits.add(habit.name);
      }
    }
  }

  static Future<void> _hydrateAdvisorTier(ProviderContainer container) async {
    try {
      final svc = container.read(settingsServiceProvider);
      final cloudEnabled = await svc.getCloudGeminiEnabled();
      if (cloudEnabled) {
        container.read(advisorTierProvider.notifier).state = AdvisorTier.cloud;
      }
    } catch (_) {
      // Non-fatal
    }
  }
}
