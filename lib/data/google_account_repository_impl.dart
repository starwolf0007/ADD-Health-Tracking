// lib/data/google_account_repository_impl.dart
//
// Drift-backed implementation of GoogleAccountRepository, exactly parallel
// to DriftTaskRepository. Persists account METADATA only — never a token
// (schema physically has no token columns; see database.dart).

import 'package:drift/drift.dart';

import '../domain/google_account.dart';
import 'database.dart';
import 'google_account_repository.dart';

class DriftGoogleAccountRepository implements GoogleAccountRepository {
  final AppDatabase _db;

  DriftGoogleAccountRepository(this._db);

  // ------------------------------------------------------------------
  // Mappers
  // ------------------------------------------------------------------

  GoogleAccount _rowToAccount(GoogleAccountRow row) {
    return GoogleAccount(
      id: row.id,
      email: row.email,
      displayName: row.displayName,
      photoUrl: row.photoUrl,
      grantedScopes: _scopesFromString(row.grantedScopes),
      isPrimary: row.isPrimary,
      connectedAt: row.connectedAt,
      lastRefreshAt: row.lastRefreshAt,
      tokenExpiresAtEstimate: row.tokenExpiresAtEstimate,
    );
  }

  List<String> _scopesFromString(String s) {
    final trimmed = s.trim();
    return trimmed.isEmpty ? const [] : trimmed.split(' ');
  }

  String _scopesToString(List<String> scopes) => scopes.join(' ');

  // ------------------------------------------------------------------
  // Interface implementation
  // ------------------------------------------------------------------

  @override
  Stream<List<GoogleAccount>> watchAccounts() {
    return _db
        .watchGoogleAccounts()
        .map((rows) => rows.map(_rowToAccount).toList());
  }

  @override
  Future<GoogleAccount?> getPrimary() {
    return _db.transaction<GoogleAccount?>(() async {
      final rows = await _db.fetchGoogleAccounts();
      if (rows.isEmpty) return null;

      final primaries = rows.where((r) => r.isPrimary).toList();
      if (primaries.length == 1) {
        return _rowToAccount(primaries.single);
      }

      // Zero or multiple isPrimary rows (crash mid-write, cloned DB):
      // deterministically repair — most-recently-connected account wins —
      // inside this same transaction, then return it. getPrimary() never
      // simply errors on this condition (fix for m4 in
      // STAGE2_COMPONENT_DESIGN.md §2.3).
      final sorted = [...rows]
        ..sort((a, b) => b.connectedAt.compareTo(a.connectedAt));
      final winner = sorted.first;
      await _db.demoteAllGoogleAccounts();
      await _db.promoteGoogleAccount(winner.id);
      return _rowToAccount(winner).copyWith(isPrimary: true);
    });
  }

  @override
  Future<void> upsert(GoogleAccount account) {
    return _db.transaction<void>(() async {
      final existing = await _db.fetchGoogleAccounts();
      final isFirstAccount = existing.isEmpty;
      await _db.upsertGoogleAccount(
        GoogleAccountsCompanion(
          id: Value(account.id),
          email: Value(account.email),
          displayName: Value(account.displayName),
          photoUrl: Value(account.photoUrl),
          grantedScopes: Value(_scopesToString(account.grantedScopes)),
          isPrimary: Value(account.isPrimary || isFirstAccount),
          connectedAt: Value(account.connectedAt),
          lastRefreshAt: Value(account.lastRefreshAt),
          tokenExpiresAtEstimate: Value(account.tokenExpiresAtEstimate),
        ),
      );
    });
  }

  @override
  Future<void> setPrimary(String accountId) {
    return _db.transaction<void>(() async {
      final rows = await _db.fetchGoogleAccounts();
      final exists = rows.any((r) => r.id == accountId);
      if (!exists) return; // no-op: unknown id
      await _db.demoteAllGoogleAccounts();
      await _db.promoteGoogleAccount(accountId);
    });
  }

  @override
  Future<void> touch(
    String accountId, {
    DateTime? lastRefreshAt,
    DateTime? tokenExpiresAtEstimate,
    List<String>? grantedScopes,
  }) {
    return _db.touchGoogleAccount(
      accountId,
      GoogleAccountsCompanion(
        lastRefreshAt: lastRefreshAt != null
            ? Value(lastRefreshAt)
            : const Value.absent(),
        tokenExpiresAtEstimate: tokenExpiresAtEstimate != null
            ? Value(tokenExpiresAtEstimate)
            : const Value.absent(),
        grantedScopes: grantedScopes != null
            ? Value(_scopesToString(grantedScopes))
            : const Value.absent(),
      ),
    );
  }

  @override
  Future<void> remove(String accountId) => _db.removeGoogleAccount(accountId);

  @override
  Future<void> clearAll() => _db.clearGoogleAccounts();
}
