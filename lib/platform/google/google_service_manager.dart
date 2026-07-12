// lib/platform/google/google_service_manager.dart

import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:neuroflow/domain/google/google_account.dart';
import 'package:neuroflow/domain/google/google_auth_repository.dart';
import 'package:neuroflow/domain/google/google_account_repository.dart';
import 'package:neuroflow/domain/google/google_connection_state.dart';

class GoogleServiceManager {
  final GoogleAuthRepository _authRepo;
  final GoogleAccountRepository _accountRepo;

  final _connectionController =
      StreamController<GoogleConnectionState>.broadcast();
  GoogleConnectionState _currentState = const GoogleConnectionState(
    status: GoogleConnectionStatus.disconnected,
  );

  GoogleServiceManager(
    this._authRepo,
    this._accountRepo,
  ) {
    _authRepo.onAccountChanged.listen(_handleAccountChange);
    _initStatus();
  }

  Stream<GoogleConnectionState> get connectionState =>
      _connectionController.stream;
  GoogleConnectionState get currentState => _currentState;
  Stream<GoogleAccount?> get accountChanges => _authRepo.onAccountChanged;

  Future<void> _initStatus() async {
    _setState(
        const GoogleConnectionState(status: GoogleConnectionStatus.connecting));
    final account = await _authRepo.currentAccount;
    _handleAccountChange(account);
  }

  void _handleAccountChange(GoogleAccount? account) {
    if (account != null) {
      _setState(GoogleConnectionState(
        status: GoogleConnectionStatus.authenticated,
        lastCheck: DateTime.now(),
      ));
      _accountRepo.saveAccount(account);
    } else {
      _setState(const GoogleConnectionState(
          status: GoogleConnectionStatus.disconnected));
      _accountRepo.clearAccount();
    }
  }

  void _setState(GoogleConnectionState state) {
    _currentState = state;
    _connectionController.add(state);
  }

  Future<GoogleAccount?> signIn() async {
    _setState(
        const GoogleConnectionState(status: GoogleConnectionStatus.connecting));
    try {
      final account = await _authRepo.signIn();
      if (account == null) {
        _setState(const GoogleConnectionState(
            status: GoogleConnectionStatus.disconnected));
      }
      return account;
    } catch (e) {
      _setState(GoogleConnectionState(
        status: GoogleConnectionStatus.failed,
        errorMessage: e.toString(),
        lastCheck: DateTime.now(),
      ));
      return null;
    }
  }

  Future<GoogleAccount?> restoreSession() async {
    _setState(
        const GoogleConnectionState(status: GoogleConnectionStatus.connecting));
    try {
      final account = await _authRepo.signInSilently();
      if (account == null) {
        _setState(const GoogleConnectionState(
            status: GoogleConnectionStatus.disconnected));
      }
      return account;
    } catch (e) {
      _setState(GoogleConnectionState(
        status: GoogleConnectionStatus.failed,
        errorMessage: e.toString(),
        lastCheck: DateTime.now(),
      ));
      return null;
    }
  }

  Future<void> signOut() => _authRepo.signOut();

  Future<void> switchAccount() async {
    await _authRepo.signOut();
    await signIn();
  }

  Future<void> refreshToken() async {
    _setState(
        const GoogleConnectionState(status: GoogleConnectionStatus.connecting));
    try {
      await _authRepo.refreshToken();
      _setState(GoogleConnectionState(
        status: GoogleConnectionStatus.authenticated,
        lastCheck: DateTime.now(),
      ));
    } catch (e) {
      _setState(GoogleConnectionState(
        status: GoogleConnectionStatus.expired,
        errorMessage: e.toString(),
        lastCheck: DateTime.now(),
      ));
    }
  }

  // Helper for internal service factories
  Future<http.Client?> getAuthenticatedClient(List<String> scopes) =>
      _authRepo.getAuthenticatedClient(scopes);

  /// Registration point for future Google services (Tasks, Calendar, etc.)
  void registerService(String serviceName, dynamic serviceImplementation) {
    // TODO: Maintain a map of registered services for unified lifecycle management.
  }
}
