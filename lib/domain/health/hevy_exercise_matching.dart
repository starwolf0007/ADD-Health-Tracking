import 'dart:math' as math;

const noExerciseMatch = 'NO_MATCH';

enum ExerciseCorpusSource {
  catalog,
  routine,
  workout,
  synthetic,
  manual,
}

enum ExerciseCorpusLabelStatus {
  confirmed,
  needsReview,
}

class ExerciseTemplateTarget {
  final String id;
  final String title;

  const ExerciseTemplateTarget({
    required this.id,
    required this.title,
  });
}

class ExerciseCorpusRow {
  final String input;
  final String expectedTemplateId;
  final ExerciseCorpusSource source;
  final String canonicalTitle;
  final ExerciseCorpusLabelStatus labelStatus;

  const ExerciseCorpusRow({
    required this.input,
    required this.expectedTemplateId,
    required this.source,
    required this.canonicalTitle,
    required this.labelStatus,
  });

  bool get isConfirmed => labelStatus == ExerciseCorpusLabelStatus.confirmed;
}

class ExerciseMatchCandidate {
  final ExerciseTemplateTarget template;
  final double score;

  const ExerciseMatchCandidate({
    required this.template,
    required this.score,
  });
}

class ExerciseCalibrationResult {
  final ExerciseCorpusRow row;
  final double? correctScore;
  final ExerciseMatchCandidate? bestMatch;
  final ExerciseMatchCandidate? bestWrongMatch;

  const ExerciseCalibrationResult({
    required this.row,
    required this.correctScore,
    required this.bestMatch,
    required this.bestWrongMatch,
  });
}

class ExerciseCalibrationReport {
  final double threshold;
  final double margin;
  final double highestWrongScore;
  final bool hasWrongMatchEvidence;
  final int labeledRowCount;
  final int autoResolvedCount;
  final int reviewCount;
  final int wrongAutoResolveCount;
  final List<ExerciseCalibrationResult> results;

  const ExerciseCalibrationReport({
    required this.threshold,
    required this.margin,
    required this.highestWrongScore,
    required this.hasWrongMatchEvidence,
    required this.labeledRowCount,
    required this.autoResolvedCount,
    required this.reviewCount,
    required this.wrongAutoResolveCount,
    required this.results,
  });

  double get autoResolveRate =>
      labeledRowCount == 0 ? 0 : autoResolvedCount / labeledRowCount;
}

/// Deterministic baseline matcher used by the corpus calibration tool.
///
/// Production matching must reuse this scorer (or recalibrate the replacement)
/// so the measured false-positive guarantee still applies.
class HevyExerciseMatcher {
  const HevyExerciseMatcher();

  List<ExerciseMatchCandidate> rank(
    String input,
    List<ExerciseTemplateTarget> catalog,
  ) {
    final candidates = catalog
        .map(
          (template) => ExerciseMatchCandidate(
            template: template,
            score: score(input, template.title),
          ),
        )
        .toList(growable: false)
      ..sort((left, right) {
        final scoreOrder = right.score.compareTo(left.score);
        if (scoreOrder != 0) return scoreOrder;
        return left.template.id.compareTo(right.template.id);
      });
    return candidates;
  }

  ExerciseTemplateTarget? resolve(
    String input,
    List<ExerciseTemplateTarget> catalog, {
    required double threshold,
  }) {
    final ranked = rank(input, catalog);
    if (ranked.isEmpty || ranked.first.score < threshold) return null;

    // A tie at the threshold is ambiguous and must go to review.
    if (ranked.length > 1 &&
        ranked[1].score == ranked.first.score &&
        ranked[1].score >= threshold) {
      return null;
    }
    return ranked.first.template;
  }

  double score(String input, String canonicalTitle) {
    final left = normalizeExerciseName(input);
    final right = normalizeExerciseName(canonicalTitle);
    if (left.isEmpty || right.isEmpty) return 0;
    if (left == right) return 1;

    final leftTokens = left.split(' ').toSet();
    final rightTokens = right.split(' ').toSet();
    final shared = leftTokens.intersection(rightTokens).length;
    final union = leftTokens.union(rightTokens).length;
    final tokenJaccard = union == 0 ? 0.0 : shared / union;
    final editSimilarity = _normalizedEditSimilarity(left, right);

    // Token equality ignores harmless equipment-prefix reordering while the
    // edit score rewards conventional word order.
    final tokenScore =
        leftTokens.length == rightTokens.length && shared == union
            ? 0.98
            : tokenJaccard;
    return math.max(editSimilarity, tokenScore).clamp(0.0, 1.0);
  }
}

ExerciseCalibrationReport calibrateExerciseMatcher({
  required List<ExerciseCorpusRow> rows,
  required List<ExerciseTemplateTarget> catalog,
  double margin = 0.01,
  HevyExerciseMatcher matcher = const HevyExerciseMatcher(),
}) {
  if (margin <= 0) {
    throw RangeError.value(margin, 'margin', 'must be greater than zero');
  }

  final confirmedRows = rows.where((row) => row.isConfirmed).toList();
  if (confirmedRows.isEmpty) {
    throw StateError('The corpus has no confirmed labels.');
  }
  final catalogById = {for (final target in catalog) target.id: target};
  final results = <ExerciseCalibrationResult>[];
  var highestWrongScore = 0.0;
  var hasWrongMatchEvidence = false;

  for (final row in confirmedRows) {
    if (row.expectedTemplateId != noExerciseMatch &&
        !catalogById.containsKey(row.expectedTemplateId)) {
      throw StateError(
        'Corpus row references unknown template ID '
        '${row.expectedTemplateId}.',
      );
    }

    final ranked = matcher.rank(row.input, catalog);
    final correct = row.expectedTemplateId == noExerciseMatch
        ? null
        : ranked
            .where(
              (candidate) => candidate.template.id == row.expectedTemplateId,
            )
            .firstOrNull;
    final wrong = ranked
        .where(
          (candidate) => candidate.template.id != row.expectedTemplateId,
        )
        .firstOrNull;
    if (wrong != null) {
      hasWrongMatchEvidence = true;
      highestWrongScore = math.max(highestWrongScore, wrong.score);
    }
    results.add(
      ExerciseCalibrationResult(
        row: row,
        correctScore: correct?.score,
        bestMatch: ranked.firstOrNull,
        bestWrongMatch: wrong,
      ),
    );
  }

  // With no wrong-match evidence there is no demonstrated safe threshold.
  // Fail closed exactly as we do when an observed wrong score pushes the
  // threshold above the matcher's maximum score.
  final threshold =
      hasWrongMatchEvidence ? highestWrongScore + margin : 1.0 + margin;
  var autoResolvedCount = 0;
  var wrongAutoResolveCount = 0;

  for (final result in results) {
    final resolved = matcher.resolve(
      result.row.input,
      catalog,
      threshold: threshold,
    );
    if (resolved == null) continue;
    autoResolvedCount++;
    if (result.row.expectedTemplateId == noExerciseMatch ||
        resolved.id != result.row.expectedTemplateId) {
      wrongAutoResolveCount++;
    }
  }

  return ExerciseCalibrationReport(
    threshold: threshold,
    margin: margin,
    highestWrongScore: highestWrongScore,
    hasWrongMatchEvidence: hasWrongMatchEvidence,
    labeledRowCount: results.length,
    autoResolvedCount: autoResolvedCount,
    reviewCount: results.length - autoResolvedCount,
    wrongAutoResolveCount: wrongAutoResolveCount,
    results: List.unmodifiable(results),
  );
}

String normalizeExerciseName(String value) {
  var normalized = value.toLowerCase();
  normalized = normalized.replaceAll(RegExp(r'@\s*rpe\s*\d+(?:\.\d+)?'), ' ');
  normalized = normalized.replaceAll(RegExp(r'\b\d+\s*x\s*\d+\b'), ' ');
  normalized = normalized.replaceAll(RegExp(r'\b(?:ss|superset)\s*:\s*'), ' ');
  normalized = normalized.replaceAll(RegExp(r'\b[a-z]\d\s*[/:-]\s*'), ' ');
  normalized = normalized.replaceAllMapped(
    RegExp(r'\b(bb|db|kb)\b'),
    (match) => switch (match.group(1)) {
      'bb' => 'barbell',
      'db' => 'dumbbell',
      'kb' => 'kettlebell',
      _ => match.group(0)!,
    },
  );
  normalized = normalized
      .replaceAll('&', ' and ')
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim();
  return normalized.replaceAll(RegExp(r'\s+'), ' ');
}

double _normalizedEditSimilarity(String left, String right) {
  final maxLength = math.max(left.length, right.length);
  if (maxLength == 0) return 1;
  return 1 - (_levenshteinDistance(left, right) / maxLength);
}

int _levenshteinDistance(String left, String right) {
  var previous = List<int>.generate(right.length + 1, (index) => index);
  for (var leftIndex = 0; leftIndex < left.length; leftIndex++) {
    final current = List<int>.filled(right.length + 1, 0);
    current[0] = leftIndex + 1;
    for (var rightIndex = 0; rightIndex < right.length; rightIndex++) {
      final substitutionCost =
          left.codeUnitAt(leftIndex) == right.codeUnitAt(rightIndex) ? 0 : 1;
      current[rightIndex + 1] = math.min(
        math.min(
          current[rightIndex] + 1,
          previous[rightIndex + 1] + 1,
        ),
        previous[rightIndex] + substitutionCost,
      );
    }
    previous = current;
  }
  return previous.last;
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
