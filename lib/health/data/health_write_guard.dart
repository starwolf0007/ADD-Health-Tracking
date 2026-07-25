import 'package:neuroflow/domain/health/health_enums.dart';
import 'package:neuroflow/domain/health/health_transaction.dart';

/// Enforces the Phase-1 Health Intelligence repository boundary.
///
/// Medical-tier evidence belongs in the future encrypted medical vault and
/// must never reach the general health evidence tables.
///
/// [requirePhase1Transaction] is the canonical repository-boundary check.
/// [requirePhase1Sensitivity] remains available for adapters and draft
/// factories that need to reject one value before a transaction is assembled.
abstract final class HealthWriteGuard {
  static void requirePhase1Transaction(HealthTransaction transaction) {
    if (transaction.containsMedicalTierData) {
      throw MedicalTierWriteRejected(
        safeIdentifier: transaction.transactionId,
      );
    }
  }

  static void requirePhase1Sensitivity(SensitivityClass sensitivity) {
    if (sensitivity == SensitivityClass.medical) {
      throw const MedicalTierWriteRejected();
    }
  }
}

final class MedicalTierWriteRejected implements Exception {
  final String? safeIdentifier;

  const MedicalTierWriteRejected({this.safeIdentifier});

  @override
  String toString() => safeIdentifier == null
      ? 'MedicalTierWriteRejected(reasonCode: medical_tier_not_allowed)'
      : 'MedicalTierWriteRejected(reasonCode: medical_tier_not_allowed, '
          'safeIdentifier: $safeIdentifier)';
}
