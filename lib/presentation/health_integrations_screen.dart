import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuroflow/app/hevy_integration_controller.dart';
import 'package:neuroflow/app/hevy_providers.dart';
import 'package:neuroflow/data/hevy_repository.dart';
import 'package:neuroflow/presentation/theme.dart';

class HealthIntegrationsScreen extends ConsumerStatefulWidget {
  static const routeName = '/settings/health-integrations';

  const HealthIntegrationsScreen({super.key});

  @override
  ConsumerState<HealthIntegrationsScreen> createState() =>
      _HealthIntegrationsScreenState();
}

class _HealthIntegrationsScreenState
    extends ConsumerState<HealthIntegrationsScreen> {
  final _keyController = TextEditingController();

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final integration = ref.watch(hevyIntegrationControllerProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Health Integrations')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        children: [
          integration.when(
            loading: () => const _LoadingCard(),
            error: (_, __) => const _SafeStartupError(),
            data: (state) => _HevyCard(
              state: state,
              keyController: _keyController,
              onConnect: () {
                final key = _keyController.text;
                _keyController.clear();
                FocusScope.of(context).unfocus();
                ref
                    .read(hevyIntegrationControllerProvider.notifier)
                    .connect(key);
              },
              onSync: () => ref
                  .read(hevyIntegrationControllerProvider.notifier)
                  .syncNow(),
              onDisconnect: _confirmDisconnect,
            ),
          ),
          const SizedBox(height: 28),
          const Text('RECENT WORKOUTS', style: AppTextStyles.label),
          const SizedBox(height: 10),
          const _RecentWorkouts(),
        ],
      ),
    );
  }

  Future<void> _confirmDisconnect() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Disconnect Hevy?'),
        content: const Text(
          'The saved Hevy credential will be removed. Imported workouts will remain stored locally. Future syncs require reconnecting.',
          style: AppTextStyles.bodySmall,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep connected'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(hevyIntegrationControllerProvider.notifier).disconnect();
    }
  }
}

class _HevyCard extends StatelessWidget {
  final HevyIntegrationState state;
  final TextEditingController keyController;
  final VoidCallback onConnect;
  final VoidCallback onSync;
  final VoidCallback onDisconnect;

  const _HevyCard({
    required this.state,
    required this.keyController,
    required this.onConnect,
    required this.onSync,
    required this.onDisconnect,
  });

  @override
  Widget build(BuildContext context) {
    final busy = state.status == HevyUiStatus.verifying ||
        state.status == HevyUiStatus.syncing;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpace.radiusCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Hevy', style: AppTextStyles.titleMedium),
              ),
              _StatusLabel(state: state),
            ],
          ),
          const SizedBox(height: 12),
          if (!state.isConnected) ...[
            const Text(
              'A Hevy Pro API key is required. It is stored securely on this device.',
              style: AppTextStyles.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('hevyApiKeyField'),
              controller: keyController,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              enabled: !busy,
              decoration: const InputDecoration(
                labelText: 'API key',
                hintText: 'Paste your key',
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              key: const Key('hevyConnectButton'),
              onPressed: busy ? null : onConnect,
              child: Text(busy ? 'Verifying…' : 'Connect'),
            ),
          ] else ...[
            Text(
              '${state.importedWorkoutCount} imported ${state.importedWorkoutCount == 1 ? 'workout' : 'workouts'}',
              style: AppTextStyles.bodyMedium,
            ),
            const SizedBox(height: 4),
            Text(
              state.lastSuccessfulSync == null
                  ? 'No completed sync yet'
                  : 'Last synced ${_localDateTime(state.lastSuccessfulSync!)}',
              style: AppTextStyles.bodySmall,
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  key: const Key('hevySyncButton'),
                  onPressed: busy ? null : onSync,
                  child: Text(
                    state.status == HevyUiStatus.syncing
                        ? 'Syncing…'
                        : 'Sync now',
                  ),
                ),
                TextButton(
                  key: const Key('hevyDisconnectButton'),
                  onPressed: busy ? null : onDisconnect,
                  child: const Text('Disconnect'),
                ),
              ],
            ),
          ],
          if (state.message != null) ...[
            const SizedBox(height: 12),
            Text(state.message!, style: AppTextStyles.bodySmall),
          ],
        ],
      ),
    );
  }
}

class _StatusLabel extends StatelessWidget {
  final HevyIntegrationState state;
  const _StatusLabel({required this.state});

  @override
  Widget build(BuildContext context) {
    final label = switch (state.status) {
      HevyUiStatus.notConnected => 'Not connected',
      HevyUiStatus.verifying => 'Verifying',
      HevyUiStatus.connected => 'Connected',
      HevyUiStatus.syncing => 'Syncing',
      HevyUiStatus.syncComplete => 'Sync complete',
      HevyUiStatus.error => 'Error',
    };
    return Text(
      label,
      style: AppTextStyles.bodySmall.copyWith(
        color: state.status == HevyUiStatus.error
            ? AppColors.warning
            : AppColors.accent,
      ),
    );
  }
}

class _RecentWorkouts extends ConsumerWidget {
  const _RecentWorkouts();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(recentHevyWorkoutsProvider).when(
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ),
          ),
          error: (_, __) => const Text(
            'Recent workouts aren’t available right now.',
            style: AppTextStyles.bodySmall,
          ),
          data: (workouts) => workouts.isEmpty
              ? const Text(
                  'No imported workouts yet.',
                  style: AppTextStyles.bodySmall,
                )
              : Column(
                  children: workouts
                      .map((workout) => _WorkoutTile(workout: workout))
                      .toList(growable: false),
                ),
        );
  }
}

class _WorkoutTile extends StatelessWidget {
  final HevyWorkoutSummary workout;
  const _WorkoutTile({required this.workout});

  @override
  Widget build(BuildContext context) {
    final minutes = workout.duration.inMinutes;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  workout.title,
                  style: AppTextStyles.bodyMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  '${_localDate(workout.startTime)} · $minutes min',
                  style: AppTextStyles.bodySmall,
                ),
              ],
            ),
          ),
          Text(
            '${workout.exerciseCount} exercises\n${workout.setCount} sets',
            textAlign: TextAlign.right,
            style: AppTextStyles.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();
  @override
  Widget build(BuildContext context) => const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(),
        ),
      );
}

class _SafeStartupError extends StatelessWidget {
  const _SafeStartupError();
  @override
  Widget build(BuildContext context) => const Text(
        'Hevy settings aren’t available right now.',
        style: AppTextStyles.bodySmall,
      );
}

String _localDate(DateTime value) {
  final date = value.toLocal();
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[date.month - 1]} ${date.day}, ${date.year}';
}

String _localDateTime(DateTime value) {
  final date = value.toLocal();
  final minute = date.minute.toString().padLeft(2, '0');
  return '${_localDate(date)} at ${date.hour}:$minute';
}
