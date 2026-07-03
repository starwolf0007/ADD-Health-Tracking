// lib/presentation/widgets/energy_glyph.dart
//
// PRESENTATION LAYER. Energy shown as flat monochrome glyphs, distinguished
// by SHAPE only (§13, locked v1.3). Colour-coding these would create a
// second signal layer competing with the one action-accent.
//
// ⚠ RECONCILIATION NOTE (see RECONCILIATION.md, decision #1):
// Spec §13 locks FOUR energy tags (deep-work · phone · low-energy · waiting),
// but lib/domain/task.dart currently models EnergyLevel {low, medium, high}.
// This widget compiles against the CURRENT domain so the app builds today.
// When the domain migrates to EnergyTag, only the switch below changes —
// no screen files need touching.

import 'package:flutter/material.dart';
import '../../domain/task.dart';
import '../theme.dart';

class EnergyGlyph extends StatelessWidget {
  final EnergyLevel energy;
  final double size;

  /// When true, renders "low energy" etc. next to the glyph.
  final bool showLabel;

  const EnergyGlyph(
    this.energy, {
    super.key,
    this.size = 18,
    this.showLabel = false,
  });

  (IconData, String) get _glyph => switch (energy) {
        // Shapes chosen to stay distinct at 16px in peripheral vision.
        EnergyLevel.low => (Icons.battery_2_bar_outlined, 'low energy'),
        EnergyLevel.medium => (Icons.circle_outlined, 'medium energy'),
        EnergyLevel.high => (Icons.bolt_outlined, 'high energy'),
      };

  @override
  Widget build(BuildContext context) {
    final (icon, label) = _glyph;
    final glyph = Icon(icon, size: size, color: AppColors.textSecondary);

    if (!showLabel) return Semantics(label: label, child: glyph);

    return Semantics(
      label: label,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          glyph,
          const SizedBox(width: 6),
          Text(label, style: AppTextStyles.bodySmall),
        ],
      ),
    );
  }
}
