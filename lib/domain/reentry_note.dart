class ReentryNote {
  final String? lastCompletedStep;
  final String? nextAction;
  final DateTime? returnAt;
  final DateTime updatedAt;

  const ReentryNote({
    this.lastCompletedStep,
    this.nextAction,
    this.returnAt,
    required this.updatedAt,
  });

  bool get isEmpty =>
      (lastCompletedStep == null || lastCompletedStep!.isEmpty) &&
      (nextAction == null || nextAction!.isEmpty) &&
      returnAt == null;
}
