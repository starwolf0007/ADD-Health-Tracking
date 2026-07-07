// lib/platform/google/google_permission_manager.dart
//
// Requests OAuth scopes incrementally and caches which scopes are granted.
// The cache is hydrated from GoogleAccounts.grantedScopes at initialize()
// (via GoogleServiceManager) and kept in memory. This component is a pure
// request+cache component and has NO dependency on GoogleAccountRepository
// and never writes to Drift itself — GoogleServiceManager is the single
// writer of grantedScopes, persisting via GoogleAccountRepository.touch()
// using the result this component returns. (google_sign_in v6.2.1 also
// exposes no "list granted scopes" getter — the cache is necessarily just
// "scopes we requested and got true for", seeded with [email, profile] at
// sign-in; externally revoked scopes are only detected via a future API
// 403, not proactively.)
//
// Impl (GooglePermissionManagerImpl, same directory) binds the google_sign_in
// plugin — the abstract class itself has no plugin import.

abstract class GooglePermissionManager {
  /// Hydrate the granted-scope cache for the primary account. No-op when
  /// signed out (cache stays empty).
  Future<void> hydrate(List<String> grantedScopes);

  /// True iff every scope in [scopes] is in the granted cache. Always false
  /// when signed out. Pure cache read — no network.
  bool hasScopes(List<String> scopes);

  /// Ensure [scopes] are granted, prompting the user via incremental auth
  /// (google_sign_in requestScopes) only for the missing ones. Returns the
  /// resulting ScopeGrantResult; never throws for user denial. Signed out →
  /// returns ScopeGrantResult.notSignedIn without any UI.
  Future<ScopeGrantResult> ensureScopes(List<String> scopes);

  /// Snapshot of currently granted scopes (empty when signed out).
  List<String> get grantedScopes;

  /// Drop the cache (sign-out / account switch).
  void clear();
}

enum ScopeGrantOutcome { granted, denied, notSignedIn, failed }

class ScopeGrantResult {
  final ScopeGrantOutcome outcome;
  final List<String> grantedScopes; // post-request granted set

  const ScopeGrantResult(this.outcome, this.grantedScopes);

  bool get isGranted => outcome == ScopeGrantOutcome.granted;
}
