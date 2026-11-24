import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/audit.dart';
import '../../../core/firebase/firebase_providers.dart';
import '../domain/design_model.dart';

class DesignRepository {
  DesignRepository(this._db);

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> _drawings(String projectId) =>
      _db.collection('projects').doc(projectId).collection('drawings');

  Stream<List<DesignDrawing>> watchDrawings(String projectId) =>
      _drawings(projectId).snapshots().map(
            (snap) => snap.docs.map((d) => DesignDrawing.fromMap(d.id, projectId, d.data())).toList(),
          );

  Future<String> addDrawing({
    required String uid,
    required String designerName,
    required String projectId,
    required String title,
    required DrawingCategory category,
    required String version,
    required DrawingStatus status,
    String fileUrl = '',
    String notes = '',
  }) async {
    final docRef = _drawings(projectId).doc();
    final batch = _db.batch();

    final initialRev = DrawingRevision(
      version: version,
      fileUrl: fileUrl,
      notes: notes.isNotEmpty ? notes : 'Initial version',
      changedBy: designerName,
      changedAt: DateTime.now(),
    );

    final drawing = DesignDrawing(
      id: docRef.id,
      projectId: projectId,
      title: title,
      category: category,
      currentVersion: version,
      status: status,
      fileUrl: fileUrl,
      designerUid: uid,
      designerName: designerName,
      notes: notes,
      revisions: [initialRev],
      revision: 1,
    );

    batch.set(docRef, {
      ...drawing.toMap(),
      ...auditCreate(uid),
    });

    ActivityEntry(
      actorId: uid,
      projectId: projectId,
      action: 'drawing_created',
      entity: 'drawing',
      entityId: docRef.id,
      summary: 'Added drawing "$title" ($version) in ${category.label}',
    ).addTo(batch, _db);

    await batch.commit();
    return docRef.id;
  }

  Future<void> uploadRevision({
    required String uid,
    required String designerName,
    required String projectId,
    required DesignDrawing drawing,
    required String newVersion,
    required String fileUrl,
    required String notes,
  }) async {
    final docRef = _drawings(projectId).doc(drawing.id);
    final batch = _db.batch();

    final newRev = DrawingRevision(
      version: newVersion,
      fileUrl: fileUrl,
      notes: notes,
      changedBy: designerName,
      changedAt: DateTime.now(),
    );

    final updatedRevs = [...drawing.revisions, newRev];

    batch.update(docRef, {
      'currentVersion': newVersion,
      'fileUrl': fileUrl,
      'notes': notes,
      'revisions': updatedRevs.map((r) => r.toMap()).toList(),
      'revision': drawing.revision + 1,
      ...auditUpdate(uid),
    });

    ActivityEntry(
      actorId: uid,
      projectId: projectId,
      action: 'drawing_revision',
      entity: 'drawing',
      entityId: drawing.id,
      summary: 'Uploaded $newVersion for "${drawing.title}"',
    ).addTo(batch, _db);

    await batch.commit();
  }

  Future<void> updateStatus({
    required String uid,
    required String projectId,
    required DesignDrawing drawing,
    required DrawingStatus newStatus,
    String? clientFeedback,
  }) async {
    final docRef = _drawings(projectId).doc(drawing.id);
    final batch = _db.batch();

    final updates = <String, dynamic>{
      'status': newStatus.name,
      'revision': drawing.revision + 1,
      ...auditUpdate(uid),
    };
    if (clientFeedback != null) {
      updates['clientFeedback'] = clientFeedback;
    }

    batch.update(docRef, updates);

    ActivityEntry(
      actorId: uid,
      projectId: projectId,
      action: 'drawing_status',
      entity: 'drawing',
      entityId: drawing.id,
      summary: 'Updated "${drawing.title}" status to ${newStatus.label}',
    ).addTo(batch, _db);

    await batch.commit();
  }
}

final designRepositoryProvider = Provider<DesignRepository>((ref) {
  return DesignRepository(ref.watch(firestoreProvider));
});

final projectDrawingsProvider = StreamProvider.family<List<DesignDrawing>, String>((ref, projectId) {
  return ref.watch(designRepositoryProvider).watchDrawings(projectId);
});
