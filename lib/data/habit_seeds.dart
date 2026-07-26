// lib/data/habit_seeds.dart
//
// Default habits for first launch. Chosen to be neutral and achievable —
// user can edit, archive, or delete any of them at any time.
//
// ADHD design rationale:
//   • Only 3 starter habits — more than 3 overwhelming before the app is
//     even personalised. (HabitsWidget also caps display at 3.)
//   • No medication reminders — too personal and varies too much.
//   • No streaks pressure in the seed data — they start at zero.
//   • All daily frequency — weekly habits add decision fatigue early on.

import 'package:neuroflow/domain/habit.dart';
import 'package:neuroflow/data/habit_repository.dart';

/// Call once during onboarding or first launch.
/// Safe to call on every startup — no-ops if habits with these names already exist.
Future<void> seedDefaultHabits(HabitRepository repo) async {
  final existing = await repo.watchActive().first;
  final existingNames = existing.map((h) => h.name).toSet();

  if (!existingNames.contains('Drink a glass of water')) {
    await repo.save(
      Habit.create(
        name: 'Drink a glass of water',
        frequency: HabitFrequency.daily,
      ),
    );
  }

  if (!existingNames.contains('Get outside for 5 minutes')) {
    await repo.save(
      Habit.create(
        name: 'Get outside for 5 minutes',
        frequency: HabitFrequency.daily,
      ),
    );
  }

  if (!existingNames.contains('Phone away 30 min before bed')) {
    await repo.save(
      Habit.create(
        name: 'Phone away 30 min before bed',
        frequency: HabitFrequency.daily,
      ),
    );
  }
}
