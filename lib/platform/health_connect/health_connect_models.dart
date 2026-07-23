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
