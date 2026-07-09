// lib/platform/sync/foreground_sync_observer.dart
//
// Triggers a Google Tasks sync flush the moment the app comes to the
// foreground (AppLifecycleState.resumed).
//
// Why this matters (Gemini's recommendation):
//   WorkManager runs flush() every 4 hours for battery efficiency — correct
//   for outbound (local → cloud). But if the user adds a task in Google Tasks
//   on their desktop, they'd wait up to 4h to see it in NeuroFlow. That
//   inbound lag erodes trust fast.
//
//   Triggering flush() on resume costs one HTTP round-trip only when the user
//   actually opens the app — acceptable latency tradeoff, negligible battery.
//
// Architecture notes:
//   • Fully auth-gated: flush() is a no-op if no Google Tasks token is stored.
//   • Errors are recorded for diagnostics without surfacing background sync
//     failures as UI noise.
//   • Works alongside WorkManager: WorkManager handles periodic catch-up;
//     this handles the "user just opened the app" moment.
//
// Registration: call start() once from main() before runApp().

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:neuroflow/app/providers.dart';
import 'package:neuroflow/platform/error_reporter.dart';

class ForegroundSyncObserver extends WidgetsBindingObserver {
  final ProviderContainer _container;
  bool _isStarted = false;

  ForegroundSyncObserver(this._container);

  /// Register with WidgetsBinding. Safe to call multiple times — only
  /// registers once.
  void start() {
    if (_isStarted) return;
    _isStarted = true;
    WidgetsBinding.instance.addObserver(this);
  }

  /// Unregister — call if you ever tear down the container (e.g. in tests).
  void stop() {
    if (!_isStarted) return;
    _isStarted = false;
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncOnForeground();
    }
  }

  void _syncOnForeground() {
    // Fire-and-forget. Auth-gated inside flush() — no-op if not connected.
    // Use Future.microtask so we don't block the lifecycle callback.
    Future.microtask(() async {
      try {
        await _container.read(googleTasksSyncServiceProvider).flush();
      } catch (error, stackTrace) {
        reportNonFatalError('Foreground sync failed', error, stackTrace);
      }
    });
  }
}
