import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuroflow/data/database.dart';

/// Lives outside providers.dart so provider modules it exports (for example
/// hevy_providers.dart) can depend on the database without importing the
/// composition root back — that would create a library cycle.
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});
