// Executive layer — pure day resolver for fixed blocks.
// Derived-not-stored. Priority: exception > holiday > recurrence.

enum ExceptionType { skip, force }

enum BlockKind { fixed, commute }

class RuleSpec {
  final String id;
  final String name;
  final Set<int> byDay;
  final int startMinutes;
  final int endMinutes;
  final int commuteBeforeMin;
  final int commuteAfterMin;
  final String? exclusionCalendarId;

  const RuleSpec({
    required this.id,
    required this.name,
    required this.byDay,
    required this.startMinutes,
    required this.endMinutes,
    this.commuteBeforeMin = 0,
    this.commuteAfterMin = 0,
    this.exclusionCalendarId,
  });
}

class ExceptionSpec {
  final String ruleId;
  final String date;
  final ExceptionType type;

  const ExceptionSpec({
    required this.ruleId,
    required this.date,
    required this.type,
  });
}

class ResolvedBlock {
  final BlockKind kind;
  final String label;
  final int startMinutes;
  final int endMinutes;
  final String sourceRuleId;

  const ResolvedBlock({
    required this.kind,
    required this.label,
    required this.startMinutes,
    required this.endMinutes,
    required this.sourceRuleId,
  });

  @override
  String toString() => '$label $startMinutes-$endMinutes ($kind)';
}

class InvalidScheduleRule implements Exception {
  final String ruleId;
  final String field;
  final Object value;
  final String reason;

  const InvalidScheduleRule({
    required this.ruleId,
    required this.field,
    required this.value,
    required this.reason,
  });

  @override
  String toString() =>
      'InvalidScheduleRule(rule: $ruleId, field: $field, value: $value): $reason';
}

void validateRule(RuleSpec rule) {
  if (rule.startMinutes < 0 ||
      rule.startMinutes >= rule.endMinutes ||
      rule.endMinutes > 1440) {
    throw InvalidScheduleRule(
      ruleId: rule.id,
      field: 'startMinutes/endMinutes',
      value: '${rule.startMinutes}-${rule.endMinutes}',
      reason: 'require 0 <= start < end <= 1440',
    );
  }
  if (rule.commuteBeforeMin < 0) {
    throw InvalidScheduleRule(
      ruleId: rule.id,
      field: 'commuteBeforeMin',
      value: rule.commuteBeforeMin,
      reason: 'must be >= 0',
    );
  }
  if (rule.commuteAfterMin < 0) {
    throw InvalidScheduleRule(
      ruleId: rule.id,
      field: 'commuteAfterMin',
      value: rule.commuteAfterMin,
      reason: 'must be >= 0',
    );
  }
  if (rule.startMinutes - rule.commuteBeforeMin < 0) {
    throw InvalidScheduleRule(
      ruleId: rule.id,
      field: 'commuteBeforeMin',
      value: rule.commuteBeforeMin,
      reason: 'commute pushes block before midnight',
    );
  }
  if (rule.endMinutes + rule.commuteAfterMin > 1440) {
    throw InvalidScheduleRule(
      ruleId: rule.id,
      field: 'commuteAfterMin',
      value: rule.commuteAfterMin,
      reason: 'commute pushes block past midnight',
    );
  }
}

String formatDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

List<ResolvedBlock> resolveDay({
  required DateTime day,
  required List<RuleSpec> rules,
  required List<ExceptionSpec> exceptions,
  required Map<String, Set<String>> holidayCalendars,
}) {
  final dateStr = formatDate(day);
  final blocks = <ResolvedBlock>[];

  for (final rule in rules) {
    validateRule(rule);

    ExceptionSpec? exception;
    for (final candidate in exceptions) {
      if (candidate.ruleId == rule.id && candidate.date == dateStr) {
        exception = candidate;
        break;
      }
    }

    final bool emit;
    if (exception != null) {
      emit = exception.type == ExceptionType.force;
    } else if (rule.exclusionCalendarId != null &&
        (holidayCalendars[rule.exclusionCalendarId]?.contains(dateStr) ??
            false)) {
      emit = false;
    } else {
      emit = rule.byDay.contains(day.weekday);
    }

    if (!emit) continue;

    if (rule.commuteBeforeMin > 0) {
      blocks.add(ResolvedBlock(
        kind: BlockKind.commute,
        label: 'Commute',
        startMinutes: rule.startMinutes - rule.commuteBeforeMin,
        endMinutes: rule.startMinutes,
        sourceRuleId: rule.id,
      ));
    }

    blocks.add(ResolvedBlock(
      kind: BlockKind.fixed,
      label: rule.name,
      startMinutes: rule.startMinutes,
      endMinutes: rule.endMinutes,
      sourceRuleId: rule.id,
    ));

    if (rule.commuteAfterMin > 0) {
      blocks.add(ResolvedBlock(
        kind: BlockKind.commute,
        label: 'Commute Home',
        startMinutes: rule.endMinutes,
        endMinutes: rule.endMinutes + rule.commuteAfterMin,
        sourceRuleId: rule.id,
      ));
    }
  }

  blocks.sort((a, b) => a.startMinutes.compareTo(b.startMinutes));
  return blocks;
}
