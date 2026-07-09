// lib/presentation/settings_screen.dart
//
// Settings screen — minimal by design.
//
// ADHD UX rationale:
//   • Three settings only. Every additional option is a decision the user
//     has to make, and decisions cost dopamine.
//   • No "Advanced" section — if something needs to be hidden, it shouldn't
//     be in the settings screen at all.
//   • Name field is optional — app works fine without it (greeting stays neutral).
//   • Destructive actions (clear data) live here but require a confirmation tap.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:neuroflow/platform/alarms/alarm_scheduler.dart';
import 'package:neuroflow/app/providers.dart';
import 'package:neuroflow/platform/error_reporter.dart';
import 'package:neuroflow/presentation/connected_services_screen.dart';
import 'package:neuroflow/presentation/theme.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _nameController = TextEditingController();
  bool _morningBriefing = true;
  bool _cloudGemini = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final svc = ref.read(settingsServiceProvider);
      final name = await svc.getDisplayName();
      final briefing = await svc.getMorningBriefingEnabled();
      final cloud = await svc.getCloudGeminiEnabled();
      if (!mounted) return;
      setState(() {
        _nameController.text = name;
        _morningBriefing = briefing;
        _cloudGemini = cloud;
        _loading = false;
      });
      ref
          .read(advisorTierProvider.notifier)
          .set(cloud ? AdvisorTier.cloud : AdvisorTier.lexi);
    } catch (error, stackTrace) {
      reportNonFatalError('Failed to load settings', error, stackTrace);
      if (!mounted) return;
      setState(() => _loading = false);
      _showError('Settings could not be loaded.');
    }
  }

  Future<void> _saveName(String value) async {
    try {
      await ref.read(settingsServiceProvider).setDisplayName(value);
      ref.invalidate(displayNameProvider);
    } catch (error, stackTrace) {
      reportNonFatalError('Failed to save display name', error, stackTrace);
      if (mounted) _showError('Your name could not be saved.');
    }
  }

  Future<void> _toggleMorningBriefing(bool value) async {
    final previous = _morningBriefing;
    setState(() => _morningBriefing = value);
    try {
      final settings = ref.read(settingsServiceProvider);
      await settings.setMorningBriefingEnabled(value);
      if (value) {
        await AlarmScheduler.scheduleMorning();
      } else {
        await AlarmScheduler.cancelMorning();
      }
    } catch (error, stackTrace) {
      reportNonFatalError(
        'Failed to update morning briefing setting',
        error,
        stackTrace,
      );
      try {
        await ref
            .read(settingsServiceProvider)
            .setMorningBriefingEnabled(previous);
      } catch (rollbackError, rollbackStackTrace) {
        reportNonFatalError(
          'Failed to restore morning briefing setting',
          rollbackError,
          rollbackStackTrace,
        );
      }
      if (!mounted) return;
      setState(() => _morningBriefing = previous);
      _showError('Morning briefing could not be updated.');
    }
  }

  Future<void> _toggleCloudGemini(bool value) async {
    if (value) {
      // Confirm before enabling — Cloud Gemini sends task context to Google.
      final confirmed = await _confirmCloudGemini();
      if (!confirmed) return;
    }
    final previous = _cloudGemini;
    setState(() => _cloudGemini = value);
    try {
      await ref.read(settingsServiceProvider).setCloudGeminiEnabled(value);
      ref
          .read(advisorTierProvider.notifier)
          .set(value ? AdvisorTier.cloud : AdvisorTier.lexi);
    } catch (error, stackTrace) {
      reportNonFatalError(
        'Failed to update Cloud Gemini setting',
        error,
        stackTrace,
      );
      if (!mounted) return;
      setState(() => _cloudGemini = previous);
      _showError('Cloud Gemini could not be updated.');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<bool> _confirmCloudGemini() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Enable Cloud Gemini?',
            style: AppTextStyles.titleMedium),
        content: const Text(
          'Task titles and descriptions will be sent to Google for AI suggestions. '
          'No health data, energy logs, or personal notes are shared. '
          'You can turn this off at any time.',
          style: AppTextStyles.bodySmall,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child:
                const Text('Enable', style: TextStyle(color: AppColors.accent)),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textSecondary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Settings', style: AppTextStyles.titleMedium),
      ),
      body: _loading
          ? const SizedBox.shrink()
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
              children: [
                // ------------------------------------------------ Name
                const _SectionLabel('About you'),
                const SizedBox(height: 8),
                _NameField(
                  controller: _nameController,
                  onSubmitted: _saveName,
                ),
                const SizedBox(height: 32),

                // ----------------------------------------- Connections
                const _SectionLabel('Integrations'),
                const SizedBox(height: 8),
                ListTile(
                  leading: const Icon(Icons.cloud_sync_outlined,
                      color: AppColors.accent),
                  title: const Text('Connected Services',
                      style: AppTextStyles.bodyMedium),
                  subtitle: const Text('Google Tasks, Calendar, and more',
                      style: AppTextStyles.bodySmall),
                  trailing: const Icon(Icons.chevron_right,
                      size: 20, color: AppColors.textMuted),
                  tileColor: AppColors.surface,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const ConnectedServicesScreen()),
                  ),
                ),
                const SizedBox(height: 32),

                // ----------------------------------------- Notifications
                const _SectionLabel('Notifications'),
                const SizedBox(height: 8),
                _ToggleTile(
                  title: 'Morning briefing',
                  subtitle:
                      'A quiet nudge each morning showing how many tasks are waiting.',
                  value: _morningBriefing,
                  onChanged: _toggleMorningBriefing,
                ),
                const SizedBox(height: 32),

                // -------------------------------------------- AI (§14)
                const _SectionLabel('AI'),
                const SizedBox(height: 8),
                _ToggleTile(
                  title: 'Cloud Gemini suggestions',
                  subtitle:
                      'Sends task titles to Google for smarter suggestions. '
                      'Off by default. Health data never shared.',
                  value: _cloudGemini,
                  onChanged: _toggleCloudGemini,
                ),
              ],
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sub-widgets
// ---------------------------------------------------------------------------

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: AppTextStyles.monoSmall.copyWith(
        color: AppColors.textMuted,
        letterSpacing: 1.2,
      ),
    );
  }
}

class _NameField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onSubmitted;

  const _NameField({
    required this.controller,
    required this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      style: AppTextStyles.bodyMedium,
      cursorColor: AppColors.accent,
      decoration: InputDecoration(
        hintText: 'Your first name (optional)',
        hintStyle:
            AppTextStyles.bodyMedium.copyWith(color: AppColors.textMuted),
        enabledBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: AppColors.surfaceVariant),
        ),
        focusedBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: AppColors.accent),
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
      ),
      onSubmitted: onSubmitted,
      onEditingComplete: () => onSubmitted(controller.text),
      textInputAction: TextInputAction.done,
    );
  }
}

class _ToggleTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTextStyles.bodyMedium),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: AppTextStyles.bodySmall
                      .copyWith(color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: AppColors.accent,
            inactiveTrackColor: AppColors.surfaceVariant,
          ),
        ],
      ),
    );
  }
}
