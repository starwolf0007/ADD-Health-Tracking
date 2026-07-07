// lib/app/bootstrap.dart
//
// App-wide initialization and seeding logic.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/habit_seeds.dart';
import '../data/routine_seeds.dart';
import '../platform/daily_reset.dart';
import '../platform/notifications/notification_service.dart';
import '../platform/background/background_scheduler.dart';
import '../platform/wear/wear_action_handler.dart';
import '../platform/sync/foreground_sync_observer.dart';
import '../platform/alarms/alarm_scheduler.dart';
import 'providers.dart';

class AppBootstrap {
  /// Run all startup initialization.
  static Future<void> init(ProviderContainer container) async {
    // 1. Platform services
    await NotificationService().init();
    await BackgroundScheduler().init();
    await BackgroundScheduler().registerPeriodicJobs();

    // 2. Data seeding (no-ops if already seeded)
    await _seedOnFirstLaunch(container);
    
    // 3. State maintenance
    await resetRoutinesIfNewDay(container);
    await _hydrateAdvisorTier(container);

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
