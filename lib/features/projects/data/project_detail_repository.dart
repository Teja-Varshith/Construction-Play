import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/firebase/firebase_providers.dart';
import '../../../core/data/audit.dart';
import '../../../core/utils/work_day.dart';
import '../domain/project_detail.dart';

/// Read models for the CEO drill-down. Each stream uses the project's own
/// subcollection, which keeps project security boundaries intact.
class ProjectDetailRepository {
  ProjectDetailRepository(this._db);

  final FirebaseFirestore _db;

  /// A single transaction protects against concurrent edits, project closure,
  /// and duplicate reports. Prior versions live in an immutable history.
  Future<void> save(
    String projectId,
    String collection,
    Map<String, dynamic> data, {
    required String uid,
    String? id,
    int? expectedRevision,
  }) async {
    if (!const {'phases', 'dprs', 'issues', 'documents'}.contains(collection)) {
      throw ArgumentError('Unsupported project record');
    }
    final parent = _db.collection('projects').doc(projectId);
    final record = _collection(projectId, collection).doc(id);
    final history = record.collection('revisions').doc();
    await _db.runTransaction((tx) async {
      final project = await tx.get(parent);
      final settings = await tx.get(
        _db.collection('config').doc('projectStatuses'),
      );
      final company = await tx.get(_db.collection('config').doc('company'));
      final current = await tx.get(record);
      final p = project.data();
      if (p == null || p['deleted'] == true) {
        throw StateError('Project is archived or unavailable.');
      }
      final statuses = (settings.data()?['items'] as List?) ?? [];
      final status = statuses
          .whereType<Map>()
          .where((s) => s['id'] == p['statusId'])
          .firstOrNull;
      if (const ['completed', 'cancelled'].contains(status?['stage'])) {
        throw StateError(
          'This project is closed. Ask the office to reopen it first.',
        );
      }
      final revision = (current.data()?['revision'] as num?)?.toInt() ?? 0;
      if (current.exists &&
          (expectedRevision == null || revision != expectedRevision)) {
        throw StateError(
          'This record has changed. Close this form and open the latest version.',
        );
      }
      if (!current.exists && expectedRevision != null) {
        throw StateError('Record no longer exists.');
      }
      if (collection == 'dprs') {
        final date = WorkDay.tryParse(data['date'] as String?);
        final today = WorkDay.tryParse(
          WorkDay.today(
            utcOffsetMinutes:
                (company.data()?['utcOffsetMinutes'] as num?)?.toInt() ?? 330,
          ),
        )!;
        final backdate =
            (company.data()?['dprBackdateDays'] as num?)?.toInt() ?? 7;
        if (date == null ||
            date.isAfter(today) ||
            today.difference(date).inDays > backdate) {
          throw StateError(
            'Reports must be dated within the last $backdate days.',
          );
        }
        if (id != data['date']) {
          throw StateError('Daily report date cannot change.');
        }
      }
      if (current.exists) {
        tx.set(history, {
          ...current.data()!,
          'savedAt': FieldValue.serverTimestamp(),
          'savedBy': uid,
        });
      }
      tx.set(record, {
        ...data,
        if (!current.exists) ...auditCreate(uid) else ...auditUpdate(uid),
        'revision': revision + 1,
      }, SetOptions(merge: true));
      tx.update(parent, auditUpdate(uid));
      ActivityEntry(
        actorId: uid,
        action: current.exists ? 'updated' : 'created',
        entity: collection,
        entityId: record.id,
        projectId: projectId,
        summary:
            '${data['deleted'] == true
                ? 'Archived'
                : current.exists
                ? 'Updated'
                : 'Added'} ${data['name'] ?? data['title'] ?? data['date'] ?? collection}',
      ).addToTransaction(tx, _db);
    });
  }

  Future<void> movePhase(
    String projectId,
    ProjectPhase a,
    ProjectPhase b,
    String uid,
  ) async {
    final parent = _db.collection('projects').doc(projectId);
    final aRef = _collection(projectId, 'phases').doc(a.id);
    final bRef = _collection(projectId, 'phases').doc(b.id);
    await _db.runTransaction((tx) async {
      final first = await tx.get(aRef);
      final second = await tx.get(bRef);
      if ((first.data()?['revision'] ?? 0) != a.revision ||
          (second.data()?['revision'] ?? 0) != b.revision) {
        throw StateError('Phases changed. Please retry using the latest list.');
      }
      tx.update(aRef, {
        'order': b.order,
        'revision': a.revision + 1,
        ...auditUpdate(uid),
      });
      tx.update(bRef, {
        'order': a.order,
        'revision': b.revision + 1,
        ...auditUpdate(uid),
      });
      tx.update(parent, auditUpdate(uid));
      ActivityEntry(
        actorId: uid,
        action: 'reordered',
        entity: 'phases',
        entityId: a.id,
        projectId: projectId,
        summary: 'Reordered ${a.name} and ${b.name}',
      ).addToTransaction(tx, _db);
    });
  }

  CollectionReference<Map<String, dynamic>> _collection(
    String projectId,
    String name,
  ) => _db.collection('projects').doc(projectId).collection(name);

  Stream<List<ProjectPhase>> watchPhases(String projectId) =>
      _collection(
        projectId,
        'phases',
      ).where('deleted', isEqualTo: false).snapshots().map((snapshot) {
        final values = snapshot.docs
            .map((doc) => ProjectPhase.fromMap(doc.id, doc.data()))
            .toList();
        values.sort((a, b) => a.order.compareTo(b.order));
        return values;
      });

  Stream<List<DailyProgressReport>> watchDprs(String projectId) =>
      _collection(
        projectId,
        'dprs',
      ).where('deleted', isEqualTo: false).snapshots().map((snapshot) {
        final values = snapshot.docs
            .map((doc) => DailyProgressReport.fromMap(doc.id, doc.data()))
            .toList();
        values.sort((a, b) => b.date.compareTo(a.date));
        return values;
      });

  Stream<List<ProjectIssue>> watchIssues(String projectId) =>
      _collection(
        projectId,
        'issues',
      ).where('deleted', isEqualTo: false).snapshots().map((snapshot) {
        final values = snapshot.docs
            .map((doc) => ProjectIssue.fromMap(doc.id, doc.data()))
            .toList();
        values.sort(
          (a, b) => (b.reportedAt ?? DateTime(0)).compareTo(
            a.reportedAt ?? DateTime(0),
          ),
        );
        return values;
      });

  Stream<List<ProjectDocument>> watchDocuments(String projectId) =>
      _collection(
        projectId,
        'documents',
      ).where('deleted', isEqualTo: false).snapshots().map((snapshot) {
        final values = snapshot.docs
            .map((doc) => ProjectDocument.fromMap(doc.id, doc.data()))
            .toList();
        values.sort(
          (a, b) => (b.createdAt ?? DateTime(0)).compareTo(
            a.createdAt ?? DateTime(0),
          ),
        );
        return values;
      });
}

final projectDetailRepositoryProvider = Provider<ProjectDetailRepository>(
  (ref) => ProjectDetailRepository(ref.watch(firestoreProvider)),
);

final projectPhasesProvider = StreamProvider.family<List<ProjectPhase>, String>(
  (ref, projectId) =>
      ref.watch(projectDetailRepositoryProvider).watchPhases(projectId),
);

final projectDprsProvider =
    StreamProvider.family<List<DailyProgressReport>, String>(
      (ref, projectId) =>
          ref.watch(projectDetailRepositoryProvider).watchDprs(projectId),
    );

final projectIssuesProvider = StreamProvider.family<List<ProjectIssue>, String>(
  (ref, projectId) =>
      ref.watch(projectDetailRepositoryProvider).watchIssues(projectId),
);

final projectDocumentsProvider =
    StreamProvider.family<List<ProjectDocument>, String>(
      (ref, projectId) =>
          ref.watch(projectDetailRepositoryProvider).watchDocuments(projectId),
    );
