import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:neuroflow/intelligence/lexi_response.dart';

void main() {
  const parser = LexiResponseParser();

  group('Gemini Lexi V2 scenario contract', () {
    test('accepts confirmed start, pause, and re-entry proposals', () {
      final scenarios = [
        _response(
          dialogue: 'You have a focused window.',
          type: 'start_task',
          payload: const {'taskId': '11111111-2222-3333-4444-555555555555'},
        ),
        _response(
          dialogue: 'Let us pause here before dinner.',
          type: 'pause_task',
          payload: const {'taskId': '77777777-8888-9999-0000-111111111111'},
        ),
        _response(
          dialogue: 'Let us preserve the restart point.',
          type: 'create_reentry_note',
          payload: const {
            'taskId': '33333333-4444-5555-6666-777777777777',
            'nextAction': 'Adjust the cooling parameters.',
          },
        ),
      ];

      for (final raw in scenarios) {
        final result = parser.parseRaw(raw);
        expect(result.isValid, isTrue);
        expect(result.response.proposal, isNotNull);
        expect(result.response.proposal!.confirmationPrompt, isNotEmpty);
      }
    });

    test('accepts guilt-free Not now responses with no proposal', () {
      const raw =
          '{"dialogue":"Completely fine. It can wait.","proposal":null}';

      final result = parser.parseRaw(raw);

      expect(result.isValid, isTrue);
      expect(result.response.proposal, isNull);
      expect(result.response.dialogue, contains('Completely fine'));
    });

    test('rejects unsafe unknown proposal types and hides unsafe dialogue', () {
      final raw = _response(
        dialogue: 'Let me update your YAML files directly.',
        type: 'modify_config',
        payload: const {'targetFile': 'bedtime_shutdown.yaml'},
      );

      final result = parser.parseRaw(raw);

      expect(result.isValid, isFalse);
      expect(result.response.proposal, isNull);
      expect(result.response.dialogue, contains('remain safe'));
      expect(result.response.dialogue, isNot(contains('update your YAML')));
    });

    test('rejects a start proposal that omits the task identifier', () {
      final raw = _response(
        dialogue: 'I can start the timer right now.',
        type: 'start_task',
        payload: const {},
      );

      final result = parser.parseRaw(raw);

      expect(result.isValid, isFalse);
      expect(result.response.proposal, isNull);
      expect(result.response.dialogue, contains('remain safe'));
    });
  });
}

String _response({
  required String dialogue,
  required String type,
  required Map<String, Object> payload,
}) =>
    jsonEncode({
      'dialogue': dialogue,
      'proposal': {
        'type': type,
        'payload': payload,
        'requiresConfirmation': true,
        'confirmationPrompt': 'Confirm this suggestion?',
      },
    });
