// lib/data/connected_services_repository_impl.dart
//
// Drift-backed implementation of ConnectedServicesRepository, exactly
// parallel to DriftGoogleAccountRepository.
//
// Seeding fix (m5 in STAGE2_CRITIC_REPORT.md): lazy seeding *inside* a
// Drift watch() stream risks a write-triggers-rewatch loop (a table write
// during stream setup re-fires the same watcher). Instead, this repository
// seeds once via `_seeded`, a Future kicked off in the constructor and
// awaited at the START of every public method — never inside the stream
// pipeline itself.

import 'package:drift/drift.dart';

import '../domain/google_service.dart';
import 'connected_services_repository.dart';
import 'database.dart';

class DriftConnectedServicesRepository implements ConnectedServicesRepository {
  final AppDatabase _db;

  /// Kicked off once in the constructor, awaited (not re-triggered) by every
  /// public method before it touches the table. Idempotent: only inserts
  /// rows for GoogleServiceId values that don't already have one.
  final Future<void> _seeded;

  DriftConnectedServicesRepository(this._db) : _seeded = _seedMissing(_db);

  static Future<void> _seedMissing(AppDatabase db) async {
    final existing = await db.fetchConnectedServices();
    final existingIds = existing.map((r) => r.serviceId).toSet();
    for (final serviceId in GoogleServiceId.values) {
      if (existingIds.contains(serviceId.name)) continue;
      await db.upsertConnectedService(
        ConnectedServicesCompanion.insert(serviceId: serviceId.name),
      );
    }
  }

  // ------------------------------------------------------------------
  // Mappers
  // ------------------------------------------------------------------

  ConnectedService _rowToService(GoogleServiceId id, ConnectedServiceRow row) {
    return ConnectedService(
      id: id,
      status: GoogleServiceStatus.values.byName(row.status),
      enabledAt: row.enabledAt,
      lastUsedAt: row.lastUsedAt,
    );
  }

  /// Re-sorts rows into GoogleServiceId enum order (Drift's text-column
  /// order != enum order) and defensively fills in any missing id with a
  /// comingSoon placeholder rather than ever dropping a row from the list —
  /// seeding guarantees this never happens in practice, but watchAll() must
  /// never crash Settings if it somehow did.
  List<ConnectedService> _rowsToOrderedList(List<ConnectedServiceRow> rows) {
    final byId = {for (final r in rows) r.serviceId: r};
    return GoogleServiceId.values.map((id) {
      final row = byId[id.name];
      if (row == null) {
        return ConnectedService(id: id, status: GoogleServiceStatus.comingSoon);
      }
      return _rowToService(id, row);
    }).toList();
  }

  // ------------------------------------------------------------------
  // Interface implementation
  // ------------------------------------------------------------------

  @override
  Stream<List<ConnectedService>> watchAll() async* {
    await _seeded;
    yield* _db.watchConnectedServices().map(_rowsToOrderedList);
  }

  @override
  Future<ConnectedService> get(GoogleServiceId id) async {
    await _seeded;
    final rows = await _db.fetchConnectedServices();
    for (final row in rows) {
      if (row.serviceId == id.name) return _rowToService(id, row);
    }
    // Defensive: seeding guarantees a row per GoogleServiceId; never throw.
    return ConnectedService(id: id, status: GoogleServiceStatus.comingSoon);
  }

  @override
  Future<void> setStatus(GoogleServiceId id, GoogleServiceStatus status) async {
    await _seeded;
    await _db.patchConnectedService(
      id.name,
      ConnectedServicesCompanion(status: Value(status.name)),
    );
  }

  @override
  Future<void> touchLastUsed(GoogleServiceId id) async {
    await _seeded;
    await _db.patchConnectedService(
      id.name,
      ConnectedServicesCompanion(lastUsedAt: Value(DateTime.now())),
    );
  }

  @override
  Future<void> clearAll() async {
    await _seeded;
    await _db.clearConnectedServices();
    await _seedMissing(_db);
  }
}
