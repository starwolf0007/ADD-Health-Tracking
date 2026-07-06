// lib/data/database.dart
//
// The system of record (§12.3): local Drift/SQLite, source of truth.
// Google services are mirrors, never masters. This file is the ONLY place
// schema lives — one generation, one schema, no forks.
//
// v2 unified schema — seven tables:
//   Tasks, Habits, HabitCheckIns, Routines, RoutineSteps  (Phase-1 core)
//   Notes                                                  (v2 capture hub)
//   MoodLogs                                               (v2 §6 trigger — §2.8 ON-DEVICE ONLY)
//
// Method surface below matches lib/data/*_repository_impl.dart exactly.
// After dropping this file in: dart run build_runner build -d
// generates database.g.dart.

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'database.g.dart';

// ---------------------------------------------------------------------------
// Tables
// ---------------------------------------------------------------------------

@DataClassName('TaskRow')
class Tasks extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get notes => text().nullable()();
  TextColumn get energy => text()(); // 'low' | 'medium' | 'high'
  // v3: holds TaskState.storageKey ('not_started'..'complete').
  // Legacy v2 values ('pending'/'completed'/'skipped') are rewritten by the
  // v2→v3 migration below.
  TextColumn get status => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get dueDate => dateTime().nullable()();
  BoolColumn get isQuickWin => boolean().withDefault(const Constant(false))();
  IntColumn get estimatedMinutes => integer().nullable()(); // v2 focus target
  DateTimeColumn get completedAt => dateTime().nullable()();
  // v3 living-state / Re-Entry metadata:
  DateTimeColumn get pausedAt => dateTime().nullable()();
  TextColumn get pausedStep => text().nullable()();
  TextColumn get pausedNote => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('HabitRow')
class Habits extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get notes => text().nullable()();
  TextColumn get frequency => text()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('HabitCheckInRow')
class HabitCheckIns extends Table {
  TextColumn get id => text()();
  TextColumn get habitId => text()();
  DateTimeColumn get date => dateTime()(); // day-truncated by the repository
  BoolColumn get completed => boolean()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('RoutineRow')
class Routines extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get anchor => text()(); // RoutineAnchor.name
  IntColumn get scheduleHour => integer().nullable()(); // custom anchor only
  IntColumn get scheduleMinute => integer().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  // Which weekdays this routine fires, as a compact string of ISO weekday
  // digits (Mon=1 … Sun=7). "12345" = weekdays. NULL = every day (back-comat).
  TextColumn get activeDays => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('RoutineStepRow')
class RoutineSteps extends Table {
  TextColumn get id => text()();
  TextColumn get routineId => text()();
  IntColumn get position => integer()();
  TextColumn get title => text()();
  TextColumn get notes => text().nullable()();
  IntColumn get durationMinutes => integer().nullable()();
  BoolColumn get isComplete => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('NoteRow')
class Notes extends Table {
  TextColumn get id => text()();
  TextColumn get body => text()();
  BoolColumn get pinned => boolean().withDefault(const Constant(false))();
  TextColumn get linkedTaskId => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// §2.8 HARD RULE — SENSITIVE, ON-DEVICE ONLY.
/// No googleId column, no sync flag, no mirror companion. The absence is
/// the enforcement: a row that cannot reference a remote cannot leak.
/// Any future SyncQueue work MUST NOT touch this table.
@DataClassName('MoodLogRow')
class MoodLogs extends Table {
  TextColumn get id => text()();
  IntColumn get level => integer()(); // MoodLevel.score, 1..5
  TextColumn get note => text().nullable()();
  DateTimeColumn get loggedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

// ---------------------------------------------------------------------------
// Database
// ---------------------------------------------------------------------------

@DriftDatabase(tables: [
  Tasks,
  Habits,
  HabitCheckIns,
  Routines,
  RoutineSteps,
  Notes,
  MoodLogs,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_open());

  /// Test constructor — inject an in-memory executor.
  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          // v1 -> v2: add Routines.activeDays (nullable; null = every day).
          if (from < 2) {
            await m.addColumn(routines, routines.activeDays);
          }
          // v2 -> v3: living-state model.
          // 1. add the three pause-metadata columns.
          // 2. rewrite legacy status strings into TaskState keys.
          if (from < 3) {
            await m.addColumn(tasks, tasks.pausedAt);
            await m.addColumn(tasks, tasks.pausedStep);
            await m.addColumn(tasks, tasks.pausedNote);
            // Map old binary states → living states (data-preserving).
            await customStatement(
                "UPDATE tasks SET status = 'not_started' WHERE status = 'pending'");
            await customStatement(
                "UPDATE tasks SET status = 'complete' WHERE status = 'completed'");
            await customStatement(
                "UPDATE tasks SET status = 'blocked' WHERE status = 'skipped'");
          }
        },
      );

  DateTime get _startOfToday {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  static int _energyRank(String e) => switch (e) {
        'low' => 0,
        'medium' => 1,
        'high' => 2,
        _ => 1,
      };

  // ---- Tasks --------------------------------------------------------------

  Future<void> upsertTask(TasksCompanion entry) =>
      into(tasks).insertOnConflictUpdate(entry);

  Future<void> markComplete(String id) =>
      (update(tasks)..where((t) => t.id.equals(id))).write(
        TasksCompanion(
          status: const Value('complete'),
          completedAt: Value(DateTime.now()),
        ),
      );

  Future<void> deleteTask(String id) =>
      (delete(tasks)..where((t) => t.id.equals(id))).go();

  /// "Open, not-yet-started" tasks, easiest first. Under living-state, the
  /// plan surfaces not_started tasks; interrupted (paused/blocked) tasks are
  /// handled by the Re-Entry flow, not the normal plan.
  Stream<List<TaskRow>> watchPendingByEnergyAsc() {
    final query = select(tasks)
      ..where((t) => t.status.equals('not_started'));
    return query.watch().map((rows) {
      rows.sort((a, b) {
        final e = _energyRank(a.energy).compareTo(_energyRank(b.energy));
        if (e != 0) return e;
        if (a.dueDate != null || b.dueDate != null) {
          if (a.dueDate == null) return 1;
          if (b.dueDate == null) return -1;
          final d = a.dueDate!.compareTo(b.dueDate!);
          if (d != 0) return d;
        }
        return a.createdAt.compareTo(b.createdAt);
      });
      return rows;
    });
  }

  /// Interrupted tasks (paused/blocked), most-recently-paused first — the
  /// Re-Entry Card's data source (Phase 2). These are what the user should be
  /// nudged to *return* to.
  Stream<List<TaskRow>> watchInterrupted() {
    final query = select(tasks)
      ..where((t) => t.status.equals('paused') | t.status.equals('blocked'))
      ..orderBy([(t) => OrderingTerm.desc(t.pausedAt)]);
    return query.watch();
  }

  Stream<int> watchCompletedTodayCount() {
    final query = select(tasks)
      ..where((t) =>
          t.status.equals('complete') &
          t.completedAt.isBiggerOrEqualValue(_startOfToday));
    return query.watch().map((rows) => rows.length);
  }

  /// Completed tasks today, as rows (for the timeline projection).
  Stream<List<TaskRow>> watchCompletedToday() {
    final query = select(tasks)
      ..where((t) =>
          t.status.equals('complete') &
          t.completedAt.isBiggerOrEqualValue(_startOfToday))
      ..orderBy([(t) => OrderingTerm.asc(t.completedAt)]);
    return query.watch();
  }

  // ---- Habits ---------------------------------------------------------------

  Future<void> upsertHabit(HabitsCompanion entry) =>
      into(habits).insertOnConflictUpdate(entry);

  Future<void> archiveHabit(String id) =>
      (update(habits)..where((h) => h.id.equals(id)))
          .write(const HabitsCompanion(isActive: Value(false)));

  Future<void> deleteHabit(String id) => transaction(() async {
        await (delete(habitCheckIns)..where((c) => c.habitId.equals(id))).go();
        await (delete(habits)..where((h) => h.id.equals(id))).go();
      });

  Stream<List<HabitRow>> watchActiveHabits() =>
      (select(habits)..where((h) => h.isActive.equals(true))).watch();

  Future<List<HabitCheckInRow>> fetchRecentCheckIns(String habitId) {
    final since = _startOfToday.subtract(const Duration(days: 30));
    return (select(habitCheckIns)
          ..where((c) =>
              c.habitId.equals(habitId) & c.date.isBiggerOrEqualValue(since))
          ..orderBy([(c) => OrderingTerm.desc(c.date)]))
        .get();
  }

  Future<void> upsertCheckIn(HabitCheckInsCompanion entry) =>
      into(habitCheckIns).insertOnConflictUpdate(entry);

  Future<void> deleteCheckInForToday(String habitId) =>
      (delete(habitCheckIns)
            ..where((c) =>
                c.habitId.equals(habitId) & c.date.equals(_startOfToday)))
          .go();

  // ---- Routines -------------------------------------------------------------

  Future<void> upsertRoutine(RoutinesCompanion entry) =>
      into(routines).insertOnConflictUpdate(entry);

  Future<void> upsertStep(RoutineStepsCompanion entry) =>
      into(routineSteps).insertOnConflictUpdate(entry);

  Future<void> markStepComplete(String stepId, bool isComplete) =>
      (update(routineSteps)..where((s) => s.id.equals(stepId)))
          .write(RoutineStepsCompanion(isComplete: Value(isComplete)));

  Future<void> resetRoutineSteps(String routineId) =>
      (update(routineSteps)..where((s) => s.routineId.equals(routineId)))
          .write(const RoutineStepsCompanion(isComplete: Value(false)));

  Future<void> deleteRoutine(String id) => transaction(() async {
        await (delete(routineSteps)..where((s) => s.routineId.equals(id))).go();
        await (delete(routines)..where((r) => r.id.equals(id))).go();
      });

  Stream<List<RoutineRow>> watchActiveRoutines() =>
      (select(routines)..where((r) => r.isActive.equals(true))).watch();

  Future<List<RoutineStepRow>> fetchStepsForRoutine(String routineId) =>
      (select(routineSteps)
            ..where((s) => s.routineId.equals(routineId))
            ..orderBy([(s) => OrderingTerm.asc(s.position)]))
          .get();

  // ---- Notes (v2) -----------------------------------------------------------

  Future<void> upsertNote(NotesCompanion entry) =>
      into(notes).insertOnConflictUpdate(entry);

  Future<void> deleteNote(String id) =>
      (delete(notes)..where((n) => n.id.equals(id))).go();

  Stream<List<NoteRow>> watchNotes() => (select(notes)
        ..orderBy([
          (n) => OrderingTerm.desc(n.pinned),
          (n) => OrderingTerm.desc(n.updatedAt),
        ]))
      .watch();

  // ---- MoodLogs (v2, §2.8 on-device only) ------------------------------------

  Future<void> insertMoodLog(MoodLogsCompanion entry) =>
      into(moodLogs).insert(entry);

  Stream<MoodLogRow?> watchTodayLatestMood() => (select(moodLogs)
        ..where((m) => m.loggedAt.isBiggerOrEqualValue(_startOfToday))
        ..orderBy([(m) => OrderingTerm.desc(m.loggedAt)])
        ..limit(1))
      .watchSingleOrNull();

  Stream<List<MoodLogRow>> watchRecentMoods(int days) {
    final since = _startOfToday.subtract(Duration(days: days - 1));
    return (select(moodLogs)
          ..where((m) => m.loggedAt.isBiggerOrEqualValue(since))
          ..orderBy([(m) => OrderingTerm.asc(m.loggedAt)]))
        .watch();
  }
}

LazyDatabase _open() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'neuroflow.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
