// lib/platform/wear/wear_sync_service.dart
//
// Pushes the current primary task to the Pixel Watch 4 via the
// Wearable Data Layer API (Android-native, accessed via platform channel).
//
// Design:
//   • Phone is always source of truth — watch only renders what phone pushes.
//   • DataMap is tiny: taskId, taskTitle (≤40 chars), quickWinCount,
//     pendingCount, pushedAt. No notes, no energy, no health data.
//   • No-ops gracefully if watch is unpaired or Data Layer unavailable.
//   • Called by TodayController after every TodayState change.
//
// Platform channel: 'neuroflow/wear'
//   Methods outbound (phone → watch via Data Layer):
//     pushPrimaryTask(Map)   — writes /neuroflow/primary DataItem
//   Methods inbound (watch → phone, listened via MessageClient):
//     Handled in WearActionHandler (separate class).

import 'package:flutter/services.dart';

import 'package:neuroflow/app/providers.dart'; // TodayState

const _kChannel = 'neuroflow/wear';
const _kMethodPush = 'pushPrimaryTask';

class WearSyncService {
  static const _channel = MethodChannel(_kChannel);

  /// Push current plan state to the watch.
  /// Truncates task title to 40 chars — watch tile has limited space.
  /// Silent no-op on any error (watch may be unpaired, Bluetooth off, etc.).
  Future<void> pushPrimaryTask(TodayState state) async {
    try {
      final title = state.primaryTask?.title ?? '';
      await _channel.invokeMethod<void>(_kMethodPush, {
        'taskId': state.primaryTask?.id ?? '',
        'taskTitle': title.length > 40 ? title.substring(0, 40) : title,
        'quickWinCount': state.quickWins.length,
        // pendingCount derived on phone side from task repo; passed via state
        // TODO(wear/phase1): pass pendingCount through TodayState or fetch here
        'pendingCount': state.quickWins.length + (state.primaryTask != null ? 1 : 0),
        'pushedAt': DateTime.now().millisecondsSinceEpoch,
        'hasPrimaryTask': state.primaryTask != null,
      });
    } on PlatformException catch (_) {
      // Watch not paired, Data Layer not available, etc. Non-fatal.
    } on MissingPluginException catch (_) {
      // Running on simulator or before native channel is wired. Non-fatal.
    }
  }
}
