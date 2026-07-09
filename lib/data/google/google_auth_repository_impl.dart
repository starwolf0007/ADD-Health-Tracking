// lib/data/google/google_auth_repository_impl.dart
//
// google_sign_in 7.x API:
//   - Singleton: GoogleSignIn.instance (no constructor)
//   - initialize() must be called before use
//   - authenticationEvents stream for sign-in / sign-out events
//   - authenticate() / attemptLightweightAuthentication() return the account
//   - authorizationClient.authorizationHeaders() returns Map<String,String>? headers

import 'dart:async';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import 'package:neuroflow/domain/google/google_account.dart';
import 'package:neuroflow/domain/google/google_auth_repository.dart';

/// Thin HTTP client that injects Google auth headers on every request.
class _GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _inner;

  _GoogleAuthClient(this._headers) : _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _inner.send(request);
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}

class GoogleAuthRepositoryImpl implements GoogleAuthRepository {
  static final _signIn = GoogleSignIn.instance;

  GoogleSignInAccount? _currentUser;
  final _accountController = StreamController<GoogleAccount?>.broadcast();
  late final Future<void> _initialization;

  GoogleAuthRepositoryImpl() {
    _initialization = _initialize();
  }

  Future<void> _initialize() async {
    await _signIn.initialize(
      clientId:
          '287604372230-bpcl30912rp38ou92ltcs6iqe2977lrf.apps.googleusercontent.com',
      serverClientId:
          '287604372230-bpcl30912rp38ou92ltcs6iqe2977lrf.apps.googleusercontent.com',
    );
    _signIn.authenticationEvents.listen(
      _handleAuthEvent,
      onError: _accountController.addError,
    );
  }

  void _handleAuthEvent(GoogleSignInAuthenticationEvent event) {
    if (event is GoogleSignInAuthenticationEventSignIn) {
      _currentUser = event.user;
      _accountController.add(_mapAccount(event.user));
    } else if (event is GoogleSignInAuthenticationEventSignOut) {
      _currentUser = null;
      _accountController.add(null);
    }
  }

  @override
  Stream<GoogleAccount?> get onAccountChanged async* {
    await _initialization;
    // Emit current state immediately, then stream future changes.
    yield _mapAccount(_currentUser);
    yield* _accountController.stream;
  }

  @override
  Future<GoogleAccount?> get currentAccount async {
    await _initialization;
    return _mapAccount(_currentUser);
  }

  @override
  Future<GoogleAccount?> signIn() async {
    await _initialization;
    if (!_signIn.supportsAuthenticate()) return null;
    final user = await _signIn.authenticate();
    _currentUser = user;
    return _mapAccount(user);
  }

  @override
  Future<GoogleAccount?> signInSilently() async {
    await _initialization;
    // attemptLightweightAuthentication() returns null Future on unsupported platforms.
    final user = await (_signIn.attemptLightweightAuthentication() ??
        Future.value(null));
    if (user != null) _currentUser = user;
    return _mapAccount(user);
  }

  @override
  Future<void> signOut() async {
    await _initialization;
    await _signIn.signOut();
    // The sign-out event will arrive via authenticationEvents → _handleAuthEvent.
  }

  @override
  Future<http.Client?> getAuthenticatedClient(List<String> scopes) async {
    await _initialization;
    final account = _currentUser;
    if (account == null) return null;

    // Silent only. Callers that need interactive auth should use
    // GooglePermissionManager.requestScopes() first.
    final headers =
        await account.authorizationClient.authorizationHeaders(scopes);
    if (headers == null) return null;
    return _GoogleAuthClient(headers);
  }

  @override
  Future<void> refreshToken() async {
    await _initialization;
    // Lightweight re-auth; the event stream updates _currentUser.
    await (_signIn.attemptLightweightAuthentication() ?? Future.value(null));
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
