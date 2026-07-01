// lib/presentation/widgets/heartbeat_line.dart
//
// PRESENTATION LAYER. The Today "heartbeat" status line (§13, locked v1.3):
// a STATIC fill that updates only on a state transition. No idle or ambient
// animation — that was an explicit correction in the design cross-check (the
// original mockup's continuously-pulsing line was flagged as a §13 violation).
//
// Implementation note: TweenAnimationBuilder only re-animates when its `tween`
// target changes between rebuilds. There is no AnimationController driving a
// repeating/looping animation here — that's what guarantees no idle motion.

import 'package:flutter/material.dart';
import '../theme.dart';

class HeartbeatLine extends StatelessWidget {
  /// 0.0–1.0. Caller computes this from real data (completed / total) —
  /// never a placeholder.
  final double value;

  const HeartbeatLine({super.key, required this.value});

  @override
  Widget build(BuildContext context) {
    final clamped = value.clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: Container(
        height: 3,
        color: AppColors.divider,
        alignment: Alignment.centerLeft,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: clamped),
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOut,
          builder: (context, animatedValue, _) {
            return FractionallySizedBox(
              widthFactor: animatedValue,
              child: Container(color: AppColors.accent),
            );
          },
        ),
      ),
    );
  }
}
