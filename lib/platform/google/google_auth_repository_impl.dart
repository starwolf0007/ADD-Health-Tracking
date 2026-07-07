// lib/platform/google/google_auth_repository_impl.dart
//
// Wraps package:google_sign_in behind GoogleAuthRepository. Lives in the
// platform layer because it binds a plugin; the interface lives in
// lib/data/ per the sprint brief and mirrors TaskRepository /
// DriftTaskRepository in spirit.
//
// Token handling (hard constraint — see DECISIONS.md):
//   • Access token: NEVER persisted. currentAccessToken() reads the
//     plugin's live `currentUser.authentication` getter every time it's
//     called — never a stored copy.
//   • ID token: written to FlutterSecureStorage under a per-account key,
//     deleted on signOut(). Nothing else is ever written to secure storage
//     by this class.
//
// NEVER log tokens, ID tokens, or user IDs. Emails may appear in the
// GoogleAccount objects this class returns, but never in a log/print
// statement here.

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../data/google_auth_repository.dart';
import '../../domain/google_account.dart';

String _idTokenKey(String accountId) =>
    'neuroflow_google_id_token_$accountId';

class GoogleSignInAuthRepository implements GoogleAuthRepository {
  static const _storage = FlutterSecureStorage();

  final GoogleSignIn _plugin;

  GoogleSignInAuthRepository(this._plugin);

  @override
  Future<GoogleAccount?> signIn() async {
    GoogleSignInAccount? account;
    try {
      account = await _plugin.signIn();
    } on PlatformException catch (e) {
      if (e.code == 'sign_in_canceled' || e.code == 'sign_in_cancelled') {
        return null; // cancel is NOT an error
      }
      throw GoogleAuthException(_sanitizePlatformException(e));
    } catch (_) {
      throw const GoogleAuthException('google sign-in failed');
    }

    if (account == null) return null; // Android: null return on cancel

    final now = DateTime.now();
    await _persistIdToken(account);
    return _toAccount(account, connectedAt: now);
  }

  @override
  Future<GoogleAccount?> silentSignIn() async {
    GoogleSignInAccount? account;
    try {
      account = await _plugin.signInSilently();
    } catch (_) {
      // No previous session (or the plugin couldn't restore it) is a
      // normal signed-out outcome here, never an error — the manager
      // distinguishes "never connected" from "prior session, can't restore"
      // using GoogleAccountRepository, not an exception from this method.
      return null;
    }
    if (account == null) return null;

    final now = DateTime.now();
    await _persistIdToken(account);
    return _toAccount(account, connectedAt: now);
  }

  @override
  Future<void> signOut() async {
    // Capture the account id BEFORE signing out — currentUser is null
    // immediately after signOut() completes.
    final accountId = _plugin.currentUser?.id;
    try {
      await _plugin.signOut();
    } catch (_) {
      // Best-effort — still clear local token storage below regardless.
    }
    if (accountId != null) {
      await _storage.delete(key: _idTokenKey(accountId));
    }
  }

  @override
  Future<GoogleAccount> refreshToken() async {
    GoogleSignInAccount? account;
    try {
      account = await _plugin.signInSilently();
    } catch (_) {
      throw const GoogleAuthTokenExpiredException();
    }
    if (account == null) {
      throw const GoogleAuthTokenExpiredException();
    }

    final now = DateTime.now();
    await _persistIdToken(account);
    return _toAccount(account, connectedAt: now, lastRefreshAt: now);
  }

  @override
  Future<String?> currentAccessToken() async {
    final account = _plugin.currentUser;
    if (account == null) return null;
    try {
      final auth = await account.authentication;
      return auth.accessToken;
    } catch (_) {
      // Never throw for "not signed in" / a transient plugin hiccup — the
      // caller (GoogleApiFactory) treats null as "no client available".
      return null;
    }
  }

  // ------------------------------------------------------------------
  // Helpers
  // ------------------------------------------------------------------

  GoogleAccount _toAccount(
    GoogleSignInAccount account, {
    required DateTime connectedAt,
    DateTime? lastRefreshAt,
  }) {
    final refreshInstant = lastRefreshAt ?? connectedAt;
    return GoogleAccount(
      id: account.id,
      email: account.email,
      displayName: account.displayName,
      photoUrl: account.photoUrl,
      // Base sign-in scopes only — anything beyond email/profile is
      // GooglePermissionManager's job (incremental auth), never requested
      // here.
      grantedScopes: const ['email', 'profile'],
      // isPrimary is unknown to the auth layer — GoogleServiceManager
      // reconciles this against the persisted account (or the
      // "first account ever saved becomes primary" rule in
      // GoogleAccountRepository.upsert()) before persisting.
      isPrimary: false,
      connectedAt: connectedAt,
      lastRefreshAt: lastRefreshAt,
      tokenExpiresAtEstimate: GoogleAccount.estimateExpiry(refreshInstant),
    );
  }

  Future<void> _persistIdToken(GoogleSignInAccount account) async {
    final auth = await account.authentication;
    final idToken = auth.idToken;
    if (idToken != null) {
      await _storage.write(key: _idTokenKey(account.id), value: idToken);
    }
  }

  /// Sanitizes a caught PlatformException into a message safe to log or
  /// display — never includes tokens or email addresses (only the plugin's
  /// error code, which is a fixed enum-like string).
  String _sanitizePlatformException(PlatformException e) =>
      'google sign-in failed (${e.code})';
}
