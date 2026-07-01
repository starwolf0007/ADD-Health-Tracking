// lib/platform/local/database.dart
//
// Platform layer. Drift/SQLite is the LOCAL SOURCE OF TRUTH for the full Task
// record, including every extended field Google Tasks can't hold (§12.3, v1.4).
// Google Tasks is only a mirror of the syncable subset — see SyncQueue.
//
// Codegen: run `dart run build_runner build` in Bryan's env to generate
// database.g.dart. (Cannot be generated from the chat sandbox.)

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'dart:io';

import '../../domain/task.dart';

part 'database.g.dart';

/// Full task record. The extended fields (energy, priority, snapRef, confirmed,
/// estimatedMinutes, lastTouchedAt) live ONLY here — they never round-trip
/// through Google Tasks.
@DataClassName('TaskRow') // avoid clash with the domain `Task`
class Tasks extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  IntColumn get source => intEnum<TaskSource>()();
  IntColumn get status => intEnum<TaskStatus>()();
  DateTimeColumn get due => dateTime().nullable()();
  IntColumn get energy => intEnum<EnergyTag>().nullable()();
  IntColumn get priority => intEnum<Priority>().withDefault(const Constant(0))();
  IntColumn get estimatedMinutes => integer().nullable()();
  TextColumn get listName => text().nullable()();
  TextColumn get contactRef => text().nullable()();
  TextColumn get attachmentRef => text().nullable()();
  TextColumn get snapRef => text().nullable()();
  BoolColumn get confirmed => boolean().withDefault(const Constant(true))();
  TextColumn get googleTaskId => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get completedAt => dateTime().nullable()();
  DateTimeColumn get lastTouchedAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Pending operations to mirror to Google Tasks (the subset Google can hold:
/// title/notes/due/status). Flushed when online — offline-first (§12.3).
enum SyncOp { create, update, delete }

class SyncQueue extends Table {
  IntColumn get queueId => integer().autoIncrement()();
  TextColumn get taskId => text()();
  IntColumn get op => intEnum<SyncOp>()();
  TextColumn get payloadJson => text()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
}

@DriftDatabase(tables: [Tasks, SyncQueue])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_open());

  @override
  int get schemaVersion => 1;

  Future<List<Task>> openTasks() async {
    final rows = await (select(tasks)
          ..where((t) => t.status.isIn([
                TaskStatus.inbox.index,
                TaskStatus.today.index,
                TaskStatus.scheduled.index,
              ])))
        .get();
    return rows.map(_toDomain).toList();
  }

  Stream<List<Task>> watchOpenTasks() {
    return (select(tasks)
          ..where((t) => t.status.isIn([
                TaskStatus.inbox.index,
                TaskStatus.today.index,
                TaskStatus.scheduled.index,
              ])))
        .watch()
        .map((rows) => rows.map(_toDomain).toList());
  }

  Future<void> upsertTask(Task t) =>
      into(tasks).insertOnConflictUpdate(_toCompanion(t));

  Future<List<Task>> untouchedFor(int days) async {
    final cutoff = DateTime.now().subtract(Duration(days: days));
    final rows = await (select(tasks)
          ..where((t) =>
              t.lastTouchedAt.isSmallerThanValue(cutoff) &
              t.status.isIn([TaskStatus.inbox.index, TaskStatus.today.index])))
        .get();
    return rows.map(_toDomain).toList();
  }

  /// Drives the §13 heartbeat line. Counts tasks completed since local
  /// midnight today.
  Stream<int> watchCompletedTodayCount() {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    final countExp = tasks.id.count();
    final query = selectOnly(tasks)
      ..addColumns([countExp])
      ..where(tasks.status.equals(TaskStatus.done.index) &
          tasks.completedAt.isBiggerOrEqualValue(startOfDay) &
          tasks.completedAt.isSmallerThanValue(endOfDay));
    return query.watchSingle().map((row) => row.read(countExp) ?? 0);
  }

  // --- mappers (Drift row <-> domain) ---
  Task _toDomain(TaskRow r) => Task(
        id: r.id,
        title: r.title,
        source: r.source,
        status: r.status,
        due: r.due,
        energy: r.energy,
        priority: r.priority,
        estimatedMinutes: r.estimatedMinutes,
        listName: r.listName,
        contactRef: r.contactRef,
        attachmentRef: r.attachmentRef,
        snapRef: r.snapRef,
        confirmed: r.confirmed,
        googleTaskId: r.googleTaskId,
        createdAt: r.createdAt,
        completedAt: r.completedAt,
        lastTouchedAt: r.lastTouchedAt,
        updatedAt: r.updatedAt,
      );

  TasksCompanion _toCompanion(Task t) => TasksCompanion(
        id: Value(t.id),
        title: Value(t.title),
        source: Value(t.source),
        status: Value(t.status),
        due: Value(t.due),
        energy: Value(t.energy),
        priority: Value(t.priority),
        estimatedMinutes: Value(t.estimatedMinutes),
        listName: Value(t.listName),
        contactRef: Value(t.contactRef),
        attachmentRef: Value(t.attachmentRef),
        snapRef: Value(t.snapRef),
        confirmed: Value(t.confirmed),
        googleTaskId: Value(t.googleTaskId),
        createdAt: Value(t.createdAt),
        completedAt: Value(t.completedAt),
        lastTouchedAt: Value(t.lastTouchedAt),
        updatedAt: Value(t.updatedAt),
      );
}

// Drift generates the row data class as `TaskRow` (via @DataClassName above),
// avoiding a clash with the domain `Task`.

LazyDatabase _open() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'neuroflow.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
