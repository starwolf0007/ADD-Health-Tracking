enum StartupDiagnosticSeverity {
  info,
  warning,
  error,
  fatal,
}

/// Fail-safe startup diagnostics for Crashlytics.
///
/// Diagnostics are disabled until Firebase initialization succeeds. Every
/// Crashlytics call is swallowed so observability can never become a startup
/// dependency or change app behavior.
class StartupDiagnostics {
  StartupDiagnostics._();

  static bool _enabled = false;
  static final List<Map<String, String>> _events = <Map<String, String>>[];

  static List<Map<String, String>> get events =>
      List<Map<String, String>>.unmodifiable(_events);

  static void configure({required bool enabled}) {
    _enabled = enabled;
  }

  static void reset() {
    _events.clear();
  }

  static Future<void> recordBuildMetadata() async {
    if (!_enabled) return;

    const buildCommit = String.fromEnvironment(
      'BUILD_COMMIT',
      defaultValue: 'unknown',
    );
    const buildDate = String.fromEnvironment(
      'BUILD_DATE',
      defaultValue: 'unknown',
    );

    await _safe(() async {
      await FirebaseCrashlytics.instance.setCustomKey(
        'build_commit',
        buildCommit,
      );
      await FirebaseCrashlytics.instance.setCustomKey('build_date', buildDate);
      await FirebaseCrashlytics.instance.setCustomKey('is_debug', kDebugMode);
    });

    _recordEvent('build_metadata', 'ready', StartupDiagnosticSeverity.info);
  }

  static Future<void> checkpoint(
    String phase, {
    required String status,
    StartupDiagnosticSeverity severity = StartupDiagnosticSeverity.info,
  }) async {
    if (!_enabled) return;

    final value = '$phase:$status';
    await _safe(() async {
      await FirebaseCrashlytics.instance.setCustomKey('startup_phase', value);
      await FirebaseCrashlytics.instance.log('startup: $phase $status');
    });

    _recordEvent(phase, status, severity);

    if (kDebugMode) {
      debugPrint('[StartupDiagnostics] startup: $phase $status');
    }
  }

  static Future<void> markFailure(
    String phase,
    Object error, {
    StartupDiagnosticSeverity severity = StartupDiagnosticSeverity.error,
  }) async {
    if (!_enabled) return;

    await _safe(() async {
      await FirebaseCrashlytics.instance.setCustomKey(
        'startup_failed_at',
        phase,
      );
      await FirebaseCrashlytics.instance.setCustomKey(
        'startup_failure_severity',
        severity.name,
      );
      await FirebaseCrashlytics.instance.setCustomKey(
        'startup_phase',
        '$phase:failed',
      );
      await FirebaseCrashlytics.instance.log(
        'startup: $phase failed (${error.runtimeType}) [${severity.name}]',
      );
    });

    _recordEvent(phase, 'failed', severity, details: error.toString());
  }

  static Future<void> markRunning() async {
    if (!_enabled) return;

    await _safe(() async {
      await FirebaseCrashlytics.instance.setCustomKey(
        'startup_phase',
        'running',
      );
      await FirebaseCrashlytics.instance.log('startup: complete');
    });

    _recordEvent('startup', 'running', StartupDiagnosticSeverity.info);
  }

  static void _recordEvent(
    String phase,
    String status,
    StartupDiagnosticSeverity severity, {
    String? details,
  }) {
    _events.add({
      'phase': phase,
      'status': status,
      'severity': severity.name,
      if (details != null) 'details': details,
    });
  }

  static Future<void> _safe(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[StartupDiagnostics] diagnostic write failed: $error');
      }
    }
  }
}
