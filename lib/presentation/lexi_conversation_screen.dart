import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:neuroflow/app/providers.dart';
import 'package:neuroflow/intelligence/lexi_response.dart';
import 'package:neuroflow/presentation/theme.dart';
import 'package:neuroflow/presentation/today/lexi_avatar.dart';
import 'package:neuroflow/presentation/widgets/lexi_proposal_card.dart';

class LexiConversationScreen extends ConsumerStatefulWidget {
  const LexiConversationScreen({super.key});

  @override
  ConsumerState<LexiConversationScreen> createState() =>
      _LexiConversationScreenState();
}

class _LexiConversationScreenState
    extends ConsumerState<LexiConversationScreen> {
  final _parser = const LexiResponseParser();
  LexiResponse? _response;
  String? _validationIssue;
  bool _confirming = false;

  void _loadDebugPreview(_LexiPreview preview) {
    final task = ref.read(todayControllerProvider).value?.primaryTask;
    if (task == null && preview != _LexiPreview.malformed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Add a task before previewing a suggestion.')),
      );
      return;
    }

    final raw = switch (preview) {
      _LexiPreview.start => jsonEncode({
          'dialogue': 'Your next step is ready when you are.',
          'contextUsedSummary': ['Recommended task: ${task!.title}'],
          'proposal': {
            'type': 'start_task',
            'payload': {'taskId': task.id},
            'requiresConfirmation': true,
            'confirmationPrompt': 'Start ${task.title}?',
          },
          'memoryCandidate': null,
        }),
      _LexiPreview.pause => jsonEncode({
          'dialogue': 'We can pause this without losing it.',
          'contextUsedSummary': ['Recommended task: ${task!.title}'],
          'proposal': {
            'type': 'pause_task',
            'payload': {'taskId': task.id},
            'requiresConfirmation': true,
            'confirmationPrompt': 'Pause ${task.title}?',
          },
          'memoryCandidate': null,
        }),
      _LexiPreview.reentry => jsonEncode({
          'dialogue': 'Let\'s preserve your exact restart point first.',
          'contextUsedSummary': ['Recommended task: ${task!.title}'],
          'proposal': {
            'type': 'create_reentry_note',
            'payload': {
              'taskId': task.id,
              'nextAction': 'Open the task and choose the first physical step.',
            },
            'requiresConfirmation': true,
            'confirmationPrompt':
                'Save that return point and pause ${task.title}?',
          },
          'memoryCandidate': null,
        }),
      _LexiPreview.malformed => '{not valid JSON',
    };
    final parsed = _parser.parseRaw(raw);
    setState(() {
      _response = parsed.response;
      _validationIssue = parsed.validationIssue;
    });
  }

  Future<void> _confirmProposal() async {
    final proposal = _response?.proposal;
    if (proposal == null || _confirming) return;
    setState(() => _confirming = true);
    try {
      await ref.read(lexiProposalActionHandlerProvider).confirm(proposal);
      if (!mounted) return;
      setState(() => _response = _copyWithProposal(_response!, null));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lexi\'s suggestion is applied.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not apply this suggestion: $error')),
      );
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  void _notNow() {
    if (_response == null) return;
    setState(() => _response = _copyWithProposal(_response!, null));
  }

  void _editProposal() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Editing suggestion details is the next Lexi step.'),
      ),
    );
  }

  LexiResponse _copyWithProposal(LexiResponse source, LexiProposal? proposal) {
    return LexiResponse(
      dialogue: source.dialogue,
      contextUsedSummary: source.contextUsedSummary,
      proposal: proposal,
      memoryCandidate: source.memoryCandidate,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lexi'),
        actions: [
          if (kDebugMode)
            PopupMenuButton<_LexiPreview>(
              tooltip: 'Preview safe Lexi responses',
              onSelected: _loadDebugPreview,
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: _LexiPreview.start,
                  child: Text('Preview start task'),
                ),
                PopupMenuItem(
                  value: _LexiPreview.pause,
                  child: Text('Preview pause task'),
                ),
                PopupMenuItem(
                  value: _LexiPreview.reentry,
                  child: Text('Preview save return point'),
                ),
                PopupMenuItem(
                  value: _LexiPreview.malformed,
                  child: Text('Preview malformed response'),
                ),
              ],
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(AppSpace.xxl),
        child: Column(
          children: [
            const LexiAvatar(
              visualState: LexiVisualState.idle,
              assetPath: 'assets/lexi/public/lexi-canonical-face.jpg',
              size: 72,
            ),
            const SizedBox(height: AppSpace.lg),
            Text(
              _response?.dialogue ??
                  'Lexi is available when you want a little clarity.',
              style: AppTextStyles.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpace.sm),
            Text(
              _validationIssue == null
                  ? 'Live conversation is not connected yet. Your plan still works without AI.'
                  : 'Lexi\'s response was safely ignored. Your plan is unchanged.',
              style: AppTextStyles.bodySmall,
              textAlign: TextAlign.center,
            ),
            if (_response?.contextUsedSummary.isNotEmpty ?? false) ...[
              const SizedBox(height: AppSpace.md),
              Text(
                'Using: ${_response!.contextUsedSummary.join(' · ')}',
                style: AppTextStyles.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
            if (_response?.proposal != null) ...[
              const SizedBox(height: AppSpace.lg),
              LexiProposalCard(
                proposal: _response!.proposal!,
                onConfirm: _confirming ? () {} : _confirmProposal,
                onEdit: _editProposal,
                onNotNow: _notNow,
              ),
            ],
            const Spacer(),
            const TextField(
              enabled: false,
              decoration: InputDecoration(
                hintText: 'Lexi is taking a quiet moment. Offline mode active.',
                prefixIcon: Icon(Icons.chat_bubble_outline),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _LexiPreview { start, pause, reentry, malformed }
