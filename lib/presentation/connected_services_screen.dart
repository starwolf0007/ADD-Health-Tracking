// lib/presentation/connected_services_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:neuroflow/app/providers.dart';
import 'package:neuroflow/domain/google/connected_services_repository.dart';
import 'package:neuroflow/domain/google/google_account.dart';
import 'package:neuroflow/platform/error_reporter.dart';
import 'package:neuroflow/platform/google/google_service_manager.dart';
import 'package:neuroflow/presentation/theme.dart';

class ConnectedServicesScreen extends ConsumerWidget {
  const ConnectedServicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountAsync = ref.watch(googleAccountProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textSecondary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title:
            const Text('Connected Services', style: AppTextStyles.titleMedium),
      ),
      body: accountAsync.when(
        data: (account) => ListView(
          padding: const EdgeInsets.all(AppSpace.xl),
          children: [
            _GoogleAccountTile(account: account),
            const SizedBox(height: AppSpace.xxl),
            const _SectionHeader(title: 'Integrations'),
            const SizedBox(height: AppSpace.md),
            const _ServiceTile(
              title: 'Google Tasks',
              icon: Icons.check_circle_outline,
              status: 'Coming Soon',
              service: GoogleService.tasks,
              isAvailable: false,
            ),
            const _ServiceTile(
              title: 'Google Calendar',
              icon: Icons.calendar_today_outlined,
              status: 'Coming Soon',
              service: GoogleService.calendar,
              isAvailable: false,
            ),
            const _ServiceTile(
              title: 'Google Drive',
              icon: Icons.cloud_outlined,
              status: 'Coming Soon',
              service: GoogleService.drive,
              isAvailable: false,
            ),
            const _ServiceTile(
              title: 'Health Connect',
              icon: Icons.favorite_outline,
              status: 'Coming Soon',
              service: GoogleService.healthConnect,
              isAvailable: false,
            ),
            const _ServiceTile(
              title: 'Gemini AI',
              icon: Icons.auto_awesome_outlined,
              status: 'Coming Soon',
              service: GoogleService.gemini,
              isAvailable: false,
            ),
            const _ServiceTile(
              title: 'Gmail',
              icon: Icons.email_outlined,
              status: 'Coming Soon',
              service: GoogleService.gmail,
              isAvailable: false,
            ),
            const _ServiceTile(
              title: 'Contacts',
              icon: Icons.contacts_outlined,
              status: 'Coming Soon',
              service: GoogleService.contacts,
              isAvailable: false,
            ),
          ],
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) =>
            const Center(child: Text('Google account status is unavailable.')),
      ),
    );
  }
}

class _GoogleAccountTile extends ConsumerWidget {
  final GoogleAccount? account;

  const _GoogleAccountTile({required this.account});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final manager = ref.read(googleServiceManagerProvider);

    return Container(
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpace.radiusCard),
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: AppColors.surfaceVariant,
                backgroundImage: (account?.photoUrl != null)
                    ? NetworkImage(account!.photoUrl!)
                    : null,
                child: account == null
                    ? const Icon(Icons.person_outline,
                        color: AppColors.textMuted)
                    : null,
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      account?.displayName ??
                          (account == null
                              ? 'Not Connected'
                              : 'Google Account'),
                      style: AppTextStyles.titleMedium,
                    ),
                    if (account != null)
                      Text(
                        account!.email,
                        style: AppTextStyles.bodySmall
                            .copyWith(color: AppColors.textMuted),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.lg),
          if (account == null)
            ElevatedButton(
              onPressed: () => _runAction(
                context,
                () async {
                  await manager.signIn();
                },
                'Google sign-in failed.',
              ),
              child: const Text('Connect Google Account'),
            )
          else
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => _runAction(
                      context,
                      manager.switchAccount,
                      'Google account switching failed.',
                    ),
                    child: const Text('Switch Account'),
                  ),
                ),
                Expanded(
                  child: TextButton(
                    onPressed: () => _confirmSignOut(context, manager),
                    child: const Text('Sign Out',
                        style: TextStyle(color: Colors.redAccent)),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _runAction(
    BuildContext context,
    Future<void> Function() action,
    String errorMessage,
  ) async {
    try {
      await action();
    } catch (error, stackTrace) {
      reportNonFatalError(errorMessage, error, stackTrace);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessage)),
      );
    }
  }

  void _confirmSignOut(
    BuildContext context,
    GoogleServiceManager manager,
  ) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceRaised,
        title: const Text('Disconnect Google?'),
        content: const Text(
            'This will stop all cloud synchronization. Your local data will remain safe.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _runAction(
                context,
                manager.signOut,
                'Google sign-out failed.',
              );
            },
            child: const Text('Disconnect',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title.toUpperCase(),
      style: AppTextStyles.label.copyWith(color: AppColors.textMuted),
    );
  }
}

class _ServiceTile extends StatelessWidget {
  final String title;
  final IconData icon;
  final String status;
  final GoogleService service;
  final bool isAvailable;

  const _ServiceTile({
    required this.title,
    required this.icon,
    required this.status,
    required this.service,
    required this.isAvailable,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: isAvailable ? 1.0 : 0.5,
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.sm),
        child: ListTile(
          leading: Icon(icon,
              color: isAvailable ? AppColors.accent : AppColors.textMuted),
          title: Text(title, style: AppTextStyles.bodyMedium),
          subtitle: Text(status,
              style:
                  AppTextStyles.bodySmall.copyWith(color: AppColors.textMuted)),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSpace.radiusInput)),
          tileColor: AppColors.surface,
          trailing: const Switch(
            value: false,
            onChanged: null, // Disabled in Sprint 1
            activeThumbColor: AppColors.accent,
          ),
        ),
      ),
    );
  }
}
