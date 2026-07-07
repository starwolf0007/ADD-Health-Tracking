// lib/platform/sync/sync_engine_impl.dart
//
// DefaultSyncEngine — the concrete, generic SyncEngine. Zero third-party-
// provider imports; see sync_engine.dart for the full contract this
// implements.
//
// THIS SPRINT no code calls registerChannel(), so `_channels` is always
// empty and every flush() call takes the SyncReport.idle fast path below.
// The per-channel flush loop is nonetheless fully implemented (not a
// stub) so it is testable today and requires no further changes when a
// future sprint registers the first channel.

import 'dart:async';
import 'dart:io';

import 'sync_engine.dart';

class DefaultSyncEngine implements SyncEngine {
  DefaultSyncEngine({ConnectivityProbe? connectivityProbe})
    : _connectivityProbe = connectivityProbe ?? const SocketConnectivityProbe();

  final ConnectivityProbe _connectivityProbe;

  final Map<String, SyncChannel> _channels = {};

  final StreamController<SyncProgress> _progressController =
      StreamController<SyncProgress>.broadcast();
  final StreamController<SyncReport> _reportsController = StreamController<SyncReport>.broadcast();

  SyncProgress _lastProgress = SyncProgress.idle;
  SyncReport _lastReport = SyncReport.idle;

  @override
  void registerChannel(SyncChannel channel) {
    // Idempotent per channel id: first registration wins, later calls with
    // the same id are no-ops rather than replacing/erroring.
    _channels.putIfAbsent(channel.id, () => channel);
  }

  @override
  Future<bool> get isOnline => _connectivityProbe.isOnline;

  @override
  Future<SyncReport> flush({String? channelId}) async {
    if (_channels.isEmpty) {
      return _emitReport(SyncReport.idle);
    }

    final targets = channelId == null
        ? _channels.values.toList(growable: false)
        : [if (_channels[channelId] case final channel?) channel];

    if (targets.isEmpty) {
      // Unknown channelId — nothing registered under it. Degrade
      // gracefully rather than throwing.
      return _emitReport(SyncReport.idle);
    }

    SyncReport last = SyncReport.idle;
    for (final channel in targets) {
      last = _emitReport(await _flushChannel(channel));
    }
    return last;
  }

  Future<SyncReport> _flushChannel(SyncChannel channel) async {
    final online = await isOnline;
    if (!online) {
      return SyncReport.offline(channel.id);
    }

    final pending = await channel.queue.fetchPending();
    if (pending.isEmpty) {
      return SyncReport.completed(channelId: channel.id);
    }

    var succeeded = 0;
    var failed = 0;
    var skipped = 0;
    final errors = <SyncOpError>[];

    for (var i = 0; i < pending.length; i++) {
      final op = pending[i];
      _emitProgress(SyncProgress(channelId: channel.id, done: i, total: pending.length));

      // Space out retries WITHIN this flush only per BackoffPolicy — see
      // BackoffPolicy doc: never persisted/deferred across flush() calls.
      if (op.retryCount > 0) {
        final delay = channel.backoff.delayFor(op.retryCount);
        if (delay > Duration.zero) {
          await Future<void>.delayed(delay);
        }
      }

      SyncExecutionResult result;
      try {
        result = await channel.executor.execute(op);
      } catch (_) {
        // An executor that throws is treated as a transient failure so a
        // buggy/unreachable remote never crashes the flush loop.
        result = const SyncExecutionResult.fail(SyncFailureKind.transientNetwork);
      }

      if (result.success) {
        await channel.queue.markDone(op.id);
        succeeded++;
        continue;
      }

      final kind = result.failure ?? SyncFailureKind.permanent;

      switch (kind) {
        case SyncFailureKind.conflict:
          final decision = await channel.conflictResolver.resolve(op, null);
          switch (decision) {
            case ConflictDecision.keepLocal:
              // Local should win — leave it queued for another attempt.
              await channel.queue.incrementRetry(op.id);
              failed++;
              errors.add(SyncOpError(opId: op.id, kind: kind));
              break;
            case ConflictDecision.keepRemote:
              // Remote wins — discard the local op, nothing to retry.
              await channel.queue.markDone(op.id);
              skipped++;
              break;
            case ConflictDecision.skip:
              // Defer the decision entirely — leave the queue row untouched.
              skipped++;
              break;
          }
          break;
        case SyncFailureKind.authRequired:
          // Stop flushing this channel for the rest of this call; leave the
          // failing op (and everything after it) pending for a future
          // flush once the channel's auth is restored. Do NOT incrementRetry
          // here — this isn't a retry-worthy failure, it's "paused".
          failed++;
          errors.add(SyncOpError(opId: op.id, kind: kind));
          skipped += pending.length - (i + 1);
          return SyncReport.completed(
            channelId: channel.id,
            succeeded: succeeded,
            failed: failed,
            skipped: skipped,
            errors: errors,
          );
        case SyncFailureKind.transientNetwork:
          // Retry-worthy: incrementRetry (caps at 'failed' after
          // BackoffPolicy.maxRetries, matching AppDatabase.incrementSyncRetry).
          await channel.queue.incrementRetry(op.id);
          failed++;
          errors.add(SyncOpError(opId: op.id, kind: kind));
          break;
        case SyncFailureKind.permanent:
          // Not retry-worthy: close out the queue row via markDone (the
          // only terminal, no-retry primitive SyncQueueRepository exposes)
          // while still categorizing it as a failure in this report.
          await channel.queue.markDone(op.id);
          failed++;
          errors.add(SyncOpError(opId: op.id, kind: kind));
          break;
      }
    }

    _emitProgress(SyncProgress.idle);

    return SyncReport.completed(
      channelId: channel.id,
      succeeded: succeeded,
      failed: failed,
      skipped: skipped,
      errors: errors,
    );
  }

  SyncReport _emitReport(SyncReport report) {
    _lastReport = report;
    if (!_reportsController.isClosed) {
      _reportsController.add(report);
    }
    return report;
  }

  void _emitProgress(SyncProgress progress) {
    _lastProgress = progress;
    if (!_progressController.isClosed) {
      _progressController.add(progress);
    }
  }

  @override
  Stream<SyncProgress> get progress async* {
    yield _lastProgress;
    yield* _progressController.stream;
  }

  @override
  Stream<SyncReport> get reports async* {
    yield _lastReport;
    yield* _reportsController.stream;
  }

  @override
  void dispose() {
    _progressController.close();
    _reportsController.close();
  }
}

/// Default [ConnectivityProbe]: attempts a short-timeout TCP connection to
/// a well-known public DNS resolver. No new pubspec dependency (no
/// connectivity_plus) per the design's non-goal — swap this implementation
/// for a platform-aware one later without touching [SyncEngine] callers.
class SocketConnectivityProbe implements ConnectivityProbe {
  const SocketConnectivityProbe({
    this.host = '8.8.8.8',
    this.port = 53,
    this.timeout = const Duration(seconds: 2),
  });

  final String host;
  final int port;
  final Duration timeout;

  @override
  Future<bool> get isOnline async {
    Socket? socket;
    try {
      socket = await Socket.connect(host, port, timeout: timeout);
      return true;
    } catch (_) {
      return false;
    } finally {
      socket?.destroy();
    }
  }
}
