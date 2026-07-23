// lib/data/database.dart
//
// The system of record (§12.3): local Drift/SQLite, source of truth.
// Google services are mirrors, never masters.

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'health_tables.dart';

part 'database.g.dart';

@DataClassName('TaskRow')
class Tasks extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get notes => text().nullable()();
  TextColumn get energy => text()();
  TextColumn get status => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get dueDate => dateTime().nullable()();
  BoolColumn get isQuickWin => boolean().withDefault(const Constant(false))();
  IntColumn get estimatedMinutes => integer().nullable()();
  DateTimeColumn get completedAt => dateTime().nullable()();
  DateTimeColumn get activeStartedAt => dateTime().nullable()();
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
  TextColumn get anchor => text()();
  IntColumn get scheduleHour => integer().nullable()();
  IntColumn get scheduleMinute => integer().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
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
  IntColumn get level => integer()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get loggedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('SyncQueueData')
class SyncQueue extends Table {
  TextColumn get id => text()();
  TextColumn get operation => text()();
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

@DataClassName('HevyWorkoutRow')
class HevyWorkouts extends Table {
  TextColumn get id => text()();
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
  TextColumn get id => text()();
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
  TextColumn get id => text()();
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
  TextColumn get id => text()();
  DateTimeColumn get lastAttemptAt => dateTime().nullable()();
  DateTimeColumn get lastSuccessAt => dateTime().nullable()();
  TextColumn get lastError => text().nullable()();
  IntColumn get lastImportedCount => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('HolidayCalendarEntryRow')
class HolidayCalendarEntries extends Table {
  TextColumn get calendarId => text()();
  TextColumn get date => text()();
  TextColumn get name => text()();

  @override
  Set<Column> get primaryKey => {calendarId, date};
}

@DataClassName('ScheduleRuleRow')
class ScheduleRules extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get byDay => text()();
  IntColumn get startMinutes => integer()();
  IntColumn get endMinutes => integer()();
  IntColumn get commuteBeforeMin => integer().withDefault(const Constant(0))();
  IntColumn get commuteAfterMin => integer().withDefault(const Constant(0))();
  TextColumn get exclusionCalendarId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('ScheduleExceptionRow')
class ScheduleExceptions extends Table {
  TextColumn get ruleId => text().references(ScheduleRules, #id)();
  TextColumn get date => text()();
  TextColumn get type => text()();

  @override
  Set<Column> get primaryKey => {ruleId, date};
}

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
  HolidayCalendarEntries,
  ScheduleRules,
  ScheduleExceptions,
  HealthSources,
  HealthDevices,
  HealthSourceRecords,
  HealthEvents,
  HealthSpans,
  HealthSeries,
  HealthTimeSeries,
  HealthContextEvents,
  HealthDataCoverage,
  HealthIngestionRuns,
  HealthIngestionCheckpoints,
  HealthTombstones,
  HealthPermissions,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_open());

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 7;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _createHealthIndexes();
          await _seedPermanentScheduleInputs();
        },
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
          if (from < 5) {
            await m.addColumn(tasks, tasks.activeStartedAt);
            await (update(tasks)
                  ..where((task) =>
                      task.status.equals('inProgress') &
                      task.activeStartedAt.isNull()))
                .write(
              TasksCompanion(activeStartedAt: Value(DateTime.now())),
            );
          }
          if (from < 6) {
            await m.createTable(holidayCalendarEntries);
            await m.createTable(scheduleRules);
            await m.createTable(scheduleExceptions);
            await _seedPermanentScheduleInputs();
          }
          if (from < 7) {
            await m.createTable(healthSources);
            await m.createTable(healthDevices);
            await m.createTable(healthSourceRecords);
            await m.createTable(healthEvents);
            await m.createTable(healthSpans);
            await m.createTable(healthSeries);
            await m.createTable(healthTimeSeries);
            await m.createTable(healthContextEvents);
            await m.createTable(healthDataCoverage);
            await m.createTable(healthIngestionRuns);
            await m.createTable(healthIngestionCheckpoints);
            await m.createTable(healthTombstones);
            await m.createTable(healthPermissions);
            await _createHealthIndexes();
          }
        },
      );

  Future<void> _createHealthIndexes() async {
    const statements = <String>[
      'CREATE INDEX IF NOT EXISTS idx_health_source_records_type_time ON health_source_records(source_record_type, started_at_utc)',
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_health_source_records_external ON health_source_records(source_id, source_app_id, external_id) WHERE external_id IS NOT NULL',
      'CREATE INDEX IF NOT EXISTS idx_health_events_concept_time ON health_events(concept_type, event_timestamp_utc)',
      'CREATE INDEX IF NOT EXISTS idx_health_events_local_date ON health_events(concept_type, local_date)',
      'CREATE INDEX IF NOT EXISTS idx_health_spans_concept_start ON health_spans(concept_type, start_timestamp_utc)',
      'CREATE INDEX IF NOT EXISTS idx_health_spans_concept_end ON health_spans(concept_type, end_timestamp_utc)',
      'CREATE INDEX IF NOT EXISTS idx_health_spans_local_date ON health_spans(concept_type, local_date)',
      'CREATE INDEX IF NOT EXISTS idx_health_series_concept_start ON health_series(concept_type, start_timestamp_utc)',
      'CREATE INDEX IF NOT EXISTS idx_health_samples_concept_time ON health_time_series(concept_type, timestamp_utc)',
      'CREATE INDEX IF NOT EXISTS idx_health_samples_series_time ON health_time_series(series_id, timestamp_utc)',
      'CREATE INDEX IF NOT EXISTS idx_health_samples_local_date ON health_time_series(concept_type, local_date)',
      'CREATE INDEX IF NOT EXISTS idx_health_context_type_time ON health_context_events(event_type, start_timestamp_utc)',
      'CREATE INDEX IF NOT EXISTS idx_health_coverage_concept_window ON health_data_coverage(concept_type, window_start_utc, window_end_utc)',
      'CREATE INDEX IF NOT EXISTS idx_health_tombstones_source_external ON health_tombstones(source_id, source_app_id, external_id)',
    ];
    for (final statement in statements) {
      await customStatement(statement);
    }
  }

  Future<void> _seedPermanentScheduleInputs() => batch((batch) {
        batch.insertAll(
          holidayCalendarEntries,
          [
            HolidayCalendarEntriesCompanion.insert(
              calendarId: 'pge_2026',
              date: '2026-01-01',
              name: "New Year's Day",
            ),
            HolidayCalendarEntriesCompanion.insert(
              calendarId: 'pge_2026',
              date: '2026-01-19',
              name: 'Martin Luther King Jr. Day',
            ),
            HolidayCalendarEntriesCompanion.insert(
              calendarId: 'pge_2026',
              date: '2026-02-16',
              name: "Presidents' Day",
            ),
            HolidayCalendarEntriesCompanion.insert(
              calendarId: 'pge_2026',
              date: '2026-05-25',
              name: 'Memorial Day',
            ),
            HolidayCalendarEntriesCompanion.insert(
              calendarId: 'pge_2026',
              date: '2026-06-19',
              name: 'Juneteenth',
            ),
            HolidayCalendarEntriesCompanion.insert(
              calendarId: 'pge_2026',
              date: '2026-07-03',
              name: 'Independence Day (Observed)',
            ),
            HolidayCalendarEntriesCompanion.insert(
              calendarId: 'pge_2026',
              date: '2026-09-07',
              name: 'Labor Day',
            ),
            HolidayCalendarEntriesCompanion.insert(
              calendarId: 'pge_2026',
              date: '2026-11-11',
              name: 'Veterans Day',
            ),
            HolidayCalendarEntriesCompanion.insert(
              calendarId: 'pge_2026',
              date: '2026-11-26',
              name: 'Thanksgiving Holiday',
            ),
            HolidayCalendarEntriesCompanion.insert(
              calendarId: 'pge_2026',
              date: '2026-11-27',
              name: 'Thanksgiving Holiday (Day 2)',
            ),
            HolidayCalendarEntriesCompanion.insert(
              calendarId: 'pge_2026',
              date: '2026-12-25',
              name: 'Christmas Day',
            ),
          ],
          mode: InsertMode.insertOrIgnore,
        );
        batch.insert(
          scheduleRules,
          ScheduleRulesCompanion.insert(
            id: 'rule_work',
            name: 'PG&E Work Schedule',
            byDay: '1,2,3,4,5',
            startMinutes: 360,
            endMinutes: 870,
            commuteBeforeMin: const Value(20),
            commuteAfterMin: const Value(20),
            exclusionCalendarId: const Value('pge_2026'),
          ),
          mode: InsertMode.insertOrIgnore,
        );
      });

  DateTime _startOfDay(DateTime day) => DateTime(day.year, day.month, day.day);
  DateTime get _startOfToday => _startOfDay(DateTime.now());

  Future<void> upsertTask(TasksCompanion entry) =>
      into(tasks).insertOnConflictUpdate(entry);

  Future<void> markComplete(String id) =>
      (update(tasks)..where((t) => t.id.equals(id))).write(
        TasksCompanion(
          status: const Value('completed'),
          completedAt: Value(DateTime.now()),
          activeStartedAt: const Value(null),
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

  Stream<List<TaskRow>> watchTimelineForDay(
    DateTime day, {
    required bool includeFlexibleTasks,
  }) {
    final start = _startOfDay(day);
    final tomorrow = DateTime(start.year, start.month, start.day + 1);
    final scheduledForDay = tasks.dueDate.isBiggerOrEqualValue(start) &
        tasks.dueDate.isSmallerThanValue(tomorrow);
    final completedOnDay = tasks.status.equals('completed') &
        tasks.completedAt.isBiggerOrEqualValue(start) &
        tasks.completedAt.isSmallerThanValue(tomorrow);
    final flexibleForToday = includeFlexibleTasks
        ? tasks.dueDate.isNull() & tasks.status.isNotIn(['completed'])
        : const Constant(false);
    return (select(tasks)
          ..where((t) =>
              t.status.isNotIn(['skipped']) &
              (scheduledForDay | completedOnDay | flexibleForToday))
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
        activeStartedAt:
            status == 'inProgress' ? Value(DateTime.now()) : const Value(null),
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

  Future<void> insertMoodLog(MoodLogsCompanion entry) =>
      into(moodLogs).insert(entry);

  Stream<MoodLogRow?> watchTodayLatestMood() => (select(moodLogs)
        ..where((m) => m.loggedAt.isBiggerOrEqualValue(_startOfToday))
        ..orderBy([(m) => OrderingTerm.desc(m.loggedAt)])
        ..limit(1))
      .watchSingleOrNull();

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

  Future<List<ScheduleRuleRow>> fetchScheduleRules() =>
      (select(scheduleRules)..orderBy([(r) => OrderingTerm.asc(r.id)])).get();

  Future<List<ScheduleExceptionRow>> fetchScheduleExceptionsForDate(
    String date,
  ) =>
      (select(scheduleExceptions)
            ..where((entry) => entry.date.equals(date))
            ..orderBy([(entry) => OrderingTerm.asc(entry.ruleId)]))
          .get();

  Future<Set<String>> fetchHolidayDates(String calendarId) async {
    final rows = await (select(holidayCalendarEntries)
          ..where((entry) => entry.calendarId.equals(calendarId))
          ..orderBy([(entry) => OrderingTerm.asc(entry.date)]))
        .get();
    return rows.map((row) => row.date).toSet();
  }
}

LazyDatabase _open() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'neuroflow.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
