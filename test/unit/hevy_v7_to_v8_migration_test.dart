import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuroflow/data/database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  test('version 7 converts Hevy custom metrics to numeric storage', () async {
    final directory =
        await Directory.systemTemp.createTemp('neuroflow-hevy-v7');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/v7.sqlite');

    final raw = sqlite.sqlite3.open(file.path);
    raw.execute('PRAGMA foreign_keys = ON');
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
    raw.execute('''
      INSERT INTO hevy_workouts
        (id, title, start_time, end_time, imported_at)
      VALUES ('workout-1', 'Legacy', 1, 2, 3)
    ''');
    raw.execute('''
      INSERT INTO hevy_exercises
        (id, workout_id, position, title, exercise_template_id)
      VALUES ('exercise-1', 'workout-1', 0, 'Stairs', 'template-1')
    ''');
    raw.execute('''
      INSERT INTO hevy_sets
        (id, exercise_id, position, type, custom_metric, raw_json)
      VALUES (
        'set-1',
        'exercise-1',
        0,
        'normal',
        1,
        '{"custom_metric":1}'
      )
    ''');
    raw.execute('PRAGMA user_version = 7');
    raw.close();

    final database = AppDatabase.forTesting(NativeDatabase(file));
    addTearDown(database.close);

    final set = await database.select(database.hevySets).getSingle();
    expect(set.customMetric, 1.0);

    final tableInfo =
        await database.customSelect('PRAGMA table_info(hevy_sets)').get();
    final customMetric = tableInfo.singleWhere(
      (row) => row.read<String>('name') == 'custom_metric',
    );
    expect(customMetric.read<String>('type'), 'REAL');

    final userVersion =
        await database.customSelect('PRAGMA user_version').getSingle();
    expect(userVersion.read<int>('user_version'), 8);
  });
}
