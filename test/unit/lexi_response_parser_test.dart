import 'package:flutter_test/flutter_test.dart';
import 'package:neuroflow/intelligence/lexi_response.dart';

void main() {
  const parser = LexiResponseParser();

  test('accepts a confirmed start-task proposal', () {
    final result = parser.parseRaw('''
      {
        "dialogue": "Your next step is ready.",
        "contextUsedSummary": ["Current task: Plan"],
        "proposal": {
          "type": "start_task",
          "payload": {"taskId": "task-1"},
          "requiresConfirmation": true,
          "confirmationPrompt": "Start the timer?"
        },
        "memoryCandidate": null
      }
    ''');

    expect(result.isValid, isTrue);
    expect(result.response.proposal?.type, LexiProposalType.startTask);
    expect(result.response.proposal?.payload['taskId'], 'task-1');
  });

  test('replaces dialogue when an unknown proposal could claim unsafe action',
      () {
    final result = parser.parseRaw('''
      {
        "dialogue": "I can help you think this through.",
        "proposal": {
          "type": "modify_config",
          "payload": {},
          "requiresConfirmation": true,
          "confirmationPrompt": "Apply this?"
        }
      }
    ''');

    expect(result.isValid, isFalse);
    expect(result.response.dialogue, contains('remain safe'));
    expect(result.response.proposal, isNull);
  });

  test('drops a proposal that does not require explicit confirmation', () {
    final result = parser.parseRaw('''
      {
        "dialogue": "Here is a suggestion.",
        "proposal": {
          "type": "pause_task",
          "payload": {"taskId": "task-1"},
          "requiresConfirmation": false,
          "confirmationPrompt": "Pause it?"
        }
      }
    ''');

    expect(result.isValid, isFalse);
    expect(result.response.proposal, isNull);
  });

  test('handles malformed JSON without throwing', () {
    final result = parser.parseRaw('{not valid json');

    expect(result.isValid, isFalse);
    expect(result.response.proposal, isNull);
    expect(result.response.dialogue, contains('remain safe'));
  });

  test('caps memory context to confirmed preferences and recent turns', () {
    final snapshot = LexiContextSnapshot(
      confirmedPreferences: const ['one', 'two', 'three', 'four'],
      recentHistory: List.generate(
        8,
        (index) => LexiConversationTurn(role: 'user', text: '$index'),
      ),
    );

    expect(snapshot.confirmedPreferences, ['one', 'two', 'three']);
    expect(snapshot.recentHistory.map((turn) => turn.text),
        ['2', '3', '4', '5', '6', '7']);
  });
}
