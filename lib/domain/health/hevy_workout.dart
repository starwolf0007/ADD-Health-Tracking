class HevyWorkout {
  final String id;
  final String title;
  final String? description;
  final DateTime startTime;
  final DateTime endTime;
  final DateTime? updatedAt;
  final DateTime? createdAt;
  final List<HevyExercise> exercises;

  const HevyWorkout({
    required this.id,
    required this.title,
    required this.startTime,
    required this.endTime,
    required this.exercises,
    this.description,
    this.updatedAt,
    this.createdAt,
  });

  factory HevyWorkout.fromJson(Map<String, dynamic> json) {
    return HevyWorkout(
      id: _requiredString(json, 'id'),
      title: _requiredString(json, 'title'),
      description: json['description'] as String?,
      startTime: _requiredDateTime(json, 'start_time'),
      endTime: _requiredDateTime(json, 'end_time'),
      updatedAt: _optionalDateTime(json['updated_at']),
      createdAt: _optionalDateTime(json['created_at']),
      exercises: _listOfMaps(json['exercises'])
          .map(HevyExercise.fromJson)
          .toList(growable: false),
    );
  }
}

class HevyExercise {
  final int index;
  final String title;
  final String? notes;
  final String exerciseTemplateId;
  final String? supersetId;
  final List<HevySet> sets;

  const HevyExercise({
    required this.index,
    required this.title,
    required this.exerciseTemplateId,
    required this.sets,
    this.notes,
    this.supersetId,
  });

  factory HevyExercise.fromJson(Map<String, dynamic> json) {
    return HevyExercise(
      index: (json['index'] as num?)?.toInt() ?? 0,
      title: _requiredString(json, 'title'),
      notes: json['notes'] as String?,
      exerciseTemplateId: _requiredString(json, 'exercise_template_id'),
      supersetId: json['superset_id'] as String?,
      sets: _listOfMaps(json['sets'])
          .map(HevySet.fromJson)
          .toList(growable: false),
    );
  }
}

class HevySet {
  final int index;
  final String type;
  final num? weightKg;
  final int? reps;
  final int? distanceMeters;
  final int? durationSeconds;
  final num? rpe;
  final bool? customMetric;
  final Map<String, dynamic> raw;

  const HevySet({
    required this.index,
    required this.type,
    required this.raw,
    this.weightKg,
    this.reps,
    this.distanceMeters,
    this.durationSeconds,
    this.rpe,
    this.customMetric,
  });

  factory HevySet.fromJson(Map<String, dynamic> json) {
    return HevySet(
      index: (json['index'] as num?)?.toInt() ?? 0,
      type: (json['type'] as String?) ?? 'normal',
      weightKg: json['weight_kg'] as num?,
      reps: (json['reps'] as num?)?.toInt(),
      distanceMeters: (json['distance_meters'] as num?)?.toInt(),
      durationSeconds: (json['duration_seconds'] as num?)?.toInt(),
      rpe: json['rpe'] as num?,
      customMetric: json['custom_metric'] as bool?,
      raw: Map<String, dynamic>.unmodifiable(json),
    );
  }
}

class HevyWorkoutPage {
  final int page;
  final int pageCount;
  final List<HevyWorkout> workouts;

  const HevyWorkoutPage({
    required this.page,
    required this.pageCount,
    required this.workouts,
  });

  /// Pagination metadata is required: defaulting a malformed page to
  /// `page == pageCount == 1` with no workouts would make it indistinguishable
  /// from a valid empty first page and silently truncate imports.
  factory HevyWorkoutPage.fromJson(Map<String, dynamic> json) {
    return HevyWorkoutPage(
      page: _requiredInt(json, 'page'),
      pageCount: _requiredInt(json, 'page_count'),
      workouts: _requiredListOfMaps(json, 'workouts')
          .map(HevyWorkout.fromJson)
          .toList(growable: false),
    );
  }

  bool get hasNextPage => page < pageCount;
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is String && value.isNotEmpty) return value;
  throw FormatException('Missing or invalid Hevy field: $key');
}

DateTime _requiredDateTime(Map<String, dynamic> json, String key) {
  final parsed = _optionalDateTime(json[key]);
  if (parsed != null) return parsed;
  throw FormatException('Missing or invalid Hevy timestamp: $key');
}

DateTime? _optionalDateTime(Object? value) {
  if (value is! String || value.isEmpty) return null;
  return DateTime.tryParse(value)?.toUtc();
}

int _requiredInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is num) return value.toInt();
  throw FormatException('Missing or invalid Hevy field: $key');
}

List<Map<String, dynamic>> _listOfMaps(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList(growable: false);
}

List<Map<String, dynamic>> _requiredListOfMaps(
  Map<String, dynamic> json,
  String key,
) {
  final value = json[key];
  if (value is! List) {
    throw FormatException('Missing or invalid Hevy field: $key');
  }
  return _listOfMaps(value);
}
