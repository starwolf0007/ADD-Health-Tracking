// lib/domain/google_connection_state.dart
//
// Pure domain model — no Flutter, no Drift, no plugin imports.
//
// GoogleConnectionState is owned and driven exclusively by
// GoogleServiceManager (lib/platform/google/google_service_manager.dart).
// See STAGE2_COMPONENT_DESIGN.md §2.7 for the full state diagram.

/// Google connection status. The manager asserts transitions against
/// [GoogleConnectionState.isLegalTransition] in debug builds.
enum GoogleConnectionStatus {
  /// No Google account. The app's default and its permanent state for
  /// "Continue without Google" users.
  disconnected,

  /// A sign-in, silent restore, or token refresh is in flight. Transient.
  connecting,

  /// Signed in with a valid access token.
  connected,

  /// Signed in but the access token lapsed and silent refresh has not yet
  /// succeeded; interactive re-auth may be required. Sync is paused.
  expired,

  /// The last connect/refresh attempt failed (network, config, plugin).
  /// Recoverable via connect(). User cancellation does NOT land here.
  error,
}

/// Immutable snapshot of the Google connection. Carries metadata only — no
/// tokens, ever. [lastError] is a sanitized, user-displayable message (no
/// tokens, no account IDs, no stack traces).
class GoogleConnectionState {
  final GoogleConnectionStatus status;
  final String? email; // null unless connected/expired
  final String? displayName;
  final List<String> grantedScopes;
  final String? lastError; // null unless status == error
  final DateTime? lastRefreshAt;
  final DateTime? connectedAt;

  const GoogleConnectionState({
    required this.status,
    this.email,
    this.displayName,
    this.grantedScopes = const [],
    this.lastError,
    this.lastRefreshAt,
    this.connectedAt,
  });

  /// The app-start default, before GoogleServiceManager.initialize() runs
  /// (and its permanent state for "Continue without Google" users).
  const GoogleConnectionState.disconnected()
      : status = GoogleConnectionStatus.disconnected,
        email = null,
        displayName = null,
        grantedScopes = const [],
        lastError = null,
        lastRefreshAt = null,
        connectedAt = null;

  bool get isConnected => status == GoogleConnectionStatus.connected;
  bool get isBusy => status == GoogleConnectionStatus.connecting;

  GoogleConnectionState copyWith({
    GoogleConnectionStatus? status,
    String? email,
    String? displayName,
    List<String>? grantedScopes,
    String? lastError,
    DateTime? lastRefreshAt,
    DateTime? connectedAt,
  }) {
    return GoogleConnectionState(
      status: status ?? this.status,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      grantedScopes: grantedScopes ?? this.grantedScopes,
      // lastError is NOT `?? this.lastError` — callers that transition to a
      // non-error status must be able to clear it by passing null explicitly
      // via the status param path; error-setting call sites always pass an
      // explicit lastError alongside status: error. See
      // GoogleServiceManager._setState usage.
      lastError: lastError,
      lastRefreshAt: lastRefreshAt ?? this.lastRefreshAt,
      connectedAt: connectedAt ?? this.connectedAt,
    );
  }

  /// Legal transitions per STAGE2_COMPONENT_DESIGN.md §2.7 (revision 2):
  ///   disconnected  → {connecting}
  ///   connecting    → {connected, expired, error, disconnected}
  ///   connected     → {expired, connecting, disconnected}
  ///   expired       → {connecting, error, disconnected}
  ///   error         → {connecting, disconnected}
  /// A same-status "transition" (metadata-only update, e.g. touch()) is
  /// always legal — it isn't a state-machine move.
  static bool isLegalTransition(
    GoogleConnectionStatus from,
    GoogleConnectionStatus to,
  ) {
    if (from == to) return true;
    switch (from) {
      case GoogleConnectionStatus.disconnected:
        return to == GoogleConnectionStatus.connecting;
      case GoogleConnectionStatus.connecting:
        return to == GoogleConnectionStatus.connected ||
            to == GoogleConnectionStatus.expired ||
            to == GoogleConnectionStatus.error ||
            to == GoogleConnectionStatus.disconnected;
      case GoogleConnectionStatus.connected:
        return to == GoogleConnectionStatus.expired ||
            to == GoogleConnectionStatus.connecting ||
            to == GoogleConnectionStatus.disconnected;
      case GoogleConnectionStatus.expired:
        return to == GoogleConnectionStatus.connecting ||
            to == GoogleConnectionStatus.error ||
            to == GoogleConnectionStatus.disconnected;
      case GoogleConnectionStatus.error:
        return to == GoogleConnectionStatus.connecting ||
            to == GoogleConnectionStatus.disconnected;
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GoogleConnectionState &&
          runtimeType == other.runtimeType &&
          status == other.status &&
          email == other.email &&
          displayName == other.displayName &&
          _sameScopes(grantedScopes, other.grantedScopes) &&
          lastError == other.lastError &&
          lastRefreshAt == other.lastRefreshAt &&
          connectedAt == other.connectedAt;

  @override
  int get hashCode => Object.hash(
        status,
        email,
        displayName,
        Object.hashAll(grantedScopes),
        lastError,
        lastRefreshAt,
        connectedAt,
      );

  static bool _sameScopes(List<String> a, List<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
