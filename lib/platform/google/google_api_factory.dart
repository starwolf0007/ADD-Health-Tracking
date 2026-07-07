// lib/platform/google/google_api_factory.dart
//
// Creates and caches authenticated http.Client objects (the per-service
// client-creation seam) — the only place an access token is turned into an
// Authorization header. NO concrete product clients (TasksApi, CalendarApi,
// …) are constructed here this sprint — future service integrations
// receive the raw authenticated client and build their own googleapis
// wrapper behind the GoogleServiceManager registration seam.

import 'package:http/http.dart' as http;

import '../../domain/google_service.dart';

abstract class GoogleApiFactory {
  /// Authenticated client for [service], or null when signed out or the
  /// required scopes are not granted. Cached until invalidate(). The client
  /// injects "Authorization: Bearer <token>" per request by asking
  /// GoogleAuthRepository.currentAccessToken() at call time, so a token
  /// refresh transparently propagates without cache invalidation. Never
  /// throws for "not signed in".
  Future<http.Client?> clientFor(
    GoogleServiceId service, {
    required List<String> requiredScopes,
  });

  /// Drop all cached clients (and close them). Called by the manager on
  /// sign-out and scope revocation.
  void invalidate();

  /// Wires the 401 feedback callback. Called once by GoogleServiceManager
  /// right after construction (composition root — see providers.dart);
  /// deliberately a post-construction setter rather than a constructor
  /// argument, since the manager itself depends on this factory (a
  /// constructor-time callback would create a circular Riverpod provider
  /// dependency).
  void wireAuthFailureCallback(void Function() onAuthFailure);
}
