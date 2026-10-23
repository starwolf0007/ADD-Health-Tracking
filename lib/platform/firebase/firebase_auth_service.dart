import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'package:neuroflow/platform/google/google_sign_in_bootstrap.dart';

/// Firebase Authentication boundary for NeuroFlow.
///
/// This owns Firebase account identity only. It deliberately does not sign the
/// shared GoogleSignIn singleton out when FirebaseAuth signs out, because that
/// singleton is also used by the independent Google Tasks integration.
class FirebaseAuthService {
  FirebaseAuthService({FirebaseAuth? auth})
      : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;

  Stream<User?> get authStateChanges => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  static bool get isFirebaseReady => Firebase.apps.isNotEmpty;

  Future<UserCredential> createAccountWithEmail({
    required String email,
    required String password,
  }) {
    _requireFirebase();
    return _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<UserCredential> signInWithEmail({
    required String email,
    required String password,
  }) {
    _requireFirebase();
    return _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<void> sendPasswordResetEmail(String email) {
    _requireFirebase();
    return _auth.sendPasswordResetEmail(email: email.trim());
  }

  Future<void> sendEmailVerification() async {
    _requireFirebase();
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('No Firebase user is signed in.');
    }
    await user.sendEmailVerification();
  }

  Future<UserCredential> signInWithGoogle() async {
    _requireFirebase();
    final signIn = await GoogleSignInBootstrap.instance();
    if (!signIn.supportsAuthenticate()) {
      throw StateError('Google Sign-In is not supported on this platform.');
    }

    final account = await signIn.authenticate();
    if (account == null) {
      throw StateError('Google Sign-In did not return an account.');
    }
    final GoogleSignInAuthentication authentication = account.authentication;
    final idToken = authentication.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw StateError('Google Sign-In did not return an ID token.');
    }

    final credential = GoogleAuthProvider.credential(idToken: idToken);
    return _auth.signInWithCredential(credential);
  }

  Future<void> startPhoneVerification({
    required String phoneNumber,
    required void Function(PhoneAuthCredential credential)
        verificationCompleted,
    required void Function(FirebaseAuthException error) verificationFailed,
    required void Function(String verificationId, int? resendToken) codeSent,
    required void Function(String verificationId) codeAutoRetrievalTimeout,
    int? forceResendingToken,
  }) async {
    _requireFirebase();
    await _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber.trim(),
      verificationCompleted: verificationCompleted,
      verificationFailed: verificationFailed,
      codeSent: codeSent,
      codeAutoRetrievalTimeout: codeAutoRetrievalTimeout,
      forceResendingToken: forceResendingToken,
    );
  }

  Future<UserCredential> signInWithPhoneCode({
    required String verificationId,
    required String smsCode,
  }) {
    _requireFirebase();
    final credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode.trim(),
    );
    return _auth.signInWithCredential(credential);
  }

  Future<UserCredential> signInWithPhoneCredential(
    PhoneAuthCredential credential,
  ) {
    _requireFirebase();
    return _auth.signInWithCredential(credential);
  }

  Future<void> signOut() {
    _requireFirebase();
    return _auth.signOut();
  }

  void _requireFirebase() {
    if (!isFirebaseReady) {
      throw StateError(
        'Firebase is unavailable in this build. Use a configured build with '
        'google-services.json restored before using cloud account features.',
      );
    }
  }
}
