import 'package:flutter_test/flutter_test.dart';
import 'package:neuroflow/data/health_tables.dart';
import 'package:neuroflow/health/data/health_write_guard.dart';

void main() {
  group('HealthWriteGuard', () {
    test('allows routine and sensitive evidence', () {
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

    test('rejects medical-tier evidence from Phase 1 repositories', () {
      expect(
        () => HealthWriteGuard.requirePhase1Sensitivity(
          SensitivityClass.medical,
        ),
        throwsA(isA<MedicalTierWriteRejected>()),
      );
    });
  });
}
