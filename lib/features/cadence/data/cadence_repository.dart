import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/audit.dart';
import '../../../core/firebase/firebase_providers.dart';
import '../domain/daily_cadence_model.dart';

class CadenceRepository {
  CadenceRepository(this._db);

  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> _cadenceDoc(String projectId, String date) =>
      _db.collection('projects').doc(projectId).collection('cadence').doc(date);

  Stream<DailyCadence?> watchCadence(String projectId, String date) =>
      _cadenceDoc(projectId, date).snapshots().map((s) =>
          s.exists ? DailyCadence.fromMap(s.id, projectId, s.data()!) : null);

  Future<void> submitMorningPlan({
    required String uid,
    required String projectId,
    required String date,
    required String plannedTasks,
    required String targetOutput,
    required int plannedLaborCount,
    required bool materialsReady,
    required String supervisorNotes,
  }) async {
    final docRef = _cadenceDoc(projectId, date);
    final snap = await docRef.get();
    final batch = _db.batch();

    final morningMap = {
      'plannedTasks': plannedTasks,
      'targetOutput': targetOutput,
      'plannedLaborCount': plannedLaborCount,
      'materialsReady': materialsReady,
      'supervisorNotes': supervisorNotes,
      'submittedBy': uid,
      'submittedAt': DateTime.now().toIso8601String(),
    };

    if (snap.exists) {
      final rev = (snap.data()?['revision'] as int?) ?? 1;
      batch.update(docRef, {
        'morningPlan': morningMap,
        'revision': rev + 1,
        ...auditUpdate(uid),
      });
    } else {
      batch.set(docRef, {
        'date': date,
        'morningPlan': morningMap,
        'middayReview': {},
        'dailyClosing': {},
        'revision': 1,
        ...auditCreate(uid),
      });
    }

    ActivityEntry(
      actorId: uid,
      projectId: projectId,
      action: 'cadence_morning_submitted',
      entity: 'cadence',
      entityId: date,
      summary: 'Submitted 8:30 AM Daily Plan for $date',
    ).addTo(batch, _db);

    await batch.commit();
  }

  Future<void> submitMiddayReview({
    required String uid,
    required String projectId,
    required String date,
    required MiddayStatus status,
    required String progressNotes,
    required int laborPresentCount,
    required String bottlenecks,
  }) async {
    final docRef = _cadenceDoc(projectId, date);
    final snap = await docRef.get();
    final batch = _db.batch();

    final middayMap = {
      'status': status.name,
      'progressNotes': progressNotes,
      'laborPresentCount': laborPresentCount,
      'bottlenecks': bottlenecks,
      'submittedBy': uid,
      'submittedAt': DateTime.now().toIso8601String(),
    };

    if (snap.exists) {
      final rev = (snap.data()?['revision'] as int?) ?? 1;
      batch.update(docRef, {
        'middayReview': middayMap,
        'revision': rev + 1,
        ...auditUpdate(uid),
      });
    } else {
      batch.set(docRef, {
        'date': date,
        'morningPlan': {},
        'middayReview': middayMap,
        'dailyClosing': {},
        'revision': 1,
        ...auditCreate(uid),
      });
    }

    ActivityEntry(
      actorId: uid,
      projectId: projectId,
      action: 'cadence_midday_submitted',
      entity: 'cadence',
      entityId: date,
      summary: 'Logged 1:00 PM Progress Review ($status) for $date',
    ).addTo(batch, _db);

    await batch.commit();
  }

  Future<void> submitDailyClosing({
    required String uid,
    required String projectId,
    required String date,
    required String actualOutput,
    required String workCompletedSummary,
    required String delaysEncountered,
    List<String> photoUrls = const [],
  }) async {
    final docRef = _cadenceDoc(projectId, date);
    final snap = await docRef.get();
    final batch = _db.batch();

    final closingMap = {
      'actualOutput': actualOutput,
      'workCompletedSummary': workCompletedSummary,
      'delaysEncountered': delaysEncountered,
      'photoUrls': photoUrls,
      'managerSignoff': 'pending',
      'submittedBy': uid,
      'submittedAt': DateTime.now().toIso8601String(),
    };

    if (snap.exists) {
      final rev = (snap.data()?['revision'] as int?) ?? 1;
      batch.update(docRef, {
        'dailyClosing': closingMap,
        'revision': rev + 1,
        ...auditUpdate(uid),
      });
    } else {
      batch.set(docRef, {
        'date': date,
        'morningPlan': {},
        'middayReview': {},
        'dailyClosing': closingMap,
        'revision': 1,
        ...auditCreate(uid),
      });
    }

    ActivityEntry(
      actorId: uid,
      projectId: projectId,
      action: 'cadence_closing_submitted',
      entity: 'cadence',
      entityId: date,
      summary: 'Submitted 9:30 PM Daily Closing for $date',
    ).addTo(batch, _db);

    await batch.commit();
  }

  Future<void> signoffDailyClosing({
    required String uid,
    required String projectId,
    required String date,
    required String managerSignoff, // approved | queried
    required String managerFeedback,
  }) async {
    final docRef = _cadenceDoc(projectId, date);
    final snap = await docRef.get();
    if (!snap.exists) return;

    final batch = _db.batch();
    final currentClosing = (snap.data()?['dailyClosing'] as Map<String, dynamic>?) ?? {};
    final updatedClosing = {
      ...currentClosing,
      'managerSignoff': managerSignoff,
      'managerFeedback': managerFeedback,
      'signedOffBy': uid,
      'signedOffAt': DateTime.now().toIso8601String(),
    };

    final rev = (snap.data()?['revision'] as int?) ?? 1;
    batch.update(docRef, {
      'dailyClosing': updatedClosing,
      'revision': rev + 1,
      ...auditUpdate(uid),
    });

    ActivityEntry(
      actorId: uid,
      projectId: projectId,
      action: 'cadence_signoff',
      entity: 'cadence',
      entityId: date,
      summary: 'Manager $managerSignoff Daily Closing for $date',
    ).addTo(batch, _db);

    await batch.commit();
  }
}

final cadenceRepositoryProvider = Provider<CadenceRepository>((ref) {
  return CadenceRepository(ref.watch(firestoreProvider));
});

final todayCadenceProvider = StreamProvider.family<DailyCadence?, ({String projectId, String date})>((ref, arg) {
  return ref.watch(cadenceRepositoryProvider).watchCadence(arg.projectId, arg.date);
});
