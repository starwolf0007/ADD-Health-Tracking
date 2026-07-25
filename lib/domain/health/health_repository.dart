import 'package:meta/meta.dart';
import 'package:neuroflow/domain/health/health_enums.dart';
import 'package:neuroflow/domain/health/health_transaction.dart';

/// Sole Phase-1 write boundary for canonical health evidence.
///
/// Implementations must not expose Drift rows or companion types. They must
/// reject medical-tier content, validate database-dependent invariants, and
/// commit each accepted [HealthTransaction] atomically.
abstract interface class HealthRepository {
  Future<RepositoryWriteResult> ingest(HealthTransaction transaction);
}

/// Checkpoints are deliberately separated from evidence writes at the domain
/// boundary. The ingestion service coordinates them and the Drift
/// implementation must provide a higher-level atomic commit operation before
/// checkpoint advancement is enabled in production.
abstract interface class HealthCheckpointStore {
  Future<HealthIngestionCheckpoint?> getCheckpoint(HealthCheckpointKey key);

  Future<void> commitCheckpoint(HealthIngestionCheckpoint checkpoint);
}

abstract interface class HealthIngestionRunStore {
  Future<void> recordIngestionRun(HealthIngestionRunSummary summary);
}

@immutable
class RepositoryWriteResult {
  final String transactionId;
  final int recordsInserted;
  final int recordsUpdated;
  final int recordsDeleted;
  final int recordsIgnored;

  const RepositoryWriteResult({
    required this.transactionId,
    required this.recordsInserted,
    required this.recordsUpdated,
    required this.recordsDeleted,
    required this.recordsIgnored,
  });

  int get recordsCommitted =>
      recordsInserted + recordsUpdated + recordsDeleted + recordsIgnored;
}

@immutable
class HealthCheckpointKey {
  final String sourceId;
  final String recordType;

  HealthCheckpointKey({
    required this.sourceId,
    required this.recordType,
  }) {
    if (sourceId.trim().isEmpty) {
      throw const InvalidHealthDraft(
        reasonCode: 'empty_checkpoint_source_id',
        field: 'sourceId',
      );
    }
    if (recordType.trim().isEmpty) {
      throw const InvalidHealthDraft(
        reasonCode: 'empty_checkpoint_record_type',
        field: 'recordType',
      );
    }
  }
}

@immutable
class HealthIngestionCheckpoint {
  final HealthCheckpointKey key;
  final String checkpointToken;
  final DateTime committedAtUtc;
  final String? ingestionRunId;

  HealthIngestionCheckpoint({
    required this.key,
    required this.checkpointToken,
    required this.committedAtUtc,
    this.ingestionRunId,
  }) {
    if (checkpointToken.trim().isEmpty) {
      throw const InvalidHealthDraft(
        reasonCode: 'empty_checkpoint_token',
        field: 'checkpointToken',
      );
    }
  }
}

@immutable
class HealthIngestionRunSummary {
  final String ingestionRunId;
  final String sourceId;
  final DateTime startedAtUtc;
  final DateTime? finishedAtUtc;
  final IngestionTrigger trigger;
  final IngestionStatus status;
  final int recordsSeen;
  final int recordsInserted;
  final int recordsUpdated;
  final int recordsDeleted;
  final int recordsIgnored;
  final int recordsFailed;
  final int normalizationSchemaVersion;
  final String normalizerVersion;
  final List<HealthRejectionSummary> rejections;

  HealthIngestionRunSummary({
    required this.ingestionRunId,
    required this.sourceId,
    required this.startedAtUtc,
    required this.trigger,
    required this.status,
    required this.recordsSeen,
    required this.recordsInserted,
    required this.recordsUpdated,
    required this.recordsDeleted,
    required this.recordsIgnored,
    required this.recordsFailed,
    required this.normalizationSchemaVersion,
    required this.normalizerVersion,
    Iterable<HealthRejectionSummary> rejections = const [],
    this.finishedAtUtc,
  }) : rejections = List<HealthRejectionSummary>.unmodifiable(rejections) {
    if (ingestionRunId.trim().isEmpty || sourceId.trim().isEmpty) {
      throw const InvalidHealthDraft(
        reasonCode: 'empty_ingestion_run_identity',
      );
    }
    if (finishedAtUtc != null && finishedAtUtc!.isBefore(startedAtUtc)) {
      throw const InvalidHealthDraft(
        reasonCode: 'invalid_ingestion_run_range',
      );
    }
    final counters = <int>[
      recordsSeen,
      recordsInserted,
      recordsUpdated,
      recordsDeleted,
      recordsIgnored,
      recordsFailed,
    ];
    if (counters.any((count) => count < 0)) {
      throw const InvalidHealthDraft(
        reasonCode: 'negative_ingestion_counter',
      );
    }
    if (recordsInserted + recordsUpdated + recordsDeleted + recordsIgnored + recordsFailed >
        recordsSeen) {
      throw const InvalidHealthDraft(
        reasonCode: 'ingestion_counters_exceed_records_seen',
      );
    }
    if (normalizationSchemaVersion < 1 || normalizerVersion.trim().isEmpty) {
      throw const InvalidHealthDraft(
        reasonCode: 'invalid_ingestion_normalizer_identity',
      );
    }
  }
}

/// Log-safe rejection metadata. It must never contain raw payloads, notes,
/// measurement values, or plain-text upstream identifiers.
@immutable
class HealthRejectionSummary {
  final String reasonCode;
  final String sourceRecordType;
  final String? safeIdentifierHash;

  HealthRejectionSummary({
    required this.reasonCode,
    required this.sourceRecordType,
    this.safeIdentifierHash,
  }) {
    if (reasonCode.trim().isEmpty || sourceRecordType.trim().isEmpty) {
      throw const InvalidHealthDraft(
        reasonCode: 'invalid_rejection_summary',
      );
    }
  }
}
