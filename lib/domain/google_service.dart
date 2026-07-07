// lib/domain/google_service.dart
//
// Pure Dart — no Flutter, no Drift, no plugin imports.
//
// SCOPE NOTE (Google Foundation Sprint, Stages 4-5 vs Stage 6): GoogleServiceId
// shipped in Stages 4-5. GoogleServiceStatus and ConnectedService below ship
// in Stage 6 (Connected Services Settings page), per
// STAGE2_COMPONENT_DESIGN.md §2.8. GoogleServiceId itself has no dependency
// on ConnectedServicesRepository; it is used as GoogleApiFactory's
// client-cache key, GoogleServiceIntegration's registration key, and now
// ConnectedServicesRepository's row key.

/// The Google services NeuroFlow knows about. Order = future Settings
/// display order. No product client exists for any of these yet — see
/// STAGE2_COMPONENT_DESIGN.md §7 non-goals.
///
/// NIT (n1 in STAGE2_CRITIC_REPORT.md): `healthConnect` is a device API with
/// no OAuth scope, conceptually distinct from the other (Google-account)
/// services in this enum. It is kept here because it is still one row in the
/// "Connected services" Settings list, but it will never route through
/// GooglePermissionManager / scope requests the way tasks/calendar/etc. will
/// in future sprints.
enum GoogleServiceId { tasks, calendar, drive, gmail, contacts, healthConnect, gemini }

/// Per-service connection status ("Connected services" list in Settings).
enum GoogleServiceStatus {
  /// Visible in Settings, not yet implemented. EVERY service is this status
  /// in the Google Foundation Sprint — no product client exists yet (§7).
  comingSoon,

  /// Implemented and available but the user has not enabled it.
  available,

  /// User enabled it and scopes are granted.
  enabled,

  /// User explicitly turned it off after enabling.
  disabled,
}

/// One row of the "Connected services" list in Settings. Always exactly one
/// instance per [GoogleServiceId] (see ConnectedServicesRepository.watchAll).
class ConnectedService {
  final GoogleServiceId id;
  final GoogleServiceStatus status;

  /// When the user last enabled this service. Null until a future sprint
  /// actually flips status to `enabled` — this sprint every row's status is
  /// `comingSoon`, so this stays null in practice.
  final DateTime? enabledAt;

  /// When this service was last used (sync ran, API called, or — this
  /// sprint — the user tapped a "coming soon" row to register interest; see
  /// GoogleServiceManager.enableService()).
  final DateTime? lastUsedAt;

  const ConnectedService({
    required this.id,
    required this.status,
    this.enabledAt,
    this.lastUsedAt,
  });

  ConnectedService copyWith({
    GoogleServiceStatus? status,
    DateTime? enabledAt,
    DateTime? lastUsedAt,
  }) {
    return ConnectedService(
      id: id,
      status: status ?? this.status,
      enabledAt: enabledAt ?? this.enabledAt,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConnectedService &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          status == other.status &&
          enabledAt == other.enabledAt &&
          lastUsedAt == other.lastUsedAt;

  @override
  int get hashCode => Object.hash(id, status, enabledAt, lastUsedAt);
}
