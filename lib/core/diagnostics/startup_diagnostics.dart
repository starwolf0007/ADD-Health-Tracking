import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// Fail-safe startup diagnostics for Crashlytics.
///
/// Diagnostics are disabled until Firebase initialization succeeds. Every
/// Crashlytics call is swallowed so observability can never become a startup
/// dependency or change app behavior.
class StartupDiagnostics {
  StartupDiagnostics._();

  static bool _enabled = false;

  static void configure({required bool enabled}) {
    _enabled = enabled;
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
  }

  static Future<void> checkpoint(
    String phase, {
    required String status,
  }) async {
    if (!_enabled) return;

    final value = '$phase:$status';
    await _safe(() async {
      await FirebaseCrashlytics.instance.setCustomKey('startup_phase', value);
      await FirebaseCrashlytics.instance.log('startup: $phase $status');
    });

    if (kDebugMode) {
      debugPrint('[StartupDiagnostics] startup: $phase $status');
    }
  }

  static Future<void> markFailure(String phase, Object error) async {
    if (!_enabled) return;

    await _safe(() async {
      await FirebaseCrashlytics.instance.setCustomKey(
        'startup_failed_at',
        phase,
      );
      await FirebaseCrashlytics.instance.setCustomKey(
        'startup_phase',
        '$phase:failed',
      );
      await FirebaseCrashlytics.instance.log(
        'startup: $phase failed (${error.runtimeType})',
      );
    });
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
