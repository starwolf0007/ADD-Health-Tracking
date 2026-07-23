import 'package:flutter_test/flutter_test.dart';
import 'package:neuroflow/domain/health/health_enums.dart';
import 'package:neuroflow/platform/health_connect/health_connect_steps_adapter.dart';
import 'package:neuroflow/platform/health_connect/health_connect_steps_transport.dart';

void main() {
  final capturedAt = DateTime.utc(2026, 7, 23, 12);

  Map<String, Object?> record({
    required String externalId,
    required String sourceAppId,
    int count = 100,
    String recordingMethod = 'automatic',
    int? startOffset = -25200,
    int? endOffset = -25200,
  }) => <String, Object?>{
    'externalId': externalId,
    'recordType': 'steps',
    'count': count,
    'startEpochMs': DateTime.utc(2026, 7, 23, 7).millisecondsSinceEpoch,
    'endEpochMs': DateTime.utc(2026, 7, 23, 8).millisecondsSinceEpoch,
    'startZoneOffsetSeconds': startOffset,
    'endZoneOffsetSeconds': endOffset,
    'sourceAppId': sourceAppId,
    'lastModifiedEpochMs': DateTime.utc(2026, 7, 23, 9).millisecondsSinceEpoch,
    'clientRecordId': null,
    'clientRecordVersion': null,
    'recordingMethod': recordingMethod,
  };

  test('empty successful read differs from failure', () {
    final result = HealthConnectStepsAdapter.fromWire(
      {'status': 'ok', 'records': <Object?>[]},
      capturedAtUtc: capturedAt,
    );
    expect(result.status, HealthConnectReadStatus.ok);
    expect(result.transactions, isEmpty);
  });

  test('overlapping origins remain two independent transactions', () {
    final result = HealthConnectStepsAdapter.fromWire(
      {
        'status': 'ok',
        'records': [
          record(externalId: 'watch-1', sourceAppId: 'watch.app', count: 100),
          record(externalId: 'phone-1', sourceAppId: 'phone.app', count: 120),
        ],
      },
      capturedAtUtc: capturedAt,
    );

    expect(result.transactions, hasLength(2));
    expect(result.transactions[0].spans.single.summaryValue, 100);
    expect(result.transactions[1].spans.single.summaryValue, 120);
    expect(
      result.transactions[0].transactionId,
      isNot(result.transactions[1].transactionId),
    );
  });

  test('same upstream record yields deterministic ids', () {
    final wire = {
      'status': 'ok',
      'records': [record(externalId: 'same', sourceAppId: 'watch.app')],
    };
    final first = HealthConnectStepsAdapter.fromWire(
      wire,
      capturedAtUtc: capturedAt,
    );
    final second = HealthConnectStepsAdapter.fromWire(
      wire,
      capturedAtUtc: capturedAt.add(const Duration(hours: 1)),
    );
    expect(first.transactions.single.transactionId,
        second.transactions.single.transactionId);
    expect(first.transactions.single.spans.single.evidenceId,
        second.transactions.single.spans.single.evidenceId);
  });

  test('valid sibling survives malformed record', () {
    final malformed = record(externalId: 'bad', sourceAppId: 'watch.app')
      ..remove('sourceAppId');
    final result = HealthConnectStepsAdapter.fromWire(
      {
        'status': 'ok',
        'records': [
          malformed,
          record(externalId: 'good', sourceAppId: 'phone.app'),
        ],
      },
      capturedAtUtc: capturedAt,
    );
    expect(result.transactions, hasLength(1));
    expect(result.rejectionReasonCodes, contains('invalid_sourceAppId'));
  });

  test('preserves independently nullable offsets', () {
    final result = HealthConnectStepsAdapter.fromWire(
      {
        'status': 'ok',
        'records': [
          record(
            externalId: 'travel',
            sourceAppId: 'watch.app',
            startOffset: null,
            endOffset: 3600,
          ),
        ],
      },
      capturedAtUtc: capturedAt,
    );
    final span = result.transactions.single.spans.single;
    expect(span.startTimezoneOffsetSeconds, isNull);
    expect(span.endTimezoneOffsetSeconds, 3600);
  });

  test('maps active and automatic as device measured', () {
    for (final method in ['active', 'automatic']) {
      final result = HealthConnectStepsAdapter.fromWire(
        {
          'status': 'ok',
          'records': [
            record(
              externalId: method,
              sourceAppId: 'watch.app',
              recordingMethod: method,
            ),
          ],
        },
        capturedAtUtc: capturedAt,
      );
      expect(
        result.transactions.single.spans.single.recordingMethod,
        RecordingMethod.deviceMeasured,
      );
    }
  });

  test('non-ok status cannot carry records', () {
    final result = HealthConnectStepsAdapter.fromWire(
      {
        'status': 'failed',
        'records': [record(externalId: 'x', sourceAppId: 'watch.app')],
      },
      capturedAtUtc: capturedAt,
    );
    expect(result.status, HealthConnectReadStatus.failed);
    expect(result.transactions, isEmpty);
  });
}
