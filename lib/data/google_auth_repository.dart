// lib/data/google_auth_repository.dart
//
// Abstract repository interface. Auth operations ONLY — interactive
// sign-in, silent sign-in, sign-out, and access-token refresh — wrapping
// google_sign_in behind a plugin-free interface. Executive/Platform-facade
// code depends only on this; the concrete impl
// (GoogleSignInAuthRepository, lib/platform/google/google_auth_repository_impl.dart)
// is injected via Riverpod (see providers.dart). Mirrors TaskRepository /
// DriftTaskRepository in spirit.
//
// Implementations write tokens straight into FlutterSecureStorage — tokens
// never appear in return values that callers could persist, log, or
// forward, with the single exception of currentAccessToken(), whose
// contract forbids both.

import '../domain/google_account.dart';

abstract class GoogleAuthRepository {
  /// Interactive OAuth sign-in. Returns the signed-in account's METADATA (no
  /// tokens). Returns null when the user cancels the account chooser — on
  /// Android the plugin returns null directly; on iOS (and some Android
  /// paths) it throws PlatformException(code: 'sign_in_canceled' /
  /// 'sign_in_cancelled'), which the impl MUST catch and map to null so
  /// cancel never becomes GoogleConnectionStatus.error. Other
  /// PlatformExceptions (e.g. 'network_error') rethrow as
  /// GoogleAuthException. Throws GoogleAuthException on plugin/network
  /// failure.
  ///
  /// Side effect: writes the ID token to secure storage under a per-account
  /// key (see STAGE2_COMPONENT_DESIGN.md §5). The access token itself is
  /// NEVER persisted — see currentAccessToken() below for why.
  Future<GoogleAccount?> signIn();

  /// Non-interactive session restore (app start). Returns null when there is
  /// no previous session — that is a normal signed-out outcome, not an
  /// error. Never shows UI.
  Future<GoogleAccount?> silentSignIn();

  /// Sign out and disconnect the plugin session, then delete every
  /// google-auth token key for the account (captured before signing out,
  /// since the plugin's currentUser is null immediately after signOut())
  /// from secure storage. Safe to call when already signed out (no-op).
  Future<void> signOut();

  /// Force-refresh via silent sign-in and return updated metadata
  /// (lastRefreshAt + a freshly *derived* tokenExpiresAtEstimate — see
  /// GoogleAccount.tokenExpiresAtEstimate doc; the plugin itself exposes no
  /// expiry). Throws GoogleAuthTokenExpiredException when re-auth is
  /// required — the manager maps that to GoogleConnectionStatus.expired.
  Future<GoogleAccount> refreshToken();

  /// Current access token for IN-MEMORY use by GoogleApiFactory only.
  /// Delegates directly to the plugin's `currentUser.authentication` getter
  /// (fresh, ~hour-lived, silently refreshed by Play services under the
  /// hood) — it NEVER reads a stored copy, because a secure-storage copy
  /// would be stale for any request more than ~1h after sign-in, which is
  /// the common case for the existing 4h background flush cadence. Returns
  /// null when signed out. Callers MUST NOT persist or log it. This is the
  /// only token egress point in the entire design.
  Future<String?> currentAccessToken();
}

/// Auth failure (network, plugin, config). Message must never contain
/// tokens or email addresses.
class GoogleAuthException implements Exception {
  final String message;
  const GoogleAuthException(this.message);

  @override
  String toString() => 'GoogleAuthException: $message';
}

/// Refresh impossible without interactive re-auth.
class GoogleAuthTokenExpiredException extends GoogleAuthException {
  const GoogleAuthTokenExpiredException() : super('re-authentication required');
}
