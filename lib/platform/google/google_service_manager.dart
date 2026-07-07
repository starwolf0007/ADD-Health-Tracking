// lib/platform/google/google_service_manager.dart
//
// Facade for all Google integration. The ONLY entry point the rest of the
// app (via providers) uses to talk to Google. Owns the connection state
// machine (see GoogleConnectionState) and coordinates the auth repository,
// permission manager, account repository, and API client factory.
//
// Signed-out contract: every method is safe to call with no Google
// account; it returns a disconnected/empty result and never throws for
// "not signed in".
//
// SCOPE NOTE (Google Foundation Sprint, Stages 4-5): the full facade in
// STAGE2_COMPONENT_DESIGN.md §2.1 also takes a ConnectedServicesRepository
// and a SyncEngine dependency, and exposes enableService(). Those two
// components are a separate, parallel Stage 6/7 task and are not built
// here — this class therefore does NOT depend on them and does NOT
// implement enableService() (which is specified to write through
// ConnectedServicesRepository). registerServiceIntegration()/clientFor()
// ARE implemented: the registration seam itself needs no
// ConnectedServicesRepository or SyncEngine, only an in-memory registry.
// See DECISIONS.md for the full rationale.
//
// NEVER log tokens, ID tokens, refresh tokens, or user IDs here. Emails may
// appear in GoogleConnectionState/GoogleAccount data, never in a
// log/print/debugPrint statement.

import 'dart:async';

import 'package:http/http.dart' as http;

import '../../data/google_account_repository.dart';
import '../../data/google_auth_repository.dart';
import '../../domain/google_account.dart';
import '../../domain/google_connection_state.dart';
import '../../domain/google_service.dart';
import 'google_api_factory.dart';
import 'google_permission_manager.dart';

class GoogleServiceManager {
  final GoogleAuthRepository _auth;
  final GoogleAccountRepository _accounts;
  final GooglePermissionManager _permissions;
  final GoogleApiFactory _apiFactory;

  final Map<GoogleServiceId, GoogleServiceIntegration> _registry = {};

  final StreamController<GoogleConnectionState> _controller =
      StreamController<GoogleConnectionState>.broadcast();
  GoogleConnectionState _current = const GoogleConnectionState.disconnected();

  GoogleServiceManager({
    required GoogleAuthRepository auth,
    required GoogleAccountRepository accounts,
    required GooglePermissionManager permissions,
    required GoogleApiFactory apiFactory,
  })  : _auth = auth,
        _accounts = accounts,
        _permissions = permissions,
        _apiFactory = apiFactory;

  /// Broadcast stream of connection state. Emits the current state to new
  /// listeners immediately (seeded/behavior-subject semantics — a plain
  /// `StreamController.broadcast()` does NOT replay, so this wraps it in an
  /// async* generator that yields [_current] first). UI consumes this
  /// through googleConnectionStateProvider.
  Stream<GoogleConnectionState> watchConnectionState() async* {
    yield _current;
    yield* _controller.stream;
  }

  /// Latest known state, synchronous (starts as .disconnected()).
  GoogleConnectionState get currentState => _current;

  /// App-start hook. Attempts silent restore of a previous session:
  /// disconnected → connecting → connected on success, back to disconnected
  /// on "no previous account" (NOT an error), connecting → expired when a
  /// previous session existed (per GoogleAccountRepository) but the plugin
  /// cannot silently restore it (recoverable via connect()), connecting →
  /// error on unexpected plugin/network failure. No-op (stays disconnected,
  /// completes normally) when the user never connected Google. Never shows
  /// UI.
  Future<void> initialize() async {
    final previouslyConnected = await _safeGetPrimary();

    _setState(_current.copyWith(
      status: GoogleConnectionStatus.connecting,
      lastError: null,
    ));

    try {
      final restored = await _auth.silentSignIn();
      if (restored == null) {
        if (previouslyConnected == null) {
          // Never connected — the normal signed-out baseline, not an error.
          _setState(const GoogleConnectionState.disconnected());
        } else {
          // A previous session existed but the plugin could not silently
          // restore it — recoverable via connect().
          _setState(_stateFrom(
            previouslyConnected,
            GoogleConnectionStatus.expired,
          ));
        }
        return;
      }

      final merged = _reconcile(restored, previouslyConnected);
      await _persistAndHydrate(merged);
      _setState(_stateFrom(merged, GoogleConnectionStatus.connected));
    } catch (e) {
      // Unexpected plugin/network failure — distinct from "cannot restore".
      _setState(_current.copyWith(
        status: GoogleConnectionStatus.error,
        lastError: _sanitize(e),
      ));
    }
  }

  /// Interactive sign-in ("Connect Google" button). Drives
  /// disconnected/error → connecting → connected|error. User cancellation
  /// returns a disconnected state with lastError == null (cancel ≠ error).
  /// On success: persists account metadata via GoogleAccountRepository,
  /// caches granted scopes via GooglePermissionManager, marks the account
  /// primary if it is the first one.
  Future<GoogleConnectionState> connect() async {
    final existing = await _safeGetPrimary();

    _setState(_current.copyWith(
      status: GoogleConnectionStatus.connecting,
      lastError: null,
    ));

    try {
      final signedIn = await _auth.signIn();
      if (signedIn == null) {
        // User cancelled — not an error.
        _setState(const GoogleConnectionState.disconnected());
        return _current;
      }

      final merged = _reconcile(signedIn, existing);
      await _persistAndHydrate(merged);
      if (existing == null) {
        // First account this device has ever connected — make it primary.
        await _accounts.setPrimary(merged.id);
      }
      _setState(_stateFrom(merged, GoogleConnectionStatus.connected));
    } catch (e) {
      _setState(_current.copyWith(
        status: GoogleConnectionStatus.error,
        lastError: _sanitize(e),
      ));
    }
    return _current;
  }

  /// Sign out: revokes the session via GoogleAuthRepository (which deletes
  /// tokens from secure storage), invalidates GoogleApiFactory caches,
  /// clears the permission cache, and emits .disconnected(). Account
  /// metadata rows are kept (soft disconnect) so reconnect is one tap;
  /// [forget] additionally deletes the metadata row.
  Future<void> disconnect({bool forget = false}) async {
    final primary = await _safeGetPrimary();

    try {
      await _auth.signOut();
    } catch (_) {
      // Best-effort — proceed to clear local state regardless.
    }

    _apiFactory.invalidate();
    _permissions.clear();

    if (forget && primary != null) {
      try {
        await _accounts.remove(primary.id);
      } catch (_) {
        // Non-fatal — the account row is soft-disconnect state at worst.
      }
    }

    _setState(const GoogleConnectionState.disconnected());
  }

  /// Refresh the access token for the primary account (expired → connecting
  /// → connected, or → error on failure). No-op when disconnected.
  Future<void> refreshSession() async {
    if (_current.status == GoogleConnectionStatus.disconnected) {
      return;
    }

    final before = _current;
    _setState(_current.copyWith(
      status: GoogleConnectionStatus.connecting,
      lastError: null,
    ));

    try {
      final refreshed = await _auth.refreshToken();
      final existing = await _safeGetPrimary();
      final merged = _reconcile(refreshed, existing);
      await _accounts.touch(
        merged.id,
        lastRefreshAt: merged.lastRefreshAt,
        tokenExpiresAtEstimate: merged.tokenExpiresAtEstimate,
      );
      _setState(_stateFrom(merged, GoogleConnectionStatus.connected));
    } on GoogleAuthTokenExpiredException {
      _setState(before.copyWith(status: GoogleConnectionStatus.expired));
    } catch (e) {
      _setState(before.copyWith(
        status: GoogleConnectionStatus.error,
        lastError: _sanitize(e),
      ));
    }
  }

  /// Internal feedback hook: called by GoogleApiFactory's authenticated
  /// client when a request comes back 401. Transitions connected → expired
  /// and attempts one silent refreshSession(); NOT part of the public
  /// surface widgets use. This is the only path that reaches
  /// GoogleConnectionStatus.expired in practice from live API traffic — see
  /// STAGE2_COMPONENT_DESIGN.md §2.7 for why proactive expiry detection is
  /// not attempted.
  void notifyAuthFailure() {
    if (_current.status != GoogleConnectionStatus.connected) return;
    _setState(_current.copyWith(status: GoogleConnectionStatus.expired));
    // Fire-and-forget: this is invoked synchronously from an HTTP client's
    // send(), which must not itself await. Failures are absorbed by
    // refreshSession()'s own error handling.
    unawaited(refreshSession());
  }

  /// Registration seam for future per-service integrations (Tasks,
  /// Calendar, …). A registrant supplies its GoogleServiceId, required
  /// OAuth scopes, and a factory callback that receives an authenticated
  /// http.Client. THIS SPRINT: nothing registers anything. No product
  /// client may bypass this seam.
  void registerServiceIntegration(GoogleServiceIntegration integration) {
    _registry[integration.id] = integration;
  }

  /// Authenticated HTTP client for a registered service, or null when
  /// disconnected / service not registered / scopes not granted. Delegates
  /// to GoogleApiFactory. Never throws for "not signed in".
  Future<http.Client?> clientFor(GoogleServiceId service) async {
    final integration = _registry[service];
    if (integration == null) return null; // nothing registered this sprint
    return _apiFactory.clientFor(service, requiredScopes: integration.requiredScopes);
  }

  /// Close the state stream controller. Wired to ref.onDispose in
  /// providers.dart.
  void dispose() {
    _controller.close();
  }

  // ------------------------------------------------------------------
  // Internal helpers
  // ------------------------------------------------------------------

  Future<GoogleAccount?> _safeGetPrimary() async {
    try {
      return await _accounts.getPrimary();
    } catch (_) {
      return null;
    }
  }

  Future<void> _persistAndHydrate(GoogleAccount account) async {
    await _accounts.upsert(account);
    await _permissions.hydrate(account.grantedScopes);
  }

  /// Merges freshly-returned auth metadata with the previously persisted
  /// row (if any) for the SAME account id, preserving fields the auth layer
  /// doesn't own: `connectedAt` (the true first-connection instant) and
  /// `isPrimary` (GoogleAccountRepository's concern). Returns [fresh]
  /// unmodified when there is no matching persisted row (genuinely new
  /// account).
  GoogleAccount _reconcile(GoogleAccount fresh, GoogleAccount? existing) {
    if (existing == null || existing.id != fresh.id) return fresh;
    return GoogleAccount(
      id: fresh.id,
      email: fresh.email,
      displayName: fresh.displayName,
      photoUrl: fresh.photoUrl,
      grantedScopes:
          fresh.grantedScopes.isNotEmpty ? fresh.grantedScopes : existing.grantedScopes,
      isPrimary: existing.isPrimary,
      connectedAt: existing.connectedAt,
      lastRefreshAt: fresh.lastRefreshAt ?? existing.lastRefreshAt,
      tokenExpiresAtEstimate: fresh.tokenExpiresAtEstimate,
    );
  }

  GoogleConnectionState _stateFrom(
    GoogleAccount account,
    GoogleConnectionStatus status,
  ) {
    return GoogleConnectionState(
      status: status,
      email: account.email,
      displayName: account.displayName,
      grantedScopes: account.grantedScopes,
      lastError: null,
      lastRefreshAt: account.lastRefreshAt,
      connectedAt: account.connectedAt,
    );
  }

  void _setState(GoogleConnectionState next) {
    assert(
      GoogleConnectionState.isLegalTransition(_current.status, next.status),
      'Illegal Google connection transition: ${_current.status} -> ${next.status}',
    );
    _current = next;
    if (!_controller.isClosed) {
      _controller.add(next);
    }
  }

  /// Sanitizes a caught error into a message safe to log/display — never
  /// tokens, emails, or account IDs (hard constraint).
  String _sanitize(Object error) {
    if (error is GoogleAuthException) return error.message;
    return 'unexpected error (${error.runtimeType})';
  }
}

/// Descriptor for a future Google service integration (registration seam).
/// No implementations ship this sprint.
class GoogleServiceIntegration {
  final GoogleServiceId id;
  final List<String> requiredScopes;

  /// Called by a future consumer when a client is available. Product-client
  /// construction happens behind this callback in future sprints — never in
  /// widgets, never in the manager itself.
  final void Function(http.Client client) onClientReady;

  const GoogleServiceIntegration({
    required this.id,
    required this.requiredScopes,
    required this.onClientReady,
  });
}
