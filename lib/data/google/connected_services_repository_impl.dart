// lib/data/google/connected_services_repository_impl.dart

import 'dart:async';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:neuroflow/domain/google/connected_services_repository.dart';

class ConnectedServicesRepositoryImpl implements ConnectedServicesRepository {
  static const _kPrefix = 'neuroflow_service_enabled_';
  final FlutterSecureStorage _storage;
  final _controller = StreamController<Set<GoogleService>>.broadcast();
  Set<GoogleService> _cache = {};

  ConnectedServicesRepositoryImpl(this._storage) {
    unawaited(_load().onError((error, stackTrace) {
      _controller.addError(
        error ?? StateError('Connected services failed to load'),
        stackTrace,
      );
    }));
  }

  Future<void> _load() async {
    final enabled = <GoogleService>{};
    for (final service in GoogleService.values) {
      final value = await _storage.read(key: '$_kPrefix${service.name}');
      if (value == 'true') {
        enabled.add(service);
      }
    }
    _cache = enabled;
    _controller.add(_cache);
  }

  @override
  Stream<Set<GoogleService>> get enabledServices => _controller.stream;

  @override
  Future<bool> isServiceEnabled(GoogleService service) async {
    final value = await _storage.read(key: '$_kPrefix${service.name}');
    return value == 'true';
  }

  @override
  Future<void> setServiceEnabled(GoogleService service, bool enabled) async {
    await _storage.write(
        key: '$_kPrefix${service.name}', value: enabled.toString());
    if (enabled) {
      _cache.add(service);
    } else {
      _cache.remove(service);
    }
    _controller.add(_cache);
  }
}
