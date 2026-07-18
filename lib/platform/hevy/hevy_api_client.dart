import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:neuroflow/domain/health/hevy_workout.dart';
import 'package:neuroflow/platform/hevy/hevy_credentials_store.dart';

class HevyApiException implements Exception {
  final int? statusCode;
  final String message;

  const HevyApiException(this.message, {this.statusCode});

  @override
  String toString() =>
      'HevyApiException(statusCode: $statusCode, message: $message)';
}

/// Read-only Hevy API client.
///
/// The first implementation deliberately exposes only GET endpoints. NeuroFlow
/// should prove import, caching, and analysis before it is allowed to mutate a
/// user's training log.
class HevyApiClient {
  static final Uri _baseUri = Uri.parse('https://api.hevyapp.com/v1/');

  final http.Client _http;
  final HevyCredentialsStore _credentials;

  HevyApiClient({
    required http.Client httpClient,
    required HevyCredentialsStore credentials,
  })  : _http = httpClient,
        _credentials = credentials;

  Future<void> verifyConnection() async {
    await _getJson('user/info');
  }

  Future<int> getWorkoutCount() async {
    final json = await _getJson('workouts/count');
    final count = json['workout_count'] ?? json['count'];
    if (count is num) return count.toInt();
    throw const HevyApiException(
      'Hevy returned an unexpected workout-count response.',
    );
  }

  Future<HevyWorkoutPage> getWorkouts({
    int page = 1,
    int pageSize = 10,
  }) async {
    _validatePagination(page: page, pageSize: pageSize);
    final json = await _getJson(
      'workouts',
      query: {
        'page': '$page',
        'pageSize': '$pageSize',
      },
    );
    return HevyWorkoutPage.fromJson(json);
  }

  Future<HevyWorkout> getWorkout(String workoutId) async {
    final id = workoutId.trim();
    if (id.isEmpty) {
      throw const FormatException('workoutId cannot be empty.');
    }

    final json = await _getJson('workouts/${Uri.encodeComponent(id)}');
    final body = json['workout'];
    return HevyWorkout.fromJson(
      body is Map ? Map<String, dynamic>.from(body) : json,
    );
  }

  Future<Map<String, dynamic>> _getJson(
    String path, {
    Map<String, String>? query,
  }) async {
    final apiKey = await _credentials.readApiKey();
    if (apiKey == null) {
      throw const HevyApiException(
        'Hevy is not configured. Add an API key in Health Integrations.',
      );
    }

    final uri = _baseUri.resolve(path).replace(queryParameters: query);
    late http.Response response;

    try {
      response = await _http.get(
        uri,
        headers: {
          'accept': 'application/json',
          'api-key': apiKey,
        },
      ).timeout(const Duration(seconds: 20));
    } on Exception catch (error) {
      throw HevyApiException('Unable to reach Hevy: $error');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final safeMessage = switch (response.statusCode) {
        401 || 403 => 'Hevy rejected the API key.',
        404 => 'The requested Hevy resource was not found.',
        429 => 'Hevy rate-limited the request. Try again later.',
        _ => 'Hevy request failed.',
      };
      throw HevyApiException(
        safeMessage,
        statusCode: response.statusCode,
      );
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      // Never include the body: it could echo request details or server
      // internals into a user-facing message.
      throw HevyApiException(
        'Hevy returned an unexpected response format.',
        statusCode: response.statusCode,
      );
    }
    if (decoded is! Map) {
      throw HevyApiException(
        'Hevy returned an unexpected response format.',
        statusCode: response.statusCode,
      );
    }

    return Map<String, dynamic>.from(decoded);
  }

  void close() => _http.close();

  static void _validatePagination({
    required int page,
    required int pageSize,
  }) {
    if (page < 1) {
      throw RangeError('page must be at least 1.');
    }
    if (pageSize < 1 || pageSize > 10) {
      throw RangeError('pageSize must be between 1 and 10.');
    }
  }
}
