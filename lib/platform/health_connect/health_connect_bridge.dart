import 'package:flutter/services.dart';

import 'health_connect_models.dart';
import 'health_connect_steps_adapter.dart';
import 'health_connect_steps_transport.dart';

abstract interface class HealthConnectPlatform {
  Future<HealthConnectAvailability> getAvailability();

  Future<Set<HealthConnectReadPermission>> getGrantedPermissions();

  Future<Set<HealthConnectReadPermission>> requestPermissions();

  Future<HealthConnectStepsReadResult> readSteps({
    required DateTime startInclusiveUtc,
    required DateTime endExclusiveUtc,
  });
}

class MethodChannelHealthConnectPlatform implements HealthConnectPlatform {
  MethodChannelHealthConnectPlatform({
    MethodChannel channel = const MethodChannel(_channelName),
    DateTime Function()? clock,
  })  : _channel = channel,
        _clock = clock ?? DateTime.now;

  static const _channelName = 'neuroflow/health_connect';

  final MethodChannel _channel;
  final DateTime Function() _clock;

  @override
  Future<HealthConnectAvailability> getAvailability() async {
    try {
      final value = await _channel.invokeMethod<Object?>('getAvailability');
      return HealthConnectAvailability.fromWireValue(value);
    } on PlatformException {
      return HealthConnectAvailability.unsupported;
    } on MissingPluginException {
      return HealthConnectAvailability.unsupported;
    }
  }

  @override
  Future<Set<HealthConnectReadPermission>> getGrantedPermissions() async {
    return _invokePermissionMethod('getGrantedPermissions');
  }

  @override
  Future<Set<HealthConnectReadPermission>> requestPermissions() async {
    return _invokePermissionMethod('requestPermissions');
  }

  @override
  Future<HealthConnectStepsReadResult> readSteps({
    required DateTime startInclusiveUtc,
    required DateTime endExclusiveUtc,
  }) async {
    final start = startInclusiveUtc.toUtc();
    final end = endExclusiveUtc.toUtc();
    if (!end.isAfter(start)) {
      return const HealthConnectStepsReadResult(
        status: HealthConnectReadStatus.failed,
        transactions: [],
        rejectionReasonCodes: [],
      );
    }
    try {
      final value = await _channel.invokeMethod<Object?>('readSteps', {
        'startInclusiveEpochMs': start.millisecondsSinceEpoch,
        'endExclusiveEpochMs': end.millisecondsSinceEpoch,
      });
      return HealthConnectStepsAdapter.fromWire(
        value,
        capturedAtUtc: _clock().toUtc(),
      );
    } on PlatformException {
      return const HealthConnectStepsReadResult(
        status: HealthConnectReadStatus.failed,
        transactions: [],
        rejectionReasonCodes: [],
      );
    } on MissingPluginException {
      return const HealthConnectStepsReadResult(
        status: HealthConnectReadStatus.failed,
        transactions: [],
        rejectionReasonCodes: [],
      );
    }
  }

  Future<Set<HealthConnectReadPermission>> _invokePermissionMethod(
    String method,
  ) async {
    try {
      final value = await _channel.invokeMethod<Object?>(method);
      return HealthConnectReadPermission.setFromWireValue(value);
    } on PlatformException {
      return const {};
    } on MissingPluginException {
      return const {};
    }
  }
}
