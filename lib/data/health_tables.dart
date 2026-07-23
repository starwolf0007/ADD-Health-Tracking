// Phase-1 Health Intelligence evidence schema.
//
// Locked constraints:
// - These tables accept routine and sensitive health evidence only. Medical
//   records belong in the future encrypted medical vault and must be rejected
//   by the repository boundary before any write reaches Drift.
// - Missing data remains missing. Do not synthesize absent samples or coerce
//   unavailable measurements to zero.
// - Imported evidence and rebuildable NeuroFlow-derived analytics are separate.
// - Raw source payloads live at source-record level, not on every sample.
// - HealthTimeSeries samples are immutable children of HealthSeries. Corrections
//   supersede or invalidate the parent series; samples are never partly deleted.
// - Lexi and Presentation must not query raw health tables directly.

import 'package:drift/drift.dart';
import 'package:neuroflow/domain/health/health_enums.dart';

class HealthSources extends Table {
  TextColumn get id => text()();
  TextColumn get sourceSystem => text()();
  TextColumn get displayName => text()();
  TextColumn get packageName => text().nullable()();
  TextColumn get vendorName => text().nullable()();
  BoolColumn get isEnabled => boolean().withDefault(const Constant(true))();
  TextColumn get permissionStatus => text().withDefault(const Constant('unknown'))();
  DateTimeColumn get lastSuccessfulSyncAtUtc => dateTime().nullable()();
  DateTimeColumn get lastAttemptedSyncAtUtc => dateTime().nullable()();
  TextColumn get lastErrorCode => text().nullable()();
  TextColumn get lastErrorMessage => text().nullable()();
  DateTimeColumn get createdAtUtc => dateTime()();
  DateTimeColumn get updatedAtUtc => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class HealthDevices extends Table {
  TextColumn get id => text()();
  TextColumn get sourceId => text().references(HealthSources, #id)();
  TextColumn get manufacturer => text().nullable()();
  TextColumn get model => text().nullable()();
  TextColumn get deviceType => text().nullable()();
  TextColumn get hardwareVersion => text().nullable()();
  TextColumn get softwareVersion => text().nullable()();
  TextColumn get identifierHash => text().nullable()();
  DateTimeColumn get firstSeenAtUtc => dateTime()();
  DateTimeColumn get lastSeenAtUtc => dateTime()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get metadataJson => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class HealthSourceRecords extends Table {
  TextColumn get id => text()();
  TextColumn get sourceId => text().references(HealthSources, #id)();
  TextColumn get sourceAppId => text().nullable()();
  TextColumn get deviceId => text().nullable().references(HealthDevices, #id)();
  TextColumn get externalId => text().nullable()();
  TextColumn get sourceRecordType => text()();
  DateTimeColumn get startedAtUtc => dateTime()();
  DateTimeColumn get endedAtUtc => dateTime().nullable()();
  IntColumn get startOffsetSeconds => integer().nullable()();
  IntColumn get endOffsetSeconds => integer().nullable()();
  TextColumn get localDate => text()();
  DateTimeColumn get sourceModifiedAtUtc => dateTime().nullable()();
  TextColumn get rawPayloadJson => text().nullable()();
  TextColumn get rawPayloadHash => text().nullable()();
  IntColumn get sensitivity => intEnum<SensitivityClass>()();
  TextColumn get consentScope => text().nullable()();
  DateTimeColumn get ingestedAtUtc => dateTime()();
  DateTimeColumn get lastProcessedAtUtc => dateTime()();
  IntColumn get normalizationSchemaVersion => integer()();
  TextColumn get normalizerVersion => text()();
  DateTimeColumn get deletedAtUtc => dateTime().nullable()();
  TextColumn get supersedesSourceRecordId => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class HealthEvents extends Table {
  IntColumn get rowId => integer().autoIncrement()();
  TextColumn get evidenceId => text().unique()();
  TextColumn get sourceRecordId => text().nullable().references(HealthSourceRecords, #id)();
  TextColumn get conceptType => text()();
  DateTimeColumn get eventTimestampUtc => dateTime()();
  IntColumn get timezoneOffsetSeconds => integer().nullable()();
  TextColumn get localDate => text()();
  RealColumn get numericValue => real().nullable()();
  TextColumn get textValue => text().nullable()();
  BoolColumn get booleanValue => boolean().nullable()();
  TextColumn get canonicalUnit => text().nullable()();
  TextColumn get normalizedPayloadJson => text().nullable()();
  IntColumn get measurementStatus => intEnum<MeasurementStatus>()();
  IntColumn get recordingMethod => intEnum<RecordingMethod>()();
  IntColumn get qualityLabel => intEnum<QualityLabel>()();
  IntColumn get sensitivity => intEnum<SensitivityClass>()();
  RealColumn get completenessRatio => real().nullable()();
  TextColumn get validationFlagsJson => text().nullable()();
  TextColumn get normalizationWarningsJson => text().nullable()();
  IntColumn get normalizationSchemaVersion => integer()();
  TextColumn get normalizerVersion => text()();
  DateTimeColumn get ingestedAtUtc => dateTime()();
  DateTimeColumn get deletedAtUtc => dateTime().nullable()();
  TextColumn get supersedesEvidenceId => text().nullable()();
  IntColumn get retentionPolicy => intEnum<RetentionPolicy>()();
  BoolColumn get aiAccessAllowed => boolean().withDefault(const Constant(false))();

  @override
  List<String> get customConstraints => [
        'CHECK (completeness_ratio IS NULL OR (completeness_ratio >= 0.0 AND completeness_ratio <= 1.0))',
      ];
}

class HealthSpans extends Table {
  IntColumn get rowId => integer().autoIncrement()();
  TextColumn get evidenceId => text().unique()();
  TextColumn get sourceRecordId => text().nullable().references(HealthSourceRecords, #id)();
  TextColumn get conceptType => text()();
  DateTimeColumn get startTimestampUtc => dateTime()();
  DateTimeColumn get endTimestampUtc => dateTime()();
  IntColumn get startTimezoneOffsetSeconds => integer().nullable()();
  IntColumn get endTimezoneOffsetSeconds => integer().nullable()();
  TextColumn get localDate => text()();
  IntColumn get durationSeconds => integer()();
  RealColumn get summaryValue => real().nullable()();
  TextColumn get canonicalUnit => text().nullable()();
  TextColumn get summaryValuesJson => text().nullable()();
  TextColumn get parentSpanEvidenceId => text().nullable()();
  IntColumn get measurementStatus => intEnum<MeasurementStatus>()();
  IntColumn get recordingMethod => intEnum<RecordingMethod>()();
  IntColumn get qualityLabel => intEnum<QualityLabel>()();
  IntColumn get sensitivity => intEnum<SensitivityClass>()();
  RealColumn get completenessRatio => real().nullable()();
  TextColumn get validationFlagsJson => text().nullable()();
  TextColumn get normalizationWarningsJson => text().nullable()();
  IntColumn get normalizationSchemaVersion => integer()();
  TextColumn get normalizerVersion => text()();
  DateTimeColumn get ingestedAtUtc => dateTime()();
  DateTimeColumn get deletedAtUtc => dateTime().nullable()();
  TextColumn get supersedesEvidenceId => text().nullable()();
  IntColumn get retentionPolicy => intEnum<RetentionPolicy>()();
  BoolColumn get aiAccessAllowed => boolean().withDefault(const Constant(false))();

  @override
  List<String> get customConstraints => [
        'CHECK (end_timestamp_utc >= start_timestamp_utc)',
        'CHECK (duration_seconds >= 0)',
        'CHECK (completeness_ratio IS NULL OR (completeness_ratio >= 0.0 AND completeness_ratio <= 1.0))',
      ];
}

class HealthSeries extends Table {
  TextColumn get id => text()();
  TextColumn get sourceRecordId => text().nullable().references(HealthSourceRecords, #id)();
  TextColumn get conceptType => text()();
  DateTimeColumn get startTimestampUtc => dateTime()();
  DateTimeColumn get endTimestampUtc => dateTime()();
  IntColumn get startTimezoneOffsetSeconds => integer().nullable()();
  IntColumn get endTimezoneOffsetSeconds => integer().nullable()();
  TextColumn get localDate => text()();
  IntColumn get sampleCount => integer()();
  IntColumn get expectedSampleCount => integer().nullable()();
  RealColumn get completenessRatio => real().nullable()();
  IntColumn get measurementStatus => intEnum<MeasurementStatus>()();
  IntColumn get recordingMethod => intEnum<RecordingMethod>()();
  IntColumn get qualityLabel => intEnum<QualityLabel>()();
  IntColumn get sensitivity => intEnum<SensitivityClass>()();
  IntColumn get normalizationSchemaVersion => integer()();
  TextColumn get normalizerVersion => text()();
  DateTimeColumn get ingestedAtUtc => dateTime()();
  DateTimeColumn get deletedAtUtc => dateTime().nullable()();
  TextColumn get supersedesSeriesId => text().nullable()();
  IntColumn get retentionPolicy => intEnum<RetentionPolicy>()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
        'CHECK (end_timestamp_utc >= start_timestamp_utc)',
        'CHECK (sample_count >= 0)',
        'CHECK (expected_sample_count IS NULL OR expected_sample_count >= 0)',
        'CHECK (completeness_ratio IS NULL OR (completeness_ratio >= 0.0 AND completeness_ratio <= 1.0))',
      ];
}

class HealthTimeSeries extends Table {
  IntColumn get rowId => integer().autoIncrement()();
  TextColumn get evidenceId => text().unique()();
  TextColumn get seriesId => text().references(HealthSeries, #id)();
  TextColumn get conceptType => text()();
  DateTimeColumn get timestampUtc => dateTime()();
  IntColumn get timezoneOffsetSeconds => integer().nullable()();
  TextColumn get localDate => text()();
  RealColumn get numericValue => real()();
  TextColumn get canonicalUnit => text()();
  IntColumn get sequenceNumber => integer().nullable()();
  IntColumn get measurementStatus => intEnum<MeasurementStatus>()();
  IntColumn get recordingMethod => intEnum<RecordingMethod>()();
  IntColumn get qualityLabel => intEnum<QualityLabel>()();
  IntColumn get sensitivity => intEnum<SensitivityClass>()();
  TextColumn get validationFlagsJson => text().nullable()();
  IntColumn get normalizationSchemaVersion => integer()();
  TextColumn get normalizerVersion => text()();
  DateTimeColumn get ingestedAtUtc => dateTime()();
}

class HealthContextEvents extends Table {
  TextColumn get id => text()();
  TextColumn get eventType => text()();
  DateTimeColumn get startTimestampUtc => dateTime()();
  DateTimeColumn get endTimestampUtc => dateTime().nullable()();
  IntColumn get startTimezoneOffsetSeconds => integer().nullable()();
  IntColumn get endTimezoneOffsetSeconds => integer().nullable()();
  TextColumn get localDate => text()();
  IntColumn get intensity => intEnum<ContextIntensity>()();
  TextColumn get note => text().nullable()();
  TextColumn get sourceId => text().references(HealthSources, #id)();
  IntColumn get sensitivity => intEnum<SensitivityClass>()();
  DateTimeColumn get createdAtUtc => dateTime()();
  DateTimeColumn get modifiedAtUtc => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class HealthDataCoverage extends Table {
  TextColumn get id => text()();
  TextColumn get conceptType => text()();
  DateTimeColumn get windowStartUtc => dateTime()();
  DateTimeColumn get windowEndUtc => dateTime()();
  IntColumn get expectedCount => integer()();
  IntColumn get observedCount => integer()();
  IntColumn get validCount => integer()();
  RealColumn get coverageRatio => real()();
  IntColumn get qualityLabel => intEnum<QualityLabel>()();
  IntColumn get calculationVersion => integer()();
  DateTimeColumn get calculatedAtUtc => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
        'CHECK (window_end_utc >= window_start_utc)',
        'CHECK (expected_count >= 0 AND observed_count >= 0 AND valid_count >= 0)',
        'CHECK (coverage_ratio >= 0.0 AND coverage_ratio <= 1.0)',
      ];
}

class HealthIngestionRuns extends Table {
  TextColumn get id => text()();
  TextColumn get sourceId => text().references(HealthSources, #id)();
  DateTimeColumn get startedAtUtc => dateTime()();
  DateTimeColumn get finishedAtUtc => dateTime().nullable()();
  IntColumn get trigger => intEnum<IngestionTrigger>()();
  IntColumn get status => intEnum<IngestionStatus>()();
  IntColumn get recordsSeen => integer().withDefault(const Constant(0))();
  IntColumn get recordsInserted => integer().withDefault(const Constant(0))();
  IntColumn get recordsUpdated => integer().withDefault(const Constant(0))();
  IntColumn get recordsDeleted => integer().withDefault(const Constant(0))();
  IntColumn get recordsIgnored => integer().withDefault(const Constant(0))();
  IntColumn get recordsFailed => integer().withDefault(const Constant(0))();
  IntColumn get normalizationSchemaVersion => integer()();
  TextColumn get normalizerVersion => text()();
  TextColumn get errorSummaryJson => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class HealthIngestionCheckpoints extends Table {
  TextColumn get id => text()();
  TextColumn get sourceId => text().references(HealthSources, #id)();
  TextColumn get recordType => text()();
  TextColumn get changeToken => text().nullable()();
  DateTimeColumn get windowStartUtc => dateTime().nullable()();
  DateTimeColumn get windowEndUtc => dateTime().nullable()();
  DateTimeColumn get lastAttemptAtUtc => dateTime().nullable()();
  DateTimeColumn get lastSuccessAtUtc => dateTime().nullable()();
  IntColumn get status => intEnum<IngestionStatus>()();
  TextColumn get errorJson => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
        {sourceId, recordType},
      ];
}

class HealthTombstones extends Table {
  TextColumn get id => text()();
  TextColumn get sourceId => text().references(HealthSources, #id)();
  TextColumn get sourceAppId => text().nullable()();
  TextColumn get externalId => text()();
  TextColumn get conceptType => text()();
  DateTimeColumn get deletedAtSourceUtc => dateTime().nullable()();
  DateTimeColumn get observedDeletedAtUtc => dateTime()();
  TextColumn get reason => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class HealthPermissions extends Table {
  TextColumn get id => text()();
  TextColumn get sourceId => text().references(HealthSources, #id)();
  TextColumn get dataType => text()();
  TextColumn get accessMode => text()();
  TextColumn get permissionStatus => text()();
  DateTimeColumn get requestedAtUtc => dateTime().nullable()();
  DateTimeColumn get grantedAtUtc => dateTime().nullable()();
  DateTimeColumn get revokedAtUtc => dateTime().nullable()();
  DateTimeColumn get lastVerifiedAtUtc => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
        {sourceId, dataType, accessMode},
      ];
}
