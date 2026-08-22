import 'package:google_sign_in/google_sign_in.dart';

/// Owns the one-time initialization of the shared google_sign_in 7.x singleton.
///
/// Both the existing Google Tasks integration and Firebase Authentication reuse
/// this same instance so NeuroFlow never creates competing Google sessions.
class GoogleSignInBootstrap {
  GoogleSignInBootstrap._();

  static const _clientId =
      '287604372230-bpcl30912rp38ou92ltcs6iqe2977lrf.apps.googleusercontent.com';

  static final GoogleSignIn _signIn = GoogleSignIn.instance;
  static Future<void>? _initialization;

  static Future<GoogleSignIn> instance() async {
    _initialization ??= _signIn.initialize(
      clientId: _clientId,
      serverClientId: _clientId,
    );
    await _initialization;
    return _signIn;
  }
}
