import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuroflow/intelligence/lexi_response.dart';
import 'package:neuroflow/presentation/theme.dart';
import 'package:neuroflow/presentation/widgets/lexi_proposal_card.dart';

void main() {
  testWidgets('proposal card exposes Confirm, Edit, and Not now',
      (tester) async {
    var confirmed = false;
    var edited = false;
    var deferred = false;
    const proposal = LexiProposal(
      type: LexiProposalType.startTask,
      payload: {'taskId': 'task-1'},
      confirmationPrompt: 'Start the timer?',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: LexiProposalCard(
            proposal: proposal,
            onConfirm: () => confirmed = true,
            onEdit: () => edited = true,
            onNotNow: () => deferred = true,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Confirm'));
    await tester.tap(find.text('Edit'));
    await tester.tap(find.text('Not now'));

    expect(confirmed, isTrue);
    expect(edited, isTrue);
    expect(deferred, isTrue);
  });
}
