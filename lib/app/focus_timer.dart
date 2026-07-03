// lib/app/focus_timer.dart
//
// The time-blindness anchor (v2). One controller, app-wide:
// counts UP against a target ("this should take 15"), fires haptic
// milestones, flips to a kind overtime state — never a punishing one.
//
// Haptic contract (phone-side; Pixel Watch mirror is Phase W):
//   • start          -> selectionClick (handled by the caller)
//   • halfway        -> lightImpact, once
//   • 2 minutes left -> mediumImpact, once  ("focus" tap on the wrist, later)
//   • target crossed -> heavyImpact, once; phase -> overtime
//
// Overtime is information, not judgment: numerals go amber, copy stays kind.
//
// TODO(device): background nudge via NotificationService when the app is not
// foregrounded at the T-2 and target milestones (needs lifecycle wiring +
// on-device testing — Copilot, see NEUROFLOW-V2-DIRECTION.md).

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum FocusPhase { idle, running, overtime }

class FocusState {
  final String? taskId;
  final String taskTitle;
  final int targetMinutes;
  final Duration elapsed;
  final FocusPhase phase;

  const FocusState({
    this.taskId,
    this.taskTitle = '',
    this.targetMinutes = 15,
    this.elapsed = Duration.zero,
    this.phase = FocusPhase.idle,
  });

  static const idle = FocusState();

  bool get isActive => phase != FocusPhase.idle;

  Duration get target => Duration(minutes: targetMinutes);

  Duration get remaining {
    final r = target - elapsed;
    return r.isNegative ? Duration.zero : r;
  }

  Duration get overBy {
    final o = elapsed - target;
    return o.isNegative ? Duration.zero : o;
  }

  /// 0..1 progress toward target (clamps at 1 in overtime).
  double get progress {
    final t = target.inSeconds;
    if (t <= 0) return 1;
    final p = elapsed.inSeconds / t;
    return p > 1 ? 1 : p;
  }

  FocusState copyWith({
    Duration? elapsed,
    FocusPhase? phase,
  }) {
    return FocusState(
      taskId: taskId,
      taskTitle: taskTitle,
      targetMinutes: targetMinutes,
      elapsed: elapsed ?? this.elapsed,
      phase: phase ?? this.phase,
    );
  }
}

class FocusTimerController extends Notifier<FocusState> {
  Timer? _ticker;
  DateTime? _startedAt;
  bool _halfwayFired = false;
  bool _twoMinFired = false;
  bool _targetFired = false;

  @override
  FocusState build() {
    ref.onDispose(_cancelTicker);
    return FocusState.idle;
  }

  void start({
    required String taskId,
    required String taskTitle,
    int targetMinutes = 15,
  }) {
    _cancelTicker();
    _halfwayFired = false;
    _twoMinFired = false;
    _targetFired = false;
    _startedAt = DateTime.now();
    state = FocusState(
      taskId: taskId,
      taskTitle: taskTitle,
      targetMinutes: targetMinutes,
      elapsed: Duration.zero,
      phase: FocusPhase.running,
    );
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void stop() {
    _cancelTicker();
    _startedAt = null;
    state = FocusState.idle;
  }

  void _tick() {
    final startedAt = _startedAt;
    if (startedAt == null) return;

    final elapsed = DateTime.now().difference(startedAt);
    final target = state.target;

    // Milestones — each fires exactly once per session.
    if (!_halfwayFired && target.inSeconds >= 120 &&
        elapsed.inSeconds >= target.inSeconds ~/ 2 &&
        elapsed < target) {
      _halfwayFired = true;
      HapticFeedback.lightImpact();
    }

    final remaining = target - elapsed;
    if (!_twoMinFired &&
        target.inMinutes > 2 &&
        remaining.inSeconds <= 120 &&
        remaining.inSeconds > 0) {
      _twoMinFired = true;
      HapticFeedback.mediumImpact(); // "2 minutes left — focus."
    }

    var phase = state.phase;
    if (elapsed >= target) {
      phase = FocusPhase.overtime;
      if (!_targetFired) {
        _targetFired = true;
        HapticFeedback.heavyImpact();
      }
    }

    state = state.copyWith(elapsed: elapsed, phase: phase);
  }

  void _cancelTicker() {
    _ticker?.cancel();
    _ticker = null;
  }
}

final focusTimerProvider =
    NotifierProvider<FocusTimerController, FocusState>(
        FocusTimerController.new);

/// mm:ss formatter for live numerals (hours fold into minutes: 75:12).
String formatFocusClock(Duration d) {
  final m = d.inMinutes;
  final s = d.inSeconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}
