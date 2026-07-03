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

import '../platform/alarms/alarm_scheduler.dart';
import '../providers.dart';
import 'theme.dart';

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
    // Hydrate the in-memory advisor tier so it matches persisted prefs,
    // even if the user never toggled the switch in this session.
    ref.read(advisorTierProvider.notifier).state =
        cloud ? AdvisorTier.cloud : AdvisorTier.lexi;
  }

  Future<void> _saveName(String value) async {
    await ref.read(settingsServiceProvider).setDisplayName(value);
    // Invalidate greeting provider so TodayScreen rebuilds.
    ref.invalidate(displayNameProvider);
  }

  Future<void> _toggleMorningBriefing(bool value) async {
    setState(() => _morningBriefing = value);
    await ref.read(settingsServiceProvider).setMorningBriefingEnabled(value);
    // Schedule or cancel the exact alarm to match the toggle.
    if (value) {
      await AlarmScheduler.scheduleMorning();
    } else {
      await AlarmScheduler.cancelMorning();
    }
  }

  Future<void> _toggleCloudGemini(bool value) async {
    if (value) {
      // Confirm before enabling — Cloud Gemini sends task context to Google.
      final confirmed = await _confirmCloudGemini();
      if (!confirmed) return;
    }
    setState(() => _cloudGemini = value);
    await ref.read(settingsServiceProvider).setCloudGeminiEnabled(value);
    // Immediately swap the live advisor so TodayController picks it up
    // without requiring an app restart.
    ref.read(advisorTierProvider.notifier).state =
        value ? AdvisorTier.cloud : AdvisorTier.lexi;
  }

  Future<bool> _confirmCloudGemini() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Enable Cloud Gemini?',
            style: AppTextStyles.titleMedium),
        content: Text(
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
            child: Text('Enable',
                style: TextStyle(color: AppColors.accent)),
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
        title: Text('Settings', style: AppTextStyles.titleMedium),
      ),
      body: _loading
          ? const SizedBox.shrink()
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
              children: [
                // ------------------------------------------------ Name
                _SectionLabel('About you'),
                const SizedBox(height: 8),
                _NameField(
                  controller: _nameController,
                  onSubmitted: _saveName,
                ),
                const SizedBox(height: 32),

                // ----------------------------------------- Notifications
                _SectionLabel('Notifications'),
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
                _SectionLabel('AI'),
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
        hintStyle: AppTextStyles.bodyMedium.copyWith(color: AppColors.textMuted),
        enabledBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: AppColors.surfaceVariant),
        ),
        focusedBorder: UnderlineInputBorder(
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
            activeColor: AppColors.accent,
            inactiveTrackColor: AppColors.surfaceVariant,
          ),
        ],
      ),
    );
  }
}
