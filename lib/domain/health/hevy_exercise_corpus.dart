import 'package:neuroflow/domain/health/hevy_exercise_matching.dart';

class ExerciseCorpusBuilder {
  const ExerciseCorpusBuilder();

  List<ExerciseCorpusRow> build({
    required List<ExerciseTemplateTarget> catalog,
    Iterable<ExerciseCorpusRow> apiLabeledRows = const [],
    Iterable<String> noMatchInputs = const [],
  }) {
    final rows = <ExerciseCorpusRow>[
      ...apiLabeledRows,
      for (final template in catalog)
        ExerciseCorpusRow(
          input: template.title,
          expectedTemplateId: template.id,
          source: ExerciseCorpusSource.catalog,
          canonicalTitle: template.title,
          labelStatus: ExerciseCorpusLabelStatus.confirmed,
        ),
      for (final template in catalog)
        for (final perturbation in perturbExerciseName(template.title))
          ExerciseCorpusRow(
            input: perturbation,
            expectedTemplateId: template.id,
            source: ExerciseCorpusSource.synthetic,
            canonicalTitle: template.title,
            labelStatus: ExerciseCorpusLabelStatus.needsReview,
          ),
      for (final input in noMatchInputs)
        if (input.trim().isNotEmpty)
          ExerciseCorpusRow(
            input: input.trim(),
            expectedTemplateId: noExerciseMatch,
            source: ExerciseCorpusSource.manual,
            canonicalTitle: '',
            labelStatus: ExerciseCorpusLabelStatus.needsReview,
          ),
    ];

    final unique = <String, ExerciseCorpusRow>{};
    for (final row in rows) {
      final key =
          '${row.input.toLowerCase()}\u0000${row.expectedTemplateId}\u0000'
          '${row.source.name}';
      unique.putIfAbsent(key, () => row);
    }
    final result = unique.values.toList()
      ..sort((left, right) {
        final sourceOrder = left.source.index.compareTo(right.source.index);
        if (sourceOrder != 0) return sourceOrder;
        final inputOrder = left.input.compareTo(right.input);
        if (inputOrder != 0) return inputOrder;
        return left.expectedTemplateId.compareTo(right.expectedTemplateId);
      });
    return List.unmodifiable(result);
  }
}

List<String> perturbExerciseName(String canonicalTitle) {
  final values = <String>{};
  final equipmentMatch =
      RegExp(r'^(.*?)\s*\((Barbell|Dumbbell|Kettlebell|Machine)\)$')
          .firstMatch(canonicalTitle.trim());
  if (equipmentMatch != null) {
    final movement = equipmentMatch.group(1)!.trim();
    final equipment = equipmentMatch.group(2)!;
    values
      ..add(movement)
      ..add('${_equipmentAbbreviation(equipment)} $movement');
  }

  final abbreviated = canonicalTitle
      .replaceAll(RegExp('Dumbbell', caseSensitive: false), 'DB')
      .replaceAll(RegExp('Barbell', caseSensitive: false), 'BB')
      .replaceAll(RegExp('Kettlebell', caseSensitive: false), 'KB')
      .replaceAll(RegExp('Incline', caseSensitive: false), 'Inc')
      .replaceAll(RegExp('Romanian', caseSensitive: false), 'RDL')
      .replaceAll(RegExp(r'[()]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (abbreviated != canonicalTitle) values.add(abbreviated);

  final words = canonicalTitle.split(RegExp(r'\s+'));
  if (words.length > 1) {
    values.add(words.map((word) => word.substring(0, 1)).join());
  }

  final typoSource = canonicalTitle.replaceAll(RegExp(r'[^A-Za-z]'), '');
  if (typoSource.length >= 6) {
    final character = typoSource[typoSource.length ~/ 2];
    final index = canonicalTitle.indexOf(character);
    if (index >= 0) {
      values.add(
        canonicalTitle.substring(0, index) +
            canonicalTitle.substring(index + 1),
      );
    }
  }

  values
    ..remove(canonicalTitle)
    ..removeWhere((value) => value.trim().isEmpty);
  return values.toList()..sort();
}

String _equipmentAbbreviation(String equipment) => switch (equipment) {
      'Barbell' => 'BB',
      'Dumbbell' => 'DB',
      'Kettlebell' => 'KB',
      'Machine' => 'Machine',
      _ => equipment,
    };

String exerciseCorpusToCsv(List<ExerciseCorpusRow> rows) {
  final output = StringBuffer(
    'input,expected_template_id,source,canonical_title,label_status\r\n',
  );
  for (final row in rows) {
    output
      ..write(
        [
          row.input,
          row.expectedTemplateId,
          row.source.name,
          row.canonicalTitle,
          row.labelStatus.name,
        ].map(_escapeCsv).join(','),
      )
      ..write('\r\n');
  }
  return output.toString();
}

List<ExerciseCorpusRow> exerciseCorpusFromCsv(String csv) {
  final records = _parseCsv(csv);
  if (records.isEmpty) return const [];
  const expectedHeader = [
    'input',
    'expected_template_id',
    'source',
    'canonical_title',
    'label_status',
  ];
  if (!_listEquals(records.first, expectedHeader)) {
    throw const FormatException('Unexpected exercise corpus CSV header.');
  }

  return records
      .skip(1)
      .where((record) => record.any((cell) => cell.isNotEmpty))
      .map(
    (record) {
      if (record.length != expectedHeader.length) {
        throw const FormatException('Exercise corpus row has the wrong width.');
      }
      return ExerciseCorpusRow(
        input: record[0],
        expectedTemplateId: record[1],
        source: ExerciseCorpusSource.values.byName(record[2]),
        canonicalTitle: record[3],
        labelStatus: ExerciseCorpusLabelStatus.values.byName(record[4]),
      );
    },
  ).toList(growable: false);
}

String _escapeCsv(String value) {
  if (!value.contains(RegExp(r'[",\r\n]'))) return value;
  return '"${value.replaceAll('"', '""')}"';
}

List<List<String>> _parseCsv(String csv) {
  final records = <List<String>>[];
  var record = <String>[];
  var field = StringBuffer();
  var inQuotes = false;

  for (var index = 0; index < csv.length; index++) {
    final character = csv[index];
    if (inQuotes) {
      if (character == '"' && index + 1 < csv.length && csv[index + 1] == '"') {
        field.write('"');
        index++;
      } else if (character == '"') {
        inQuotes = false;
      } else {
        field.write(character);
      }
      continue;
    }
    if (character == '"') {
      inQuotes = true;
    } else if (character == ',') {
      record.add(field.toString());
      field = StringBuffer();
    } else if (character == '\n') {
      if (field.isNotEmpty && field.toString().endsWith('\r')) {
        final value = field.toString();
        field = StringBuffer()..write(value.substring(0, value.length - 1));
      }
      record.add(field.toString());
      records.add(record);
      record = <String>[];
      field = StringBuffer();
    } else {
      field.write(character);
    }
  }

  if (inQuotes) throw const FormatException('Unterminated CSV quote.');
  if (field.isNotEmpty || record.isNotEmpty) {
    record.add(field.toString());
    records.add(record);
  }
  return records;
}

bool _listEquals(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
