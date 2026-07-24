import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:neuroflow/domain/health/hevy_exercise_corpus.dart';
import 'package:neuroflow/domain/health/hevy_exercise_matching.dart';

const _baseUrl = 'https://api.hevyapp.com/v1/';

Future<void> main(List<String> arguments) async {
  if (arguments.isEmpty || arguments.contains('--help')) {
    _printUsage();
    return;
  }

  switch (arguments.first) {
    case 'build':
      await _buildCorpus(arguments.skip(1).toList());
    case 'calibrate':
      await _calibrate(arguments.skip(1).toList());
    default:
      stderr.writeln('Unknown command: ${arguments.first}');
      _printUsage();
      exitCode = 64;
  }
}

Future<void> _buildCorpus(List<String> arguments) async {
  final outputDirectory = Directory(
    _option(arguments, '--output') ?? 'build/hevy_match_corpus',
  );
  final noMatchPath = _option(arguments, '--no-match-file');
  final apiKey = await _readApiKey();
  final client = _HevyCorpusClient(apiKey: apiKey);

  try {
    final templates = await client.getExerciseTemplates();
    final apiRows = <ExerciseCorpusRow>[
      ...await client.getRoutineExerciseRows(),
      ...await client.getWorkoutExerciseRows(),
    ];
    final noMatchInputs = noMatchPath == null
        ? const <String>[]
        : await File(noMatchPath).readAsLines();
    final corpus = const ExerciseCorpusBuilder().build(
      catalog: templates,
      apiLabeledRows: apiRows,
      noMatchInputs: noMatchInputs,
    );

    await outputDirectory.create(recursive: true);
    final catalogFile = File(
      '${outputDirectory.path}${Platform.pathSeparator}catalog.json',
    );
    final corpusFile = File(
      '${outputDirectory.path}${Platform.pathSeparator}corpus.csv',
    );
    await catalogFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(
        [
          for (final template in templates)
            {'id': template.id, 'title': template.title},
        ],
      ),
    );
    await corpusFile.writeAsString(exerciseCorpusToCsv(corpus));

    final reviewCount = corpus.where((row) => !row.isConfirmed).length;
    stdout.writeln('Catalog templates: ${templates.length}');
    stdout.writeln('Corpus rows: ${corpus.length}');
    stdout.writeln('Rows requiring human review: $reviewCount');
    stdout.writeln('Catalog: ${catalogFile.path}');
    stdout.writeln('Corpus: ${corpusFile.path}');
  } finally {
    client.close();
  }
}

Future<void> _calibrate(List<String> arguments) async {
  final catalogPath = _requiredOption(arguments, '--catalog');
  final corpusPath = _requiredOption(arguments, '--corpus');
  final reportPath =
      _option(arguments, '--report') ?? 'build/hevy_match_corpus/report.csv';
  final margin = double.parse(_option(arguments, '--margin') ?? '0.01');

  final catalogJson = jsonDecode(await File(catalogPath).readAsString());
  if (catalogJson is! List) {
    throw const FormatException('Catalog JSON must contain a list.');
  }
  final catalog = catalogJson.map((item) {
    if (item is! Map) {
      throw const FormatException('Catalog entry must be an object.');
    }
    return ExerciseTemplateTarget(
      id: _requiredString(item, 'id'),
      title: _requiredString(item, 'title'),
    );
  }).toList(growable: false);
  final corpus = exerciseCorpusFromCsv(
    await File(corpusPath).readAsString(),
  );
  final report = calibrateExerciseMatcher(
    rows: corpus,
    catalog: catalog,
    margin: margin,
  );

  final reportFile = File(reportPath);
  await reportFile.parent.create(recursive: true);
  await reportFile.writeAsString(_reportToCsv(report));

  if (report.hasWrongMatchEvidence) {
    stdout.writeln(
      'Threshold: ${report.threshold.toStringAsFixed(4)} '
      '(highest wrong ${report.highestWrongScore.toStringAsFixed(4)} '
      '+ margin ${report.margin.toStringAsFixed(4)})',
    );
  } else {
    stdout.writeln(
      'Threshold: ${report.threshold.toStringAsFixed(4)} '
      '(automatic resolution disabled: no confirmed wrong-match evidence)',
    );
  }
  stdout.writeln(
    'Auto-resolve: ${report.autoResolvedCount}/${report.labeledRowCount} '
    '(${(report.autoResolveRate * 100).toStringAsFixed(1)}%)',
  );
  stdout.writeln('Review: ${report.reviewCount}');
  stdout.writeln('Wrong auto-resolves: ${report.wrongAutoResolveCount}');
  stdout.writeln('Report: ${reportFile.path}');

  if (report.wrongAutoResolveCount != 0) {
    exitCode = 1;
  }
}

class _HevyCorpusClient {
  final String apiKey;
  final http.Client _http;

  _HevyCorpusClient({
    required this.apiKey,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  Future<List<ExerciseTemplateTarget>> getExerciseTemplates() async {
    final targets = <ExerciseTemplateTarget>[];
    await for (final item in _getPages(
      path: 'exercise_templates',
      collectionKey: 'exercise_templates',
      pageSize: 100,
    )) {
      targets.add(
        ExerciseTemplateTarget(
          id: _requiredString(item, 'id'),
          title: _requiredString(item, 'title'),
        ),
      );
    }
    return targets;
  }

  Future<List<ExerciseCorpusRow>> getRoutineExerciseRows() =>
      _getExerciseRows(path: 'routines', collectionKey: 'routines');

  Future<List<ExerciseCorpusRow>> getWorkoutExerciseRows() =>
      _getExerciseRows(path: 'workouts', collectionKey: 'workouts');

  Future<List<ExerciseCorpusRow>> _getExerciseRows({
    required String path,
    required String collectionKey,
  }) async {
    final source = path == 'routines'
        ? ExerciseCorpusSource.routine
        : ExerciseCorpusSource.workout;
    final rows = <ExerciseCorpusRow>[];
    await for (final container in _getPages(
      path: path,
      collectionKey: collectionKey,
      pageSize: 10,
    )) {
      final exercises = container['exercises'];
      if (exercises is! List) continue;
      for (final item in exercises.whereType<Map>()) {
        final exercise = Map<String, dynamic>.from(item);
        final title = _requiredString(exercise, 'title');
        rows.add(
          ExerciseCorpusRow(
            input: title,
            expectedTemplateId:
                _requiredString(exercise, 'exercise_template_id'),
            source: source,
            canonicalTitle: title,
            labelStatus: ExerciseCorpusLabelStatus.confirmed,
          ),
        );
      }
    }
    return rows;
  }

  Stream<Map<String, dynamic>> _getPages({
    required String path,
    required String collectionKey,
    required int pageSize,
  }) async* {
    var page = 1;
    var pageCount = 1;
    do {
      final uri = Uri.parse(_baseUrl).resolve(path).replace(
        queryParameters: {'page': '$page', 'pageSize': '$pageSize'},
      );
      final response = await _http.get(
        uri,
        headers: {'accept': 'application/json', 'api-key': apiKey},
      ).timeout(const Duration(seconds: 20));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'Hevy request failed with status ${response.statusCode}.',
          uri: uri,
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        throw const FormatException('Hevy returned a non-object response.');
      }
      final json = Map<String, dynamic>.from(decoded);
      pageCount = _requiredInt(json, 'page_count');
      final items = json[collectionKey];
      if (items is! List) {
        throw FormatException('Hevy response is missing $collectionKey.');
      }
      for (final item in items.whereType<Map>()) {
        yield Map<String, dynamic>.from(item);
      }
      page++;
    } while (page <= pageCount);
  }

  void close() => _http.close();
}

Future<String> _readApiKey() async {
  if (!stdin.hasTerminal) {
    throw StateError(
      'Interactive input is required. Run the command in a terminal; '
      'the API key is never accepted as a command-line argument.',
    );
  }
  stdout.write('Hevy API key (input hidden): ');
  final previousEchoMode = stdin.echoMode;
  try {
    stdin.echoMode = false;
    final apiKey = stdin.readLineSync()?.trim() ?? '';
    stdout.writeln();
    if (apiKey.isEmpty) throw StateError('Hevy API key cannot be empty.');
    return apiKey;
  } finally {
    stdin.echoMode = previousEchoMode;
  }
}

String _reportToCsv(ExerciseCalibrationReport report) {
  final output = StringBuffer(
    'input,expected_template_id,correct_score,best_match_id,'
    'best_match_score,best_wrong_id,best_wrong_score,auto_resolved\r\n',
  );
  for (final result in report.results) {
    final bestScore = result.bestMatch?.score;
    final tiedAtBest =
        bestScore != null && result.bestWrongMatch?.score == bestScore;
    final autoResolved =
        bestScore != null && bestScore >= report.threshold && !tiedAtBest;
    output.writeln(
      [
        result.row.input,
        result.row.expectedTemplateId,
        result.correctScore?.toStringAsFixed(6) ?? '',
        result.bestMatch?.template.id ?? '',
        result.bestMatch?.score.toStringAsFixed(6) ?? '',
        result.bestWrongMatch?.template.id ?? '',
        result.bestWrongMatch?.score.toStringAsFixed(6) ?? '',
        '$autoResolved',
      ].map(_escapeCsv).join(','),
    );
  }
  return output.toString();
}

String _escapeCsv(String value) {
  if (!value.contains(RegExp(r'[",\r\n]'))) return value;
  return '"${value.replaceAll('"', '""')}"';
}

String? _option(List<String> arguments, String name) {
  final index = arguments.indexOf(name);
  if (index == -1) return null;
  if (index + 1 >= arguments.length) {
    throw FormatException('$name requires a value.');
  }
  return arguments[index + 1];
}

String _requiredOption(List<String> arguments, String name) {
  final value = _option(arguments, name);
  if (value == null || value.isEmpty) {
    throw FormatException('$name is required.');
  }
  return value;
}

String _requiredString(Map<dynamic, dynamic> json, String key) {
  final value = json[key];
  if (value is String && value.trim().isNotEmpty) return value.trim();
  throw FormatException('Missing or invalid field: $key');
}

int _requiredInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is num) return value.toInt();
  throw FormatException('Missing or invalid field: $key');
}

void _printUsage() {
  stdout.writeln('''
Build a private, label-ready Hevy exercise corpus:
  dart run tool/hevy_exercise_corpus.dart build
    [--output build/hevy_match_corpus]
    [--no-match-file path/to/no_match_inputs.txt]

Calibrate the matcher after every needsReview row has been labeled:
  dart run tool/hevy_exercise_corpus.dart calibrate
    --catalog build/hevy_match_corpus/catalog.json
    --corpus build/hevy_match_corpus/corpus.csv
    [--margin 0.01]
    [--report build/hevy_match_corpus/report.csv]

The build command prompts for the Hevy API key with terminal echo disabled.
The key is never accepted as an argument, printed, or written to disk.
''');
}
