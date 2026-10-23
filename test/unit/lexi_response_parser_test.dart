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

  test('accepts a typed task-breakdown draft', () {
    final result = parser.parseRaw('''
      {
        "dialogue": "That task is too big as written. Here is a starting path.",
        "proposal": {
          "type": "break_down_task_draft",
          "requiresConfirmation": true,
          "confirmationPrompt": "Use these steps?",
          "payload": {
            "taskId": "garage-1",
            "title": "Clean the garage",
            "steps": [
              {"title": "Get one trash bag and one empty bin", "estimatedMinutes": 3},
              {"title": "Throw away the obvious trash", "estimatedMinutes": 10},
              {"title": "Clear one shelf", "estimatedMinutes": 15}
            ],
            "suggestedFirstStepIndex": 0,
            "totalEstimatedMinutes": 28,
            "strategy": "activation_first"
          }
        }
      }
    ''');

    expect(result.isValid, isTrue);
    final proposal = result.response.proposal;
    expect(proposal?.type, LexiProposalType.breakDownTaskDraft);
    expect(proposal?.taskBreakdownDraft?.taskId, 'garage-1');
    expect(proposal?.taskBreakdownDraft?.title, 'Clean the garage');
    expect(proposal?.taskBreakdownDraft?.steps, hasLength(3));
    expect(
      proposal?.taskBreakdownDraft?.steps.first.title,
      'Get one trash bag and one empty bin',
    );
    expect(proposal?.taskBreakdownDraft?.suggestedFirstStepIndex, 0);
    expect(proposal?.taskBreakdownDraft?.strategy, 'activation_first');
  });

  test('rejects task breakdowns with fewer than two steps', () {
    final result = parser.parseRaw('''
      {
        "dialogue": "I made the change.",
        "proposal": {
          "type": "break_down_task_draft",
          "requiresConfirmation": true,
          "confirmationPrompt": "Use this step?",
          "payload": {
            "title": "Clean the garage",
            "steps": [{"title": "Get a trash bag"}],
            "suggestedFirstStepIndex": 0,
            "strategy": "activation_first"
          }
        }
      }
    ''');

    expect(result.isValid, isFalse);
    expect(result.response.proposal, isNull);
    expect(result.response.dialogue, contains('remain safe'));
  });

  test('rejects nested task breakdown steps', () {
    final result = parser.parseRaw('''
      {
        "dialogue": "Here are the steps.",
        "proposal": {
          "type": "break_down_task_draft",
          "requiresConfirmation": true,
          "confirmationPrompt": "Use these steps?",
          "payload": {
            "title": "Clean the garage",
            "steps": [
              {"title": "Sort tools", "subtasks": [{"title": "Find hammer"}]},
              {"title": "Sweep the floor"}
            ],
            "suggestedFirstStepIndex": 0,
            "strategy": "activation_first"
          }
        }
      }
    ''');

    expect(result.isValid, isFalse);
    expect(result.response.proposal, isNull);
  });

  test('rejects an out-of-range suggested first step', () {
    final result = parser.parseRaw('''
      {
        "dialogue": "Here are the steps.",
        "proposal": {
          "type": "break_down_task_draft",
          "requiresConfirmation": true,
          "confirmationPrompt": "Use these steps?",
          "payload": {
            "title": "Clean the garage",
            "steps": [
              {"title": "Get a trash bag"},
              {"title": "Throw away obvious trash"}
            ],
            "suggestedFirstStepIndex": 2,
            "strategy": "activation_first"
          }
        }
      }
    ''');

    expect(result.isValid, isFalse);
    expect(result.response.proposal, isNull);
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
