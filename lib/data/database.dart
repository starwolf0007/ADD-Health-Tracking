// lib/data/database.dart
//
// The system of record (§12.3): local Drift/SQLite, source of truth.
// Google services are mirrors, never masters.
//
// v2 unified schema — eight tables:
//   Tasks, Habits, HabitCheckIns, Routines, RoutineSteps  (Phase-1 core)
//   Notes                                                  (v2 capture hub)
//   MoodLogs                                               (v2 §6 trigger — §2.8 ON-DEVICE ONLY)
//   SyncQueue                                              (Google Tasks mirror)

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
  TextColumn get status => text()(); // 'pending' | 'completed' | 'skipped'
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get dueDate => dateTime().nullable()();
  BoolColumn get isQuickWin => boolean().withDefault(const Constant(false))();
  IntColumn get estimatedMinutes => integer().nullable()();
  DateTimeColumn get completedAt => dateTime().nullable()();
  TextColumn get googleTaskId => text().nullable()();
  TextColumn get reentryLastCompletedStep => text().nullable()();
  TextColumn get reentryNextAction => text().nullable()();
  DateTimeColumn get reentryReturnAt => dateTime().nullable()();
  DateTimeColumn get reentryUpdatedAt => dateTime().nullable()();

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
  DateTimeColumn get date => dateTime()();
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
  IntColumn get scheduleHour => integer().nullable()();
  IntColumn get scheduleMinute => integer().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  // Which weekdays this routine fires (Mon=1 … Sun=7). "12345" = weekdays.
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

@DataClassName('MoodLogRow')
class MoodLogs extends Table {
  TextColumn get id => text()();
  IntColumn get level => integer()(); // MoodLevel.score, 1..5
  TextColumn get note => text().nullable()();
  DateTimeColumn get loggedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('SyncQueueData')
class SyncQueue extends Table {
  TextColumn get id => text()();
  TextColumn get operation =>
      text()(); // 'create' | 'update' | 'complete' | 'delete'
  TextColumn get taskId => text()();
  TextColumn get taskTitle => text().nullable()();
  TextColumn get taskNotes => text().nullable()();
  TextColumn get googleTaskId => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('pending'))();
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

// ---------------------------------------------------------------------------
// Hevy cache (read-only import mirror — Hevy remains the source of truth)
// ---------------------------------------------------------------------------

@DataClassName('HevyWorkoutRow')
class HevyWorkouts extends Table {
  TextColumn get id => text()(); // stable Hevy workout ID = upsert key
  TextColumn get title => text()();
  TextColumn get description => text().nullable()();
  DateTimeColumn get startTime => dateTime()();
  DateTimeColumn get endTime => dateTime()();
  DateTimeColumn get hevyUpdatedAt => dateTime().nullable()();
  DateTimeColumn get hevyCreatedAt => dateTime().nullable()();
  DateTimeColumn get importedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('HevyExerciseRow')
class HevyExercises extends Table {
  TextColumn get id => text()(); // '<workoutId>:<position>'
  TextColumn get workoutId => text().references(HevyWorkouts, #id)();
  IntColumn get position => integer()();
  TextColumn get title => text()();
  TextColumn get notes => text().nullable()();
  TextColumn get exerciseTemplateId => text()();
  TextColumn get supersetId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('HevySetRow')
class HevySets extends Table {
  TextColumn get id => text()(); // '<exerciseId>:<position>'
  TextColumn get exerciseId => text().references(HevyExercises, #id)();
  IntColumn get position => integer()();
  TextColumn get type => text()();
  RealColumn get weightKg => real().nullable()();
  IntColumn get reps => integer().nullable()();
  IntColumn get distanceMeters => integer().nullable()();
  IntColumn get durationSeconds => integer().nullable()();
  RealColumn get rpe => real().nullable()();
  BoolColumn get customMetric => boolean().nullable()();
  TextColumn get rawJson => text()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('HevySyncMetadataRow')
class HevySyncMetadata extends Table {
  TextColumn get id => text()(); // single row keyed 'hevy'
  DateTimeColumn get lastAttemptAt => dateTime().nullable()();
  DateTimeColumn get lastSuccessAt => dateTime().nullable()();
  TextColumn get lastError =>
      text().nullable()(); // failure type only, never bodies
  IntColumn get lastImportedCount => integer().nullable()();

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
  SyncQueue,
  HevyWorkouts,
  HevyExercises,
  HevySets,
  HevySyncMetadata,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_open());

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.addColumn(routines, routines.activeDays);
          }
          if (from < 3) {
            await m.addColumn(tasks, tasks.reentryLastCompletedStep);
            await m.addColumn(tasks, tasks.reentryNextAction);
            await m.addColumn(tasks, tasks.reentryReturnAt);
            await m.addColumn(tasks, tasks.reentryUpdatedAt);
          }
          if (from < 4) {
            await m.createTable(hevyWorkouts);
            await m.createTable(hevyExercises);
            await m.createTable(hevySets);
            await m.createTable(hevySyncMetadata);
          }
        },
      );

  DateTime get _startOfToday {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  // ---- Tasks --------------------------------------------------------------

  Future<void> upsertTask(TasksCompanion entry) =>
      into(tasks).insertOnConflictUpdate(entry);

  Future<void> markComplete(String id) =>
      (update(tasks)..where((t) => t.id.equals(id))).write(
        TasksCompanion(
          status: const Value('completed'),
          completedAt: Value(DateTime.now()),
        ),
      );

  Future<void> deleteTask(String id) =>
      (delete(tasks)..where((t) => t.id.equals(id))).go();

  Stream<List<TaskRow>> watchPendingByEnergyAsc() {
    return (select(tasks)
          ..where((t) =>
              t.status.isIn(['pending', 'inProgress', 'paused', 'blocked']))
          ..orderBy([(t) => OrderingTerm.asc(t.energy)]))
        .watch();
  }

  Stream<List<TaskRow>> watchTodayTimeline() {
    final tomorrow = _startOfToday.add(const Duration(days: 1));
    return (select(tasks)
          ..where((t) =>
              t.status.isNotIn(['skipped']) &
              (t.status.isNotIn(['completed']) |
                  (t.completedAt.isBiggerOrEqualValue(_startOfToday) &
                      t.completedAt.isSmallerThanValue(tomorrow))))
          ..orderBy([
            (t) => OrderingTerm.asc(t.dueDate),
            (t) => OrderingTerm.asc(t.createdAt),
          ]))
        .watch();
  }

  Future<void> updateTaskStatus(String id, String status) async {
    final rowsUpdated =
        await (update(tasks)..where((t) => t.id.equals(id))).write(
      TasksCompanion(
        status: Value(status),
        completedAt:
            status == 'completed' ? Value(DateTime.now()) : const Value(null),
      ),
    );

    if (rowsUpdated == 0) {
      throw Exception('Task with id $id not found or could not be updated');
    }
  }

  Future<void> saveTaskReentry({
    required String taskId,
    String? lastCompletedStep,
    String? nextAction,
    DateTime? returnAt,
    required DateTime updatedAt,
  }) =>
      (update(tasks)..where((t) => t.id.equals(taskId))).write(
        TasksCompanion(
          reentryLastCompletedStep: Value(lastCompletedStep),
          reentryNextAction: Value(nextAction),
          reentryReturnAt: Value(returnAt),
          reentryUpdatedAt: Value(updatedAt),
        ),
      );

  Future<void> clearTaskReentry(String taskId) =>
      (update(tasks)..where((t) => t.id.equals(taskId))).write(
        const TasksCompanion(
          reentryLastCompletedStep: Value(null),
          reentryNextAction: Value(null),
          reentryReturnAt: Value(null),
          reentryUpdatedAt: Value(null),
        ),
      );

  Stream<int> watchCompletedTodayCount() {
    final query = select(tasks)
      ..where((t) =>
          t.status.equals('completed') &
          t.completedAt.isBiggerOrEqualValue(_startOfToday));
    return query.watch().map((rows) => rows.length);
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

  Future<void> deleteCheckInForToday(String habitId) => (delete(habitCheckIns)
        ..where(
            (c) => c.habitId.equals(habitId) & c.date.equals(_startOfToday)))
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

  // ---- Notes -----------------------------------------------------------

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

  // ---- MoodLogs ------------------------------------

  Future<void> insertMoodLog(MoodLogsCompanion entry) =>
      into(moodLogs).insert(entry);

  Stream<MoodLogRow?> watchTodayLatestMood() => (select(moodLogs)
        ..where((m) => m.loggedAt.isBiggerOrEqualValue(_startOfToday))
        ..orderBy([(m) => OrderingTerm.desc(m.loggedAt)])
        ..limit(1))
      .watchSingleOrNull();

  // ---- Sync Queue -----------------------------------------------------------

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
    final op = await (select(syncQueue)..where((s) => s.id.equals(opId)))
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

LazyDatabase _open() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'neuroflow.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
