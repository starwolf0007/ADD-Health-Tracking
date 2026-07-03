// lib/data/database.dart
//
// Drift schema. @DataClassName('TaskRow') avoids collision with domain Task.
// Source of truth per §12.3 — Google Tasks is the mirror/sync queue only.

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'database.g.dart';

// ---------------------------------------------------------------------------
// Table definitions
// ---------------------------------------------------------------------------

class Tasks extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get notes => text().nullable()();
  TextColumn get energy => text()(); // 'low' | 'medium' | 'high'
  TextColumn get status => text()(); // 'pending' | 'completed' | 'skipped'
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get dueDate => dateTime().nullable()();
  BoolColumn get isQuickWin => boolean().withDefault(const Constant(false))();

  // Google Tasks mirror fields
  TextColumn get googleTaskId => text().nullable()();
  DateTimeColumn get lastSyncedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

// ---------------------------------------------------------------------------
// Routines tables
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Habits tables
// ---------------------------------------------------------------------------

class Habits extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get notes => text().nullable()();
  TextColumn get frequency => text()(); // 'daily' | 'weekdays' | 'weekends'
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class HabitCheckIns extends Table {
  TextColumn get id => text()();
  TextColumn get habitId => text()();
  DateTimeColumn get date => dateTime()(); // normalized to midnight
  BoolColumn get completed => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

// ---------------------------------------------------------------------------
// Sync queue table
// ---------------------------------------------------------------------------

/// Durable queue of pending Google Tasks mirror operations.
/// Operations survive app restarts and are flushed by WorkManager every 4 h.
/// Auth-gated: the sync service checks for an OAuth token before flushing —
/// if the user hasn't connected Google Tasks, all ops stay pending silently.
@DataClassName('SyncQueueData')
class SyncQueue extends Table {
  TextColumn get id => text()();

  /// 'create' | 'update' | 'complete' | 'delete'
  TextColumn get operation => text()();

  /// Local task ID this operation refers to.
  TextColumn get taskId => text()();

  /// Snapshot of title at time of enqueue — used for create/update calls.
  TextColumn get taskTitle => text().nullable()();

  /// Snapshot of notes at time of enqueue.
  TextColumn get taskNotes => text().nullable()();

  /// Google Tasks remote ID — null until first successful create sync.
  TextColumn get googleTaskId => text().nullable()();

  /// 'pending' | 'done' | 'failed' (failed = >5 retries, won't retry again)
  TextColumn get status => text().withDefault(const Constant('pending'))();

  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

// ---------------------------------------------------------------------------
// Routines tables
// ---------------------------------------------------------------------------

class Routines extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get anchor => text()(); // 'morning' | 'midday' | 'evening' | 'custom'
  IntColumn get scheduleHour => integer().nullable()();
  IntColumn get scheduleMinute => integer().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

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

// ---------------------------------------------------------------------------
// Database
// ---------------------------------------------------------------------------

@DriftDatabase(tables: [Tasks, SyncQueue, Habits, HabitCheckIns, Routines, RoutineSteps])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(routines);
        await m.createTable(routineSteps);
      }
      if (from < 3) {
        await m.createTable(habits);
        await m.createTable(habitCheckIns);
      }
      if (from < 4) {
        await m.createTable(syncQueue);
      }
    },
  );

  // ------------------------------------------------------------------
  // Queries
  // ------------------------------------------------------------------

  /// All pending tasks ordered by energy (low first — Quick Wins logic).
  Stream<List<TaskRow>> watchPendingByEnergyAsc() {
    return (select(tasks)
          ..where((t) => t.status.equals('pending'))
          ..orderBy([(t) => OrderingTerm.asc(t.energy)]))
        .watch();
  }

  /// Count of tasks completed today — drives the heartbeat line (§13).
  Stream<int> watchCompletedTodayCount() {
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    return (selectOnly(tasks)
          ..addColumns([tasks.id.count()])
          ..where(tasks.status.equals('completed') &
              tasks.createdAt.isBetweenValues(startOfDay, endOfDay)))
        .map((row) => row.read(tasks.id.count()) ?? 0)
        .watchSingle();
  }

  Future<void> upsertTask(TasksCompanion task) =>
      into(tasks).insertOnConflictUpdate(task);

  Future<void> markComplete(String id) => (update(tasks)
        ..where((t) => t.id.equals(id)))
      .write(TasksCompanion(
        status: const Value('completed'),
      ));

  Future<void> deleteTask(String id) =>
      (delete(tasks)..where((t) => t.id.equals(id))).go();

  // ------------------------------------------------------------------
  // Habit queries
  // ------------------------------------------------------------------

  Stream<List<HabitRow>> watchActiveHabits() {
    return (select(habits)
          ..where((h) => h.isActive.equals(true))
          ..orderBy([(h) => OrderingTerm.asc(h.createdAt)]))
        .watch();
  }

  Future<List<HabitCheckInRow>> fetchRecentCheckIns(String habitId) {
    final cutoff = DateTime.now().subtract(const Duration(days: 30));
    return (select(habitCheckIns)
          ..where((c) =>
              c.habitId.equals(habitId) & c.date.isBiggerThanValue(cutoff))
          ..orderBy([(c) => OrderingTerm.desc(c.date)]))
        .get();
  }

  Future<void> upsertHabit(HabitsCompanion habit) =>
      into(habits).insertOnConflictUpdate(habit);

  Future<void> upsertCheckIn(HabitCheckInsCompanion checkIn) =>
      into(habitCheckIns).insertOnConflictUpdate(checkIn);

  Future<void> deleteCheckInForToday(String habitId) async {
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    await (delete(habitCheckIns)
          ..where((c) =>
              c.habitId.equals(habitId) &
              c.date.isBetweenValues(startOfDay, endOfDay)))
        .go();
  }

  Future<void> archiveHabit(String id) =>
      (update(habits)..where((h) => h.id.equals(id)))
          .write(const HabitsCompanion(isActive: Value(false)));

  Future<void> deleteHabit(String id) async {
    await (delete(habitCheckIns)..where((c) => c.habitId.equals(id))).go();
    await (delete(habits)..where((h) => h.id.equals(id))).go();
  }

  // ------------------------------------------------------------------
  // Routine queries
  // ------------------------------------------------------------------

  Stream<List<RoutineRow>> watchActiveRoutines() {
    return (select(routines)
          ..where((r) => r.isActive.equals(true))
          ..orderBy([(r) => OrderingTerm.asc(r.anchor),
                     (r) => OrderingTerm.asc(r.name)]))
        .watch();
  }

  Future<List<RoutineStepRow>> fetchStepsForRoutine(String routineId) {
    return (select(routineSteps)
          ..where((s) => s.routineId.equals(routineId))
          ..orderBy([(s) => OrderingTerm.asc(s.position)]))
        .get();
  }

  Future<void> upsertRoutine(RoutinesCompanion routine) =>
      into(routines).insertOnConflictUpdate(routine);

  Future<void> upsertStep(RoutineStepsCompanion step) =>
      into(routineSteps).insertOnConflictUpdate(step);

  Future<void> markStepComplete(String stepId, bool complete) =>
      (update(routineSteps)..where((s) => s.id.equals(stepId)))
          .write(RoutineStepsCompanion(isComplete: Value(complete)));

  Future<void> resetRoutineSteps(String routineId) =>
      (update(routineSteps)..where((s) => s.routineId.equals(routineId)))
          .write(const RoutineStepsCompanion(isComplete: Value(false)));

  Future<void> deleteRoutine(String routineId) async {
    await (delete(routineSteps)
          ..where((s) => s.routineId.equals(routineId)))
        .go();
    await (delete(routines)..where((r) => r.id.equals(routineId))).go();
  }

  // ------------------------------------------------------------------
  // Sync queue queries
  // ------------------------------------------------------------------

  Future<void> enqueueSyncOp(SyncQueueCompanion op) =>
      into(syncQueue).insert(op);

  Future<List<SyncQueueData>> fetchPendingSyncOps({int limit = 50}) {
    return (select(syncQueue)
          ..where((s) => s.status.equals('pending'))
          ..orderBy([(s) => OrderingTerm.asc(s.createdAt)])
          ..limit(limit))
        .get();
  }

  Future<void> markSyncOpDone(String opId) =>
      (update(syncQueue)..where((s) => s.id.equals(opId)))
          .write(const SyncQueueCompanion(status: Value('done')));

  Future<void> incrementSyncRetry(String opId) async {
    final op = await (select(syncQueue)
          ..where((s) => s.id.equals(opId)))
        .getSingleOrNull();
    if (op == null) return;
    final newCount = op.retryCount + 1;
    final newStatus = newCount >= 5 ? 'failed' : 'pending';
    await (update(syncQueue)..where((s) => s.id.equals(opId))).write(
      SyncQueueCompanion(
        retryCount: Value(newCount),
        status: Value(newStatus),
      ),
    );
  }

  Future<void> clearDoneSyncOps() =>
      (delete(syncQueue)..where((s) => s.status.equals('done'))).go();
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbDir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbDir.path, 'neuroflow.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
