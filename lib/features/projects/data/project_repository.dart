import 'package:cloud_firestore/cloud_firestore.dart';

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/audit.dart';
import '../../../core/config/config_models.dart';
import '../../../core/config/config_repository.dart';
import '../../../core/utils/work_day.dart';
import '../../../core/firebase/firebase_providers.dart';
import '../../auth/data/session.dart';
import '../../auth/domain/app_user.dart';
import '../domain/project.dart';
import '../domain/project_analysis.dart';
import 'project_detail_repository.dart';

/// Data access for projects. Phase 2 builds the screens on top of this.
class ProjectRepository {
  ProjectRepository(this._db);

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _projects =>
      _db.collection('projects');

  /// All projects, for the CEO and admins.
  Stream<List<Project>> watchAll() => _projects
      .where('deleted', isEqualTo: false)
      .snapshots()
      .map((s) => s.docs.map((d) => Project.fromMap(d.id, d.data())).toList());

  /// Projects a manager or supervisor belongs to. The query must filter on
  /// memberIds, or the security rules refuse it.
  Stream<List<Project>> watchForMember(String uid) => _projects
      .where('memberIds', arrayContains: uid)
      .where('deleted', isEqualTo: false)
      .snapshots()
      .map((s) => s.docs.map((d) => Project.fromMap(d.id, d.data())).toList());

  Stream<Project?> watch(String id) => _projects
      .doc(id)
      .snapshots()
      .map((s) => s.exists ? Project.fromMap(s.id, s.data()!) : null);

  Future<String> create(
    Project project, {
    required String uid,
    PhaseTemplate? phaseTemplate,
    required ProjectStage stage,
    required int statusIndex,
  }) async {
    final ref = _projects.doc();
    final batch = _db.batch();
    batch.set(ref, {
      ...project.toEditableMap(),
      'statusId': project.statusId,
      'stage': stage.name,
      'statusIndex': statusIndex,
      'revision': 0,
      'statusHistory': [
        {
          'statusId': project.statusId,
          'at': Timestamp.now(),
          'by': uid,
          'note': 'Created',
        },
      ],
      'plannedPct': 0,
      'actualPct': 0,
      'health': ProjectHealth.noData.name,
      'budgetTotalPaise': 0,
      'spentTotalPaise': 0,
      ...auditCreate(uid),
    });
    if (phaseTemplate != null) {
      for (var order = 0; order < phaseTemplate.phases.length; order++) {
        final phase = phaseTemplate.phases[order];
        final phaseRef = phase.id.isEmpty
            ? ref.collection('phases').doc()
            : ref.collection('phases').doc(phase.id);
        batch.set(phaseRef, {
          'name': phase.name,
          'order': order,
          'weight': phase.weight,
          'actualPct': 0,
          'deleted': false,
          ...auditCreate(uid),
        });
      }
    }
    ActivityEntry(
      actorId: uid,
      action: 'created',
      entity: 'project',
      entityId: ref.id,
      projectId: ref.id,
      summary: 'Created project ${project.name.trim()}',
    ).addTo(batch, _db);
    await batch.commit();
    return ref.id;
  }

  Future<void> update(Project project, {required String uid}) async {
    final batch = _db.batch();
    batch.update(_projects.doc(project.id), {
      ...project.toEditableMap(),
      ...auditUpdate(uid),
    });
    ActivityEntry(
      actorId: uid,
      action: 'updated',
      entity: 'project',
      entityId: project.id,
      projectId: project.id,
      summary: 'Updated project ${project.name.trim()}',
    ).addTo(batch, _db);
    await batch.commit();
  }

  Future<void> saveDetails(
    Project before,
    Map<String, dynamic> details,
    String uid,
  ) async {
    final doc = _projects.doc(before.id);
    await _db.runTransaction((tx) async {
      final current = await tx.get(doc);
      if ((current.data()?['revision'] ?? 0) != before.revision) {
        throw StateError(
          'Project details changed. Reopen the form to use the latest version.',
        );
      }
      tx.update(doc, {
        ...details,
        'revision': before.revision + 1,
        ...auditUpdate(uid),
      });
      ActivityEntry(
        actorId: uid,
        action: 'updated',
        entity: 'project',
        entityId: before.id,
        projectId: before.id,
        summary: 'Updated project details and team',
      ).addToTransaction(tx, _db);
    });
  }

  Future<void> setStatus(
    Project before,
    String statusId,
    String note,
    String uid,
    int offset,
  ) async {
    if (note.trim().isEmpty) {
      throw ArgumentError('Add a reason for the status change.');
    }
    final doc = _projects.doc(before.id);
    await _db.runTransaction((tx) async {
      final current = await tx.get(doc);
      final settings = await tx.get(
        _db.collection('config').doc('projectStatuses'),
      );
      final data = current.data()!;
      if (data['statusId'] != before.statusId) {
        throw StateError('Status changed. Please reload.');
      }
      final statuses = (settings.data()?['items'] as List?) ?? [];
      final index = statuses.indexWhere(
        (s) => s['id'] == statusId && s['archived'] != true,
      );
      if (index < 0) throw StateError('This status is no longer available.');
      final stage = statuses[index]['stage'] as String;
      final oldIndex = statuses.indexWhere((s) => s['id'] == data['statusId']);
      final oldStage = oldIndex < 0 ? 'pipeline' : statuses[oldIndex]['stage'];
      final today = WorkDay.today(utcOffsetMinutes: offset);
      final holds = [
        for (final h in (data['holdPeriods'] as List? ?? []))
          Map<String, dynamic>.from(h as Map),
      ];
      if (stage == 'onHold' && oldStage != 'onHold') {
        holds.add({'start': today});
      }
      if (oldStage == 'onHold' && stage != 'onHold' && holds.isNotEmpty) {
        holds.last['end'] = today;
      }
      if (stage == 'ongoing' &&
          (data['managerId'] == null ||
              data['startDate'] == null ||
              data['endDate'] == null)) {
        throw StateError(
          'Assign a manager and planned dates before starting the project.',
        );
      }
      tx.update(doc, {
        'statusId': statusId,
        'stage': stage,
        'statusIndex': index,
        'holdPeriods': holds,
        'statusHistory': FieldValue.arrayUnion([
          {
            'statusId': statusId,
            'at': Timestamp.now(),
            'by': uid,
            'note': note.trim(),
          },
        ]),
        'revision': ((data['revision'] as num?)?.toInt() ?? 0) + 1,
        ...auditUpdate(uid),
      });
      ActivityEntry(
        actorId: uid,
        action: 'status-changed',
        entity: 'project',
        entityId: before.id,
        projectId: before.id,
        summary: '${statuses[index]['label']}: ${note.trim()}',
        changes: {
          'statusId': [before.statusId, statusId],
        },
      ).addToTransaction(tx, _db);
    });
  }

  /// Moves a project to another status and records the change.
  Future<void> changeStatus(
    Project project,
    String statusId, {
    required String uid,
    String note = '',
  }) async {
    if (statusId == project.statusId) return;
    final batch = _db.batch();
    batch.update(_projects.doc(project.id), {
      'statusId': statusId,
      // serverTimestamp() is not allowed inside arrays, so the device time is used.
      'statusHistory': FieldValue.arrayUnion([
        {'statusId': statusId, 'at': Timestamp.now(), 'by': uid, 'note': note},
      ]),
      ...auditUpdate(uid),
    });
    ActivityEntry(
      actorId: uid,
      action: 'status-changed',
      entity: 'project',
      entityId: project.id,
      projectId: project.id,
      summary: 'Status changed for ${project.name}',
      changes: {
        'statusId': [project.statusId, statusId],
      },
    ).addTo(batch, _db);
    await batch.commit();
  }
}

final projectRepositoryProvider = Provider<ProjectRepository>(
  (ref) => ProjectRepository(ref.watch(firestoreProvider)),
);

/// The portfolio feed is deliberately role-aware. Leaders can read the whole
/// portfolio; delivery roles only receive projects where Firestore membership
/// is present, matching the security rule's required query shape.
final rawVisibleProjectsProvider = StreamProvider<List<Project>>((ref) {
  final user = ref.watch(currentUserProvider);
  final repository = ref.watch(projectRepositoryProvider);
  return switch (user.role) {
    UserRole.ceo || UserRole.admin => repository.watchAll(),
    _ => repository.watchForMember(user.uid),
  };
});

// Re-evaluate the schedule as the company's day changes, even with no writes.
final projectClockProvider = StreamProvider<DateTime>((ref) async* {
  yield DateTime.now();
  yield* Stream.periodic(const Duration(minutes: 1), (_) => DateTime.now());
});

final visibleProjectsProvider = Provider<AsyncValue<List<Project>>>((ref) {
  final raw = ref.watch(rawVisibleProjectsProvider);
  final config = ref.watch(appConfigProvider);
  final clock = ref.watch(projectClockProvider).value ?? DateTime.now();
  if (!raw.hasValue) return raw;
  final result = <Project>[];
  final phaseFeeds = {for (final p in raw.requireValue) p.id: ref.watch(projectPhasesProvider(p.id))};
  for (final project in raw.requireValue) {
      final phases = phaseFeeds[project.id]!;
      if (phases.hasError) {
        return AsyncError(phases.error!, phases.stackTrace ?? StackTrace.current);
      }
      if (!phases.hasValue) return const AsyncLoading();
      final analysis = ProjectAnalysis.calculate(
        project,
        phases.requireValue,
        config.stageOfStatus(project.statusId),
        WorkDay.key(clock, utcOffsetMinutes: config.company.utcOffsetMinutes),
      );
      result.add(project.withProgress(
        analysis.planned,
        analysis.actual,
        analysis.health,
      ));
  }
  return AsyncData(result);
});

final projectProvider = StreamProvider.family<Project?, String>(
  (ref, id) => ref.watch(projectRepositoryProvider).watch(id),
);
