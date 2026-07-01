// lib/presentation/widgets/energy_glyph.dart
//
// PRESENTATION LAYER. Energy tags as flat monochrome glyphs, distinguished by
// SHAPE only (§13, locked v1.3). Color-coding these would create a second
// signal layer competing with the one action-accent — so every glyph here
// renders in the same neutral textSecondary tone, never the accent, never a
// per-tag color.

import 'package:flutter/material.dart';
import '../../domain/task.dart';
import '../theme.dart';

IconData _iconFor(EnergyTag tag) {
  switch (tag) {
    case EnergyTag.deepWork:
      return Icons.bolt_outlined;
    case EnergyTag.phone:
      return Icons.call_outlined;
    case EnergyTag.lowEnergy:
      return Icons.battery_2_bar_outlined;
    case EnergyTag.waiting:
      return Icons.hourglass_bottom_outlined;
  }
}

class EnergyGlyph extends StatelessWidget {
  final EnergyTag tag;
  final double size;

  const EnergyGlyph(this.tag, {super.key, this.size = 16});

  @override
  Widget build(BuildContext context) {
    return Icon(_iconFor(tag), size: size, color: AppColors.textSecondary);
  }
}
