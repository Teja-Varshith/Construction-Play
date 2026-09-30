import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/audit.dart';
import '../../../core/firebase/firebase_providers.dart';
import '../../../firebase_options.dart';
import '../../auth/data/session.dart';
import '../../auth/domain/app_user.dart';

class UserRepository {
  UserRepository(this._db);

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _users => _db.collection('users');

  Stream<AppUser?> watch(String uid) => _users
      .doc(uid)
      .snapshots()
      .map((s) => s.exists ? AppUser.fromMap(s.id, s.data()!) : null);

  Stream<List<AppUser>> watchAll() => _users.orderBy('name').snapshots().map(
        (snap) => snap.docs.map((d) => AppUser.fromMap(d.id, d.data())).toList(),
      );

  /// Creates a login and profile for someone else.
  ///
  /// Without Cloud Functions, the client SDK would sign the admin out when it
  /// creates a new login. A separate, temporary Firebase app instance creates
  /// the login instead, so the admin stays signed in.
  Future<String> createUser({
    required String adminUid,
    required String name,
    required String email,
    required String password,
    required UserRole role,
    String phone = '',
    String designation = '',
  }) async {
    final app = await _secondaryApp();
    final secondaryAuth = FirebaseAuth.instanceFor(app: app);
    final cred = await secondaryAuth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final uid = cred.user!.uid;
    try {
      final batch = _db.batch();
      batch.set(_users.doc(uid), {
        'uid': uid,
        'name': name.trim(),
        'email': email.trim().toLowerCase(),
        'phone': phone.trim(),
        'designation': designation.trim(),
        'role': role.name,
        'active': true,
        ...auditCreate(adminUid),
      });
      ActivityEntry(
        actorId: adminUid,
        action: 'created',
        entity: 'user',
        entityId: uid,
        summary: 'Added ${name.trim()} as ${role.label}',
      ).addTo(batch, _db);
      await batch.commit();
    } catch (_) {
      // Don't leave a login behind that has no profile.
      await cred.user?.delete();
      rethrow;
    } finally {
      await secondaryAuth.signOut();
    }
    return uid;
  }

  Future<void> updateUser({
    required String adminUid,
    required AppUser before,
    required String name,
    required String phone,
    required String designation,
    required UserRole role,
    required bool active,
  }) async {
    final changes = <String, dynamic>{
      if (before.name != name.trim()) 'name': [before.name, name.trim()],
      if (before.role != role) 'role': [before.role.name, role.name],
      if (before.active != active) 'active': [before.active, active],
    };
    final batch = _db.batch();
    batch.update(_users.doc(before.uid), {
      'name': name.trim(),
      'phone': phone.trim(),
      'designation': designation.trim(),
      'role': role.name,
      'active': active,
      ...auditUpdate(adminUid),
    });
    ActivityEntry(
      actorId: adminUid,
      action: before.active && !active ? 'deactivated' : (!before.active && active ? 'reactivated' : 'updated'),
      entity: 'user',
      entityId: before.uid,
      summary: 'Updated ${name.trim()}',
      changes: changes.isEmpty ? null : changes,
    ).addTo(batch, _db);
    await batch.commit();
  }

  /// A person editing their own name or phone number.
  Future<void> updateOwnProfile({required String uid, required String name, required String phone}) =>
      _users.doc(uid).update({'name': name.trim(), 'phone': phone.trim(), ...auditUpdate(uid)});

  /// Returns the uid for a demo login, creating the login if needed. If the
  /// login already exists (e.g. an earlier demo load), signs in with the
  /// shared demo password to find it.
  Future<String> ensureLogin(String email, String password) async {
    final auth = FirebaseAuth.instanceFor(app: await _secondaryApp());
    try {
      final cred = await auth.createUserWithEmailAndPassword(email: email, password: password);
      return cred.user!.uid;
    } on FirebaseAuthException catch (e) {
      if (e.code != 'email-already-in-use') rethrow;
      final cred = await auth.signInWithEmailAndPassword(email: email, password: password);
      return cred.user!.uid;
    } finally {
      await auth.signOut();
    }
  }

  /// Writes a profile for a login that already exists (see [ensureLogin]),
  /// or reactivates it if it is already there.
  Future<void> upsertProfile({
    required String adminUid,
    required String uid,
    required String name,
    required String email,
    required UserRole role,
    String designation = '',
  }) async {
    final doc = await _users.doc(uid).get();
    final batch = _db.batch();
    if (doc.exists) {
      batch.update(_users.doc(uid), {
        'name': name,
        'role': role.name,
        'active': true,
        'designation': designation,
        ...auditUpdate(adminUid),
      });
    } else {
      batch.set(_users.doc(uid), {
        'uid': uid,
        'name': name,
        'email': email.toLowerCase(),
        'phone': '',
        'designation': designation,
        'role': role.name,
        'active': true,
        ...auditCreate(adminUid),
      });
    }
    ActivityEntry(
      actorId: adminUid,
      action: doc.exists ? 'updated' : 'created',
      entity: 'user',
      entityId: uid,
      summary: '${doc.exists ? 'Reactivated' : 'Added'} demo login $name as ${role.label}',
    ).addTo(batch, _db);
    await batch.commit();
  }

  static Future<FirebaseApp> _secondaryApp() async {
    const name = 'user-admin';
    final existing = Firebase.apps.where((a) => a.name == name).firstOrNull;
    return existing ??
        Firebase.initializeApp(name: name, options: DefaultFirebaseOptions.currentPlatform);
  }
}

final userRepositoryProvider = Provider<UserRepository>(
  (ref) => UserRepository(ref.watch(firestoreProvider)),
);

final userProvider = StreamProvider.family<AppUser?, String>(
  (ref, uid) => ref.watch(userRepositoryProvider).watch(uid),
);

final allUsersProvider = StreamProvider<List<AppUser>>((ref) {
  final ready = ref.watch(sessionProvider.select((s) => s.isReady));
  if (!ready) return Stream.value(const []);
  return ref.watch(userRepositoryProvider).watchAll();
});
