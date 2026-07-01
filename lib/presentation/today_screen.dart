// lib/presentation/today_screen.dart
//
// PRESENTATION LAYER. Consumes app/providers.dart's todayControllerProvider —
// this screen has zero knowledge of Drift, Riverpod internals beyond `ref`,
// or how the deterministic/AI split works. It just renders a TodayState.
//
// §13 rules this screen is built against:
//  - one primary action per screen: the Next-Best-Action card's "Done" button
//    is THE unmistakable action. The capture FAB is a separate, always-present
//    affordance (its own locked rule), not a competing primary action.
//  - depth hidden by default: no nav bar, no settings, no stats here — just
//    today. (Other destinations are a future, deliberately minor, addition.)
//  - capture reachable from anywhere in one gesture: persistent FAB -> sheet.
//  - motion confirms state, never performs: HeartbeatLine only animates on
//    value change; nothing on this screen idles.
//  - dark/restrained palette, one accent: see theme.dart, used exclusively.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../domain/task.dart';
import 'theme.dart';
import 'widgets/capture_sheet.dart';
import 'widgets/energy_glyph.dart';
import 'widgets/heartbeat_line.dart';

class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final todayAsync = ref.watch(todayControllerProvider);
    final completedToday = ref.watch(completedTodayCountProvider).value ?? 0;
    final openCount =
        ref.watch(openTasksProvider).value?.length ?? 0;
    final heartbeatValue = (completedToday + openCount) == 0
        ? 0.0
        : completedToday / (completedToday + openCount);

    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: FloatingActionButton(
        onPressed: () => showCaptureSheet(context, ref),
        child: const Icon(Icons.add),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              Text(
                _greeting(),
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 14),
              HeartbeatLine(value: heartbeatValue),
              const SizedBox(height: 28),
              Expanded(
                child: todayAsync.when(
                  loading: () => const _CalmLoading(),
                  error: (e, st) => _ErrorState(error: e),
                  data: (state) => _TodayBody(state: state),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return "Good morning.";
    if (h < 17) return "Good afternoon.";
    return "Good evening.";
  }
}

class _TodayBody extends ConsumerWidget {
  final TodayState state;
  const _TodayBody({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (state.mode == TodayMode.quickWins) {
      return _QuickWinsView(state: state);
    }
    return _NormalView(state: state);
  }
}

/// Normal mode: one Next-Best-Action card. THE primary action of this screen.
class _NormalView extends ConsumerWidget {
  final TodayState state;
  const _NormalView({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final primary = state.primary;
    if (primary == null) {
      return Center(
        child: Text(
          state.reason, // "Today's clear."
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(state.reason, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 10),
        _NextActionCard(task: primary),
      ],
    );
  }
}

class _NextActionCard extends ConsumerWidget {
  final Task task;
  const _NextActionCard({required this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (task.energy != null) ...[
            EnergyGlyph(task.energy!),
            const SizedBox(height: 10),
          ],
          Text(task.title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () =>
                  ref.read(todayControllerProvider.notifier).complete(task.id),
              child: const Text("Done"),
            ),
          ),
        ],
      ),
    );
  }
}

/// Quick Wins mode (§6, automatic mode-swap — locked v1.3/v1.4). Capped list,
/// no separate screen, no toggle. Status label says so plainly; the
/// reassurance line is the close, not an afterthought.
class _QuickWinsView extends ConsumerWidget {
  final TodayState state;
  const _QuickWinsView({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.accent.withOpacity(0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            "Lighter day",
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: AppColors.accent, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 16),
        if (state.items.isEmpty)
          Text(state.reason, style: Theme.of(context).textTheme.bodyMedium)
        else ...[
          for (final task in state.items) ...[
            _QuickWinRow(task: task),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 10),
          Text(
            "Nothing else is tracked today.",
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}

class _QuickWinRow extends ConsumerWidget {
  final Task task;
  const _QuickWinRow({required this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => ref.read(todayControllerProvider.notifier).complete(task.id),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.accent, width: 1.5),
              ),
            ),
            const SizedBox(width: 12),
            if (task.energy != null) ...[
              EnergyGlyph(task.energy!, size: 14),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(task.title,
                  style: Theme.of(context).textTheme.titleMedium),
            ),
          ],
        ),
      ),
    );
  }
}

class _CalmLoading extends StatelessWidget {
  const _CalmLoading();

  @override
  Widget build(BuildContext context) {
    // No spinner-as-decoration — a quiet, static placeholder. The data layer
    // is local-first and fast; this state should be visible for milliseconds.
    return const SizedBox.shrink();
  }
}

class _ErrorState extends StatelessWidget {
  final Object error;
  const _ErrorState({required this.error});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        "Something didn't load. Try reopening.",
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }
}
