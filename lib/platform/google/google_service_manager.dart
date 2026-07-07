// lib/platform/google/google_service_manager.dart

import 'dart:async';
import 'package:neuroflow/domain/google/google_account.dart';
import 'package:neuroflow/domain/google/google_auth_repository.dart';
import 'package:neuroflow/domain/google/google_account_repository.dart';
import 'package:neuroflow/domain/google/google_connection_state.dart';

class GoogleServiceManager {
  final GoogleAuthRepository _authRepo;
  final GoogleAccountRepository _accountRepo;

  final _connectionController = StreamController<GoogleConnectionState>.broadcast();
  GoogleConnectionState _currentState = const GoogleConnectionState(status: GoogleConnectionStatus.notConnected);

  GoogleServiceManager(
    this._authRepo,
    this._accountRepo,
  ) {
    _authRepo.onAccountChanged.listen(_handleAccountChange);
    _initStatus();
  }

  Stream<GoogleConnectionState> get connectionState => _connectionController.stream;
  GoogleConnectionState get currentState => _currentState;
  Stream<GoogleAccount?> get accountChanges => _authRepo.onAccountChanged;

  Future<void> _initStatus() async {
    final account = await _authRepo.currentAccount;
    _handleAccountChange(account);
  }

  void _handleAccountChange(GoogleAccount? account) {
    if (account != null) {
      _currentState = GoogleConnectionState(
        status: GoogleConnectionStatus.connected,
        lastCheck: DateTime.now(),
      );
      _accountRepo.saveAccount(account);
    } else {
      _currentState = const GoogleConnectionState(status: GoogleConnectionStatus.notConnected);
      _accountRepo.clearAccount();
    }
    _connectionController.add(_currentState);
  }

  Future<GoogleAccount?> signIn() => _authRepo.signIn();

  Future<GoogleAccount?> restoreSession() => _authRepo.signInSilently();

  Future<void> signOut() => _authRepo.signOut();

  Future<void> switchAccount() async {
    await signOut();
    await signIn();
  }

  Future<void> refreshToken() => _authRepo.refreshToken();

  // Helper for internal service factories
  Future<dynamic> getAuthenticatedClient(List<String> scopes) =>
      _authRepo.getAuthenticatedClient(scopes);

  /// Registration point for future Google services (Tasks, Calendar, etc.)
  void registerService(String serviceName, dynamic serviceImplementation) {
    // TODO: Maintain a map of registered services for unified lifecycle management.
  }
}
