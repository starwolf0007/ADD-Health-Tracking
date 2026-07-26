// lib/data/google/google_permission_manager_impl.dart
//
// google_sign_in 7.x: scope management moves to GoogleSignInAuthorizationClient.
//   hasScopes  → authorizationForScopes() (null = not granted, no UI)
//   requestScopes → authorizeScopes() (interactive; caller must invoke from user action)

import 'package:google_sign_in/google_sign_in.dart';
import 'package:neuroflow/domain/google/google_permission_manager.dart';

class GooglePermissionManagerImpl implements GooglePermissionManager {
  @override
  Future<bool> hasScopes(List<String> scopes) async {
    final auth = await GoogleSignIn.instance.authorizationClient
        .authorizationForScopes(scopes);
    return auth != null;
  }

  @override
  Future<bool> requestScopes(List<String> scopes) async {
    try {
      await GoogleSignIn.instance.authorizationClient.authorizeScopes(scopes);
      return true;
    } catch (_) {
      return false;
    }
  }
}
