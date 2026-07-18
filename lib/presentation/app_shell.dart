// lib/presentation/app_shell.dart
//
// The hub: Today, Notes, Routines, Reflect.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:neuroflow/presentation/notes_screen.dart';
import 'package:neuroflow/presentation/reflect_screen.dart';
import 'package:neuroflow/presentation/routines_list_screen.dart';
import 'package:neuroflow/presentation/today_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _index != 0) {
          setState(() => _index = 0);
        }
      },
      child: Scaffold(
        body: IndexedStack(
          index: _index,
          children: const [
            TodayScreen(),
            NotesScreen(),
            RoutinesListScreen(),
            ReflectScreen(),
          ],
        ),
        bottomNavigationBar: NavigationBar(
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
