// lib/platform/sync/sync_engine.dart
//
// GENERIC offline-first sync framework. MUST NOT import anything from any
// third-party-provider platform directory or reference any such provider's
// API types — remote specifics are injected via SyncExecutor at channel
// registration time. See STAGE2_COMPONENT_DESIGN.md §2.5 for the full
// design rationale.
//
// THIS SPRINT: no channels are registered anywhere in the app (see
// sync_engine_impl.dart), so every SyncEngine method degrades to a
// graceful no-op / idle value. The types and machinery below are real and
// fully implemented so future channel registrations "just work" without
// touching this file again.

import 'sync_operation.dart';
import 'sync_queue_repository.dart';

/// Generic offline-first sync engine. A "channel" pairs a durable queue
/// (SyncQueueRepository) with a SyncExecutor that knows how to perform an
/// operation remotely. THIS SPRINT: no channels are registered; every
/// method degrades to a graceful no-op / empty stream value.
abstract class SyncEngine {
  /// Register a sync channel. Idempotent per channel id. Called by future
  /// service integrations (e.g. a tasks-mirroring provider), never by
  /// widgets.
  void registerChannel(SyncChannel channel);

  /// Flush pending ops for one channel (or all when [channelId] is null).
  /// Behavior per op: check connectivity → skip entirely if offline (report
  /// SyncReport.offline) → execute via the channel's executor → markDone on
  /// success → on failure incrementRetry and apply BackoffPolicy
  /// WITHIN THIS FLUSH ONLY (see BackoffPolicy doc — fix for M7: there is no
  /// durable due-time storage, so backoff cannot delay retries *across*
  /// flushes yet) → on conflict consult the channel's ConflictResolver.
  /// With zero channels registered (this sprint) it completes immediately
  /// with SyncReport.idle. Never throws to callers.
  Future<SyncReport> flush({String? channelId});

  /// Live progress for UI (e.g. "syncing 3/7"). Emits SyncProgress.idle
  /// when nothing is running.
  Stream<SyncProgress> get progress;

  /// Terminal per-flush reports (success/partial/offline/idle) for
  /// diagnostics surfaces. Error payloads are sanitized: op ids and
  /// categories only — no titles/notes/tokens/emails.
  Stream<SyncReport> get reports;

  /// Cheap connectivity signal used by flush(); also available to UI.
  Future<bool> get isOnline;

  void dispose();
}

/// A named durable-queue + executor pairing.
class SyncChannel {
  final String id; // e.g. a future tasks-mirroring provider id
  final SyncQueueRepository queue; // existing interface, reused verbatim
  final SyncExecutor executor;
  final ConflictResolver conflictResolver;
  final BackoffPolicy backoff;

  const SyncChannel({
    required this.id,
    required this.queue,
    required this.executor,
    this.conflictResolver = const LastWriteWinsResolver(),
    this.backoff = const BackoffPolicy(),
  });
}

/// Performs one operation against a remote system. Implementations live
/// with their integration (future sprints), NEVER inside the engine.
abstract class SyncExecutor {
  Future<SyncExecutionResult> execute(SyncOperation op);
}

class SyncExecutionResult {
  final bool success;
  final String? remoteId; // e.g. newly created remote record id
  final SyncFailureKind? failure;

  const SyncExecutionResult.ok({this.remoteId})
    : success = true,
      failure = null;

  const SyncExecutionResult.fail(this.failure) : success = false, remoteId = null;
}

/// Failure taxonomy drives retry policy: transient → backoff retry;
/// auth → stop flushing this channel, surface via reports; conflict →
/// ConflictResolver; permanent → markDone-with-failure (no retry).
enum SyncFailureKind { transientNetwork, authRequired, conflict, permanent }

/// Hook: decide what to do when local and remote disagree. Takes the
/// remote snapshot too (fix for m8 — a resolver handed only the local op
/// can never actually express keepRemote) — future executors populate
/// [remoteSnapshot] from whatever they fetched; today's LastWriteWinsResolver
/// ignores it.
abstract class ConflictResolver {
  Future<ConflictDecision> resolve(SyncOperation local, Object? remoteSnapshot);
}

class LastWriteWinsResolver implements ConflictResolver {
  const LastWriteWinsResolver();

  @override
  Future<ConflictDecision> resolve(SyncOperation local, Object? remoteSnapshot) async =>
      ConflictDecision.keepLocal;
}

enum ConflictDecision { keepLocal, keepRemote, skip }

/// Backoff delay calculator: delay = min(base * multiplier^retryCount, max).
/// maxRetries = 5 matches the existing SyncQueue 'failed' threshold (see
/// AppDatabase.incrementSyncRetry) so the engine and DriftSyncQueueRepository
/// never disagree on when to give up.
///
/// **Scope this sprint (fix for M7):** `SyncQueue` has no `nextAttemptAt` /
/// `scheduledAt` column and `SyncQueueRepository.fetchPending()` has no way
/// to filter by due-time — durable, cross-flush-delayed retries are
/// therefore physically unimplementable on the current schema. `delayFor`
/// is consumed ONLY *within a single flush* (e.g. to order/space retries of
/// ops already being processed in this call), never to skip an op until a
/// future flush. True durable backoff (skip retrying until `delayFor` has
/// elapsed across restarts) requires adding a due-time column and is
/// deferred to the channel-registration sprint alongside the
/// SyncOperation payload generalization — it is NOT shipped now, and the
/// engine must not be "fixed" mid-implementation by adding that column.
class BackoffPolicy {
  final Duration base;
  final double multiplier;
  final Duration max;
  final int maxRetries;

  const BackoffPolicy({
    this.base = const Duration(seconds: 30),
    this.multiplier = 2.0,
    this.max = const Duration(hours: 1),
    this.maxRetries = 5,
  });

  /// Delay to apply before the next attempt following [retryCount] prior
  /// failures. Used only to order/space retries WITHIN a single flush()
  /// call — see class doc for why this is not (yet) durable across flushes.
  Duration delayFor(int retryCount) {
    var factor = 1.0;
    for (var i = 0; i < retryCount; i++) {
      factor *= multiplier;
    }
    final scaledMicros = base.inMicroseconds * factor;
    final scaled = Duration(microseconds: scaledMicros.round());
    return scaled > max ? max : scaled;
  }
}

/// Connectivity seam — injectable so tests can fake offline. Default impl
/// (see sync_engine_impl.dart) uses a lightweight socket probe; swap for
/// connectivity_plus later WITHOUT changing the engine (no new dependency
/// this sprint).
abstract class ConnectivityProbe {
  Future<bool> get isOnline;
}

/// Live progress for UI (e.g. "syncing 3/7"). [SyncProgress.idle] is the
/// default/rest value.
class SyncProgress {
  final String? channelId;
  final int done;
  final int total;

  const SyncProgress({this.channelId, this.done = 0, this.total = 0});

  static const idle = SyncProgress();

  bool get isIdle => total == 0;

  @override
  bool operator ==(Object other) =>
      other is SyncProgress &&
      other.channelId == channelId &&
      other.done == done &&
      other.total == total;

  @override
  int get hashCode => Object.hash(channelId, done, total);
}

/// Terminal per-flush report. Sanitized: [errors] carries only op ids and
/// failure-kind categories — never operation payloads (titles/notes).
class SyncReport {
  final String? channelId;
  final int succeeded;
  final int failed;
  final int skipped;
  final SyncReportKind kind;
  final List<SyncOpError> errors;

  const SyncReport({
    this.channelId,
    this.succeeded = 0,
    this.failed = 0,
    this.skipped = 0,
    required this.kind,
    this.errors = const [],
  });

  /// Nothing to do — zero channels registered, or an unknown channelId was
  /// requested. The default/rest value for the [SyncEngine.reports] stream.
  static const idle = SyncReport(kind: SyncReportKind.idle);

  /// The requested channel(s) were skipped entirely because [SyncEngine.isOnline]
  /// was false.
  factory SyncReport.offline(String? channelId) =>
      SyncReport(channelId: channelId, kind: SyncReportKind.offline);

  /// A flush actually ran against the durable queue. [SyncReportKind.partial]
  /// when at least one op failed, [SyncReportKind.completed] otherwise.
  factory SyncReport.completed({
    String? channelId,
    int succeeded = 0,
    int failed = 0,
    int skipped = 0,
    List<SyncOpError> errors = const [],
  }) {
    return SyncReport(
      channelId: channelId,
      succeeded: succeeded,
      failed: failed,
      skipped: skipped,
      kind: failed > 0 ? SyncReportKind.partial : SyncReportKind.completed,
      errors: errors,
    );
  }
}

enum SyncReportKind { idle, offline, completed, partial }

/// Sanitized error record: op id + failure-kind category ONLY. Never the
/// operation's title/notes or any remote payload.
class SyncOpError {
  final String opId;
  final SyncFailureKind kind;
  const SyncOpError({required this.opId, required this.kind});
}
