// lib/domain/google/google_connection_state.dart

enum GoogleConnectionStatus {
  notConnected,
  connected,
  expired,
  error,
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

  bool get isConnected => status == GoogleConnectionStatus.connected;
}
