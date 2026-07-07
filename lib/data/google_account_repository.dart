// lib/data/google_account_repository.dart
//
// Abstract repository interface. Persistence and (future) switching of
// connected-account METADATA (list accounts, mark primary) in Drift —
// nothing about tokens or the OAuth flow. Drift implementation is injected
// via Riverpod (see providers.dart). Mirrors TaskRepository /
// DriftTaskRepository in spirit.
//
// Hard rule: no method, column, parameter, or return value here ever
// contains a token.

import '../domain/google_account.dart';

abstract class GoogleAccountRepository {
  /// All known accounts, primary first. Emits [] when none — the signed-out
  /// baseline. Streams so Settings UI stays live.
  Stream<List<GoogleAccount>> watchAccounts();

  /// The primary (active-for-sync) account, or null when signed out.
  Future<GoogleAccount?> getPrimary();

  /// Insert-or-update metadata after a successful sign-in or refresh. First
  /// account ever saved becomes primary automatically.
  Future<void> upsert(GoogleAccount account);

  /// Atomically make [accountId] primary and demote all others. No-op if
  /// the ID is unknown.
  ///
  /// Multi-account status: this interface's N-account shape (watchAccounts
  /// returning a list, setPrimary) is kept because it costs nothing and is
  /// future-proof, but no account-switching UI or manager method consumes
  /// it this sprint — GoogleServiceManager has no switchAccount because
  /// google_sign_in ^6.2.1 has no account-targeted silent sign-in (see
  /// DECISIONS.md).
  Future<void> setPrimary(String accountId);

  /// Update lastRefreshAt / tokenExpiresAtEstimate / grantedScopes metadata
  /// after a token refresh or scope grant. **Single writer:** called only by
  /// GoogleServiceManager (never by GooglePermissionManager, and never by
  /// UI), which prevents two components racing on the same grantedScopes
  /// column.
  Future<void> touch(
    String accountId, {
    DateTime? lastRefreshAt,
    DateTime? tokenExpiresAtEstimate,
    List<String>? grantedScopes,
  });

  /// Remove one account's metadata row ("forget this account"). Token
  /// deletion is NOT done here — GoogleAuthRepository.signOut() owns it.
  Future<void> remove(String accountId);

  /// Wipe all account metadata (factory reset path).
  Future<void> clearAll();
}
