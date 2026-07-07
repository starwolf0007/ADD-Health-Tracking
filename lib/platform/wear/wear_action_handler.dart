// lib/platform/wear/wear_action_handler.dart
//
// Listens for actions sent by the watch (Complete, Snooze) via the
// Wearable MessageClient, then calls into the task repository.
//
// Message paths (watch → phone):
//   /neuroflow/complete  { taskId: String }  → markComplete
//   /neuroflow/snooze    { taskId: String }  → add to in-memory snooze set
//
// Platform channel: 'neuroflow/wear'
//   Method channel receives calls FROM native (Kotlin MethodChannel.invokeMethod
//   on the Flutter engine) when a MessageClient message arrives.
//   This is the reverse direction from WearSyncService.
//
// Snooze semantics (per spec §8):
//   No DB write. The taskId is added to an in-memory exclusion set held
//   by TodayController. Executive.evaluate() skips excluded tasks for the
//   session. On app restart or morning refresh, excluded tasks reappear.

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';

const _kChannel = 'neuroflow/wear';
const _kMethodComplete = 'onWatchComplete';
const _kMethodSnooze = 'onWatchSnooze';

class WearActionHandler {
  static const _channel = MethodChannel(_kChannel);

  final ProviderContainer _container;

  WearActionHandler(this._container);

  /// Start listening for messages from the watch.
  /// Call once from main() after ProviderContainer is ready.
  void start() {
    _channel.setMethodCallHandler(_handleCall);
  }

  Future<dynamic> _handleCall(MethodCall call) async {
    final taskId = call.arguments['taskId'] as String? ?? '';
    if (taskId.isEmpty) return;

    switch (call.method) {
      case _kMethodComplete:
        await _onComplete(taskId);
        break;
      case _kMethodSnooze:
        await _onSnooze(taskId);
        break;
    }
  }

  Future<void> _onComplete(String taskId) async {
    try {
      await _container.read(taskRepositoryProvider).markComplete(taskId);
      // TodayController watches the task stream and will rebuild automatically,
      // then WearSyncService.pushPrimaryTask() will push the updated state.
    } catch (_) {
      // Non-fatal — task stays pending, user can complete from phone.
    }
  }

  Future<void> _onSnooze(String taskId) async {
    try {
      // Add to the in-memory snooze set via TodayController.
      // TodayController.snoozeForSession() holds a Set<String> of excluded ids.
      final controller = _container.read(todayControllerProvider.notifier);
      controller.snoozeForSession(taskId);
    } catch (_) {
      // Non-fatal.
    }
  }
}
