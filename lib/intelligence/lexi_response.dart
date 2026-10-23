import 'dart:convert';

enum LexiProposalType {
  startTask,
  pauseTask,
  createTaskDraft,
  createRoutineDraft,
  createReentryNote,
  setReminderDraft,
  preparePhoneCall,
  reduceInputMode,
  breakDownTaskDraft,
}

extension LexiProposalTypeWireName on LexiProposalType {
  String get wireName => switch (this) {
        LexiProposalType.startTask => 'start_task',
        LexiProposalType.pauseTask => 'pause_task',
        LexiProposalType.createTaskDraft => 'create_task_draft',
        LexiProposalType.createRoutineDraft => 'create_routine_draft',
        LexiProposalType.createReentryNote => 'create_reentry_note',
        LexiProposalType.setReminderDraft => 'set_reminder_draft',
        LexiProposalType.preparePhoneCall => 'prepare_phone_call',
        LexiProposalType.reduceInputMode => 'reduce_input_mode',
        LexiProposalType.breakDownTaskDraft => 'break_down_task_draft',
      };

  static LexiProposalType? fromWireName(String value) {
    for (final type in LexiProposalType.values) {
      if (type.wireName == value) return type;
    }
    return null;
  }
}

class LexiConversationTurn {
  final String role;
  final String text;

  const LexiConversationTurn({required this.role, required this.text});

  Map<String, String> toJson() => {'role': role, 'text': text};
}

class LexiContextSnapshot {
  final String? currentPlace;
  final Map<String, Object?>? activeTaskOrRoutine;
  final Map<String, Object?>? nextAnchor;
  final String? pausedTaskReentryNote;
  final List<String> confirmedPreferences;
  final List<LexiConversationTurn> recentHistory;

  LexiContextSnapshot({
    this.currentPlace,
    this.activeTaskOrRoutine,
    this.nextAnchor,
    this.pausedTaskReentryNote,
    List<String> confirmedPreferences = const [],
    List<LexiConversationTurn> recentHistory = const [],
  })  : confirmedPreferences = List.unmodifiable(
          confirmedPreferences.take(3),
        ),
        recentHistory = List.unmodifiable(
          recentHistory.length <= 6
              ? recentHistory
              : recentHistory.sublist(recentHistory.length - 6),
        );

  Map<String, Object?> toJson() => {
        'currentPlace': currentPlace,
        'activeTaskOrRoutine': activeTaskOrRoutine,
        'nextAnchor': nextAnchor,
        'pausedTaskReentryNote': pausedTaskReentryNote,
        'confirmedPreferences': confirmedPreferences,
        'recentHistory': recentHistory.map((turn) => turn.toJson()).toList(),
      };
}

class LexiTaskBreakdownStep {
  final String title;
  final int? estimatedMinutes;

  const LexiTaskBreakdownStep({
    required this.title,
    this.estimatedMinutes,
  });
}

class LexiTaskBreakdownDraft {
  final String? taskId;
  final String title;
  final List<LexiTaskBreakdownStep> steps;
  final int suggestedFirstStepIndex;
  final int? totalEstimatedMinutes;
  final String strategy;

  LexiTaskBreakdownDraft({
    this.taskId,
    required this.title,
    required List<LexiTaskBreakdownStep> steps,
    required this.suggestedFirstStepIndex,
    this.totalEstimatedMinutes,
    required this.strategy,
  }) : steps = List.unmodifiable(steps);
}

class LexiProposal {
  final LexiProposalType type;
  final Map<String, Object?> payload;
  final String confirmationPrompt;
  final LexiTaskBreakdownDraft? taskBreakdownDraft;

  const LexiProposal({
    required this.type,
    required this.payload,
    required this.confirmationPrompt,
    this.taskBreakdownDraft,
  });
}

class LexiMemoryCandidate {
  final String text;
  final String reason;

  const LexiMemoryCandidate({required this.text, required this.reason});
}

class LexiResponse {
  final String dialogue;
  final List<String> contextUsedSummary;
  final LexiProposal? proposal;
  final LexiMemoryCandidate? memoryCandidate;

  const LexiResponse({
    required this.dialogue,
    this.contextUsedSummary = const [],
    this.proposal,
    this.memoryCandidate,
  });
}

class LexiResponseParseResult {
  final LexiResponse response;
  final String? validationIssue;

  const LexiResponseParseResult({
    required this.response,
    this.validationIssue,
  });

  bool get isValid => validationIssue == null;
}

class LexiResponseParser {
  static const _fallbackDialogue =
      'Lexi\'s response could not be parsed. Your tasks and local data remain safe.';
  static const _maxStepTitleLength = 120;
  static const _maxEstimatedMinutes = 480;
  const LexiResponseParser();

  LexiResponseParseResult parseRaw(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return _fallback('Response was not a JSON object.');
      return parseMap(Map<String, Object?>.from(decoded));
    } catch (_) {
      return _fallback('Response was not valid JSON.');
    }
  }

  LexiResponseParseResult parseMap(Map<String, Object?> raw) {
    final dialogue =
        raw['dialogue'] is String ? (raw['dialogue'] as String).trim() : '';
    final safeDialogue = dialogue.isEmpty ? _fallbackDialogue : dialogue;
    final summary = _stringList(raw['contextUsedSummary']);

    try {
      final proposal = _parseProposal(raw['proposal']);
      final candidate = _parseMemoryCandidate(raw['memoryCandidate']);
      return LexiResponseParseResult(
        response: LexiResponse(
          dialogue: safeDialogue,
          contextUsedSummary: summary,
          proposal: proposal,
          memoryCandidate: candidate,
        ),
      );
    } catch (error) {
      return LexiResponseParseResult(
        response: LexiResponse(
          dialogue: _fallbackDialogue,
          contextUsedSummary: summary,
        ),
        validationIssue: error.toString(),
      );
    }
  }

  LexiResponseParseResult _fallback(String issue) => LexiResponseParseResult(
        response: const LexiResponse(dialogue: _fallbackDialogue),
        validationIssue: issue,
      );

  LexiProposal? _parseProposal(Object? value) {
    if (value == null) return null;
    if (value is! Map) {
      throw const FormatException('Proposal was not an object.');
    }
    final map = Map<String, Object?>.from(value);
    final typeName = map['type'];
    if (typeName is! String) {
      throw const FormatException('Proposal type missing.');
    }
    final type = LexiProposalTypeWireName.fromWireName(typeName);
    if (type == null) throw FormatException('Unknown proposal type: $typeName');
    if (map['requiresConfirmation'] != true) {
      throw const FormatException('Proposal requires explicit confirmation.');
    }
    final prompt = map['confirmationPrompt'];
    if (prompt is! String || prompt.trim().isEmpty) {
      throw const FormatException('Proposal confirmation prompt missing.');
    }
    final payloadValue = map['payload'];
    if (payloadValue is! Map) {
      throw const FormatException('Proposal payload missing.');
    }
    final payload = Map<String, Object?>.from(payloadValue);
    final taskBreakdownDraft = _validatePayload(type, payload);
    return LexiProposal(
      type: type,
      payload: payload,
      confirmationPrompt: prompt.trim(),
      taskBreakdownDraft: taskBreakdownDraft,
    );
  }

  LexiMemoryCandidate? _parseMemoryCandidate(Object? value) {
    if (value == null) return null;
    if (value is! Map) {
      throw const FormatException('Memory candidate was not an object.');
    }
    final map = Map<String, Object?>.from(value);
    final text = map['text'];
    final reason = map['reason'];
    if (text is! String ||
        text.trim().isEmpty ||
        reason is! String ||
        reason.trim().isEmpty) {
      throw const FormatException('Memory candidate was incomplete.');
    }
    return LexiMemoryCandidate(text: text.trim(), reason: reason.trim());
  }

  List<String> _stringList(Object? value) {
    if (value is! Iterable) return const [];
    return value
        .whereType<String>()
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .take(3)
        .toList();
  }

  LexiTaskBreakdownDraft? _validatePayload(
    LexiProposalType type,
    Map<String, Object?> payload,
  ) {
    switch (type) {
      case LexiProposalType.startTask:
      case LexiProposalType.pauseTask:
        _requiredString(payload, 'taskId');
        return null;
      case LexiProposalType.createTaskDraft:
        _requiredString(payload, 'title');
        return null;
      case LexiProposalType.createRoutineDraft:
        _requiredString(payload, 'name');
        return null;
      case LexiProposalType.createReentryNote:
        _requiredString(payload, 'taskId');
        _requiredString(payload, 'nextAction');
        return null;
      case LexiProposalType.setReminderDraft:
        _requiredString(payload, 'title');
        _requiredString(payload, 'remindAt');
        return null;
      case LexiProposalType.preparePhoneCall:
        _requiredString(payload, 'title');
        return null;
      case LexiProposalType.reduceInputMode:
        return null;
      case LexiProposalType.breakDownTaskDraft:
        return _parseTaskBreakdown(payload);
    }
  }

  LexiTaskBreakdownDraft _parseTaskBreakdown(Map<String, Object?> payload) {
    final title = _requiredString(payload, 'title');
    final taskId = _optionalString(payload, 'taskId');
    final rawSteps = payload['steps'];
    if (rawSteps is! List || rawSteps.length < 2 || rawSteps.length > 7) {
      throw const FormatException('Task breakdown must contain 2 to 7 steps.');
    }

    final steps = <LexiTaskBreakdownStep>[];
    for (final rawStep in rawSteps) {
      if (rawStep is! Map) {
        throw const FormatException('Task breakdown step was not an object.');
      }
      final step = Map<String, Object?>.from(rawStep);
      if (step.containsKey('steps') || step.containsKey('subtasks')) {
        throw const FormatException('Nested task breakdown steps are not supported.');
      }
      final stepTitle = _requiredString(step, 'title');
      if (stepTitle.length > _maxStepTitleLength) {
        throw const FormatException('Task breakdown step title is too long.');
      }
      final estimate = _boundedPositiveInt(
        step['estimatedMinutes'],
        'estimatedMinutes',
        required: false,
      );
      steps.add(
        LexiTaskBreakdownStep(
          title: stepTitle,
          estimatedMinutes: estimate,
        ),
      );
    }

    final firstStepIndex = _boundedPositiveInt(
      payload['suggestedFirstStepIndex'],
      'suggestedFirstStepIndex',
      allowZero: true,
      required: true,
    )!;
    if (firstStepIndex >= steps.length) {
      throw const FormatException('Suggested first step index is out of range.');
    }

    final totalEstimate = _boundedPositiveInt(
      payload['totalEstimatedMinutes'],
      'totalEstimatedMinutes',
      required: false,
    );
    final strategy = _optionalString(payload, 'strategy') ?? 'activation_first';
    if (strategy != 'activation_first') {
      throw const FormatException('Unsupported task breakdown strategy.');
    }

    return LexiTaskBreakdownDraft(
      taskId: taskId,
      title: title,
      steps: steps,
      suggestedFirstStepIndex: firstStepIndex,
      totalEstimatedMinutes: totalEstimate,
      strategy: strategy,
    );
  }

  String _requiredString(Map<String, Object?> payload, String key) {
    final value = payload[key];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('Missing $key in proposal payload.');
    }
    return value.trim();
  }

  String? _optionalString(Map<String, Object?> payload, String key) {
    final value = payload[key];
    if (value == null) return null;
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('Invalid $key in proposal payload.');
    }
    return value.trim();
  }

  int? _boundedPositiveInt(
    Object? value,
    String key, {
    required bool required,
    bool allowZero = false,
  }) {
    if (value == null) {
      if (required) throw FormatException('Missing $key in proposal payload.');
      return null;
    }
    if (value is! int || value < (allowZero ? 0 : 1)) {
      throw FormatException('Invalid $key in proposal payload.');
    }
    if (key != 'suggestedFirstStepIndex' && value > _maxEstimatedMinutes) {
      throw FormatException('$key exceeds the supported maximum.');
    }
    return value;
  }
}
