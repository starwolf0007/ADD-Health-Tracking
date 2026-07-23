// Public storage-schema surface for Drift and consumers.
//
// Re-export the domain-owned enum types so libraries importing this schema
// (including database.dart and its generated part) resolve the same types.
export 'package:neuroflow/domain/health/health_enums.dart';
export 'health_tables_impl.dart';
