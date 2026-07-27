// lib/app/mood_providers.dart
//
// Reflect / mood presentation streams. Kept thin so providers.dart stays focused.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:neuroflow/app/providers.dart';
import 'package:neuroflow/domain/mood.dart';

/// Latest mood check-in logged today (null if none).
final todayMoodProvider = StreamProvider<MoodLog?>((ref) {
  return ref.watch(moodRepositoryProvider).watchTodayLatest();
});

/// Recent mood logs (last 14 days), newest first.
final recentMoodsProvider = StreamProvider<List<MoodLog>>((ref) {
  return ref.watch(moodRepositoryProvider).watchRecent(days: 14);
});
