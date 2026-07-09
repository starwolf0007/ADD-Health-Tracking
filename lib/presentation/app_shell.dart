// lib/presentation/app_shell.dart
//
// The hub (v2, approved; Phase 2 · Stage 3 adds Your Day): five tabs, one
// job each.
//   Today    — the one thing (+ focus timer)
//   Your Day — the read-only timeline spine + Re-Entry Card
//   Notes    — frictionless capture, promote to task
//   Routines — one-step-at-a-time runners
//   Reflect  — mood check-in, gentle week view, habits
//
// IndexedStack keeps every tab's state alive — a half-run routine or a
// ticking focus timer survives tab switches. NavigationBar is styled
// inline against locked tokens; no theme-level override needed.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'notes_screen.dart';
import 'reflect_screen.dart';
import 'routines_list_screen.dart';
import 'theme.dart';
import 'timeline_screen.dart';
import 'today_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [
          TodayScreen(),
          TimelineScreen(),
          NotesScreen(),
          RoutinesListScreen(),
          ReflectScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          backgroundColor: AppColors.surface,
          indicatorColor: AppColors.accentWash,
          surfaceTintColor: Colors.transparent,
          height: 64,
          labelTextStyle: WidgetStateProperty.resolveWith(
            (states) => AppTextStyles.label.copyWith(
              fontSize: 11,
              color: states.contains(WidgetState.selected)
                  ? AppColors.accent
                  : AppColors.textSecondary,
            ),
          ),
          iconTheme: WidgetStateProperty.resolveWith(
            (states) => IconThemeData(
              size: 22,
              color: states.contains(WidgetState.selected)
                  ? AppColors.accent
                  : AppColors.textSecondary,
            ),
          ),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) {
            if (i == _index) return;
            HapticFeedback.selectionClick();
            setState(() => _index = i);
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.wb_sunny_outlined),
              selectedIcon: Icon(Icons.wb_sunny),
              label: 'Today',
            ),
            NavigationDestination(
              icon: Icon(Icons.view_day_outlined),
              selectedIcon: Icon(Icons.view_day),
              label: 'Your Day',
            ),
            NavigationDestination(
              icon: Icon(Icons.sticky_note_2_outlined),
              selectedIcon: Icon(Icons.sticky_note_2),
              label: 'Notes',
            ),
            NavigationDestination(
              icon: Icon(Icons.repeat_rounded),
              selectedIcon: Icon(Icons.repeat_on_rounded),
              label: 'Routines',
            ),
            NavigationDestination(
              icon: Icon(Icons.spa_outlined),
              selectedIcon: Icon(Icons.spa),
              label: 'Reflect',
            ),
          ],
        ),
      ),
    );
  }
}
