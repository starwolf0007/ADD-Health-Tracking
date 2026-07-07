// lib/main.dart
//
// Entry point. Initializes services and seeds data via AppBootstrap
// before launching the widget tree.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:neuroflow/app/bootstrap.dart';
import 'package:neuroflow/presentation/app_shell.dart';
import 'package:neuroflow/presentation/theme.dart';
import 'package:neuroflow/presentation/widgets/achievement_toast.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Create the shared container for early-initialization.
  final container = ProviderContainer();

  // Run all startup work (platform init, seeding, maintenance).
  await AppBootstrap.init(container);

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
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.dark, // calm-functional is dark-only by design (§13)
      home: const AchievementToastHost(child: AppShell()),
    );
  }
}
