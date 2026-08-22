import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

/// Authenticated, user-scoped Firestore mirror for NeuroFlow cloud data.
///
/// Drift remains the on-device source of truth. This boundary intentionally
/// exposes explicit mirror operations instead of silently replacing local data.
class FirestoreBackend {
  FirestoreBackend({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  String get _uid {
    if (Firebase.apps.isEmpty) {
      throw StateError('Firebase is unavailable in this build.');
    }
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('A Firebase account is required for cloud sync.');
    }
    return user.uid;
  }

  DocumentReference<Map<String, dynamic>> get _userDoc =>
      _firestore.collection('users').doc(_uid);

  CollectionReference<Map<String, dynamic>> collection(String name) =>
      _userDoc.collection(name);

  Future<void> ensureUserProfile() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('A Firebase account is required for cloud sync.');
    }
    await _userDoc.set(
      {
        'uid': user.uid,
        'emailVerified': user.emailVerified,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> upsertTask({
    required String id,
    required Map<String, Object?> data,
  }) {
    return collection('tasks').doc(id).set(
      {
        ...data,
        'id': id,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> deleteTask(String id) => collection('tasks').doc(id).delete();

  Future<void> upsertRoutine({
    required String id,
    required Map<String, Object?> data,
  }) {
    return collection('routines').doc(id).set(
      {
        ...data,
        'id': id,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> deleteRoutine(String id) =>
      collection('routines').doc(id).delete();

  Future<DocumentReference<Map<String, dynamic>>> appendDailyStoryEvent({
    required Map<String, Object?> data,
  }) {
    return collection('dailyStory').add({
      ...data,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchTasks() =>
      collection('tasks').snapshots();

  Stream<QuerySnapshot<Map<String, dynamic>>> watchRoutines() =>
      collection('routines').snapshots();
}
