import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stores the Hevy API key in Android Keystore / iOS Keychain.
///
/// The key must never be written to Drift, logs, analytics, crash reports,
/// source control, or plain-text preferences.
class HevyCredentialsStore {
  static const _apiKeyStorageKey = 'integration.hevy.api_key';

  final FlutterSecureStorage _storage;

  const HevyCredentialsStore(this._storage);

  Future<bool> get isConfigured async {
    final value = await _storage.read(key: _apiKeyStorageKey);
    return value != null && value.trim().isNotEmpty;
  }

  Future<void> saveApiKey(String apiKey) async {
    final normalized = apiKey.trim();
    if (normalized.isEmpty) {
      throw const FormatException('Hevy API key cannot be empty.');
    }

    await _storage.write(
      key: _apiKeyStorageKey,
      value: normalized,
    );
  }

  Future<String?> readApiKey() async {
    final value = await _storage.read(key: _apiKeyStorageKey);
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  Future<void> clear() => _storage.delete(key: _apiKeyStorageKey);
}
