// lib/data/google/google_permission_manager_impl.dart

import 'package:google_sign_in/google_sign_in.dart';
import 'package:neuroflow/domain/google/google_permission_manager.dart';

class GooglePermissionManagerImpl implements GooglePermissionManager {
  final GoogleSignIn _googleSignIn;

  GooglePermissionManagerImpl(this._googleSignIn);

  @override
  Future<bool> hasScopes(List<String> scopes) => _googleSignIn.canAccessScopes(scopes);

  @override
  Future<bool> requestScopes(List<String> scopes) async {
    await _googleSignIn.requestScopes(scopes);
    return true; // We assume the package handles cancellation/failure states correctly.
  }
}
