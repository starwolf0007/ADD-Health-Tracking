import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuroflow/data/database.dart';
import 'package:neuroflow/data/task_repository_impl.dart';
import 'package:neuroflow/domain/reentry_note.dart';
import 'package:neuroflow/domain/task.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  test('re-entry note survives database close and reopen', () async {
    final directory =
        await Directory.systemTemp.createTemp('neuroflow-reentry');
    final file = File('${directory.path}/test.sqlite');
    final task = Task(
      id: 'task-1',
      title: 'Draft plan',
      energy: EnergyLevel.medium,
      createdAt: DateTime(2026, 7, 10),
    );
    final updatedAt = DateTime(2026, 7, 10, 14, 30);
    final returnAt = DateTime(2026, 7, 11, 9);

    var database = AppDatabase.forTesting(NativeDatabase(file));
    var repository = DriftTaskRepository(database);
    await repository.save(task);
    await repository.saveReentryNote(
      task.id,
      ReentryNote(
        lastCompletedStep: 'Outlined section one',
        nextAction: 'Write the first paragraph',
        returnAt: returnAt,
        updatedAt: updatedAt,
      ),
    );
    await database.close();

    database = AppDatabase.forTesting(NativeDatabase(file));
    repository = DriftTaskRepository(database);
    final restored = await repository.getReentryNote(task.id);

    expect(restored?.lastCompletedStep, 'Outlined section one');
    expect(restored?.nextAction, 'Write the first paragraph');
    expect(restored?.returnAt, returnAt);
    expect(restored?.updatedAt, updatedAt);
    expect(database.schemaVersion, 6);

    await repository.clearReentryNote(task.id);
    expect(await repository.getReentryNote(task.id), isNull);
    await database.close();
    await directory.delete(recursive: true);
  });

  test('version 2 schema migrates re-entry columns and Hevy tables', () async {
    final directory =
        await Directory.systemTemp.createTemp('neuroflow-migration');
    final file = File('${directory.path}/v2.sqlite');
    final raw = sqlite.sqlite3.open(file.path);
    raw.execute('''
      CREATE TABLE tasks (
        id TEXT NOT NULL PRIMARY KEY,
        title TEXT NOT NULL,
        notes TEXT NULL,
        energy TEXT NOT NULL,
        status TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        due_date INTEGER NULL,
        is_quick_win INTEGER NOT NULL DEFAULT 0,
        estimated_minutes INTEGER NULL,
        completed_at INTEGER NULL,
        google_task_id TEXT NULL
      )
    ''');
    raw.execute('PRAGMA user_version = 2');
    raw.close();

    final database = AppDatabase.forTesting(NativeDatabase(file));
    final columns =
        await database.customSelect('PRAGMA table_info(tasks)').get();
    final names = columns.map((row) => row.read<String>('name')).toSet();

    expect(
        names,
        containsAll([
          'reentry_last_completed_step',
          'reentry_next_action',
          'reentry_return_at',
          'reentry_updated_at',
        ]));
    final tables = await database
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
        .get();
    final tableNames = tables.map((row) => row.read<String>('name')).toSet();
    expect(
      tableNames,
      containsAll([
        'hevy_workouts',
        'hevy_exercises',
        'hevy_sets',
        'hevy_sync_metadata',
      ]),
    );

    await database.close();
    await directory.delete(recursive: true);
  });

  test('version 4 schema backfills active timer for running tasks', () async {
    final directory =
        await Directory.systemTemp.createTemp('neuroflow-v4-migration');
    final file = File('${directory.path}/v4.sqlite');
    final raw = sqlite.sqlite3.open(file.path);
    raw.execute('''
      CREATE TABLE tasks (
        id TEXT NOT NULL PRIMARY KEY,
        title TEXT NOT NULL,
        notes TEXT NULL,
        energy TEXT NOT NULL,
        status TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        due_date INTEGER NULL,
        is_quick_win INTEGER NOT NULL DEFAULT 0,
        estimated_minutes INTEGER NULL,
        completed_at INTEGER NULL,
        google_task_id TEXT NULL,
        reentry_last_completed_step TEXT NULL,
        reentry_next_action TEXT NULL,
        reentry_return_at INTEGER NULL,
        reentry_updated_at INTEGER NULL
      )
    ''');
    raw.execute(
      "INSERT INTO tasks (id, title, energy, status, created_at) "
      "VALUES ('running', 'Focus', 'medium', 'inProgress', 0)",
    );
    raw.execute('PRAGMA user_version = 4');
    raw.close();

    final database = AppDatabase.forTesting(NativeDatabase(file));
    final row = await database
        .customSelect(
          "SELECT active_started_at FROM tasks WHERE id = 'running'",
        )
        .getSingle();

    expect(row.data['active_started_at'], isNotNull);

    await database.close();
    await directory.delete(recursive: true);
  });
}
