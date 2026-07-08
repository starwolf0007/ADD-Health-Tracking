// lib/domain/google/google_connection_state.dart

/// Five-state auth state machine (ADR-006 Stage 4).
///
/// Lifecycle:
///   disconnected → connecting → authenticated
///   authenticated → expired (token stale)
///   connecting | authenticated → failed (sign-in error)
///   expired | failed → connecting (retry)
enum GoogleConnectionStatus {
  /// No account linked; initial state.
  disconnected,

  /// Sign-in or token-refresh in flight.
  connecting,

  /// Signed in with valid token.
  authenticated,

  /// Token expired; re-auth needed.
  expired,

  /// Sign-in or refresh failed.
  failed,
}

class GoogleConnectionState {
  final GoogleConnectionStatus status;
  final String? errorMessage;
  final DateTime? lastCheck;

  const GoogleConnectionState({
    required this.status,
    this.errorMessage,
    this.lastCheck,
  });

  bool get isConnected => status == GoogleConnectionStatus.authenticated;
}
