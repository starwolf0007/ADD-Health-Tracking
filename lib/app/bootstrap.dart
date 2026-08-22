// lib/app/bootstrap.dart
//
// App-wide initialization and seeding logic.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:neuroflow/app/providers.dart';
import 'package:neuroflow/core/diagnostics/startup_diagnostics.dart';
import 'package:neuroflow/data/habit_seeds.dart';
import 'package:neuroflow/data/routine_seeds.dart';
import 'package:neuroflow/platform/alarms/alarm_scheduler.dart';
import 'package:neuroflow/platform/background/background_scheduler.dart';
import 'package:neuroflow/platform/daily_reset.dart';
import 'package:neuroflow/platform/notifications/notification_service.dart';
import 'package:neuroflow/platform/sync/foreground_sync_observer.dart';
import 'package:neuroflow/platform/wear/wear_action_handler.dart';

class AppBootstrap {
  /// Run all startup initialization.
  static Future<void> init(ProviderContainer container) async {
    // 1. Platform services
    await _executePhase('notifications', () => NotificationService().init());
    await _executePhase('workmanager_init', () => BackgroundScheduler().init());
    await _executePhase(
      'workmanager_register',
      () => BackgroundScheduler().registerPeriodicJobs(),
    );

    // 2. Data seeding (no-ops if already seeded)
    await _executePhase('database_seed', () => _seedOnFirstLaunch(container));
    await _executePhase(
      'database_dedupe',
      () => _cleanupDuplicates(container),
    );

    // 3. State maintenance
    await _executePhase(
      'daily_reset',
      () => resetRoutinesIfNewDay(container),
    );
    await _executePhase(
      'advisor_tier',
      () => _hydrateAdvisorTier(container),
    );
    await _executePhase(
      'restore_session',
      () => container.read(googleServiceManagerProvider).restoreSession(),
    );

    // 4. Integrations
    await _executePhase(
      'wear_actions',
      () => Future.sync(() => WearActionHandler(container).start()),
    );
    await _executePhase(
      'foreground_sync',
      () => Future.sync(() => ForegroundSyncObserver(container).start()),
    );

    // 5. Alarms
    final briefingEnabled = await _executePhase<bool>(
      'morning_briefing_setting',
      () => container
          .read(settingsServiceProvider)
          .getMorningBriefingEnabled(),
    );
    if (briefingEnabled) {
      await _executePhase('morning_alarm', AlarmScheduler.scheduleMorning);
    }

    await StartupDiagnostics.markRunning();
  }

  static Future<T> _executePhase<T>(
    String phase,
    Future<T> Function() action,
  ) async {
    await StartupDiagnostics.checkpoint(phase, status: 'begin');
    try {
      final result = await action();
      await StartupDiagnostics.checkpoint(phase, status: 'ready');
      return result;
    } catch (error) {
      await StartupDiagnostics.markFailure(phase, error);
      rethrow;
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
        container.read(advisorTierProvider.notifier).set(AdvisorTier.cloud);
      }
    } catch (_) {
      // Non-fatal
    }
  }
}
