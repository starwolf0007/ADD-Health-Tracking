// lib/data/google/google_account_repository_impl.dart

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:neuroflow/domain/google/google_account.dart';
import 'package:neuroflow/domain/google/google_account_repository.dart';

class GoogleAccountRepositoryImpl implements GoogleAccountRepository {
  static const _kGoogleAccountId = 'neuroflow_google_account_id';
  final FlutterSecureStorage _storage;

  GoogleAccountRepositoryImpl(this._storage);

  @override
  Future<void> saveAccount(GoogleAccount account) async {
    await _storage.write(key: _kGoogleAccountId, value: account.id);
  }

  @override
  Future<void> clearAccount() async {
    await _storage.delete(key: _kGoogleAccountId);
  }

  @override
  Future<String?> getPersistedAccountId() async {
    return await _storage.read(key: _kGoogleAccountId);
  }
}
