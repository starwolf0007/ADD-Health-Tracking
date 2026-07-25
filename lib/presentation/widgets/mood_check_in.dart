// lib/presentation/widgets/mood_check_in.dart
//
// The 5-point mood check-in — the Quick Wins entry signal (spec §6).
//
// §13: the 1..5 score is storage only. This surface shows the labels
// (Rough / Low / Okay / Good / Great) and never a number.
// §2.8: mood is on-device only. This writes through MoodRepository and
// nothing else — no sync, no push, no cloud advisor.
// §6: entry and exit are automatic. Tapping a level records how the day is
// going; it is not a switch for the mode itself, and there is no control here
// to turn Quick Wins on or off.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:neuroflow/app/providers.dart';
import 'package:neuroflow/domain/mood.dart';
import 'package:neuroflow/presentation/theme.dart';

class MoodCheckInStrip extends ConsumerStatefulWidget {
  const MoodCheckInStrip({super.key});

  @override
  ConsumerState<MoodCheckInStrip> createState() => _MoodCheckInStripState();
}

class _MoodCheckInStripState extends ConsumerState<MoodCheckInStrip> {
  /// Set when the user reopens an already-answered check-in to change it.
  /// §6 exits Quick Wins when a better check-in lands, so revising has to stay
  /// possible all day.
  bool _reopened = false;
  bool _submitting = false;

  Future<void> _log(MoodLevel level) async {
    if (_submitting) return;
    setState(() => _submitting = true);

    try {
      await ref.read(moodRepositoryProvider).log(MoodLog.create(level));
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save your check-in.')),
      );
      return;
    }

    // TodayController reads its streams once per build, so the reshaped plan
    // only arrives if the controller is invalidated. Without this the mood
    // persists but Today keeps its previous shape — on a rough day, that is
    // the one interaction the user is least likely to go and trigger himself.
    ref.invalidate(todayControllerProvider);

    if (!mounted) return;
    setState(() {
      _submitting = false;
      _reopened = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ref.watch(todayMoodProvider).when(
          // Nothing to say until the answer is known; rendering the prompt
          // first would make it jump to the summary a frame later.
          loading: () => const SizedBox.shrink(),
          // Safe no-op — a check-in that cannot be read must not block Today.
          error: (_, __) => const SizedBox.shrink(),
          data: (log) {
            if (log == null || _reopened) {
              return _MoodPrompt(
                current: log?.level,
                submitting: _submitting,
                onSelected: _log,
              );
            }
            return _MoodSummary(
              level: log.level,
              onReopen: () => setState(() => _reopened = true),
            );
          },
        );
  }
}

class _MoodPrompt extends StatelessWidget {
  final MoodLevel? current;
  final bool submitting;
  final ValueChanged<MoodLevel> onSelected;

  const _MoodPrompt({
    required this.current,
    required this.submitting,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("HOW'S TODAY GOING?", style: AppTextStyles.label),
        const SizedBox(height: AppSpace.sm),
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          children: [
            for (final level in MoodLevel.values)
              ChoiceChip(
                key: Key('moodChip_${level.name}'),
                label: Text(level.label),
                selected: level == current,
                onSelected:
                    submitting ? null : (_) => onSelected(level),
              ),
          ],
        ),
      ],
    );
  }
}

class _MoodSummary extends StatelessWidget {
  final MoodLevel level;
  final VoidCallback onReopen;

  const _MoodSummary({required this.level, required this.onReopen});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: const Key('moodSummary'),
      onTap: onReopen,
      borderRadius: BorderRadius.circular(AppSpace.radiusInput),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Checked in · ${level.label}',
              style: AppTextStyles.bodySmall,
            ),
            const SizedBox(width: AppSpace.xs),
            const Icon(
              Icons.expand_more,
              size: 16,
              color: AppColors.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}
