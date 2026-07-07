// lib/app/achievements.dart
//
// Light gamification trial layer (§-trial).
// Built to be explicitly reversible. No persisted state, no score.
// A moment fires once and is gone.

import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum AchievementKind {
  /// "You came back and finished it. That's the hard part."
  /// Fired when a task that was previously paused or blocked is completed.
  reEntryCompleted,
}

/// Kill switch for the entire achievement layer.
final achievementsEnabledProvider = StateProvider<bool>((ref) => true);

/// Internal event bus for achievements.
class AchievementBus {
  AchievementBus._();
  static final instance = AchievementBus._();

  final _controller = StreamController<AchievementKind>.broadcast();
  Stream<AchievementKind> get stream => _controller.stream;

  void fire(AchievementKind kind) {
    _controller.add(kind);
  }
}

/// Stream of fired achievements for the UI to consume.
final achievementStreamProvider = StreamProvider<AchievementKind>((ref) {
  return AchievementBus.instance.stream;
});

/// Helper to fire an achievement moment from a provider.
void fireAchievement(Ref ref, AchievementKind kind) {
  if (!ref.read(achievementsEnabledProvider)) return;
  AchievementBus.instance.fire(kind);
}
