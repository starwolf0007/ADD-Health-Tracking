// lib/app/timeline.dart
//
// PHASE 2 · STEP 2 — "Your Day" timeline projection.
//
// ⚠️ ARCHITECTURAL LAW (DEC-004): this is a READ-ONLY PROJECTION.
// TimelineEvent is a PRESENTATION object assembled at read time by merging
// the typed source tables (Tasks, Routines, MoodLogs, ...) by timestamp.
// NOTHING writes a TimelineEvent. The typed tables remain the source of
// truth. Present as events; persist as types. Do not add a TimelineEvents
// table. Do not let this provider mutate anything.
//
// The merge listens to the existing providers and re-emits a single ordered
// list whenever any source changes — zero new tracking, zero new storage.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:neuroflow/domain/routine.dart';
import 'package:neuroflow/domain/task.dart';
import 'package:neuroflow/domain/mood.dart';
import 'package:neuroflow/app/providers.dart';

/// The kind of thing that happened, for icon/label/color mapping in the UI.
enum TimelineEventKind {
  taskCompleted,
  taskPaused,
  taskBlocked,
  taskCheckpoint,
  routineDue,
  moodLogged,
}

/// A single point on the day's spine. Presentation-only — never persisted.
class TimelineEvent {
  final String id; // source row id (for tap-through), NOT a new identity
  final TimelineEventKind kind;
  final DateTime timestamp;
  final String title;
  final String? subtitle;

  /// Back-reference to the source entity so the UI can navigate to it.
  /// One of these is set depending on kind.
  final Task? task;
  final Routine? routine;
  final MoodLog? mood;

  const TimelineEvent({
    required this.id,
    required this.kind,
    required this.timestamp,
    required this.title,
    this.subtitle,
    this.task,
    this.routine,
    this.mood,
  });
}

/// MVP scope (per the roadmap): the spine is task completions + interrupted
/// tasks + due routines + the day's mood check-in. Focus sessions and voice
/// captures are opt-in layers added later. Calm is the default.
///
/// This provider MERGES existing providers — it does not query the DB directly
/// and it does not write. It re-projects whenever any source emits.
final timelineProvider = Provider<List<TimelineEvent>>((ref) {
  final events = <TimelineEvent>[];

  // --- Tasks: interruptions (paused / blocked) ---
  final interrupted = ref.watch(interruptedTasksProvider).value ?? const [];
  for (final t in interrupted) {
    if (t.pausedAt == null) continue;
    final kind = t.state == TaskState.blocked
        ? TimelineEventKind.taskBlocked
        : TimelineEventKind.taskPaused;
    events.add(TimelineEvent(
      id: t.id,
      kind: kind,
      timestamp: t.pausedAt!,
      title: t.title,
      subtitle: t.pausedStep == null
          ? (kind == TimelineEventKind.taskBlocked ? 'Blocked' : 'Paused')
          : 'Stopped at: ${t.pausedStep}',
      task: t,
    ));
  }

  // --- Tasks: completions today (from the typed rows, read only) ---
  final completed = ref.watch(completedTodayProvider).value ?? const [];
  for (final t in completed) {
    if (t.completedAt == null) continue;
    events.add(TimelineEvent(
      id: t.id,
      kind: TimelineEventKind.taskCompleted,
      timestamp: t.completedAt!,
      title: t.title,
      subtitle: 'Done',
      task: t,
    ));
  }

  // --- Mood check-in (today) ---
  final mood = ref.watch(todayMoodProvider).value;
  if (mood != null) {
    events.add(TimelineEvent(
      id: mood.id,
      kind: TimelineEventKind.moodLogged,
      timestamp: mood.loggedAt,
      title: 'Checked in · ${mood.level.label}',
      mood: mood,
    ));
  }

  // --- Due routines (anchor points on the spine) ---
  final routines = ref.watch(dueRoutinesProvider).value ?? const [];
  for (final r in routines) {
    final ts = _routineAnchorToday(r);
    if (ts == null) continue;
    events.add(TimelineEvent(
      id: r.id,
      kind: TimelineEventKind.routineDue,
      timestamp: ts,
      title: r.name,
      subtitle: '${r.completedCount}/${r.steps.length} steps',
      routine: r,
    ));
  }

  // Merge by timestamp — the whole point. A stable, deterministic tiebreaker
  // (kind, then source id) keeps identical-timestamp events from reordering
  // unpredictably between rebuilds.
  events.sort((a, b) {
    final byTime = a.timestamp.compareTo(b.timestamp);
    if (byTime != 0) return byTime;
    final byKind = a.kind.index.compareTo(b.kind.index);
    if (byKind != 0) return byKind;
    return a.id.compareTo(b.id);
  });
  return events;
});

DateTime? _routineAnchorToday(Routine r) {
  final h = r.scheduleHour;
  if (h == null) return null;
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day, h, r.scheduleMinute ?? 0);
}
