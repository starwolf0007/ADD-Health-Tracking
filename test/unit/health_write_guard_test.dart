import 'package:flutter_test/flutter_test.dart';
import 'package:neuroflow/domain/health/health_enums.dart';
import 'package:neuroflow/domain/health/health_transaction.dart';
import 'package:neuroflow/health/data/health_write_guard.dart';

void main() {
  final capturedAtUtc = DateTime.utc(2026, 7, 23, 6);

  HealthSourceRecordDraft sourceRecord(SensitivityClass sensitivity) =>
      HealthSourceRecordDraft(
        id: 'safe-source-record-id',
        sourceId: 'health-connect',
        sourceRecordType: 'heart_rate',
        startedAtUtc: capturedAtUtc,
        localDate: '2026-07-23',
        sensitivity: sensitivity,
        normalizationSchemaVersion: 1,
        normalizerVersion: 'health_connect_v1',
      );

  group('HealthWriteGuard', () {
    test('allows routine and sensitive values before transaction assembly', () {
      expect(
        () => HealthWriteGuard.requirePhase1Sensitivity(
          SensitivityClass.routine,
        ),
        returnsNormally,
      );
      expect(
        () => HealthWriteGuard.requirePhase1Sensitivity(
          SensitivityClass.sensitive,
        ),
        returnsNormally,
      );
    });

    test('rejects medical-tier values before transaction assembly', () {
      expect(
        () => HealthWriteGuard.requirePhase1Sensitivity(
          SensitivityClass.medical,
        ),
        throwsA(isA<MedicalTierWriteRejected>()),
      );
    });

    test('transaction-level guard is the canonical repository check', () {
      final transaction = HealthTransaction(
        transactionId: 'safe-transaction-id',
        capturedAtUtc: capturedAtUtc,
        sourceRecord: sourceRecord(SensitivityClass.medical),
      );

      expect(
        () => HealthWriteGuard.requirePhase1Transaction(transaction),
        throwsA(
          isA<MedicalTierWriteRejected>().having(
            (error) => error.safeIdentifier,
            'safeIdentifier',
            'safe-transaction-id',
          ),
        ),
      );
    });
  });
}
