import 'package:flutter/material.dart';

import 'package:neuroflow/intelligence/lexi_response.dart';
import 'package:neuroflow/presentation/theme.dart';

class LexiProposalCard extends StatelessWidget {
  final LexiProposal proposal;
  final VoidCallback? onConfirm;
  final VoidCallback onEdit;
  final VoidCallback onNotNow;

  const LexiProposalCard({
    super.key,
    required this.proposal,
    required this.onConfirm,
    required this.onEdit,
    required this.onNotNow,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Lexi suggestion: ${proposal.confirmationPrompt}',
      child: Container(
        padding: const EdgeInsets.all(AppSpace.lg),
        decoration: BoxDecoration(
          color: AppColors.surfaceRaised,
          borderRadius: BorderRadius.circular(AppSpace.radiusCard),
          border: Border.all(color: AppColors.accent.withValues(alpha: .35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Lexi suggests', style: AppTextStyles.label),
            const SizedBox(height: AppSpace.sm),
            Text(proposal.confirmationPrompt, style: AppTextStyles.bodyMedium),
            const SizedBox(height: AppSpace.md),
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.sm,
              children: [
                FilledButton(
                  onPressed: onConfirm,
                  child: const Text('Confirm'),
                ),
                OutlinedButton(
                  onPressed: onEdit,
                  child: const Text('Edit'),
                ),
                TextButton(
                  onPressed: onNotNow,
                  child: const Text('Not now'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
