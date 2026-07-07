// lib/presentation/widgets/energy_glyph.dart

import 'package:flutter/material.dart';
import '../../domain/task.dart';
import '../theme.dart';

class EnergyGlyph extends StatelessWidget {
  final EnergyLevel energy;
  final double size;

  const EnergyGlyph(this.energy, {super.key, this.size = 16});

  @override
  Widget build(BuildContext context) {
    final icon = switch (energy) {
      EnergyLevel.low => Icons.remove,
      EnergyLevel.medium => Icons.circle_outlined,
      EnergyLevel.high => Icons.keyboard_arrow_up,
    };
    return Icon(icon, size: size, color: AppColors.textSecondary);
  }
}
