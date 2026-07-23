import 'health_connect_steps_transport.dart';

abstract final class HealthConnectStepsParser {
  static HealthConnectReadStatus parseStatus(Object? value) => switch (value) {
    'ok' => HealthConnectReadStatus.ok,
    'unavailable' => HealthConnectReadStatus.unavailable,
    'permission_denied' => HealthConnectReadStatus.permissionDenied,
    'failed' => HealthConnectReadStatus.failed,
    _ => HealthConnectReadStatus.failed,
  };

  static HealthConnectStepsEnvelope parseEnvelope(Object? value) {
    if (value is! Map) {
      return const HealthConnectStepsEnvelope(
        status: HealthConnectReadStatus.failed,
        records: [],
      );
    }
    final status = parseStatus(value['status']);
    final rawRecords = value['records'];
    if (rawRecords is! List) {
      return const HealthConnectStepsEnvelope(
        status: HealthConnectReadStatus.failed,
        records: [],
      );
    }
    if (status != HealthConnectReadStatus.ok && rawRecords.isNotEmpty) {
      return const HealthConnectStepsEnvelope(
        status: HealthConnectReadStatus.failed,
        records: [],
      );
    }

    final records = <HealthConnectStepsTransportRecord>[];
    for (final raw in rawRecords) {
      records.add(parseRecord(raw));
    }
    return HealthConnectStepsEnvelope(status: status, records: records);
  }

  static HealthConnectStepsTransportRecord parseRecord(Object? value) {
    if (value is! Map) throw const HealthConnectTransportRejection('record_not_map');
    String requiredString(String key) {
      final raw = value[key];
      if (raw is! String || raw.trim().isEmpty) {
        throw HealthConnectTransportRejection('invalid_$key');
      }
      return raw;
    }

    int requiredInt(String key) {
      final raw = value[key];
      if (raw is! int) throw HealthConnectTransportRejection('invalid_$key');
      return raw;
    }

    int? optionalInt(String key) {
      final raw = value[key];
      if (raw == null) return null;
      if (raw is! int) throw HealthConnectTransportRejection('invalid_$key');
      return raw;
    }

    String? optionalString(String key) {
      final raw = value[key];
      if (raw == null) return null;
      if (raw is! String || raw.trim().isEmpty) {
        throw HealthConnectTransportRejection('invalid_$key');
      }
      return raw;
    }

    if (value['recordType'] != 'steps') {
      throw const HealthConnectTransportRejection('invalid_recordType');
    }
    final count = requiredInt('count');
    final start = requiredInt('startEpochMs');
    final end = requiredInt('endEpochMs');
    if (count < 0) throw const HealthConnectTransportRejection('negative_count');
    if (end < start) throw const HealthConnectTransportRejection('invalid_range');

    return HealthConnectStepsTransportRecord(
      externalId: requiredString('externalId'),
      count: count,
      startEpochMs: start,
      endEpochMs: end,
      startZoneOffsetSeconds: optionalInt('startZoneOffsetSeconds'),
      endZoneOffsetSeconds: optionalInt('endZoneOffsetSeconds'),
      sourceAppId: requiredString('sourceAppId'),
      lastModifiedEpochMs: requiredInt('lastModifiedEpochMs'),
      clientRecordId: optionalString('clientRecordId'),
      clientRecordVersion: optionalInt('clientRecordVersion'),
      recordingMethod: requiredString('recordingMethod'),
    );
  }
}
