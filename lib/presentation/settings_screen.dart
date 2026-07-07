// lib/presentation/settings_screen.dart
//
// Settings screen — minimal by design.
//
// ADHD UX rationale:
//   • Four settings only (name, notifications, AI, privacy). Every additional
//     option is a decision the user has to make, and decisions cost dopamine.
//   • No "Advanced" section — if something needs to be hidden, it shouldn't
//     be in the settings screen at all.
//   • Name field is optional — app works fine without it (greeting stays neutral).
//   • Destructive actions (clear data) live here but require a confirmation tap.
//   • Privacy toggles (Cloud Gemini, Health Sync) are opt-in only — never on by default.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/google_connection_state.dart';
import '../domain/google_service.dart';
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
  bool _globalPrivacy = false;
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
    final privacy = await svc.getGlobalPrivacyEnabled();
    if (!mounted) return;
    setState(() {
      _nameController.text = name;
      _morningBriefing = briefing;
      _cloudGemini = cloud;
      _globalPrivacy = privacy;
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

  Future<void> _toggleGlobalPrivacy(bool value) async {
    setState(() => _globalPrivacy = value);
    await ref.read(settingsServiceProvider).setGlobalPrivacyEnabled(value);
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
                const SizedBox(height: 32),

                // ----------------------------------- Privacy & Sync
                _SectionLabel('Privacy & Sync'),
                const SizedBox(height: 8),
                _ToggleTile(
                  title: 'Health data sync',
                  subtitle:
                      'When enabled, Mood Logs will sync to Apple Health and Google Health. '
                      'Off by default.',
                  value: _globalPrivacy,
                  onChanged: _toggleGlobalPrivacy,
                ),
                const SizedBox(height: 32),

                // ----------------------------------- Connected Services
                _SectionLabel('Connected Services'),
                const SizedBox(height: 8),
                const _GoogleAccountTile(),
                const SizedBox(height: 12),
                const _MoreServicesList(),
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

// ---------------------------------------------------------------------------
// Connected Services (Google Foundation Sprint, Stage 6)
//
// This screen never imports google_sign_in or anything under
// lib/platform/google/ — only providers.dart (which watches/reads
// GoogleServiceManager) and the pure domain types it exposes.
// ---------------------------------------------------------------------------

/// "Google Account" row — the ONE functional action in this sprint's
/// Connected Services UI (connect()/disconnect()). Renders correctly with
/// zero crashes in the default disconnected state.
class _GoogleAccountTile extends ConsumerWidget {
  const _GoogleAccountTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectionAsync = ref.watch(googleConnectionStateProvider);

    return connectionAsync.when(
      data: (state) {
        switch (state.status) {
          case GoogleConnectionStatus.connecting:
            return const _GoogleAccountCard(
              title: 'Google Account',
              busy: true,
              subtitle: 'Connecting…',
            );
          case GoogleConnectionStatus.connected:
          case GoogleConnectionStatus.expired:
            return _GoogleAccountCard(
              title: 'Google Account',
              subtitle: state.email ?? 'Connected',
              warning: state.status == GoogleConnectionStatus.expired
                  ? 'Session may need reconnecting.'
                  : null,
              actionLabel: 'Disconnect',
              onAction: () =>
                  ref.read(googleServiceManagerProvider).disconnect(),
            );
          case GoogleConnectionStatus.disconnected:
          case GoogleConnectionStatus.error:
            final isError = state.status == GoogleConnectionStatus.error;
            return _GoogleAccountCard(
              title: 'Google Account',
              subtitle: isError && state.lastError != null
                  ? state.lastError!
                  : 'Connect to sync tasks and unlock more services.',
              isErrorSubtitle: isError,
              actionLabel: isError ? 'Retry' : 'Connect Google',
              onAction: () => ref.read(googleServiceManagerProvider).connect(),
            );
        }
      },
      // Riverpod StreamProvider loading/error states never surface here in
      // practice — GoogleServiceManager.watchConnectionState() seeds the
      // current state (disconnected by default) to every new listener — but
      // both are handled defensively so this screen never crashes.
      loading: () => const _GoogleAccountCard(
        title: 'Google Account',
        busy: true,
        subtitle: 'Connecting…',
      ),
      error: (_, __) => _GoogleAccountCard(
        title: 'Google Account',
        subtitle: 'Connect to sync tasks and unlock more services.',
        actionLabel: 'Connect Google',
        onAction: () => ref.read(googleServiceManagerProvider).connect(),
      ),
    );
  }
}

class _GoogleAccountCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool isErrorSubtitle;
  final bool busy;
  final String? warning;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _GoogleAccountCard({
    required this.title,
    required this.subtitle,
    this.isErrorSubtitle = false,
    this.busy = false,
    this.warning,
    this.actionLabel,
    this.onAction,
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
          if (busy) ...[
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(AppColors.accent),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTextStyles.bodyMedium),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: isErrorSubtitle
                        ? AppColors.warning
                        : AppColors.textMuted,
                  ),
                ),
                if (warning != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    warning!,
                    style: AppTextStyles.bodySmall
                        .copyWith(color: AppColors.warning),
                  ),
                ],
              ],
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(width: 12),
            TextButton(
              onPressed: onAction,
              child: Text(
                actionLabel!,
                style: TextStyle(color: AppColors.accent),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// "More services" list — every row is inert this sprint (every
/// GoogleServiceId is comingSoon). A tap logs friendly no-op interest via
/// GoogleServiceManager.enableService(); deliberately no snackbar/feedback
/// loop (ADHD-friendly: no dead-end feedback for an action with no visible
/// effect).
class _MoreServicesList extends ConsumerWidget {
  const _MoreServicesList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servicesAsync = ref.watch(connectedServicesProvider);

    return servicesAsync.when(
      data: (services) => Column(
        children: [
          for (var i = 0; i < services.length; i++) ...[
            _ComingSoonServiceTile(service: services[i]),
            if (i != services.length - 1) const SizedBox(height: 8),
          ],
        ],
      ),
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class _ComingSoonServiceTile extends ConsumerWidget {
  final ConnectedService service;

  const _ComingSoonServiceTile({required this.service});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        // Fire-and-forget: this sprint every service is comingSoon, so the
        // call always no-ops (returns false) — nothing to react to in the UI.
        ref.read(googleServiceManagerProvider).enableService(service.id);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      _serviceLabel(service.id),
                      style: AppTextStyles.bodyMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const _ComingSoonBadge(),
                ],
              ),
            ),
            const SizedBox(width: 12),
            IgnorePointer(
              child: Switch(
                value: false,
                onChanged: null,
                activeColor: AppColors.accent,
                inactiveTrackColor: AppColors.surfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _serviceLabel(GoogleServiceId id) => switch (id) {
        GoogleServiceId.tasks => 'Tasks',
        GoogleServiceId.calendar => 'Calendar',
        GoogleServiceId.drive => 'Drive',
        GoogleServiceId.gmail => 'Gmail',
        GoogleServiceId.contacts => 'Contacts',
        GoogleServiceId.healthConnect => 'Health Connect',
        GoogleServiceId.gemini => 'Gemini',
      };
}

class _ComingSoonBadge extends StatelessWidget {
  const _ComingSoonBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        'COMING SOON',
        style: AppTextStyles.monoSmall.copyWith(
          fontSize: 10,
          color: AppColors.textMuted,
        ),
      ),
    );
  }
}
