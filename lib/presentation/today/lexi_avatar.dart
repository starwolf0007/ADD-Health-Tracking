import 'package:flutter/material.dart';

import 'package:neuroflow/presentation/theme.dart';

enum LexiVisualState { idle, focus, thinking, transition, success, evening }

class LexiAvatar extends StatefulWidget {
  final LexiVisualState visualState;
  final String assetPath;
  final double size;
  final String? semanticLabel;
  final bool subtleIdleAnimation;

  const LexiAvatar({
    super.key,
    required this.visualState,
    required this.assetPath,
    this.size = 48,
    this.semanticLabel,
    this.subtleIdleAnimation = false,
  });

  @override
  State<LexiAvatar> createState() => _LexiAvatarState();
}

class _LexiAvatarState extends State<LexiAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
      lowerBound: .97,
      upperBound: 1.03,
      value: 1,
    );
    if (widget.subtleIdleAnimation) _controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final icon = switch (widget.visualState) {
      LexiVisualState.focus => Icons.center_focus_strong_rounded,
      LexiVisualState.thinking => Icons.auto_awesome_rounded,
      LexiVisualState.transition => Icons.swap_horiz_rounded,
      LexiVisualState.success => Icons.check_rounded,
      LexiVisualState.evening => Icons.dark_mode_rounded,
      LexiVisualState.idle => Icons.blur_on_rounded,
    };
    return Semantics(
      image: true,
      label: widget.semanticLabel ?? 'Lexi companion',
      child: ScaleTransition(
        scale: _controller,
        child: ClipOval(
          child: SizedBox.square(
            dimension: widget.size,
            child: Image.asset(
              widget.assetPath,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.accentDim, AppColors.surfaceRaised],
                  ),
                ),
                child: Icon(icon,
                    color: AppColors.textPrimary, size: widget.size * .46),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
