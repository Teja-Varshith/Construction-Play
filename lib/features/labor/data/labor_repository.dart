import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/audit.dart';
import '../../../core/firebase/firebase_providers.dart';
import '../domain/labor_model.dart';

class LaborRepository {
  LaborRepository(this._db);

  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> _laborDoc(String projectId, String date) =>
      _db.collection('projects').doc(projectId).collection('labour').doc(date);

  Stream<DailyLaborMuster?> watchLaborMuster(String projectId, String date) =>
      _laborDoc(projectId, date).snapshots().map((s) =>
          s.exists ? DailyLaborMuster.fromMap(s.id, projectId, s.data()!) : null);

  Stream<List<DailyLaborMuster>> watchRecentMusters(String projectId) =>
      _db.collection('projects').doc(projectId).collection('labour')
          .orderBy('date', descending: true)
          .limit(30)
          .snapshots()
          .map((snap) => snap.docs.map((d) => DailyLaborMuster.fromMap(d.id, projectId, d.data())).toList());

  Future<void> saveLaborMuster({
    required String uid,
    required String supervisorName,
    required String projectId,
    required String date,
    required List<LaborEntry> entries,
  }) async {
    final docRef = _laborDoc(projectId, date);
    final snap = await docRef.get();
    final batch = _db.batch();

    final muster = DailyLaborMuster(
      id: date,
      projectId: projectId,
      date: date,
      entries: entries,
      supervisorId: uid,
      supervisorName: supervisorName,
      verifiedByManager: false,
    );

    if (snap.exists) {
      final rev = (snap.data()?['revision'] as int?) ?? 1;
      batch.update(docRef, {
        ...muster.toMap(),
        'revision': rev + 1,
        ...auditUpdate(uid),
      });
    } else {
      batch.set(docRef, {
        ...muster.toMap(),
        'revision': 1,
        ...auditCreate(uid),
      });
    }

    ActivityEntry(
      actorId: uid,
      projectId: projectId,
      action: 'labor_muster_logged',
      entity: 'labor',
      entityId: date,
      summary: 'Logged labor muster (${muster.totalWorkers} workers) for $date',
    ).addTo(batch, _db);

    await batch.commit();
  }

  Future<void> verifyLaborMuster({
    required String uid,
    required String projectId,
    required String date,
  }) async {
    final docRef = _laborDoc(projectId, date);
    final snap = await docRef.get();
    if (!snap.exists) return;

    final batch = _db.batch();
    final rev = (snap.data()?['revision'] as int?) ?? 1;
    batch.update(docRef, {
      'verifiedByManager': true,
      'verifiedBy': uid,
      'verifiedAt': FieldValue.serverTimestamp(),
      'revision': rev + 1,
      ...auditUpdate(uid),
    });

    ActivityEntry(
      actorId: uid,
      projectId: projectId,
      action: 'labor_muster_verified',
      entity: 'labor',
      entityId: date,
      summary: 'Manager verified labor muster for $date',
    ).addTo(batch, _db);

    await batch.commit();
  }
}

final laborRepositoryProvider = Provider<LaborRepository>((ref) {
  return LaborRepository(ref.watch(firestoreProvider));
});

final todayLaborProvider = StreamProvider.family<DailyLaborMuster?, ({String projectId, String date})>((ref, arg) {
  return ref.watch(laborRepositoryProvider).watchLaborMuster(arg.projectId, arg.date);
});

final recentLaborMustersProvider = StreamProvider.family<List<DailyLaborMuster>, String>((ref, projectId) {
  return ref.watch(laborRepositoryProvider).watchRecentMusters(projectId);
});
