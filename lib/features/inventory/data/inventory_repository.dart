import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/config_repository.dart';
import '../../../core/data/audit.dart';
import '../../../core/firebase/firebase_providers.dart';
import '../../../core/utils/work_day.dart';
import '../../projects/data/project_repository.dart';
import '../domain/inventory.dart';

/// Site stores: indents (requests), GRNs (receipts) and material issues, all
/// under the project. Stock is never stored; see [InventorySummary].
class InventoryRepository {
  InventoryRepository(this._db);

  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> _project(String pid) => _db.collection('projects').doc(pid);
  CollectionReference<Map<String, dynamic>> _col(String pid, String name) => _project(pid).collection(name);

  Stream<List<T>> _watch<T>(String pid, String name, T Function(String, Map<String, dynamic>) from) =>
      _col(pid, name).where('deleted', isEqualTo: false).snapshots().map((s) {
        final list = s.docs.map((d) => (d.data()['createdAt'] as Timestamp?, from(d.id, d.data()))).toList()
          ..sort((a, b) => (b.$1 ?? Timestamp.now()).compareTo(a.$1 ?? Timestamp.now()));
        return list.map((e) => e.$2).toList();
      });

  Stream<List<Indent>> watchIndents(String pid) => _watch(pid, 'indents', Indent.fromMap);
  Stream<List<Grn>> watchGrns(String pid) => _watch(pid, 'grns', Grn.fromMap);
  Stream<List<MaterialIssue>> watchIssues(String pid) => _watch(pid, 'materialIssues', MaterialIssue.fromMap);

  static String _number(String prefix) {
    final t = DateTime.now();
    return '$prefix-${t.year % 100}${t.month.toString().padLeft(2, '0')}-${(t.millisecondsSinceEpoch % 100000).toString().padLeft(5, '0')}';
  }

  static void _check(List<MaterialLine> items) {
    if (items.isEmpty) throw ArgumentError('Add at least one material.');
    for (final l in items) {
      if (l.material.trim().isEmpty || l.unit.trim().isEmpty) throw ArgumentError('Every line needs a material and a unit.');
      if (!(l.qty > 0)) throw ArgumentError('Quantities must be more than zero.');
    }
  }

  Future<void> raiseIndent({
    required String projectId,
    required List<MaterialLine> items,
    required String? neededBy,
    required String? phaseId,
    required String note,
    required String uid,
  }) async {
    _check(items);
    final ref = _col(projectId, 'indents').doc();
    final number = _number('IND');
    final batch = _db.batch();
    batch.set(ref, {
      'number': number,
      'items': [for (final l in items) l.toMap()],
      'neededBy': neededBy,
      'phaseId': phaseId,
      'note': note.trim(),
      'status': IndentStatus.pending.value,
      'requestedBy': uid,
      'requestedAt': FieldValue.serverTimestamp(),
      'revision': 1,
      ...auditCreate(uid),
    });
    ActivityEntry(
      actorId: uid,
      action: 'created',
      entity: 'indent',
      entityId: ref.id,
      projectId: projectId,
      summary: 'Raised indent $number: ${items.map((l) => '${formatQty(l.qty)} ${l.unit} ${l.material}').join(', ')}',
    ).addTo(batch, _db);
    await batch.commit();
  }

  /// Approves or rejects a pending indent. A transaction, so two approvers
  /// acting at once leave exactly one decision.
  Future<void> decideIndent(String projectId, String indentId, bool approve, String note, String uid) async {
    if (!approve && note.trim().isEmpty) throw ArgumentError('Add a reason for rejecting this indent.');
    final ref = _col(projectId, 'indents').doc(indentId);
    await _db.runTransaction((tx) async {
      final doc = await tx.get(ref);
      if (!doc.exists) throw StateError('Indent no longer exists.');
      final data = doc.data()!;
      if (IndentStatus.fromValue(data['status'] as String?) != IndentStatus.pending) {
        throw StateError('This indent was already decided.');
      }
      tx.update(ref, {
        'status': (approve ? IndentStatus.approved : IndentStatus.rejected).value,
        'decidedBy': uid,
        'decidedAt': FieldValue.serverTimestamp(),
        'decisionNote': note.trim(),
        'revision': ((data['revision'] as num?)?.toInt() ?? 0) + 1,
        ...auditUpdate(uid),
      });
      ActivityEntry(
        actorId: uid,
        action: approve ? 'approved' : 'rejected',
        entity: 'indent',
        entityId: indentId,
        projectId: projectId,
        summary: '${approve ? 'Approved' : 'Rejected'} indent ${data['number']}${note.trim().isEmpty ? '' : ': ${note.trim()}'}',
      ).addToTransaction(tx, _db);
    });
  }

  /// The requester withdraws their own indent while it is still waiting for
  /// approval. Soft delete, like everything else.
  Future<void> withdrawIndent(String projectId, String indentId, String uid) async {
    final ref = _col(projectId, 'indents').doc(indentId);
    await _db.runTransaction((tx) async {
      final doc = await tx.get(ref);
      if (!doc.exists) throw StateError('Indent no longer exists.');
      final data = doc.data()!;
      if (IndentStatus.fromValue(data['status'] as String?) != IndentStatus.pending) {
        throw StateError('This indent was already decided and can no longer be withdrawn.');
      }
      if (data['requestedBy'] != uid) throw StateError('Only the person who raised it can withdraw it.');
      tx.update(ref, {
        'deleted': true,
        'revision': ((data['revision'] as num?)?.toInt() ?? 0) + 1,
        ...auditUpdate(uid),
      });
      ActivityEntry(
        actorId: uid,
        action: 'withdrawn',
        entity: 'indent',
        entityId: indentId,
        projectId: projectId,
        summary: 'Withdrew indent ${data['number']}',
      ).addToTransaction(tx, _db);
    });
  }

  /// Closes an approved indent before everything arrived: the rest is no
  /// longer needed or was bought another way. Stops it counting as on order
  /// or late.
  Future<void> closeIndent(String projectId, String indentId, String note, String uid) async {
    if (note.trim().isEmpty) throw ArgumentError('Say why the rest is not coming.');
    final ref = _col(projectId, 'indents').doc(indentId);
    await _db.runTransaction((tx) async {
      final doc = await tx.get(ref);
      if (!doc.exists) throw StateError('Indent no longer exists.');
      final data = doc.data()!;
      if (IndentStatus.fromValue(data['status'] as String?) != IndentStatus.approved) {
        throw StateError('Only an approved indent awaiting delivery can be closed.');
      }
      tx.update(ref, {
        'status': IndentStatus.closed.value,
        'closeNote': note.trim(),
        'closedBy': uid,
        'closedAt': FieldValue.serverTimestamp(),
        'revision': ((data['revision'] as num?)?.toInt() ?? 0) + 1,
        ...auditUpdate(uid),
      });
      ActivityEntry(
        actorId: uid,
        action: 'closed',
        entity: 'indent',
        entityId: indentId,
        projectId: projectId,
        summary: 'Closed indent ${data['number']} short: ${note.trim()}',
      ).addToTransaction(tx, _db);
    });
  }

  /// Records goods received. Against an approved indent, [completesIndent]
  /// (everything ordered has now arrived) also marks the indent received;
  /// otherwise it stays open for the rest of the delivery.
  Future<void> recordGrn({
    required String projectId,
    required List<MaterialLine> items,
    required String vendor,
    required String invoiceNo,
    required String date,
    required String note,
    required String uid,
    String? indentId,
    bool completesIndent = true,
  }) async {
    _check(items);
    if (vendor.trim().isEmpty) throw ArgumentError('Enter the vendor.');
    final ref = _col(projectId, 'grns').doc();
    final number = _number('GRN');
    await _db.runTransaction((tx) async {
      DocumentSnapshot<Map<String, dynamic>>? indent;
      if (indentId != null) {
        indent = await tx.get(_col(projectId, 'indents').doc(indentId));
        if (!indent.exists) throw StateError('Indent no longer exists.');
        if (IndentStatus.fromValue(indent.data()!['status'] as String?) != IndentStatus.approved) {
          throw StateError('Only an approved indent can be received.');
        }
      }
      tx.set(ref, {
        'number': number,
        'items': [for (final l in items) l.toMap()],
        'vendor': vendor.trim(),
        'invoiceNo': invoiceNo.trim(),
        'date': date,
        'note': note.trim(),
        'indentId': indentId,
        'receivedBy': uid,
        'revision': 1,
        ...auditCreate(uid),
      });
      if (indent != null && completesIndent) {
        tx.update(indent.reference, {
          'status': IndentStatus.received.value,
          'grnId': ref.id,
          'receivedAt': FieldValue.serverTimestamp(),
          'revision': ((indent.data()!['revision'] as num?)?.toInt() ?? 0) + 1,
          ...auditUpdate(uid),
        });
      }
      ActivityEntry(
        actorId: uid,
        action: 'created',
        entity: 'grn',
        entityId: ref.id,
        projectId: projectId,
        summary: 'Received $number from ${vendor.trim()}'
            '${indent == null ? '' : '${completesIndent ? ' against' : ' (part delivery) against'} ${indent.data()!['number']}'}',
      ).addToTransaction(tx, _db);
    });
  }

  /// Issues material from the store to the work. [available] is the current
  /// stock by material key; the caller passes what it has on screen.
  Future<void> issueMaterial({
    required String projectId,
    required List<MaterialLine> items,
    required Map<String, double> available,
    required String date,
    required String? phaseId,
    required String issuedTo,
    required String note,
    required String uid,
  }) async {
    _check(items);
    // The same material on two lines must still fit in stock together.
    final wanted = <String, double>{};
    for (final l in items) {
      wanted[l.key] = (wanted[l.key] ?? 0) + l.qty;
    }
    for (final l in items) {
      final have = available[l.key] ?? 0;
      if (wanted[l.key]! > have + 1e-9) {
        throw StateError('Only ${formatQty(have)} ${l.unit} of ${l.material} in stock.');
      }
    }
    final ref = _col(projectId, 'materialIssues').doc();
    final number = _number('MI');
    final batch = _db.batch();
    batch.set(ref, {
      'number': number,
      'items': [for (final l in items) l.toMap()],
      'date': date,
      'phaseId': phaseId,
      'issuedTo': issuedTo.trim(),
      'note': note.trim(),
      'issuedBy': uid,
      'revision': 1,
      ...auditCreate(uid),
    });
    ActivityEntry(
      actorId: uid,
      action: 'created',
      entity: 'materialIssue',
      entityId: ref.id,
      projectId: projectId,
      summary: 'Issued ${items.map((l) => '${formatQty(l.qty)} ${l.unit} ${l.material}').join(', ')}'
          '${issuedTo.trim().isEmpty ? '' : ' to ${issuedTo.trim()}'}',
    ).addTo(batch, _db);
    await batch.commit();
  }
}

final inventoryRepositoryProvider = Provider<InventoryRepository>(
  (ref) => InventoryRepository(ref.watch(firestoreProvider)),
);

final projectIndentsProvider = StreamProvider.family<List<Indent>, String>(
  (ref, pid) => ref.watch(inventoryRepositoryProvider).watchIndents(pid),
);

final projectGrnsProvider = StreamProvider.family<List<Grn>, String>(
  (ref, pid) => ref.watch(inventoryRepositoryProvider).watchGrns(pid),
);

final projectMaterialIssuesProvider = StreamProvider.family<List<MaterialIssue>, String>(
  (ref, pid) => ref.watch(inventoryRepositoryProvider).watchIssues(pid),
);

/// Stock and open indents for one project, recomputed from source.
final projectInventoryProvider = Provider.family<AsyncValue<InventorySummary>, String>((ref, pid) {
  final indents = ref.watch(projectIndentsProvider(pid));
  final grns = ref.watch(projectGrnsProvider(pid));
  final issues = ref.watch(projectMaterialIssuesProvider(pid));
  final config = ref.watch(appConfigProvider);
  for (final AsyncValue<Object?> v in [indents, grns, issues]) {
    if (v.hasError) return AsyncError(v.error!, v.stackTrace ?? StackTrace.current);
    if (!v.hasValue) return const AsyncLoading();
  }
  return AsyncData(
    InventorySummary.calculate(
      indents: indents.requireValue,
      grns: grns.requireValue,
      issues: issues.requireValue,
      today: WorkDay.today(utcOffsetMinutes: config.company.utcOffsetMinutes),
    ),
  );
});

/// Indents waiting for approval on every project the user can see, for the
/// Approvals page. Each entry is (projectId, indent).
final visiblePendingIndentsProvider = Provider<AsyncValue<List<(String, Indent)>>>((ref) {
  final projects = ref.watch(rawVisibleProjectsProvider);
  if (!projects.hasValue) return const AsyncLoading();
  final feeds = [for (final p in projects.requireValue) (p.id, ref.watch(projectIndentsProvider(p.id)))];
  final out = <(String, Indent)>[];
  for (final (pid, feed) in feeds) {
    if (feed.hasError) continue;
    if (!feed.hasValue) return const AsyncLoading();
    out.addAll(feed.requireValue.where((i) => i.isPending).map((i) => (pid, i)));
  }
  out.sort((a, b) => (a.$2.requestedAt ?? DateTime(0)).compareTo(b.$2.requestedAt ?? DateTime(0)));
  return AsyncData(out);
});
