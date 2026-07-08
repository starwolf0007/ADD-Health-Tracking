// lib/data/google/google_auth_repository_impl.dart

import 'package:google_sign_in/google_sign_in.dart';
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:googleapis_auth/googleapis_auth.dart' as auth;

import 'package:neuroflow/domain/google/google_account.dart';
import 'package:neuroflow/domain/google/google_auth_repository.dart';

class GoogleAuthRepositoryImpl implements GoogleAuthRepository {
  final GoogleSignIn _googleSignIn;
  late final Stream<GoogleAccount?> _accountStream;

  GoogleAuthRepositoryImpl()
      : _googleSignIn = GoogleSignIn(
          clientId: '287604372230-bpcl30912rp38ou92ltcs6iqe2977lrf.apps.googleusercontent.com',
          serverClientId: '287604372230-bpcl30912rp38ou92ltcs6iqe2977lrf.apps.googleusercontent.com',
          scopes: [
            'openid',
            'email',
            'profile',
            'https://www.googleapis.com/auth/tasks',
          ],
        ) {
    _accountStream = _googleSignIn.onCurrentUserChanged
        .map(_mapAccount)
        .asBroadcastStream();
  }

  GoogleSignIn get googleSignIn => _googleSignIn;

  @override
  Stream<GoogleAccount?> get onAccountChanged async* {
    // Yield the initial value immediately
    yield _mapAccount(_googleSignIn.currentUser);
    // Then yield all future changes
    yield* _accountStream;
  }

  @override
  Future<GoogleAccount?> get currentAccount async =>
      _mapAccount(_googleSignIn.currentUser);

  @override
  Future<GoogleAccount?> signIn() async {
    try {
      final user = await _googleSignIn.signIn();
      return _mapAccount(user);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<GoogleAccount?> signInSilently() async {
    try {
      final user = await _googleSignIn.signInSilently();
      return _mapAccount(user);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> signOut() async {
    await _googleSignIn.signOut();
  }

  @override
  Future<auth.AuthClient?> getAuthenticatedClient(List<String> scopes) async {
    final hasScopes = await _googleSignIn.canAccessScopes(scopes);
    if (!hasScopes) {
      await _googleSignIn.requestScopes(scopes);
    }

    return _googleSignIn.authenticatedClient();
  }

  @override
  Future<void> refreshToken() async {
    // google_sign_in handles token refreshing internally when authenticatedClient() is used.
    // Explicit refresh can be triggered by signing in silently again.
    await _googleSignIn.signInSilently();
  }

  GoogleAccount? _mapAccount(GoogleSignInAccount? user) {
    if (user == null) return null;
    return GoogleAccount(
      id: user.id,
      email: user.email,
      displayName: user.displayName,
      photoUrl: user.photoUrl,
    );
  }
}
