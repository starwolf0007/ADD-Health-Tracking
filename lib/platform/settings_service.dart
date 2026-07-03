// lib/platform/settings_service.dart
//
// Thin wrapper around FlutterSecureStorage for user-facing settings.
//
// All values are optional — defaults are returned when no stored value exists.
// Callers never crash on a missing key, they get the safe default.
//
// Settings stored here (non-secret, but using SecureStorage for consistency
// with the rest of the platform layer — no need for a second storage backend):
//   • Display name          → greeting on Today screen
//   • Morning briefing      → WorkManager notification on/off (default: on)
//   • Cloud Gemini opt-in   → §14 AI tiering gate (default: off)

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _kDisplayName = 'neuroflow_display_name';
const _kMorningBriefing = 'neuroflow_morning_briefing';
const _kCloudGemini = 'neuroflow_cloud_gemini';

class SettingsService {
  static const _storage = FlutterSecureStorage();

  // ------------------------------------------------------------------ name

  Future<String> getDisplayName() async {
    return await _storage.read(key: _kDisplayName) ?? '';
  }

  Future<void> setDisplayName(String name) async {
    await _storage.write(key: _kDisplayName, value: name.trim());
  }

  // ---------------------------------------------------------- notifications

  /// Morning briefing notification. Default: enabled.
  Future<bool> getMorningBriefingEnabled() async {
    final raw = await _storage.read(key: _kMorningBriefing);
    return raw == null ? true : raw == 'true';
  }

  Future<void> setMorningBriefingEnabled(bool value) async {
    await _storage.write(key: _kMorningBriefing, value: value.toString());
  }

  // --------------------------------------------------------- Cloud Gemini

  /// Cloud Gemini opt-in. Default: off (§14 — never on by default).
  Future<bool> getCloudGeminiEnabled() async {
    final raw = await _storage.read(key: _kCloudGemini);
    return raw == 'true'; // false unless explicitly set
  }

  Future<void> setCloudGeminiEnabled(bool value) async {
    await _storage.write(key: _kCloudGemini, value: value.toString());
  }
}
