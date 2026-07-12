// lib/presentation/widgets/achievement_toast.dart
//
// Minimal gold toast for achievement moments (§-trial).
// Auto-dismisses after 3 seconds.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuroflow/app/achievements.dart';
import 'package:neuroflow/presentation/theme.dart';

class AchievementToastHost extends ConsumerStatefulWidget {
  final Widget child;

  const AchievementToastHost({super.key, required this.child});

  @override
  ConsumerState<AchievementToastHost> createState() =>
      _AchievementToastHostState();
}

class _AchievementToastHostState extends ConsumerState<AchievementToastHost> {
  final List<AchievementKind> _activeToasts = [];

  @override
  Widget build(BuildContext context) {
    ref.listen(achievementStreamProvider, (previous, next) {
      if (next.hasValue) {
        _showToast(next.value!);
      }
    });

    return Stack(
      children: [
        widget.child,
        if (_activeToasts.isNotEmpty)
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: AppSpace.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: _activeToasts
                      .map((kind) => _AchievementToast(
                            kind: kind,
                            onDismiss: () =>
                                setState(() => _activeToasts.remove(kind)),
                          ))
                      .toList(),
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _showToast(AchievementKind kind) {
    setState(() => _activeToasts.add(kind));
    Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() => _activeToasts.remove(kind));
      }
    });
  }
}

class _AchievementToast extends StatelessWidget {
  final AchievementKind kind;
  final VoidCallback onDismiss;

  const _AchievementToast({required this.kind, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final (title, subtitle) = switch (kind) {
      AchievementKind.reEntryCompleted => (
          "RE-ENTRY COMPLETE",
          "You came back and finished it. That's the hard part."
        ),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpace.sm),
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.lg, vertical: AppSpace.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(AppSpace.radiusCard),
        border: Border.all(color: AppColors.gold, width: 1),
        boxShadow: [
          BoxShadow(
            color: AppColors.gold.withValues(alpha: 0.2),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.stars, color: AppColors.gold, size: 20),
          const SizedBox(width: AppSpace.md),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title,
                  style: AppTextStyles.label.copyWith(color: AppColors.gold)),
              Text(subtitle,
                  style: AppTextStyles.bodySmall
                      .copyWith(color: AppColors.textPrimary)),
            ],
          ),
        ],
      ),
    );
  }
}
