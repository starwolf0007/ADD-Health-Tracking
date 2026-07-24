import 'package:flutter_test/flutter_test.dart';
import 'package:neuroflow/domain/health/hevy_exercise_corpus.dart';
import 'package:neuroflow/domain/health/hevy_exercise_matching.dart';

void main() {
  const catalog = [
    ExerciseTemplateTarget(id: 'bench', title: 'Bench Press (Barbell)'),
    ExerciseTemplateTarget(id: 'single-leg', title: 'Single Leg Press'),
    ExerciseTemplateTarget(id: 'leg-press', title: 'Leg Press'),
    ExerciseTemplateTarget(id: 'deadlift', title: 'Deadlift (Barbell)'),
    ExerciseTemplateTarget(
      id: 'rdl',
      title: 'Romanian Deadlift (Barbell)',
    ),
  ];

  group('HevyExerciseMatcher', () {
    const matcher = HevyExerciseMatcher();

    test('normalizes common equipment and prescription notation', () {
      expect(
        matcher.score('BB Bench Press 3x8 @RPE8', 'Bench Press (Barbell)'),
        greaterThanOrEqualTo(0.98),
      );
    });

    test('does not auto-resolve tied candidates', () {
      const duplicateCatalog = [
        ExerciseTemplateTarget(id: 'one', title: 'Row'),
        ExerciseTemplateTarget(id: 'two', title: 'Row'),
      ];

      expect(
        matcher.resolve('Row', duplicateCatalog, threshold: 0.9),
        isNull,
      );
    });
  });

  group('calibrateExerciseMatcher', () {
    test('sets threshold above every wrong score and makes zero wrong writes',
        () {
      const rows = [
        ExerciseCorpusRow(
          input: 'BB Bench Press',
          expectedTemplateId: 'bench',
          source: ExerciseCorpusSource.manual,
          canonicalTitle: 'Bench Press (Barbell)',
          labelStatus: ExerciseCorpusLabelStatus.confirmed,
        ),
        ExerciseCorpusRow(
          input: 'Single Leg Press',
          expectedTemplateId: 'single-leg',
          source: ExerciseCorpusSource.manual,
          canonicalTitle: 'Single Leg Press',
          labelStatus: ExerciseCorpusLabelStatus.confirmed,
        ),
        ExerciseCorpusRow(
          input: 'Glute Bridge',
          expectedTemplateId: noExerciseMatch,
          source: ExerciseCorpusSource.manual,
          canonicalTitle: '',
          labelStatus: ExerciseCorpusLabelStatus.confirmed,
        ),
      ];

      final report = calibrateExerciseMatcher(
        rows: rows,
        catalog: catalog,
        margin: 0.01,
      );

      expect(
        report.threshold,
        closeTo(report.highestWrongScore + 0.01, 0.0000001),
      );
      expect(report.wrongAutoResolveCount, 0);
      expect(
        report.results.every(
          (result) =>
              result.bestWrongMatch == null ||
              result.bestWrongMatch!.score < report.threshold,
        ),
        isTrue,
      );
    });

    test('ignores unreviewed synthetic rows', () {
      const rows = [
        ExerciseCorpusRow(
          input: 'Leg Press',
          expectedTemplateId: 'leg-press',
          source: ExerciseCorpusSource.manual,
          canonicalTitle: 'Leg Press',
          labelStatus: ExerciseCorpusLabelStatus.confirmed,
        ),
        ExerciseCorpusRow(
          input: 'LP',
          expectedTemplateId: 'leg-press',
          source: ExerciseCorpusSource.synthetic,
          canonicalTitle: 'Leg Press',
          labelStatus: ExerciseCorpusLabelStatus.needsReview,
        ),
      ];

      final report = calibrateExerciseMatcher(
        rows: rows,
        catalog: catalog,
      );

      expect(report.labeledRowCount, 1);
      expect(report.results.single.row.input, 'Leg Press');
    });

    test('disables automatic resolution without wrong-match evidence', () {
      const singleTemplateCatalog = [
        ExerciseTemplateTarget(id: 'bench', title: 'Bench Press'),
      ];
      const rows = [
        ExerciseCorpusRow(
          input: 'Bench Press',
          expectedTemplateId: 'bench',
          source: ExerciseCorpusSource.catalog,
          canonicalTitle: 'Bench Press',
          labelStatus: ExerciseCorpusLabelStatus.confirmed,
        ),
      ];

      final report = calibrateExerciseMatcher(
        rows: rows,
        catalog: singleTemplateCatalog,
        margin: 0.01,
      );

      expect(report.hasWrongMatchEvidence, isFalse);
      expect(report.highestWrongScore, 0);
      expect(report.threshold, 1.01);
      expect(report.autoResolvedCount, 0);
      expect(report.reviewCount, 1);
      expect(report.wrongAutoResolveCount, 0);
    });
  });

  group('ExerciseCorpusBuilder', () {
    test('marks API labels confirmed and perturbations for review', () {
      const builder = ExerciseCorpusBuilder();
      final corpus = builder.build(
        catalog: const [
          ExerciseTemplateTarget(
            id: 'bench',
            title: 'Bench Press (Barbell)',
          ),
        ],
        apiLabeledRows: const [
          ExerciseCorpusRow(
            input: 'Bench Press',
            expectedTemplateId: 'bench',
            source: ExerciseCorpusSource.routine,
            canonicalTitle: 'Bench Press',
            labelStatus: ExerciseCorpusLabelStatus.confirmed,
          ),
        ],
        noMatchInputs: const ['Glute Bridge'],
      );

      expect(
        corpus.where(
          (row) =>
              row.source == ExerciseCorpusSource.routine && row.isConfirmed,
        ),
        hasLength(1),
      );
      expect(
        corpus.where(
          (row) =>
              row.source == ExerciseCorpusSource.synthetic && !row.isConfirmed,
        ),
        isNotEmpty,
      );
      expect(
        corpus
            .singleWhere((row) => row.input == 'Glute Bridge')
            .expectedTemplateId,
        noExerciseMatch,
      );
    });

    test('CSV round trip preserves commas and quotes', () {
      const rows = [
        ExerciseCorpusRow(
          input: 'Press, "tempo"',
          expectedTemplateId: 'press',
          source: ExerciseCorpusSource.manual,
          canonicalTitle: 'Press',
          labelStatus: ExerciseCorpusLabelStatus.confirmed,
        ),
      ];

      final decoded = exerciseCorpusFromCsv(exerciseCorpusToCsv(rows));

      expect(decoded.single.input, rows.single.input);
      expect(decoded.single.expectedTemplateId, 'press');
      expect(decoded.single.isConfirmed, isTrue);
    });
  });
}
