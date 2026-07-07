// lib/domain/google_account.dart
//
// Pure domain model — no Flutter, no Drift, no plugin imports.
//
// Metadata for a connected Google account. NEVER carries tokens — tokens
// exist only in FlutterSecureStorage (ID token, see
// lib/platform/google/google_auth_repository_impl.dart) and in-memory, via
// the google_sign_in plugin's live getter (see
// GoogleAuthRepository.currentAccessToken()). Adding a token field here is a
// review-blocking violation (STAGE2_COMPONENT_DESIGN.md §5).

class GoogleAccount {
  final String id; // stable id from google_sign_in
  final String email;
  final String? displayName;
  final String? photoUrl;
  final List<String> grantedScopes;
  final bool isPrimary;
  final DateTime connectedAt;
  final DateTime? lastRefreshAt;

  /// Advisory-only estimate of when the access token may need refreshing.
  /// DERIVED as `(lastRefreshAt ?? connectedAt) + 55min` — never provided by
  /// the plugin (google_sign_in v6.2.1 exposes no token expiry). NOT
  /// authoritative and NEVER used to gate client creation; the authoritative
  /// expiry signal is a live 401 from an API call, routed back via
  /// GoogleServiceManager.notifyAuthFailure(). See [estimateExpiry].
  final DateTime? tokenExpiresAtEstimate;

  const GoogleAccount({
    required this.id,
    required this.email,
    this.displayName,
    this.photoUrl,
    this.grantedScopes = const [],
    this.isPrimary = false,
    required this.connectedAt,
    this.lastRefreshAt,
    this.tokenExpiresAtEstimate,
  });

  /// [id] and [connectedAt] are immutable once an account row exists (mirrors
  /// Task.copyWith's treatment of `id`/`createdAt`) — a component that needs
  /// to change either constructs a new GoogleAccount directly.
  GoogleAccount copyWith({
    String? email,
    String? displayName,
    String? photoUrl,
    List<String>? grantedScopes,
    bool? isPrimary,
    DateTime? lastRefreshAt,
    DateTime? tokenExpiresAtEstimate,
  }) {
    return GoogleAccount(
      id: id,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      photoUrl: photoUrl ?? this.photoUrl,
      grantedScopes: grantedScopes ?? this.grantedScopes,
      isPrimary: isPrimary ?? this.isPrimary,
      connectedAt: connectedAt,
      lastRefreshAt: lastRefreshAt ?? this.lastRefreshAt,
      tokenExpiresAtEstimate:
          tokenExpiresAtEstimate ?? this.tokenExpiresAtEstimate,
    );
  }

  /// Deliberately shy of the ~60-minute access-token TTL so it also absorbs
  /// modest device clock skew (fix for M2 in STAGE2_COMPONENT_DESIGN.md).
  static DateTime estimateExpiry(DateTime from) =>
      from.add(const Duration(minutes: 55));
}
