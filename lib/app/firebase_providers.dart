import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:neuroflow/platform/firebase/firebase_auth_service.dart';
import 'package:neuroflow/platform/firebase/firestore_backend.dart';

final firebaseAuthServiceProvider = Provider<FirebaseAuthService>((ref) {
  return FirebaseAuthService();
});

final firebaseUserProvider = StreamProvider<User?>((ref) {
  if (!FirebaseAuthService.isFirebaseReady) {
    return Stream<User?>.value(null);
  }
  return ref.watch(firebaseAuthServiceProvider).authStateChanges;
});

final firestoreBackendProvider = Provider<FirestoreBackend>((ref) {
  return FirestoreBackend();
});

final cloudSyncAvailableProvider = Provider<bool>((ref) {
  if (!FirebaseAuthService.isFirebaseReady) return false;
  return ref.watch(firebaseUserProvider).when(
        data: (user) => user != null,
        loading: () => false,
        error: (_, __) => false,
      );
});
