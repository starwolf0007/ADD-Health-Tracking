import '../../data/health_tables.dart';

/// Enforces the Phase-1 Health Intelligence repository boundary.
///
/// Medical-tier evidence belongs in the future encrypted medical vault and
/// must never reach the general health evidence tables.
abstract final class HealthWriteGuard {
  static void requirePhase1Sensitivity(SensitivityClass sensitivity) {
    if (sensitivity == SensitivityClass.medical) {
      throw const MedicalTierWriteRejected();
    }
  }
}

final class MedicalTierWriteRejected implements Exception {
  const MedicalTierWriteRejected();

  @override
  String toString() =>
      'Medical-tier health evidence must be written to the encrypted medical vault.';
}
