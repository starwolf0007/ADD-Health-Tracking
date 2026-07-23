enum HealthConnectReadStatus { ok, unavailable, permissionDenied, failed }

final class HealthConnectStepsTransportRecord {
  const HealthConnectStepsTransportRecord({
    required this.externalId,
    required this.count,
    required this.startEpochMs,
    required this.endEpochMs,
    required this.sourceAppId,
    required this.lastModifiedEpochMs,
    required this.recordingMethod,
    this.startZoneOffsetSeconds,
    this.endZoneOffsetSeconds,
    this.clientRecordId,
    this.clientRecordVersion,
  });

  final String externalId;
  final int count;
  final int startEpochMs;
  final int endEpochMs;
  final int? startZoneOffsetSeconds;
  final int? endZoneOffsetSeconds;
  final String sourceAppId;
  final int lastModifiedEpochMs;
  final String? clientRecordId;
  final int? clientRecordVersion;
  final String recordingMethod;
}

final class HealthConnectStepsEnvelope {
  const HealthConnectStepsEnvelope({
    required this.status,
    required this.records,
  });

  final HealthConnectReadStatus status;
  final List<HealthConnectStepsTransportRecord> records;
}

final class HealthConnectTransportRejection implements Exception {
  const HealthConnectTransportRejection(this.reasonCode);

  final String reasonCode;

  @override
  String toString() => 'HealthConnectTransportRejection($reasonCode)';
}
