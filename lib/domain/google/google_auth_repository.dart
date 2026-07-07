// lib/domain/google/google_auth_repository.dart

import 'package:googleapis_auth/googleapis_auth.dart' as auth;
import 'package:neuroflow/domain/google/google_account.dart';

abstract class GoogleAuthRepository {
  /// Stream of the currently signed-in Google account.
  Stream<GoogleAccount?> get onAccountChanged;

  /// Returns the currently signed-in account, or null.
  Future<GoogleAccount?> get currentAccount;

  /// Initiates the Google Sign-In flow.
  Future<GoogleAccount?> signIn();

  /// Silently signs in the user if a previous session exists.
  Future<GoogleAccount?> signInSilently();

  /// Signs the user out of Google.
  Future<void> signOut();

  /// Returns an authenticated HTTP client for the given scopes.
  Future<auth.AuthClient?> getAuthenticatedClient(List<String> scopes);

  /// Forces a token refresh.
  Future<void> refreshToken();
}
