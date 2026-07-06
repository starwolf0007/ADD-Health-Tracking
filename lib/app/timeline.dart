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
// The merge listens to the existing streams and re-emits a single ordered
// stream whenever any source changes — zero new tracking, zero new storage.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/mood.dart';
import '../domain/routine.dart';
import '../domain/task.dart';
import 'providers.dart';

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
/// tasks + due routines + mood check-ins. Focus sessions and voice captures
/// are opt-in layers added later. Calm is the default; granularity is a choice.
///
/// This provider MERGES existing streams — it does not query the DB directly
/// and it does not write. It re-projects whenever any source emits.
final timelineProvider = Provider<List<TimelineEvent>>((ref) {
  final events = <TimelineEvent>[];

  // --- Tasks: completions + interruptions + checkpoints ---
  // Completed tasks (from the pending/complete side we already track).
  // We read the interrupted stream (paused/blocked) directly; completed tasks
  // surface via their completedAt. Both come from typed rows — read only.
  final interrupted = ref.watch(interruptedTasksProvider).valueOrNull ?? const [];
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

  // Completed tasks today — from the typed rows (read only).
  final completed = ref.watch(completedTodayProvider).valueOrNull ?? const [];
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

  // --- Mood check-ins (today window) ---
  final moods = ref.watch(recentMoodsProvider).valueOrNull ?? const [];
  final todayStart = _startOfToday();
  for (final m in moods) {
    if (m.loggedAt.isBefore(todayStart)) continue;
    events.add(TimelineEvent(
      id: m.id,
      kind: TimelineEventKind.moodLogged,
      timestamp: m.loggedAt,
      title: 'Checked in · ${m.level.label}',
      mood: m,
    ));
  }

  // --- Due routines (anchor points on the spine) ---
  final routines = ref.watch(dueRoutinesProvider).valueOrNull ?? const [];
  for (final r in routines) {
    // Anchor time today from the routine's schedule, if any.
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

  // Merge by timestamp — the whole point. Chronological spine of the day.
  events.sort((a, b) => a.timestamp.compareTo(b.timestamp));
  return events;
});

DateTime _startOfToday() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

DateTime? _routineAnchorToday(Routine r) {
  final h = r.scheduleHour;
  if (h == null) return null;
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day, h, r.scheduleMinute ?? 0);
}
