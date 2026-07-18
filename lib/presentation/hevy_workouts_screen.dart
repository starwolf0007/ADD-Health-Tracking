import 'package:flutter/material.dart';
import 'package:neuroflow/presentation/health_integrations_screen.dart';
import 'package:neuroflow/presentation/hevy_workout_list.dart';
import 'package:neuroflow/presentation/theme.dart';

class HevyWorkoutsScreen extends StatelessWidget {
  static const routeName = '/health/workouts';

  const HevyWorkoutsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Workouts'),
        actions: [
          IconButton(
            key: const ValueKey('open-hevy-settings'),
            tooltip: 'Hevy settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                settings: const RouteSettings(
                  name: HealthIntegrationsScreen.routeName,
                ),
                builder: (_) => const HealthIntegrationsScreen(),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        children: const [
          Text('IMPORTED FROM HEVY', style: AppTextStyles.label),
          SizedBox(height: AppSpace.xs),
          Text(
            'Your latest synced workouts stay available on this device.',
            style: AppTextStyles.bodySmall,
          ),
          SizedBox(height: AppSpace.lg),
          HevyWorkoutList(),
        ],
      ),
    );
  }
}
