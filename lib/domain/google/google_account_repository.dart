// lib/domain/google/google_account_repository.dart

import 'package:neuroflow/domain/google/google_account.dart';

abstract class GoogleAccountRepository {
  /// Persists metadata about the connected account securely.
  Future<void> saveAccount(GoogleAccount account);

  /// Clears metadata about the connected account.
  Future<void> clearAccount();

  /// Retrieves the persisted account ID if any.
  Future<String?> getPersistedAccountId();
}
