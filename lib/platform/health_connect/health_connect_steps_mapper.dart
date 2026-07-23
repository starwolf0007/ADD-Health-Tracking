import 'package:neuroflow/domain/health/health_enums.dart';
import 'package:neuroflow/domain/health/health_transaction.dart';
import 'package:neuroflow/health/data/health_write_guard.dart';

import 'health_connect_steps_transport.dart';

abstract final class HealthConnectStepsMapper {
  static const _sourceId = 'health_connect';
  static const _recordType = 'steps';
  static const _conceptType = 'steps';
  static const _normalizerVersion = 'health-connect-steps-v1';

  static HealthTransaction toTransaction(
    HealthConnectStepsTransportRecord record, {
    required DateTime capturedAtUtc,
  }) {
    final start = DateTime.fromMillisecondsSinceEpoch(
      record.startEpochMs,
      isUtc: true,
    );
    final end = DateTime.fromMillisecondsSinceEpoch(
      record.endEpochMs,
      isUtc: true,
    );
    final localDate = _localDate(start, record.startZoneOffsetSeconds);
    final sourceRecordId = generateHealthEvidenceId(
      sourceId: _sourceId,
      sourceAppId: record.sourceAppId,
      recordType: _recordType,
      externalId: record.externalId,
    );
    final spanId = generateHealthEvidenceId(
      sourceId: _sourceId,
      sourceAppId: record.sourceAppId,
      recordType: '$_recordType.span',
      externalId: record.externalId,
    );
    final recordingMethod = _recordingMethod(record.recordingMethod);

    final transaction = HealthTransaction(
      transactionId: sourceRecordId,
      capturedAtUtc: capturedAtUtc.toUtc(),
      sourceRecord: HealthSourceRecordDraft(
        id: sourceRecordId,
        sourceId: _sourceId,
        sourceAppId: record.sourceAppId,
        externalId: record.externalId,
        sourceRecordType: _recordType,
        startedAtUtc: start,
        endedAtUtc: end,
        startOffsetSeconds: record.startZoneOffsetSeconds,
        endOffsetSeconds: record.endZoneOffsetSeconds,
        localDate: localDate,
        sourceModifiedAtUtc: DateTime.fromMillisecondsSinceEpoch(
          record.lastModifiedEpochMs,
          isUtc: true,
        ),
        sensitivity: SensitivityClass.routine,
        normalizationSchemaVersion: 1,
        normalizerVersion: _normalizerVersion,
      ),
      spans: [
        HealthSpanDraft(
          evidenceId: spanId,
          sourceRecordId: sourceRecordId,
          conceptType: _conceptType,
          startTimestampUtc: start,
          endTimestampUtc: end,
          startTimezoneOffsetSeconds: record.startZoneOffsetSeconds,
          endTimezoneOffsetSeconds: record.endZoneOffsetSeconds,
          localDate: localDate,
          summaryValue: record.count.toDouble(),
          canonicalUnit: 'count',
          measurementStatus: MeasurementStatus.valid,
          recordingMethod: recordingMethod,
          qualityLabel: QualityLabel.unknown,
          sensitivity: SensitivityClass.routine,
          normalizationSchemaVersion: 1,
          normalizerVersion: _normalizerVersion,
        ),
      ],
    );
    HealthWriteGuard.requirePhase1Transaction(transaction);
    return transaction;
  }

  static RecordingMethod _recordingMethod(String wireValue) => switch (wireValue) {
    'automatic' || 'active' => RecordingMethod.deviceMeasured,
    'manual' => RecordingMethod.userEntered,
    'unknown' => RecordingMethod.importedUnknown,
    _ => RecordingMethod.importedUnknown,
  };

  static String _localDate(DateTime startUtc, int? offsetSeconds) {
    final adjusted = offsetSeconds == null
        ? startUtc
        : startUtc.add(Duration(seconds: offsetSeconds));
    final year = adjusted.year.toString().padLeft(4, '0');
    final month = adjusted.month.toString().padLeft(2, '0');
    final day = adjusted.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }
}
