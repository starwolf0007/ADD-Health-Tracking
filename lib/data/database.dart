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
  TextColumn get operation => text()(); // 'create' | 'update' | 'complete' | 'delete'
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
// Google account metadata (schema v5)
// ---------------------------------------------------------------------------

/// Connected Google account METADATA. SECURITY INVARIANT: this table has no
/// token columns and never will — access/id/refresh tokens live exclusively
/// in FlutterSecureStorage (see
/// lib/platform/google/google_auth_repository_impl.dart key scheme). Adding
/// a token column here is a review-blocking violation.
@DataClassName('GoogleAccountRow')
class GoogleAccounts extends Table {
  TextColumn get id => text()(); // google_sign_in stable id
  TextColumn get email => text()();
  TextColumn get displayName => text().nullable()();
  TextColumn get photoUrl => text().nullable()();
  TextColumn get grantedScopes =>
      text().withDefault(const Constant(''))(); // space-separated
  BoolColumn get isPrimary => boolean().withDefault(const Constant(false))();
  DateTimeColumn get connectedAt => dateTime()();
  DateTimeColumn get lastRefreshAt => dateTime().nullable()();
  DateTimeColumn get tokenExpiresAtEstimate => dateTime().nullable()();
  // DERIVED (connectedAt/lastRefreshAt + 55min), advisory-only — see
  // GoogleAccount.tokenExpiresAtEstimate doc. Never the authoritative expiry
  // signal (a 401 is); never a token itself.

  @override
  Set<Column> get primaryKey => {id};
}

// ---------------------------------------------------------------------------
// Connected services status (schema v6)
// ---------------------------------------------------------------------------

/// Per-service connection status ("Connected services" list in Settings).
/// One row per GoogleServiceId, seeded explicitly by
/// DriftConnectedServicesRepository.ensureSeeded() (never lazily inside a
/// watch() stream — see STAGE2_CRITIC_REPORT.md m5).
@DataClassName('ConnectedServiceRow')
class ConnectedServices extends Table {
  TextColumn get serviceId => text()(); // GoogleServiceId.name
  TextColumn get status =>
      text().withDefault(const Constant('comingSoon'))();
  // 'comingSoon' | 'available' | 'enabled' | 'disabled'
  DateTimeColumn get enabledAt => dateTime().nullable()();
  DateTimeColumn get lastUsedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {serviceId};
}

// ---------------------------------------------------------------------------
// Database
// ---------------------------------------------------------------------------

@DriftDatabase(tables: [
  Tasks,
  SyncQueue,
  Habits,
  HabitCheckIns,
  Routines,
  RoutineSteps,
  GoogleAccounts,
  ConnectedServices,
  Notes,
  MoodLogs,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_open());

  @override
  int get schemaVersion => 7;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            try {
              await m.createTable(routines);
            } catch (_) {}
            try {
              await m.createTable(routineSteps);
            } catch (_) {}
          }
          if (from < 3) {
            try {
              await m.createTable(habits);
            } catch (_) {}
            try {
              await m.createTable(habitCheckIns);
            } catch (_) {}
          }
          if (from < 4) {
            try {
              await m.createTable(syncQueue);
            } catch (_) {}
          }
          if (from < 5) {
            try {
              await m.createTable(googleAccounts);
            } catch (_) {}
          }
          if (from < 6) {
            try {
              await m.createTable(connectedServices);
            } catch (_) {}
          }
          if (from < 7) {
            try {
              await m.createTable(notes);
            } catch (_) {}
            try {
              await m.createTable(moodLogs);
            } catch (_) {}
            try {
              await m.addColumn(routines, routines.activeDays);
            } catch (_) {}
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
          ..where((t) => t.status.equals('pending'))
          ..orderBy([(t) => OrderingTerm.asc(t.energy)]))
        .watch();
  }

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
      into(syncQueue).insertOnConflictUpdate(op);

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

  // ------------------------------------------------------------------
  // Google account queries
  // ------------------------------------------------------------------
  // Low-level primitives only — enum/list<->string mapping and the
  // setPrimary/getPrimary invariant enforcement live in
  // DriftGoogleAccountRepository (lib/data/google_account_repository_impl.dart),
  // which composes these via `transaction()` for atomicity.

  /// All Google account metadata rows, primary first.
  Stream<List<GoogleAccountRow>> watchGoogleAccounts() {
    return (select(googleAccounts)
          ..orderBy([
            (t) => OrderingTerm.desc(t.isPrimary),
            (t) => OrderingTerm.asc(t.connectedAt),
          ]))
        .watch();
  }

  Future<List<GoogleAccountRow>> fetchGoogleAccounts() =>
      select(googleAccounts).get();

  Future<void> upsertGoogleAccount(GoogleAccountsCompanion account) =>
      into(googleAccounts).insertOnConflictUpdate(account);

  Future<void> demoteAllGoogleAccounts() => update(googleAccounts)
      .write(const GoogleAccountsCompanion(isPrimary: Value(false)));

  Future<void> promoteGoogleAccount(String accountId) =>
      (update(googleAccounts)..where((t) => t.id.equals(accountId)))
          .write(const GoogleAccountsCompanion(isPrimary: Value(true)));

  Future<void> touchGoogleAccount(
    String accountId,
    GoogleAccountsCompanion patch,
  ) =>
      (update(googleAccounts)..where((t) => t.id.equals(accountId)))
          .write(patch);

  Future<void> removeGoogleAccount(String accountId) =>
      (delete(googleAccounts)..where((t) => t.id.equals(accountId))).go();

  Future<void> clearGoogleAccounts() => delete(googleAccounts).go();

  // ------------------------------------------------------------------
  // Connected services queries
  // ------------------------------------------------------------------
  // Low-level primitives only — enum<->string mapping, seeding, and
  // read-before-watch ordering live in DriftConnectedServicesRepository
  // (lib/data/connected_services_repository_impl.dart), mirroring the
  // GoogleAccounts primitives above.

  /// All connected-service rows, ordered by serviceId (repository re-sorts
  /// into GoogleServiceId enum order, since text sort != enum order).
  Stream<List<ConnectedServiceRow>> watchConnectedServices() {
    return select(connectedServices).watch();
  }

  Future<List<ConnectedServiceRow>> fetchConnectedServices() =>
      select(connectedServices).get();

  Future<void> upsertConnectedService(ConnectedServicesCompanion service) =>
      into(connectedServices).insertOnConflictUpdate(service);

  Future<void> patchConnectedService(
    String serviceId,
    ConnectedServicesCompanion patch,
  ) =>
      (update(connectedServices)..where((t) => t.serviceId.equals(serviceId)))
          .write(patch);

  Future<void> clearConnectedServices() => delete(connectedServices).go();
}

LazyDatabase _open() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'neuroflow.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
