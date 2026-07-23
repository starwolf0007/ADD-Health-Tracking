import 'package:flutter_test/flutter_test.dart';
import 'package:neuroflow/domain/health/health_enums.dart';
import 'package:neuroflow/domain/health/health_transaction.dart';

void main() {
  final start = DateTime.utc(2026, 7, 23, 6);
  final end = start.add(const Duration(minutes: 1));

  HealthSourceRecordDraft sourceRecord({
    SensitivityClass sensitivity = SensitivityClass.routine,
  }) =>
      HealthSourceRecordDraft(
        id: 'source-record-hash',
        sourceId: 'health-connect',
        sourceRecordType: 'heart_rate',
        startedAtUtc: start,
        endedAtUtc: end,
        localDate: '2026-07-23',
        sensitivity: sensitivity,
        normalizationSchemaVersion: 1,
        normalizerVersion: 'health_connect_v1',
      );

  HealthTimeSeriesSampleDraft sample({
    String id = 'sample-1',
    DateTime? timestamp,
    SensitivityClass sensitivity = SensitivityClass.routine,
  }) =>
      HealthTimeSeriesSampleDraft(
        evidenceId: id,
        conceptType: 'heart_rate',
        timestampUtc: timestamp ?? start,
        localDate: '2026-07-23',
        numericValue: 70,
        canonicalUnit: 'bpm',
        measurementStatus: MeasurementStatus.valid,
        recordingMethod: RecordingMethod.deviceMeasured,
        qualityLabel: QualityLabel.high,
        sensitivity: sensitivity,
        normalizationSchemaVersion: 1,
        normalizerVersion: 'health_connect_v1',
      );

  test('tombstone-only transactions are valid state changes', () {
    final transaction = HealthTransaction(
      transactionId: 'transaction-1',
      capturedAtUtc: start,
      tombstones: [
        HealthTombstoneDraft(
          id: 'tombstone-hash',
          sourceId: 'health-connect',
          externalId: 'upstream-record-id',
          conceptType: 'heart_rate',
          observedDeletedAtUtc: start,
        ),
      ],
    );

    expect(transaction.sourceRecord, isNull);
    expect(transaction.hasNoStateChanges, isFalse);
  });

  test('transaction collections reject mutation', () {
    final transaction = HealthTransaction(
      transactionId: 'transaction-1',
      capturedAtUtc: start,
      sourceRecord: sourceRecord(),
    );

    expect(
      () => transaction.events.add(
        HealthEventDraft(
          evidenceId: 'event-1',
          sourceRecordId: 'source-record-hash',
          conceptType: 'resting_heart_rate',
          eventTimestampUtc: start,
          localDate: '2026-07-23',
          measurementStatus: MeasurementStatus.valid,
          recordingMethod: RecordingMethod.deviceMeasured,
          qualityLabel: QualityLabel.high,
          sensitivity: SensitivityClass.routine,
          normalizationSchemaVersion: 1,
          normalizerVersion: 'health_connect_v1',
        ),
      ),
      throwsUnsupportedError,
    );
  });

  test('series requires samples', () {
    expect(
      () => HealthSeriesDraft(
        id: 'series-1',
        sourceRecordId: 'source-record-hash',
        conceptType: 'heart_rate',
        startTimestampUtc: start,
        endTimestampUtc: end,
        localDate: '2026-07-23',
        measurementStatus: MeasurementStatus.valid,
        recordingMethod: RecordingMethod.deviceMeasured,
        qualityLabel: QualityLabel.high,
        sensitivity: SensitivityClass.routine,
        normalizationSchemaVersion: 1,
        normalizerVersion: 'health_connect_v1',
        samples: const [],
      ),
      throwsA(isA<InvalidHealthDraft>()),
    );
  });

  test('series rejects samples outside its time range', () {
    expect(
      () => HealthSeriesDraft(
        id: 'series-1',
        sourceRecordId: 'source-record-hash',
        conceptType: 'heart_rate',
        startTimestampUtc: start,
        endTimestampUtc: end,
        localDate: '2026-07-23',
        measurementStatus: MeasurementStatus.valid,
        recordingMethod: RecordingMethod.deviceMeasured,
        qualityLabel: QualityLabel.high,
        sensitivity: SensitivityClass.routine,
        normalizationSchemaVersion: 1,
        normalizerVersion: 'health_connect_v1',
        samples: [sample(timestamp: end.add(const Duration(seconds: 1)))],
      ),
      throwsA(isA<InvalidHealthDraft>()),
    );
  });

  test('medical detection traverses nested samples', () {
    final transaction = HealthTransaction(
      transactionId: 'transaction-1',
      capturedAtUtc: start,
      sourceRecord: sourceRecord(sensitivity: SensitivityClass.medical),
    );

    expect(transaction.containsMedicalTierData, isTrue);
  });

  test('deterministic IDs distinguish null and empty source app IDs', () {
    final nullApp = generateHealthEvidenceId(
      sourceId: 'source',
      sourceAppId: null,
      recordType: 'record',
      externalId: 'external',
    );
    final emptyApp = generateHealthEvidenceId(
      sourceId: 'source',
      sourceAppId: '',
      recordType: 'record',
      externalId: 'external',
    );

    expect(nullApp, isNot(emptyApp));
    expect(nullApp, hasLength(64));
  });
}
