// lib/platform/google/google_permission_manager_impl.dart
//
// Impl of GooglePermissionManager, binds the shared google_sign_in plugin
// instance. NO GoogleAccountRepository dependency (see
// google_permission_manager.dart doc — GoogleServiceManager is the single
// writer of grantedScopes).

import 'package:google_sign_in/google_sign_in.dart';

import 'google_permission_manager.dart';

class GooglePermissionManagerImpl implements GooglePermissionManager {
  final GoogleSignIn _plugin;
  final Set<String> _granted = {};

  GooglePermissionManagerImpl(this._plugin);

  @override
  Future<void> hydrate(List<String> grantedScopes) async {
    _granted
      ..clear()
      ..addAll(grantedScopes);
  }

  @override
  bool hasScopes(List<String> scopes) {
    if (_plugin.currentUser == null) return false;
    return scopes.every(_granted.contains);
  }

  @override
  Future<ScopeGrantResult> ensureScopes(List<String> scopes) async {
    if (_plugin.currentUser == null) {
      // Signed out → short-circuit, never triggers a sign-in prompt.
      return ScopeGrantResult(
        ScopeGrantOutcome.notSignedIn,
        List.unmodifiable(_granted),
      );
    }

    final missing = scopes.where((s) => !_granted.contains(s)).toList();
    if (missing.isEmpty) {
      return ScopeGrantResult(
        ScopeGrantOutcome.granted,
        List.unmodifiable(_granted),
      );
    }

    try {
      final granted = await _plugin.requestScopes(missing);
      if (granted) {
        _granted.addAll(missing);
        return ScopeGrantResult(
          ScopeGrantOutcome.granted,
          List.unmodifiable(_granted),
        );
      }
      return ScopeGrantResult(
        ScopeGrantOutcome.denied,
        List.unmodifiable(_granted),
      );
    } catch (_) {
      // Never throws for user denial or plugin failure.
      return ScopeGrantResult(
        ScopeGrantOutcome.failed,
        List.unmodifiable(_granted),
      );
    }
  }

  @override
  List<String> get grantedScopes => List.unmodifiable(_granted);

  @override
  void clear() => _granted.clear();
}
