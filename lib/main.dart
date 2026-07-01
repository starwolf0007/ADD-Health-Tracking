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
import 'platform/background/background_scheduler.dart';
import 'platform/daily_reset.dart';
import 'platform/notifications/notification_service.dart';
import 'presentation/theme.dart';
import 'presentation/today_screen.dart';
import 'providers.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // These two are intentionally NOT Riverpod providers for their init() call
  // — provider construction stays synchronous (see lib/providers.dart), so
  // the one-time async setup happens here instead.
  await NotificationService().init();
  await BackgroundScheduler().init();
  await BackgroundScheduler().registerPeriodicJobs();

  // Bootstrap Riverpod container before runApp so we can seed the database
  // on