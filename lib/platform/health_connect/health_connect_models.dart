enum HealthConnectAvailability {
  available,
  sdkUnavailable,
  providerUpdateRequired,
  unsupported;

  static HealthConnectAvailability fromWireValue(Object? value) {
    return switch (value) {
      'available' => HealthConnectAvailability.available,
      'sdkUnavailable' => HealthConnectAvailability.sdkUnavailable,
      'providerUpdateRequired' =>
        HealthConnectAvailability.providerUpdateRequired,
      'unsupported' => HealthConnectAvailability.unsupported,
      _ => HealthConnectAvailability.unsupported,
    };
  }
}

enum HealthConnectReadPermission {
  steps,
  heartRate,
  restingHeartRate,
  sleep,
  exercise,
  weight;

  static Set<HealthConnectReadPermission> setFromWireValue(Object? value) {
    if (value is! List<Object?>) return const {};

    return value
        .map(_fromWireValue)
        .whereType<HealthConnectReadPermission>()
        .toSet();
  }

  static HealthConnectReadPermission? _fromWireValue(Object? value) {
    return switch (value) {
      'steps' => HealthConnectReadPermission.steps,
      'heartRate' => HealthConnectReadPermission.heartRate,
      'restingHeartRate' => HealthConnectReadPermission.restingHeartRate,
      'sleep' => HealthConnectReadPermission.sleep,
      'exercise' => HealthConnectReadPermission.exercise,
      'weight' => HealthConnectReadPermission.weight,
      _ => null,
    };
  }
}
