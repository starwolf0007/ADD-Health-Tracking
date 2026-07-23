import 'package:flutter/services.dart';

import 'health_connect_models.dart';

abstract interface class HealthConnectPlatform {
  Future<HealthConnectAvailability> getAvailability();
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
}
