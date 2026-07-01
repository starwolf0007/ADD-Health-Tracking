// lib/domain/task.dart
//
// The canonical Task — spec §4.2 (Inbox-ingestion contract).
// Pure domain: no Flutter, no Drift, no Google imports. Every capture rail
// (quick-add, gmail, photo, os) produces THIS object and nothing else.

/// Which capture rail produced the task.
enum TaskSource { quickAdd, gmail, photo, os }

/// Lifecycle status. `archived` = swept (recoverable), never deleted.
enum TaskStatus { inbox, today, scheduled, done, archived }

/// Energy tags — capped set, distinguished by SHAPE in the UI, never color (§13).
enum EnergyTag { lowEnergy, deepWork, phone, waiting }

/// Two levels only. No P1–P4 ladders (§4.2 cap).
enum Priority { normal, high }

class Task {
  final String id;
  final String title;
  final TaskSource source;
  final TaskStatus status;
  final DateTime? due; // from NLP parse or Calendar
  final EnergyTag? energy;
  final Priority priority;

  /// Effort estimate in minutes. Drives Quick-Wins "lowest-effort-first"
  /// selection (§6). Null = unknown (sorted as medium).
  final int? estimatedMinutes;

  final String? listName; // maps to a Google Tasks list
  final String? contactRef; // raw NAME only — resolved on view by the OS (§7). Never a stored number.
  final String? attachmentRef; // Drive file id — only for lasting-value images (§7)
  final String? snapRef; // short-lived LOCAL cache id for an unconfirmed photo (§5). Mutually exclusive with attachmentRef.
  final bool confirmed; // photo-sourced tasks start false until visually confirmed (§5); other sources true.

  final String? googleTaskId; // link to the Google Tasks mirror (subset only)

  final DateTime createdAt;
  final DateTime? completedAt;

  /// Last user interaction. Drives the sweep: resurface at 14d untouched,
  /// archive at 21d (§6, §10 resolved).
  final DateTime lastTouchedAt;

  /// Sync bookkeeping: local source-of-truth revision time (§3 sync model).
  final DateTime updatedAt;

  const Task({
    required this.id,
    required this.title,
    required this.source,
    this.status = TaskStatus.inbox,
    this.due,
    this.energy,
    this.priority = Priority.normal,
    this.estimatedMinutes,
    this.listName,
    this.contactRef,
    this.attachmentRef,
    this.snapRef,
    this.confirmed = true,
    this.googleTaskId,
    required this.createdAt,
    this.completedAt,
    required this.lastTouchedAt,
    required this.updatedAt,
  });

  bool get isOpen => status == TaskStatus.inbox ||
      status == TaskStatus.today ||
      status == TaskStatus.scheduled;

  /// A contact-actionable task — drives Contacts resolve-on-view (§7).
  bool get hasContactAction => contactRef != null && contactRef!.isNotEmpty;

  Task copyWith({
    String? title,
    TaskStatus? status,
    DateTime? due,
    EnergyTag? energy,
    Priority? priority,
    int? estimatedMinutes,
    String? listName,
    String? contactRef,
    String? attachmentRef,
    String? snapRef,
    bool? confirmed,
    String? googleTaskId,
    DateTime? completedAt,
    DateTime? lastTouchedAt,
    DateTime? updatedAt,
  }) {
    return Task(
      id: id,
      title: title ?? this.title,
      source: source,
      status: status ?? this.status,
      due: due ?? this.due,
      energy: energy ?? this.energy,
      priority: priority ?? this.priority,
      estimatedMinutes: estimatedMinutes ?? this.estimatedMinutes,
      listName: listName ?? this.listName,
      contactRef: contactRef ?? this.contactRef,
      attachmentRef: attachmentRef ?? this.attachmentRef,
      snapRef: snapRef ?? this.snapRef,
      confirmed: confirmed ?? this.confirmed,
      googleTaskId: googleTaskId ?? this.googleTaskId,
      createdAt: createdAt,
      completedAt: completedAt ?? this.completedAt,
      lastTouchedAt: lastTouchedAt ?? this.lastTouchedAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
