// lib/data/connected_services_repository.dart
//
// Abstract repository interface. Persistence for per-service connection
// status ("Connected services" list in Settings) — account-independent
// metadata, works identically signed-in or signed-out. Drift implementation
// is injected via Riverpod (see providers.dart). Mirrors GoogleAccountRepository
// / DriftGoogleAccountRepository in spirit.
//
// See STAGE2_COMPONENT_DESIGN.md §2.8.

import '../domain/google_service.dart';

/// Persistence for per-service connection status. Seeds one comingSoon row
/// per GoogleServiceId once, via an explicit ensureSeeded() step awaited
/// before the stream/read path — never lazily inside a `watch()` pipeline
/// (fix for m5 in STAGE2_CRITIC_REPORT.md: seeding inside a Drift watch()
/// stream risks a write-triggers-rewatch loop).
abstract class ConnectedServicesRepository {
  /// All services in enum order, always exactly one row per
  /// GoogleServiceId. Works identically signed-in or signed-out (service
  /// status is account-independent metadata).
  Stream<List<ConnectedService>> watchAll();

  Future<ConnectedService> get(GoogleServiceId id);

  /// Status transition, written by GoogleServiceManager only (widgets go
  /// through manager.enableService()). This sprint the manager never moves
  /// anything past comingSoon.
  Future<void> setStatus(GoogleServiceId id, GoogleServiceStatus status);

  /// Record usage. This sprint: called by
  /// GoogleServiceManager.enableService() to record that the user expressed
  /// interest in a "coming soon" service (see DECISIONS.md for why
  /// touchLastUsed — not setStatus — is what "records intent" means
  /// operationally this sprint). Future sprints: sync ran, API called.
  Future<void> touchLastUsed(GoogleServiceId id);

  /// Reset every service to comingSoon (factory reset path).
  Future<void> clearAll();
}
