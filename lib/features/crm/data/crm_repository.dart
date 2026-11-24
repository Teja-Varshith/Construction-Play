import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/audit.dart';
import '../../../core/firebase/firebase_providers.dart';
import '../domain/lead_model.dart';
import '../domain/sales_target_model.dart';

class CrmRepository {
  CrmRepository(this._db);

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _leads => _db.collection('leads');
  CollectionReference<Map<String, dynamic>> get _targets => _db.collection('salesTargets');

  Stream<List<Lead>> watchLeads({String? assignedToUid, BusinessVertical? vertical}) {
    Query<Map<String, dynamic>> q = _leads.where('deleted', isEqualTo: false);
    if (assignedToUid != null && assignedToUid.isNotEmpty) {
      q = q.where('assignedToUid', isEqualTo: assignedToUid);
    }
    if (vertical != null) {
      q = q.where('vertical', isEqualTo: vertical.name);
    }
    return q.snapshots().map(
          (snap) => snap.docs.map((d) => Lead.fromMap(d.id, d.data())).toList(),
        );
  }

  Stream<Lead?> watchLead(String leadId) => _leads
      .doc(leadId)
      .snapshots()
      .map((s) => s.exists ? Lead.fromMap(s.id, s.data()!) : null);

  Stream<List<SalesTarget>> watchTargets(String yearMonth) => _targets
      .where('yearMonth', isEqualTo: yearMonth)
      .where('deleted', isEqualTo: false)
      .snapshots()
      .map((snap) => snap.docs.map((d) => SalesTarget.fromMap(d.id, d.data())).toList());

  Future<String> createLead({
    required String uid,
    required String clientName,
    required String phone,
    String email = '',
    required BusinessVertical vertical,
    required LeadStage stage,
    int estimatedValuePaise = 0,
    int quotationValuePaise = 0,
    String assignedToUid = '',
    String assignedToName = '',
    String requirementDetails = '',
    String siteLocation = '',
  }) async {
    final docRef = _leads.doc();
    final lead = Lead(
      id: docRef.id,
      clientName: clientName,
      phone: phone,
      email: email,
      vertical: vertical,
      stage: stage,
      estimatedValuePaise: estimatedValuePaise,
      quotationValuePaise: quotationValuePaise,
      assignedToUid: assignedToUid,
      assignedToName: assignedToName,
      requirementDetails: requirementDetails,
      siteLocation: siteLocation,
      deleted: false,
      revision: 1,
    );

    final batch = _db.batch();
    batch.set(docRef, {
      ...lead.toMap(),
      ...auditCreate(uid),
    });

    ActivityEntry(
      actorId: uid,
      action: 'created',
      entity: 'lead',
      entityId: docRef.id,
      summary: 'Added new enquiry for $clientName (${vertical.label})',
    ).addTo(batch, _db);

    await batch.commit();
    return docRef.id;
  }

  Future<void> updateLeadStage({
    required String uid,
    required Lead lead,
    required LeadStage newStage,
    String? lostReason,
  }) async {
    final batch = _db.batch();
    final updates = <String, dynamic>{
      'stage': newStage.name,
      'revision': lead.revision + 1,
      ...auditUpdate(uid),
    };
    if (lostReason != null) {
      updates['lostReason'] = lostReason;
    }

    batch.update(_leads.doc(lead.id), updates);

    ActivityEntry(
      actorId: uid,
      action: 'updated',
      entity: 'lead',
      entityId: lead.id,
      summary: 'Moved ${lead.clientName} to ${newStage.label}',
    ).addTo(batch, _db);

    await batch.commit();
  }

  Future<void> updateQuotationAndEstimation({
    required String uid,
    required Lead lead,
    required int estimatedValuePaise,
    required int quotationValuePaise,
    String requirementDetails = '',
  }) async {
    final batch = _db.batch();
    batch.update(_leads.doc(lead.id), {
      'estimatedValuePaise': estimatedValuePaise,
      'quotationValuePaise': quotationValuePaise,
      if (requirementDetails.isNotEmpty) 'requirementDetails': requirementDetails,
      'revision': lead.revision + 1,
      ...auditUpdate(uid),
    });

    ActivityEntry(
      actorId: uid,
      action: 'updated',
      entity: 'lead',
      entityId: lead.id,
      summary: 'Updated quotation for ${lead.clientName}',
    ).addTo(batch, _db);

    await batch.commit();
  }

  Future<void> assignLead({
    required String uid,
    required Lead lead,
    required String assignedToUid,
    required String assignedToName,
  }) async {
    final batch = _db.batch();
    batch.update(_leads.doc(lead.id), {
      'assignedToUid': assignedToUid,
      'assignedToName': assignedToName,
      'revision': lead.revision + 1,
      ...auditUpdate(uid),
    });

    ActivityEntry(
      actorId: uid,
      action: 'assigned',
      entity: 'lead',
      entityId: lead.id,
      summary: 'Assigned lead ${lead.clientName} to $assignedToName',
    ).addTo(batch, _db);

    await batch.commit();
  }

  Future<void> addFollowUp({
    required String uid,
    required Lead lead,
    required String scheduledDate,
    required String notes,
    required String recordedByName,
  }) async {
    final newFollowUp = LeadFollowUp(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      scheduledDate: scheduledDate,
      notes: notes,
      done: false,
      recordedByName: recordedByName,
    );

    final updatedList = [...lead.followUps, newFollowUp];
    final batch = _db.batch();
    batch.update(_leads.doc(lead.id), {
      'followUps': updatedList.map((f) => f.toMap()).toList(),
      'revision': lead.revision + 1,
      ...auditUpdate(uid),
    });

    ActivityEntry(
      actorId: uid,
      action: 'follow_up_scheduled',
      entity: 'lead',
      entityId: lead.id,
      summary: 'Scheduled follow-up for ${lead.clientName} on $scheduledDate',
    ).addTo(batch, _db);

    await batch.commit();
  }

  Future<void> markFollowUpDone({
    required String uid,
    required Lead lead,
    required String followUpId,
    required String completedDate,
  }) async {
    final updatedList = lead.followUps.map((f) {
      if (f.id == followUpId) {
        return LeadFollowUp(
          id: f.id,
          scheduledDate: f.scheduledDate,
          notes: f.notes,
          done: true,
          completedDate: completedDate,
          recordedByName: f.recordedByName,
        );
      }
      return f;
    }).toList();

    final batch = _db.batch();
    batch.update(_leads.doc(lead.id), {
      'followUps': updatedList.map((f) => f.toMap()).toList(),
      'revision': lead.revision + 1,
      ...auditUpdate(uid),
    });

    await batch.commit();
  }

  Future<void> saveSalesTarget({
    required String uid,
    required String yearMonth,
    required String employeeUid,
    required String employeeName,
    required int targetPaise,
    required int targetLeadsCount,
    required int targetWonCount,
  }) async {
    final docId = '${yearMonth}_$employeeUid';
    final ref = _targets.doc(docId);
    final snap = await ref.get();
    final batch = _db.batch();

    if (snap.exists) {
      final currentRev = (snap.data()?['revision'] as int?) ?? 1;
      batch.update(ref, {
        'targetPaise': targetPaise,
        'targetLeadsCount': targetLeadsCount,
        'targetWonCount': targetWonCount,
        'employeeName': employeeName,
        'revision': currentRev + 1,
        ...auditUpdate(uid),
      });
    } else {
      batch.set(ref, {
        'yearMonth': yearMonth,
        'employeeUid': employeeUid,
        'employeeName': employeeName,
        'targetPaise': targetPaise,
        'achievedPaise': 0,
        'targetLeadsCount': targetLeadsCount,
        'achievedLeadsCount': 0,
        'targetWonCount': targetWonCount,
        'achievedWonCount': 0,
        'deleted': false,
        'revision': 1,
        ...auditCreate(uid),
      });
    }

    ActivityEntry(
      actorId: uid,
      action: 'target_set',
      entity: 'sales_target',
      entityId: docId,
      summary: 'Set sales target for $employeeName for $yearMonth',
    ).addTo(batch, _db);

    await batch.commit();
  }
}

final crmRepositoryProvider = Provider<CrmRepository>((ref) {
  return CrmRepository(ref.watch(firestoreProvider));
});

final allLeadsProvider = StreamProvider<List<Lead>>((ref) {
  return ref.watch(crmRepositoryProvider).watchLeads();
});

final myLeadsProvider = StreamProvider.family<List<Lead>, String>((ref, uid) {
  return ref.watch(crmRepositoryProvider).watchLeads(assignedToUid: uid);
});

final leadProvider = StreamProvider.family<Lead?, String>((ref, leadId) {
  return ref.watch(crmRepositoryProvider).watchLead(leadId);
});

final salesTargetsProvider = StreamProvider.family<List<SalesTarget>, String>((ref, yearMonth) {
  return ref.watch(crmRepositoryProvider).watchTargets(yearMonth);
});
