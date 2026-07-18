import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuroflow/data/database.dart';
import 'package:neuroflow/platform/hevy/hevy_api_client.dart';

/// Everything the Health Integrations UI may do with the Hevy integration.
///
/// The live implementation composes the credentials store, API client,
/// repository, and sync service; tests substitute a fake. Nothing behind this
/// boundary ever returns the API key or raw response bodies.
abstract interface class HevyIntegrationGateway {
  Future<bool> isConfigured();
  Future<void> saveCredential(String value);
  Future<void> clearCredential();
  Future<void> verify();
  Future<void> sync();
  Future<HevySyncMetadataRow?> metadata();
}

enum HevyUiStatus {
  notConnected,
  verifying,
  connected,
  syncing,
  syncComplete,
  error,
}

class HevyIntegrationState {
  final HevyUiStatus status;

  /// Kept separate from [status] so a failed sync can show an error while the
  /// card stays in its connected layout.
  final bool isConnected;
  final int importedWorkoutCount;
  final DateTime? lastSuccessfulSync;
  final String? message;

  const HevyIntegrationState({
    required this.status,
    this.isConnected = false,
    this.importedWorkoutCount = 0,
    this.lastSuccessfulSync,
    this.message,
  });
}

class HevyIntegrationController extends AsyncNotifier<HevyIntegrationState> {
  HevyIntegrationController(this._gatewayProvider, this._importedCountProvider);

  final Provider<HevyIntegrationGateway> _gatewayProvider;
  final FutureProvider<int> _importedCountProvider;

  HevyIntegrationGateway get _gateway => ref.read(_gatewayProvider);

  HevyIntegrationState get _current =>
      state.value ??
      const HevyIntegrationState(status: HevyUiStatus.notConnected);

  @override
  Future<HevyIntegrationState> build() async {
    final configured = await _gateway.isConfigured();
    if (!configured) {
      return const HevyIntegrationState(status: HevyUiStatus.notConnected);
    }
    return _connectedState(HevyUiStatus.connected);
  }

  Future<void> connect(String rawKey) async {
    if (_current.status == HevyUiStatus.verifying) return;
    final key = rawKey.trim();
    if (key.isEmpty) {
      state = const AsyncData(
        HevyIntegrationState(
          status: HevyUiStatus.notConnected,
          message: 'Enter your Hevy API key first.',
        ),
      );
      return;
    }

    state = const AsyncData(
      HevyIntegrationState(status: HevyUiStatus.verifying),
    );
    try {
      await _gateway.saveCredential(key);
      await _gateway.verify();
    } catch (error) {
      // A credential that failed verification is never kept.
      await _gateway.clearCredential();
      state = AsyncData(
        HevyIntegrationState(
          status: HevyUiStatus.error,
          message: _verifyFailureMessage(error),
        ),
      );
      return;
    }
    state = AsyncData(await _connectedState(HevyUiStatus.connected));
  }

  Future<void> syncNow() async {
    final current = _current;
    if (current.status == HevyUiStatus.syncing ||
        current.status == HevyUiStatus.verifying) {
      return;
    }

    state = AsyncData(
      HevyIntegrationState(
        status: HevyUiStatus.syncing,
        isConnected: true,
        importedWorkoutCount: current.importedWorkoutCount,
        lastSuccessfulSync: current.lastSuccessfulSync,
      ),
    );
    try {
      await _gateway.sync();
    } catch (_) {
      state = AsyncData(
        HevyIntegrationState(
          status: HevyUiStatus.error,
          isConnected: true,
          importedWorkoutCount: current.importedWorkoutCount,
          lastSuccessfulSync: current.lastSuccessfulSync,
          message:
              'NeuroFlow couldn’t reach Hevy. Your saved workouts are still available.',
        ),
      );
      return;
    }
    state = AsyncData(await _connectedState(HevyUiStatus.syncComplete));
  }

  Future<void> disconnect() async {
    await _gateway.clearCredential();
    state = const AsyncData(
      HevyIntegrationState(status: HevyUiStatus.notConnected),
    );
  }

  Future<HevyIntegrationState> _connectedState(HevyUiStatus status) async {
    final metadata = await _gateway.metadata();
    final count = await ref.read(_importedCountProvider.future);
    return HevyIntegrationState(
      status: status,
      isConnected: true,
      importedWorkoutCount: count,
      lastSuccessfulSync: metadata?.lastSuccessAt,
    );
  }

  static String _verifyFailureMessage(Object error) {
    if (error is HevyApiException &&
        (error.statusCode == 401 || error.statusCode == 403)) {
      return 'That Hevy API key wasn’t accepted.';
    }
    return 'NeuroFlow couldn’t reach Hevy. Please try again.';
  }
}
