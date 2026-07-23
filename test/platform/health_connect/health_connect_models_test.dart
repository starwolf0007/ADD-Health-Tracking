import 'package:flutter_test/flutter_test.dart';
import 'package:neuroflow/platform/health_connect/health_connect_models.dart';

void main() {
  group('HealthConnectAvailability.fromWireValue', () {
    test('maps every supported native value', () {
      expect(
        HealthConnectAvailability.fromWireValue('available'),
        HealthConnectAvailability.available,
      );
      expect(
        HealthConnectAvailability.fromWireValue('sdkUnavailable'),
        HealthConnectAvailability.sdkUnavailable,
      );
      expect(
        HealthConnectAvailability.fromWireValue('providerUpdateRequired'),
        HealthConnectAvailability.providerUpdateRequired,
      );
      expect(
        HealthConnectAvailability.fromWireValue('unsupported'),
        HealthConnectAvailability.unsupported,
      );
    });

    test('fails closed for unknown or malformed values', () {
      expect(
        HealthConnectAvailability.fromWireValue('futureStatus'),
        HealthConnectAvailability.unsupported,
      );
      expect(
        HealthConnectAvailability.fromWireValue(null),
        HealthConnectAvailability.unsupported,
      );
      expect(
        HealthConnectAvailability.fromWireValue(3),
        HealthConnectAvailability.unsupported,
      );
    });
  });

  group('HealthConnectReadPermission.setFromWireValue', () {
    test('maps the complete supported read-only permission set', () {
      expect(
        HealthConnectReadPermission.setFromWireValue(const [
          'steps',
          'heartRate',
          'restingHeartRate',
          'sleep',
          'exercise',
          'weight',
        ]),
        HealthConnectReadPermission.values.toSet(),
      );
    });

    test('ignores unknown entries and duplicates', () {
      expect(
        HealthConnectReadPermission.setFromWireValue(const [
          'steps',
          'futurePermission',
          'steps',
        ]),
        const {HealthConnectReadPermission.steps},
      );
    });

    test('fails closed for malformed payloads', () {
      expect(
        HealthConnectReadPermission.setFromWireValue(null),
        isEmpty,
      );
      expect(
        HealthConnectReadPermission.setFromWireValue('steps'),
        isEmpty,
      );
      expect(
        HealthConnectReadPermission.setFromWireValue(const [1, null]),
        isEmpty,
      );
    });
  });
}
