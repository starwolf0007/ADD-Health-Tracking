import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';
import 'package:neuroflow/domain/health/health_enums.dart';

/// Creates a deterministic internal identifier without exposing an upstream
/// external identifier in the primary key.
///
/// The encoded identity is versioned and unambiguous. A null sourceAppId is
/// intentionally different from an empty sourceAppId.
String generateHealthEvidenceId({
  required String sourceId,
  required String? sourceAppId,
  required String recordType,
  required String externalId,
}) {
  _requireNonEmpty(sourceId, 'sourceId');
  _requireNonEmpty(recordType, 'recordType');
  _requireNonEmpty(externalId, 'externalId');

  final canonicalIdentity = jsonEncode(<String, Object?>{
    'version': 1,
    'sourceId': sourceId,
    'sourceAppId': sourceAppId,
    'recordType': recordType,
    'externalId': externalId,
  });
  return sha256.convert(utf8.encode(canonicalIdentity)).toString();
}

/// Construction-time failure for a malformed adapter output record.
///
/// This exception deliberately carries no raw values, external identifiers,
/// notes, payloads, or measurements so it is safe to count and log.
class InvalidHealthDraft implements Exception {
  final String reasonCode;
  final String? field;
  final String? safeIdentifier;

  const InvalidHealthDraft({
    required this.reasonCode,
    this.field,
    this.safeIdentifier,
  });

  @override
  String toString() {
    final details = <String>[
      if (field != null) 'field=$field',
      if (safeIdentifier != null) 'id=$safeIdentifier',
    ];
    return 'InvalidHealthDraft($reasonCode${details.isEmpty ? '' : ', ${details.join(', ')}'})';
  }
}

/// Repository-boundary rejection requiring database or cross-row context.
class InvalidHealthTransaction implements Exception {
  final String transactionId;
  final String reasonCode;
  final String? field;
  final String? safeIdentifier;

  const InvalidHealthTransaction({
    required this.transactionId,
    required this.reasonCode,
    this.field,
    this.safeIdentifier,
  });

  @override
  String toString() {
    final details = <String>[
      'transaction=$transactionId',
      if (field != null) 'field=$field',
      if (safeIdentifier != null) 'id=$safeIdentifier',
    ];
    return 'InvalidHealthTransaction($reasonCode, ${details.join(', ')})';
  }
}

void _requireNonEmpty(String value, String field, {String? safeIdentifier}) {
  if (value.trim().isEmpty) {
    throw InvalidHealthDraft(
      reasonCode: 'empty_$field',
      field: field,
      safeIdentifier: safeIdentifier,
    );
  }
}

void _requireFinite(num? value, String field, {String? safeIdentifier}) {
  if (value != null && (value.isNaN || value.isInfinite)) {
    throw InvalidHealthDraft(
      reasonCode: 'non_finite_$field',
      field: field,
      safeIdentifier: safeIdentifier,
    );
  }
}

void _requireValidRatio(double? value, {String? safeIdentifier}) {
  _requireFinite(value, 'completenessRatio', safeIdentifier: safeIdentifier);
  if (value != null && (value < 0 || value > 1)) {
    throw InvalidHealthDraft(
      reasonCode: 'completeness_ratio_out_of_bounds',
      field: 'completenessRatio',
      safeIdentifier: safeIdentifier,
    );
  }
}

void _requireOrderedRange(
  DateTime start,
  DateTime end,
  String reasonCode, {
  String? safeIdentifier,
}) {
  if (end.isBefore(start)) {
    throw InvalidHealthDraft(
      reasonCode: reasonCode,
      safeIdentifier: safeIdentifier,
    );
  }
}

void _requireNoSelfSupersession(
  String id,
  String? supersedesId, {
  String? safeIdentifier,
}) {
  if (supersedesId == id) {
    throw InvalidHealthDraft(
      reasonCode: 'self_supersession_not_allowed',
      field: 'supersedesId',
      safeIdentifier: safeIdentifier,
    );
  }
}

mixin EvidenceQuality {
  MeasurementStatus get measurementStatus;
  RecordingMethod get recordingMethod;
  QualityLabel get qualityLabel;
  SensitivityClass get sensitivity;
  double? get completenessRatio;
}

@immutable
class HealthSourceRecordDraft {
  final String id;
  final String sourceId;
  final String? sourceAppId;
  final String? deviceId;
  final String? externalId;
  final String sourceRecordType;
  final DateTime startedAtUtc;
  final DateTime? endedAtUtc;
  final int? startOffsetSeconds;
  final int? endOffsetSeconds;
  final String localDate;
  final DateTime? sourceModifiedAtUtc;
  final String? rawPayloadJson;
  final String? rawPayloadHash;
  final SensitivityClass sensitivity;
  final String? consentScope;
  final int normalizationSchemaVersion;
  final String normalizerVersion;
  final String? supersedesSourceRecordId;

  HealthSourceRecordDraft({
    required this.id,
    required this.sourceId,
    required this.sourceRecordType,
    required this.startedAtUtc,
    required this.localDate,
    required this.sensitivity,
    required this.normalizationSchemaVersion,
    required this.normalizerVersion,
    this.sourceAppId,
    this.deviceId,
    this.externalId,
    this.endedAtUtc,
    this.startOffsetSeconds,
    this.endOffsetSeconds,
    this.sourceModifiedAtUtc,
    this.rawPayloadJson,
    this.rawPayloadHash,
    this.consentScope,
    this.supersedesSourceRecordId,
  }) {
    _requireNonEmpty(id, 'source_record_id', safeIdentifier: id);
    _requireNonEmpty(sourceId, 'source_id', safeIdentifier: id);
    _requireNonEmpty(sourceRecordType, 'source_record_type', safeIdentifier: id);
    _requireNonEmpty(localDate, 'local_date', safeIdentifier: id);
    _requireNonEmpty(normalizerVersion, 'normalizer_version', safeIdentifier: id);
    if (normalizationSchemaVersion < 1) {
      throw InvalidHealthDraft(
        reasonCode: 'invalid_normalization_schema_version',
        field: 'normalizationSchemaVersion',
        safeIdentifier: id,
      );
    }
    if (endedAtUtc != null) {
      _requireOrderedRange(
        startedAtUtc,
        endedAtUtc!,
        'invalid_source_record_range',
        safeIdentifier: id,
      );
    }
    _requireNoSelfSupersession(
      id,
      supersedesSourceRecordId,
      safeIdentifier: id,
    );
  }
}

@immutable
class HealthEventDraft with EvidenceQuality {
  final String evidenceId;
  final String? sourceRecordId;
  final String conceptType;
  final DateTime eventTimestampUtc;
  final int? timezoneOffsetSeconds;
  final String localDate;
  final double? numericValue;
  final String? textValue;
  final bool? booleanValue;
  final String? canonicalUnit;
  final String? normalizedPayloadJson;
  @override
  final MeasurementStatus measurementStatus;
  @override
  final RecordingMethod recordingMethod;
  @override
  final QualityLabel qualityLabel;
  @override
  final SensitivityClass sensitivity;
  @override
  final double? completenessRatio;
  final String? validationFlagsJson;
  final String? normalizationWarningsJson;
  final int normalizationSchemaVersion;
  final String normalizerVersion;
  final String? supersedesEvidenceId;
  final RetentionPolicy retentionPolicy;
  final bool aiAccessAllowed;

  HealthEventDraft({
    required this.evidenceId,
    required this.conceptType,
    required this.eventTimestampUtc,
    required this.localDate,
    required this.measurementStatus,
    required this.recordingMethod,
    required this.qualityLabel,
    required this.sensitivity,
    required this.normalizationSchemaVersion,
    required this.normalizerVersion,
    this.sourceRecordId,
    this.timezoneOffsetSeconds,
    this.numericValue,
    this.textValue,
    this.booleanValue,
    this.canonicalUnit,
    this.normalizedPayloadJson,
    this.completenessRatio,
    this.validationFlagsJson,
    this.normalizationWarningsJson,
    this.supersedesEvidenceId,
    this.retentionPolicy = RetentionPolicy.standard,
    this.aiAccessAllowed = false,
  }) {
    _requireNonEmpty(evidenceId, 'event_id', safeIdentifier: evidenceId);
    _requireNonEmpty(conceptType, 'concept_type', safeIdentifier: evidenceId);
    _requireNonEmpty(localDate, 'local_date', safeIdentifier: evidenceId);
    _requireNonEmpty(normalizerVersion, 'normalizer_version', safeIdentifier: evidenceId);
    _requireFinite(numericValue, 'numericValue', safeIdentifier: evidenceId);
    _requireValidRatio(completenessRatio, safeIdentifier: evidenceId);
    if (normalizationSchemaVersion < 1) {
      throw InvalidHealthDraft(
        reasonCode: 'invalid_normalization_schema_version',
        field: 'normalizationSchemaVersion',
        safeIdentifier: evidenceId,
      );
    }
    _requireNoSelfSupersession(
      evidenceId,
      supersedesEvidenceId,
      safeIdentifier: evidenceId,
    );
  }
}

@immutable
class HealthSpanDraft with EvidenceQuality {
  final String evidenceId;
  final String? sourceRecordId;
  final String conceptType;
  final DateTime startTimestampUtc;
  final DateTime endTimestampUtc;
  final int? startTimezoneOffsetSeconds;
  final int? endTimezoneOffsetSeconds;
  final String localDate;
  final double? summaryValue;
  final String? canonicalUnit;
  final String? summaryValuesJson;
  final String? parentSpanEvidenceId;
  @override
  final MeasurementStatus measurementStatus;
  @override
  final RecordingMethod recordingMethod;
  @override
  final QualityLabel qualityLabel;
  @override
  final SensitivityClass sensitivity;
  @override
  final double? completenessRatio;
  final String? validationFlagsJson;
  final String? normalizationWarningsJson;
  final int normalizationSchemaVersion;
  final String normalizerVersion;
  final String? supersedesEvidenceId;
  final RetentionPolicy retentionPolicy;
  final bool aiAccessAllowed;

  HealthSpanDraft({
    required this.evidenceId,
    required this.conceptType,
    required this.startTimestampUtc,
    required this.endTimestampUtc,
    required this.localDate,
    required this.measurementStatus,
    required this.recordingMethod,
    required this.qualityLabel,
    required this.sensitivity,
    required this.normalizationSchemaVersion,
    required this.normalizerVersion,
    this.sourceRecordId,
    this.startTimezoneOffsetSeconds,
    this.endTimezoneOffsetSeconds,
    this.summaryValue,
    this.canonicalUnit,
    this.summaryValuesJson,
    this.parentSpanEvidenceId,
    this.completenessRatio,
    this.validationFlagsJson,
    this.normalizationWarningsJson,
    this.supersedesEvidenceId,
    this.retentionPolicy = RetentionPolicy.standard,
    this.aiAccessAllowed = false,
  }) {
    _requireNonEmpty(evidenceId, 'span_id', safeIdentifier: evidenceId);
    _requireNonEmpty(conceptType, 'concept_type', safeIdentifier: evidenceId);
    _requireNonEmpty(localDate, 'local_date', safeIdentifier: evidenceId);
    _requireNonEmpty(normalizerVersion, 'normalizer_version', safeIdentifier: evidenceId);
    _requireOrderedRange(
      startTimestampUtc,
      endTimestampUtc,
      'invalid_span_range',
      safeIdentifier: evidenceId,
    );
    _requireFinite(summaryValue, 'summaryValue', safeIdentifier: evidenceId);
    _requireValidRatio(completenessRatio, safeIdentifier: evidenceId);
    if (normalizationSchemaVersion < 1) {
      throw InvalidHealthDraft(
        reasonCode: 'invalid_normalization_schema_version',
        field: 'normalizationSchemaVersion',
        safeIdentifier: evidenceId,
      );
    }
    _requireNoSelfSupersession(
      evidenceId,
      supersedesEvidenceId,
      safeIdentifier: evidenceId,
    );
  }

  Duration get duration => endTimestampUtc.difference(startTimestampUtc);
}

@immutable
class HealthTimeSeriesSampleDraft {
  final String evidenceId;
  final String conceptType;
  final DateTime timestampUtc;
  final int? timezoneOffsetSeconds;
  final String localDate;
  final double numericValue;
  final String canonicalUnit;
  final int? sequenceNumber;
  final MeasurementStatus measurementStatus;
  final RecordingMethod recordingMethod;
  final QualityLabel qualityLabel;
  final SensitivityClass sensitivity;
  final String? validationFlagsJson;
  final int normalizationSchemaVersion;
  final String normalizerVersion;

  HealthTimeSeriesSampleDraft({
    required this.evidenceId,
    required this.conceptType,
    required this.timestampUtc,
    required this.localDate,
    required this.numericValue,
    required this.canonicalUnit,
    required this.measurementStatus,
    required this.recordingMethod,
    required this.qualityLabel,
    required this.sensitivity,
    required this.normalizationSchemaVersion,
    required this.normalizerVersion,
    this.timezoneOffsetSeconds,
    this.sequenceNumber,
    this.validationFlagsJson,
  }) {
    _requireNonEmpty(evidenceId, 'sample_id', safeIdentifier: evidenceId);
    _requireNonEmpty(conceptType, 'concept_type', safeIdentifier: evidenceId);
    _requireNonEmpty(localDate, 'local_date', safeIdentifier: evidenceId);
    _requireNonEmpty(canonicalUnit, 'canonical_unit', safeIdentifier: evidenceId);
    _requireNonEmpty(normalizerVersion, 'normalizer_version', safeIdentifier: evidenceId);
    _requireFinite(numericValue, 'numericValue', safeIdentifier: evidenceId);
    if (sequenceNumber != null && sequenceNumber! < 0) {
      throw InvalidHealthDraft(
        reasonCode: 'negative_sequence_number',
        field: 'sequenceNumber',
        safeIdentifier: evidenceId,
      );
    }
    if (normalizationSchemaVersion < 1) {
      throw InvalidHealthDraft(
        reasonCode: 'invalid_normalization_schema_version',
        field: 'normalizationSchemaVersion',
        safeIdentifier: evidenceId,
      );
    }
  }
}

@immutable
class HealthSeriesDraft with EvidenceQuality {
  final String id;
  final String? sourceRecordId;
  final String conceptType;
  final DateTime startTimestampUtc;
  final DateTime endTimestampUtc;
  final int? startTimezoneOffsetSeconds;
  final int? endTimezoneOffsetSeconds;
  final String localDate;
  final int? expectedSampleCount;
  @override
  final double? completenessRatio;
  @override
  final MeasurementStatus measurementStatus;
  @override
  final RecordingMethod recordingMethod;
  @override
  final QualityLabel qualityLabel;
  @override
  final SensitivityClass sensitivity;
  final int normalizationSchemaVersion;
  final String normalizerVersion;
  final String? supersedesSeriesId;
  final RetentionPolicy retentionPolicy;
  final List<HealthTimeSeriesSampleDraft> samples;

  HealthSeriesDraft({
    required this.id,
    required this.conceptType,
    required this.startTimestampUtc,
    required this.endTimestampUtc,
    required this.localDate,
    required this.measurementStatus,
    required this.recordingMethod,
    required this.qualityLabel,
    required this.sensitivity,
    required this.normalizationSchemaVersion,
    required this.normalizerVersion,
    required Iterable<HealthTimeSeriesSampleDraft> samples,
    this.sourceRecordId,
    this.startTimezoneOffsetSeconds,
    this.endTimezoneOffsetSeconds,
    this.expectedSampleCount,
    this.completenessRatio,
    this.supersedesSeriesId,
    this.retentionPolicy = RetentionPolicy.standard,
  }) : samples = List<HealthTimeSeriesSampleDraft>.unmodifiable(samples) {
    _requireNonEmpty(id, 'series_id', safeIdentifier: id);
    _requireNonEmpty(conceptType, 'concept_type', safeIdentifier: id);
    _requireNonEmpty(localDate, 'local_date', safeIdentifier: id);
    _requireNonEmpty(normalizerVersion, 'normalizer_version', safeIdentifier: id);
    _requireOrderedRange(
      startTimestampUtc,
      endTimestampUtc,
      'invalid_series_range',
      safeIdentifier: id,
    );
    _requireValidRatio(completenessRatio, safeIdentifier: id);
    _requireNoSelfSupersession(id, supersedesSeriesId, safeIdentifier: id);
    if (normalizationSchemaVersion < 1) {
      throw InvalidHealthDraft(
        reasonCode: 'invalid_normalization_schema_version',
        field: 'normalizationSchemaVersion',
        safeIdentifier: id,
      );
    }
    if (this.samples.isEmpty) {
      throw InvalidHealthDraft(
        reasonCode: 'series_requires_samples',
        field: 'samples',
        safeIdentifier: id,
      );
    }
    if (expectedSampleCount != null && expectedSampleCount! < 0) {
      throw InvalidHealthDraft(
        reasonCode: 'negative_expected_sample_count',
        field: 'expectedSampleCount',
        safeIdentifier: id,
      );
    }
    if (expectedSampleCount != null && expectedSampleCount! < this.samples.length) {
      throw InvalidHealthDraft(
        reasonCode: 'expected_sample_count_below_observed',
        field: 'expectedSampleCount',
        safeIdentifier: id,
      );
    }

    final evidenceIds = <String>{};
    final sequenceNumbers = <int>{};
    DateTime? previousTimestamp;
    for (final sample in this.samples) {
      if (!evidenceIds.add(sample.evidenceId)) {
        throw InvalidHealthDraft(
          reasonCode: 'duplicate_sample_id',
          field: 'samples',
          safeIdentifier: id,
        );
      }
      final sequenceNumber = sample.sequenceNumber;
      if (sequenceNumber != null && !sequenceNumbers.add(sequenceNumber)) {
        throw InvalidHealthDraft(
          reasonCode: 'duplicate_sequence_number',
          field: 'samples',
          safeIdentifier: id,
        );
      }
      if (sample.timestampUtc.isBefore(startTimestampUtc) ||
          sample.timestampUtc.isAfter(endTimestampUtc)) {
        throw InvalidHealthDraft(
          reasonCode: 'sample_timestamp_out_of_bounds',
          field: 'samples',
          safeIdentifier: id,
        );
      }
      if (previousTimestamp != null && sample.timestampUtc.isBefore(previousTimestamp)) {
        throw InvalidHealthDraft(
          reasonCode: 'samples_not_chronologically_ordered',
          field: 'samples',
          safeIdentifier: id,
        );
      }
      if (sample.conceptType != conceptType) {
        throw InvalidHealthDraft(
          reasonCode: 'sample_concept_mismatch',
          field: 'samples',
          safeIdentifier: id,
        );
      }
      if (sample.sensitivity != sensitivity) {
        throw InvalidHealthDraft(
          reasonCode: 'sample_sensitivity_mismatch',
          field: 'samples',
          safeIdentifier: id,
        );
      }
      if (sample.recordingMethod != recordingMethod) {
        throw InvalidHealthDraft(
          reasonCode: 'sample_recording_method_mismatch',
          field: 'samples',
          safeIdentifier: id,
        );
      }
      previousTimestamp = sample.timestampUtc;
    }
  }

  int get sampleCount => samples.length;
}

@immutable
class HealthContextEventDraft {
  final String id;
  final String eventType;
  final DateTime startTimestampUtc;
  final DateTime? endTimestampUtc;
  final int? startTimezoneOffsetSeconds;
  final int? endTimezoneOffsetSeconds;
  final String localDate;
  final ContextIntensity intensity;
  final String? note;
  final String sourceId;
  final SensitivityClass sensitivity;

  HealthContextEventDraft({
    required this.id,
    required this.eventType,
    required this.startTimestampUtc,
    required this.localDate,
    required this.intensity,
    required this.sourceId,
    required this.sensitivity,
    this.endTimestampUtc,
    this.startTimezoneOffsetSeconds,
    this.endTimezoneOffsetSeconds,
    this.note,
  }) {
    _requireNonEmpty(id, 'context_event_id', safeIdentifier: id);
    _requireNonEmpty(eventType, 'event_type', safeIdentifier: id);
    _requireNonEmpty(localDate, 'local_date', safeIdentifier: id);
    _requireNonEmpty(sourceId, 'source_id', safeIdentifier: id);
    if (endTimestampUtc != null) {
      _requireOrderedRange(
        startTimestampUtc,
        endTimestampUtc!,
        'invalid_context_event_range',
        safeIdentifier: id,
      );
    }
  }
}

@immutable
class HealthTombstoneDraft {
  final String id;
  final String sourceId;
  final String? sourceAppId;
  final String externalId;
  final String conceptType;
  final DateTime? deletedAtSourceUtc;
  final DateTime observedDeletedAtUtc;
  final String? reasonCode;

  HealthTombstoneDraft({
    required this.id,
    required this.sourceId,
    required this.externalId,
    required this.conceptType,
    required this.observedDeletedAtUtc,
    this.sourceAppId,
    this.deletedAtSourceUtc,
    this.reasonCode,
  }) {
    _requireNonEmpty(id, 'tombstone_id', safeIdentifier: id);
    _requireNonEmpty(sourceId, 'source_id', safeIdentifier: id);
    _requireNonEmpty(externalId, 'external_id', safeIdentifier: id);
    _requireNonEmpty(conceptType, 'concept_type', safeIdentifier: id);
  }
}

/// Immutable unit of work corresponding to one source record, or one
/// deletion-only delta when [sourceRecord] is null.
@immutable
class HealthTransaction {
  final String transactionId;
  final String? ingestionRunId;
  final HealthSourceRecordDraft? sourceRecord;
  final List<HealthEventDraft> events;
  final List<HealthSpanDraft> spans;
  final List<HealthSeriesDraft> series;
  final List<HealthContextEventDraft> contextEvents;
  final List<HealthTombstoneDraft> tombstones;
  final DateTime capturedAtUtc;

  HealthTransaction({
    required this.transactionId,
    required this.capturedAtUtc,
    this.ingestionRunId,
    this.sourceRecord,
    Iterable<HealthEventDraft> events = const [],
    Iterable<HealthSpanDraft> spans = const [],
    Iterable<HealthSeriesDraft> series = const [],
    Iterable<HealthContextEventDraft> contextEvents = const [],
    Iterable<HealthTombstoneDraft> tombstones = const [],
  })  : events = List<HealthEventDraft>.unmodifiable(events),
        spans = List<HealthSpanDraft>.unmodifiable(spans),
        series = List<HealthSeriesDraft>.unmodifiable(series),
        contextEvents = List<HealthContextEventDraft>.unmodifiable(contextEvents),
        tombstones = List<HealthTombstoneDraft>.unmodifiable(tombstones) {
    _requireNonEmpty(transactionId, 'transaction_id', safeIdentifier: transactionId);
    if (ingestionRunId != null) {
      _requireNonEmpty(ingestionRunId!, 'ingestion_run_id', safeIdentifier: transactionId);
    }

    final requiresSourceRecord =
        this.events.isNotEmpty || this.spans.isNotEmpty || this.series.isNotEmpty;
    if (requiresSourceRecord && sourceRecord == null) {
      throw InvalidHealthDraft(
        reasonCode: 'missing_source_record_for_normalized_evidence',
        field: 'sourceRecord',
        safeIdentifier: transactionId,
      );
    }

    final sourceRecordId = sourceRecord?.id;
    for (final event in this.events) {
      _requireMatchingSourceRecord(event.sourceRecordId, sourceRecordId, 'event');
    }
    for (final span in this.spans) {
      _requireMatchingSourceRecord(span.sourceRecordId, sourceRecordId, 'span');
    }
    for (final oneSeries in this.series) {
      _requireMatchingSourceRecord(oneSeries.sourceRecordId, sourceRecordId, 'series');
    }

    final sourceId = sourceRecord?.sourceId;
    if (sourceId != null) {
      for (final contextEvent in this.contextEvents) {
        if (contextEvent.sourceId != sourceId) {
          throw InvalidHealthDraft(
            reasonCode: 'context_source_mismatch',
            field: 'contextEvents',
            safeIdentifier: transactionId,
          );
        }
      }
      for (final tombstone in this.tombstones) {
        if (tombstone.sourceId != sourceId) {
          throw InvalidHealthDraft(
            reasonCode: 'tombstone_source_mismatch',
            field: 'tombstones',
            safeIdentifier: transactionId,
          );
        }
      }
    }
  }

  void _requireMatchingSourceRecord(
    String? childSourceRecordId,
    String? expectedSourceRecordId,
    String childType,
  ) {
    if (childSourceRecordId != expectedSourceRecordId) {
      throw InvalidHealthDraft(
        reasonCode: '${childType}_source_record_mismatch',
        field: 'sourceRecordId',
        safeIdentifier: transactionId,
      );
    }
  }

  bool get hasNoStateChanges =>
      sourceRecord == null &&
      events.isEmpty &&
      spans.isEmpty &&
      series.isEmpty &&
      contextEvents.isEmpty &&
      tombstones.isEmpty;

  bool get containsMedicalTierData =>
      sourceRecord?.sensitivity == SensitivityClass.medical ||
      events.any((event) => event.sensitivity == SensitivityClass.medical) ||
      spans.any((span) => span.sensitivity == SensitivityClass.medical) ||
      series.any(
        (oneSeries) =>
            oneSeries.sensitivity == SensitivityClass.medical ||
            oneSeries.samples.any(
              (sample) => sample.sensitivity == SensitivityClass.medical,
            ),
      ) ||
      contextEvents.any(
        (contextEvent) => contextEvent.sensitivity == SensitivityClass.medical,
      );
}
