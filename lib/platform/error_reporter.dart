import 'dart:developer' as developer;

void reportNonFatalError(
  String context,
  Object error,
  StackTrace stackTrace,
) {
  developer.log(
    context,
    name: 'neuroflow',
    error: error,
    stackTrace: stackTrace,
    level: 900,
  );
}
