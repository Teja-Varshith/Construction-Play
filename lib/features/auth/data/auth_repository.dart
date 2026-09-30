import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/config_repository.dart';
import '../../../core/data/audit.dart';
import '../../../core/firebase/firebase_providers.dart';

class AuthRepository {
  AuthRepository(this._auth, this._db);

  final FirebaseAuth _auth;
  final FirebaseFirestore _db;

  Stream<User?> authStateChanges() => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  Future<void> signIn(String email, String password) =>
      _auth.signInWithEmailAndPassword(email: email.trim(), password: password);

  Future<void> signOut() => _auth.signOut();

  Future<void> sendPasswordReset(String email) => _auth.sendPasswordResetEmail(email: email.trim());

  Future<void> changePassword({required String currentPassword, required String newPassword}) async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) throw StateError('Not signed in');
    await user.reauthenticateWithCredential(
      EmailAuthProvider.credential(email: user.email!, password: currentPassword),
    );
    await user.updatePassword(newPassword);
  }

  /// Whether first-run setup has been completed. Readable before sign-in.
  Stream<bool> watchSetupDone() => _db
      .collection('config')
      .doc('bootstrap')
      .snapshots()
      .map((s) => s.exists);

  /// First-run setup: creates the owner (admin) account and default config in
  /// one batch. If the batch is refused (wrong setup code), the half-created
  /// login is deleted again so the email can be reused.
  Future<void> createOwner({
    required String companyName,
    required String name,
    required String email,
    required String password,
    required String setupCode,
  }) async {
    final cred = await _auth.createUserWithEmailAndPassword(email: email.trim(), password: password);
    final uid = cred.user!.uid;
    try {
      final batch = _db.batch();
      batch.set(_db.collection('users').doc(uid), {
        'uid': uid,
        'name': name.trim(),
        'email': email.trim().toLowerCase(),
        'phone': '',
        'designation': 'Owner',
        'role': 'admin',
        'active': true,
        ...auditCreate(uid),
      });
      for (final entry in ConfigRepository.defaultDocs(companyName.trim(), uid).entries) {
        batch.set(_db.collection('config').doc(entry.key), entry.value);
      }
      batch.set(_db.collection('config').doc('bootstrap'), {
        'createdBy': uid,
        'setupCode': setupCode.trim(),
        'createdAt': FieldValue.serverTimestamp(),
      });
      ActivityEntry(
        actorId: uid,
        action: 'created',
        entity: 'company',
        entityId: 'bootstrap',
        summary: 'Set up ${companyName.trim()}',
      ).addTo(batch, _db);
      await batch.commit();
    } catch (e) {
      await cred.user?.delete();
      if (e is FirebaseException && e.code == 'permission-denied') {
        throw Exception('Setup code is wrong, or this company has already been set up.');
      }
      rethrow;
    }
  }
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(firebaseAuthProvider), ref.watch(firestoreProvider)),
);
