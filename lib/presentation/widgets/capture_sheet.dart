// lib/presentation/widgets/capture_sheet.dart
//
// PRESENTATION LAYER. §13's "capture reachable from anywhere in one gesture."
// One input, an energy row, a quick-win toggle, one Add button. Every screen
// opens THIS sheet via showCaptureSheet() — never fork a per-screen copy.
//
// PHASE NOTE: local NLP date parsing (§5 Rail 1) is phase 2. This sheet
// creates a plain Task with no due date; swapping in the parser later only
// touches _submit().

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/task.dart';
import '../theme.dart';
import 'energy_glyph.dart';

Future<void> showCaptureSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const _CaptureSheetBody(),
  );
}

class _CaptureSheetBody extends ConsumerStatefulWidget {
  const _CaptureSheetBody();

  @override
  ConsumerState<_CaptureSheetBody> createState() => _CaptureSheetBodyState();
}

class _CaptureSheetBodyState extends ConsumerState<_CaptureSheetBody> {
  final _controller = TextEditingController();
  EnergyLevel _energy = EnergyLevel.medium;
  bool _quickWin = false;
  bool _submitting = false;
  int? _estimate; // v2 focus-timer target, optional at capture

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final title = _controller.text.trim();
    if (title.isEmpty || _submitting) return;
    setState(() => _submitting = true);

    final task = Task.create(
      title: title,
      energy: _energy,
      isQuickWin: _quickWin || _energy == EnergyLevel.low,
      estimatedMinutes: _estimate,
    );
    await ref.read(taskRepositoryProvider).save(task);

    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Captured'), duration: Duration(seconds: 1)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpace.xl,
        AppSpace.md,
        AppSpace.xl,
        MediaQuery.of(context).viewInsets.bottom + AppSpace.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Grab handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: AppSpace.lg),
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          TextField(
            controller: _controller,
            autofocus: true,
            textInputAction: TextInputAction.done,
            textCapitalization: TextCapitalization.sentences,
            onSubmitted: (_) => _submit(),
            style: AppTextStyles.bodyMedium.copyWith(fontSize: 17),
            decoration: const InputDecoration(hintText: "What's on your mind?"),
          ),
          const SizedBox(height: AppSpace.lg),
          const Text('ENERGY TO START', style: AppTextStyles.label),
          const SizedBox(height: AppSpace.sm),
          Row(
            children: EnergyLevel.values.map((e) {
              final selected = e == _energy;
              return Padding(
                padding: const EdgeInsets.only(right: AppSpace.sm),
                child: _EnergyChip(
                  energy: e,
                  selected: selected,
                  onTap: () => setState(() => _energy = e),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: AppSpace.xs),
          // Quick-win toggle — feeds §QW auto-mode
          SwitchListTile.adaptive(
            value: _quickWin || _energy == EnergyLevel.low,
            onChanged: _energy == EnergyLevel.low
                ? null // low energy is always a quick win
                : (v) => setState(() => _quickWin = v),
            contentPadding: EdgeInsets.zero,
            activeThumbColor: AppColors.accent,
            title: const Text('Quick win', style: AppTextStyles.bodyMedium),
            subtitle: const Text(
              'Under ~5 minutes — eligible for lighter days',
              style: AppTextStyles.bodySmall,
            ),
          ),
          const SizedBox(height: AppSpace.sm),
          const Text('SHOULD TAKE (OPTIONAL)', style: AppTextStyles.label),
          const SizedBox(height: AppSpace.sm),
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: [
              for (final m in const [5, 15, 30, 60])
                _EstimateChip(
                  label: '$m min',
                  selected: _estimate == m,
                  onTap: () => setState(
                      () => _estimate = _estimate == m ? null : m),
                ),
            ],
          ),
          const SizedBox(height: AppSpace.lg),
          ElevatedButton(
            onPressed: _submitting ? null : _submit,
            child: Text(_submitting ? 'Adding…' : 'Add to today'),
          ),
        ],
      ),
    );
  }
}

/// Optional time estimate. Selecting one sets the focus-timer's first chip;
/// tapping the selected one clears it (no forced decision at capture).
class _EstimateChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _EstimateChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.accentWash : AppColors.surfaceVariant,
      borderRadius: BorderRadius.circular(AppSpace.radiusInput),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpace.radiusInput),
        child: Container(
          constraints: const BoxConstraints(minHeight: AppSpace.tapTarget),
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSpace.radiusInput),
            border: Border.all(
              color: selected ? AppColors.accent : Colors.transparent,
            ),
          ),
          child: Text(
            label,
            style: AppTextStyles.bodySmall.copyWith(
              color:
                  selected ? AppColors.textPrimary : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// Energy selector chip — shape glyph + label (§13 monochrome glyphs).
class _EnergyChip extends StatelessWidget {
  final EnergyLevel energy;
  final bool selected;
  final VoidCallback onTap;

  const _EnergyChip({
    required this.energy,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.accentWash : AppColors.surfaceVariant,
      borderRadius: BorderRadius.circular(AppSpace.radiusInput),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpace.radiusInput),
        child: Container(
          constraints: const BoxConstraints(minHeight: AppSpace.tapTarget),
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSpace.radiusInput),
            border: Border.all(
              color: selected ? AppColors.accent : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              EnergyGlyph(energy, size: 15),
              const SizedBox(width: 6),
              Text(
                energy.name,
                style: AppTextStyles.bodySmall.copyWith(
                  color: selected
                      ? AppColors.textPrimary
                      : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
