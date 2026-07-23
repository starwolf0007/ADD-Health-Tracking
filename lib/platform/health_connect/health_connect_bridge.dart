import 'package:flutter/services.dart';

import 'health_connect_models.dart';

abstract interface class HealthConnectPlatform {
  Future<HealthConnectAvailability> getAvailability();

  Future<Set<HealthConnectReadPermission>> getGrantedPermissions();

  Future<Set<HealthConnectReadPermission>> requestPermissions();
}

class MethodChannelHealthConnectPlatform implements HealthConnectPlatform {
  MethodChannelHealthConnectPlatform({
    MethodChannel channel = const MethodChannel(_channelName),
  }) : _channel = channel;

  static const _channelName = 'neuroflow/health_connect';

  final MethodChannel _channel;

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
