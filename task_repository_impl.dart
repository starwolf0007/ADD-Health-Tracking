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
// Table definition
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
  TextColumn get notes => 