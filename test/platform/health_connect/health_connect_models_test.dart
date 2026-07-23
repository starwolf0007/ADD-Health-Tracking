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
}
