// lib/platform/google/google_api_factory_impl.dart
//
// Impl of GoogleApiFactory. _AuthenticatedClient extends http.BaseClient
// and reads the token via GoogleAuthRepository.currentAccessToken() (the
// plugin's live getter — never a stored copy) at send() time, so a token
// refresh transparently propagates without cache invalidation. On a 401 it
// (i) surfaces the response as-is to its caller AND (ii) invokes the
// injected onAuthFailure callback exactly once per failure — wired to
// GoogleServiceManager.notifyAuthFailure() at composition-root time (see
// providers.dart) — which is what actually drives connected → expired in
// the state machine; without this callback `expired` would be unreachable
// in practice. The client does not retry itself.
//
// Cache note: clients are cached per GoogleServiceId only (not per
// (accountId, service)) — this sprint supports a single active (primary)
// account with no switchAccount, so accountId is implicit; invalidate()
// clears everything on sign-out/disconnect regardless.

import 'package:http/http.dart' as http;

import '../../data/google_auth_repository.dart';
import '../../domain/google_service.dart';
import 'google_api_factory.dart';
import 'google_permission_manager.dart';

class GoogleApiFactoryImpl implements GoogleApiFactory {
  final GoogleAuthRepository _auth;
  final GooglePermissionManager _permissions;

  void Function() _onAuthFailure = () {};
  final Map<GoogleServiceId, http.Client> _cache = {};

  GoogleApiFactoryImpl(this._auth, this._permissions);

  @override
  void wireAuthFailureCallback(void Function() onAuthFailure) {
    _onAuthFailure = onAuthFailure;
  }

  @override
  Future<http.Client?> clientFor(
    GoogleServiceId service, {
    required List<String> requiredScopes,
  }) async {
    // Never throws for "not signed in" — null is the contract.
    final token = await _auth.currentAccessToken();
    if (token == null) return null;

    if (requiredScopes.isNotEmpty && !_permissions.hasScopes(requiredScopes)) {
      return null; // scopes not granted — caller should ensureScopes() first
    }

    final cached = _cache[service];
    if (cached != null) return cached;

    // Trampoline closure so wireAuthFailureCallback() can be called either
    // before or after this client is created and still take effect.
    final client = _AuthenticatedClient(_auth, () => _onAuthFailure());
    _cache[service] = client;
    return client;
  }

  @override
  void invalidate() {
    for (final client in _cache.values) {
      client.close();
    }
    _cache.clear();
  }
}

class _AuthenticatedClient extends http.BaseClient {
  final GoogleAuthRepository _auth;
  final void Function() _onAuthFailure;
  final http.Client _inner = http.Client();

  _AuthenticatedClient(this._auth, this._onAuthFailure);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final token = await _auth.currentAccessToken();
    if (token != null) {
      request.headers['Authorization'] = 'Bearer $token';
    }

    final response = await _inner.send(request);
    if (response.statusCode == 401) {
      _onAuthFailure();
    }
    return response;
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}
