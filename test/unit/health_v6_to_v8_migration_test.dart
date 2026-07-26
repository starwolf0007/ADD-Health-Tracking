import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuroflow/data/database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  test('version 6 database migrates health tables and indexes', () async {
    final directory =
        await Directory.systemTemp.createTemp('neuroflow-health-v6');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/v6.sqlite');

    final raw = sqlite.sqlite3.open(file.path);
    raw.execute('''
      CREATE TABLE tasks (
        id TEXT NOT NULL PRIMARY KEY,
        title TEXT NOT NULL,
        notes TEXT,
        energy TEXT NOT NULL,
        status TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        due_date INTEGER,
        is_quick_win INTEGER NOT NULL DEFAULT 0,
        estimated_minutes INTEGER,
        completed_at INTEGER,
        active_started_at INTEGER,
        google_task_id TEXT,
        reentry_last_completed_step TEXT,
        reentry_next_action TEXT,
        reentry_return_at INTEGER,
        reentry_updated_at INTEGER
      )
    ''');
    _createLegacyHevyTables(raw);
    raw.execute(
      "INSERT INTO tasks (id, title, energy, status, created_at) "
      "VALUES ('legacy-task', 'Keep me', 'low', 'notStarted', 1)",
    );
    raw.execute('PRAGMA user_version = 6');
    raw.close();

    final database = AppDatabase.forTesting(NativeDatabase(file));
    addTearDown(database.close);

    final tableRows = await database
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
        .get();
    final tableNames = tableRows.map((row) => row.read<String>('name')).toSet();

    expect(
      tableNames,
      containsAll({
        'health_sources',
        'health_devices',
        'health_source_records',
        'health_events',
        'health_spans',
        'health_series',
        'health_time_series',
        'health_context_events',
        'health_data_coverage',
        'health_ingestion_runs',
        'health_ingestion_checkpoints',
        'health_tombstones',
        'health_permissions',
      }),
    );

    final indexRows = await database
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'index'")
        .get();
    final indexNames = indexRows.map((row) => row.read<String>('name')).toSet();

    expect(
      indexNames,
      containsAll({
        'idx_health_source_records_type_time',
        'idx_health_source_records_external',
        'idx_health_events_concept_time',
        'idx_health_events_local_date',
        'idx_health_spans_concept_start',
        'idx_health_spans_concept_end',
        'idx_health_spans_local_date',
        'idx_health_series_concept_start',
        'idx_health_samples_concept_time',
        'idx_health_samples_series_time',
        'idx_health_samples_local_date',
        'idx_health_context_type_time',
        'idx_health_coverage_concept_window',
        'idx_health_tombstones_source_external',
      }),
    );

    final legacyRows = await database
        .customSelect("SELECT id, title FROM tasks WHERE id = 'legacy-task'")
        .get();
    expect(legacyRows, hasLength(1));
    expect(legacyRows.single.read<String>('title'), 'Keep me');

    final userVersion =
        await database.customSelect('PRAGMA user_version').getSingle();
    expect(userVersion.read<int>('user_version'), 8);
  });
}

void _createLegacyHevyTables(sqlite.Database raw) {
  raw.execute('''
    CREATE TABLE hevy_workouts (
      id TEXT NOT NULL PRIMARY KEY,
      title TEXT NOT NULL,
      description TEXT,
      start_time INTEGER NOT NULL,
      end_time INTEGER NOT NULL,
      hevy_updated_at INTEGER,
      hevy_created_at INTEGER,
      imported_at INTEGER NOT NULL
    )
  ''');
  raw.execute('''
    CREATE TABLE hevy_exercises (
      id TEXT NOT NULL PRIMARY KEY,
      workout_id TEXT NOT NULL REFERENCES hevy_workouts(id),
      position INTEGER NOT NULL,
      title TEXT NOT NULL,
      notes TEXT,
      exercise_template_id TEXT NOT NULL,
      superset_id TEXT
    )
  ''');
  raw.execute('''
    CREATE TABLE hevy_sets (
      id TEXT NOT NULL PRIMARY KEY,
      exercise_id TEXT NOT NULL REFERENCES hevy_exercises(id),
      position INTEGER NOT NULL,
      type TEXT NOT NULL,
      weight_kg REAL,
      reps INTEGER,
      distance_meters INTEGER,
      duration_seconds INTEGER,
      rpe REAL,
      custom_metric INTEGER,
      raw_json TEXT NOT NULL
    )
  ''');
}
