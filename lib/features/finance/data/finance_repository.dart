import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/config_repository.dart';
import '../../../core/data/audit.dart';
import '../../../core/firebase/firebase_providers.dart';
import '../../../core/utils/work_day.dart';
import '../../projects/data/project_detail_repository.dart';
import '../../projects/data/project_repository.dart';
import '../../projects/domain/project_analysis.dart';
import '../domain/expense.dart';

/// No Cloud Functions yet (see README): every total the Money tab shows is
/// recomputed from source expenses at read time (see
/// `FinanceSummary.calculate`), never stored and incremented. Firestore
/// transactions and security rules are the only guard on the approval state
/// machine and on totals until this moves server-side.
class FinanceRepository {
  FinanceRepository(this._db);

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _expenses =>
      _db.collection('expenses');

  CollectionReference<Map<String, dynamic>> _budget(String projectId) =>
      _db.collection('projects').doc(projectId).collection('budget');

  Stream<List<Expense>> watchExpenses(String projectId) => _expenses
      .where('projectId', isEqualTo: projectId)
      .where('deleted', isEqualTo: false)
      .snapshots()
      .map((s) {
        final items = s.docs
            .map((d) => Expense.fromMap(projectId, d.id, d.data()))
            .toList();
        items.sort((a, b) => b.date.compareTo(a.date));
        return items;
      });

  /// Expenses waiting on the CEO across every project they can see. The
  /// caller filters to projects they have access to.
  Stream<List<Expense>> watchPending() => _expenses
      .where('status', isEqualTo: ExpenseStatus.pending.value)
      .where('deleted', isEqualTo: false)
      .snapshots()
      .map(
        (s) => s.docs
            .map((d) => Expense.fromMap(d.data()['projectId'] as String? ?? '', d.id, d.data()))
            .toList(),
      );

  Stream<List<BudgetLine>> watchBudget(String projectId) => _budget(projectId)
      .snapshots()
      .map((s) => s.docs.map((d) => BudgetLine.fromMap(d.id, d.data())).toList());

  Future<void> saveBudget(
    String projectId,
    String categoryId,
    int plannedPaise,
    String reason,
    String uid,
  ) async {
    if (plannedPaise < 0) throw ArgumentError('Budget cannot be negative.');
    final ref = _budget(projectId).doc(categoryId);
    await _db.runTransaction((tx) async {
      final current = await tx.get(ref);
      final data = current.data();
      final before = (data?['plannedPaise'] as num?)?.toInt() ?? 0;
      if (before == plannedPaise) return;
      if (current.exists && reason.trim().isEmpty) {
        throw ArgumentError('Add a reason for the revision.');
      }
      final revisions = [
        for (final r in (data?['revisions'] as List? ?? []))
          Map<String, dynamic>.from(r as Map),
        if (current.exists)
          {
            'oldPaise': before,
            'newPaise': plannedPaise,
            'reason': reason.trim(),
            'by': uid,
            'at': Timestamp.now(),
          },
      ];
      tx.set(ref, {
        'plannedPaise': plannedPaise,
        'originalPaise': data?['originalPaise'] ?? plannedPaise,
        'revisions': revisions,
        'revision': ((data?['revision'] as num?)?.toInt() ?? 0) + 1,
        if (!current.exists) ...auditCreate(uid) else ...auditUpdate(uid),
      }, SetOptions(merge: true));
      ActivityEntry(
        actorId: uid,
        action: current.exists ? 'budget-revised' : 'budget-set',
        entity: 'budget',
        entityId: categoryId,
        projectId: projectId,
        summary: current.exists
            ? 'Revised $categoryId budget: ${reason.trim()}'
            : 'Set $categoryId budget',
      ).addToTransaction(tx, _db);
    });
  }

  /// Submits a new expense, or resubmits/edits an existing one. Auto-approves
  /// at or under [thresholdPaise] captured at submit time.
  Future<void> submit({
    required String projectId,
    required int amountPaise,
    required String categoryId,
    required String payee,
    required String date,
    required String description,
    required String? billPath,
    required String? billHash,
    required List<String> flags,
    required Map<String, dynamic> custom,
    required int thresholdPaise,
    required String? financeLockedUntil,
    required String uid,
    String? phaseId,
    String? id,
    int? expectedRevision,
    String? lockOverrideReason,
    String? grnId,
  }) async {
    final project = _db.collection('projects').doc(projectId);
    final ref = id == null ? _expenses.doc() : _expenses.doc(id);
    await _db.runTransaction((tx) async {
      final p = await tx.get(project);
      if (!p.exists || p.data()?['deleted'] == true) {
        throw StateError('Project is archived or unavailable.');
      }
      final stage = p.data()?['stage'] as String?;
      if (stage == 'completed') {
        throw StateError('This project is completed. Ask an admin to reopen it.');
      }
      final current = id == null ? null : await tx.get(ref);
      if (id != null) {
        if (current == null || !current.exists) {
          throw StateError('Expense no longer exists.');
        }
        final revision = (current.data()?['revision'] as num?)?.toInt() ?? 0;
        if (expectedRevision == null || revision != expectedRevision) {
          throw StateError('This expense changed. Reopen it to see the latest version.');
        }
        final status = ExpenseStatus.fromValue(current.data()?['status'] as String?);
        if (status == ExpenseStatus.voided) {
          throw StateError('A voided expense cannot be edited.');
        }
      }
      final locked = WorkDay.tryParse(financeLockedUntil);
      final billDate = WorkDay.tryParse(date);
      if (locked != null &&
          billDate != null &&
          !billDate.isAfter(locked) &&
          (lockOverrideReason ?? '').trim().isEmpty) {
        throw StateError('This period is closed for accounting. An admin override with a reason is needed.');
      }
      final previousStatus = current == null
          ? null
          : ExpenseStatus.fromValue(current.data()?['status'] as String?);
      final wasApproved = previousStatus == ExpenseStatus.approved;
      final changedTotals = current != null &&
          (current.data()?['amountPaise'] != amountPaise ||
              current.data()?['categoryId'] != categoryId);
      final autoApprove = id == null && amountPaise <= thresholdPaise;
      final backToPending = previousStatus == ExpenseStatus.rejected ||
          (wasApproved && changedTotals);
      final status = id == null
          ? (autoApprove ? ExpenseStatus.approved : ExpenseStatus.pending)
          : (backToPending ? ExpenseStatus.pending : previousStatus!);
      final data = {
        'projectId': projectId,
        'amountPaise': amountPaise,
        'categoryId': categoryId,
        'payee': payee.trim(),
        'date': date,
        'phaseId': phaseId,
        'description': description.trim(),
        'billPath': billPath,
        'billHash': billHash,
        'status': status.value,
        'thresholdAtSubmit': id == null ? thresholdPaise : current!.data()!['thresholdAtSubmit'],
        'flags': flags,
        'approvedBy': id == null
            ? (autoApprove ? 'system' : null)
            : (backToPending ? null : current!.data()!['approvedBy']),
        if (backToPending) 'rejectReason': '',
        'custom': custom,
        // Set once when a bill is booked from a GRN; edits keep it as is.
        if (id == null && grnId != null) 'grnId': grnId,
        // submittedBy/At identify who originally logged this expense; editing
        // it later (createdBy/updatedBy track that instead) must not change them,
        // or the security rules' changedOnly() check on edits would reject the write.
        'submittedBy': id == null ? uid : current!.data()!['submittedBy'],
        'submittedAt': id == null ? FieldValue.serverTimestamp() : current!.data()!['submittedAt'],
        if (lockOverrideReason != null && lockOverrideReason.trim().isNotEmpty)
          'lockOverrideReason': lockOverrideReason.trim(),
        'revision': (current == null ? 0 : (current.data()!['revision'] as num).toInt()) + 1,
        if (current == null) ...auditCreate(uid) else ...auditUpdate(uid),
      };
      if (current != null) {
        tx.set(ref.collection('revisions').doc(), {
          ...current.data()!,
          'savedAt': FieldValue.serverTimestamp(),
          'savedBy': uid,
        });
      }
      tx.set(ref, data, SetOptions(merge: true));
      ActivityEntry(
        actorId: uid,
        action: current == null ? 'created' : 'updated',
        entity: 'expense',
        entityId: ref.id,
        projectId: projectId,
        summary:
            '${current == null ? 'Logged' : 'Updated'} expense: ${payee.trim()} · $categoryId'
            '${wasApproved && changedTotals ? ' (sent back for approval)' : ''}',
      ).addToTransaction(tx, _db);
    });
  }

  /// Approves or rejects a pending expense. Runs in a transaction so two
  /// approvers acting at once leave exactly one decision.
  Future<void> decide(
    String id,
    bool approve,
    String reason,
    String uid,
  ) async {
    if (!approve && reason.trim().isEmpty) {
      throw ArgumentError('Add a reason for rejecting this expense.');
    }
    final ref = _expenses.doc(id);
    await _db.runTransaction((tx) async {
      final doc = await tx.get(ref);
      if (!doc.exists) throw StateError('Expense no longer exists.');
      final data = doc.data()!;
      final status = ExpenseStatus.fromValue(data['status'] as String?);
      if (status != ExpenseStatus.pending) {
        final by = data['decidedBy'] as String? ?? 'someone else';
        throw StateError('Already decided by $by.');
      }
      tx.update(ref, {
        'status': (approve ? ExpenseStatus.approved : ExpenseStatus.rejected).value,
        'approvedBy': approve ? uid : null,
        'decidedBy': uid,
        'decidedAt': FieldValue.serverTimestamp(),
        'rejectReason': approve ? '' : reason.trim(),
        'revision': ((data['revision'] as num?)?.toInt() ?? 0) + 1,
        ...auditUpdate(uid),
      });
      ActivityEntry(
        actorId: uid,
        action: approve ? 'approved' : 'rejected',
        entity: 'expense',
        entityId: id,
        projectId: data['projectId'] as String?,
        summary:
            '${approve ? 'Approved' : 'Rejected'} ${data['payee']} expense'
            '${approve ? '' : ': ${reason.trim()}'}',
      ).addToTransaction(tx, _db);
    });
  }

  /// Records that an approved bill was paid, so it stops counting as a payable.
  Future<void> markPaid(String id, String paymentRef, String uid) async {
    final ref = _expenses.doc(id);
    await _db.runTransaction((tx) async {
      final doc = await tx.get(ref);
      if (!doc.exists) throw StateError('Expense no longer exists.');
      final data = doc.data()!;
      if (ExpenseStatus.fromValue(data['status'] as String?) != ExpenseStatus.approved) {
        throw StateError('Only an approved expense can be paid.');
      }
      if (data['paidAt'] != null) throw StateError('Already marked paid.');
      tx.update(ref, {
        'paidAt': FieldValue.serverTimestamp(),
        'paidBy': uid,
        'paymentRef': paymentRef.trim(),
        'revision': ((data['revision'] as num?)?.toInt() ?? 0) + 1,
        ...auditUpdate(uid),
      });
      ActivityEntry(
        actorId: uid,
        action: 'paid',
        entity: 'expense',
        entityId: id,
        projectId: data['projectId'] as String?,
        summary: 'Paid ${data['payee']}${paymentRef.trim().isEmpty ? '' : ' · ref ${paymentRef.trim()}'}',
      ).addToTransaction(tx, _db);
    });
  }

  /// Voids an approved expense. Never deleted; totals exclude void.
  Future<void> voidExpense(String id, String reason, String uid) async {
    if (reason.trim().isEmpty) {
      throw ArgumentError('Add a reason to void this expense.');
    }
    final ref = _expenses.doc(id);
    await _db.runTransaction((tx) async {
      final doc = await tx.get(ref);
      if (!doc.exists) throw StateError('Expense no longer exists.');
      final data = doc.data()!;
      final status = ExpenseStatus.fromValue(data['status'] as String?);
      if (status != ExpenseStatus.approved) {
        throw StateError('Only an approved expense can be voided.');
      }
      tx.update(ref, {
        'status': ExpenseStatus.voided.value,
        'voidReason': reason.trim(),
        'revision': ((data['revision'] as num?)?.toInt() ?? 0) + 1,
        ...auditUpdate(uid),
      });
      ActivityEntry(
        actorId: uid,
        action: 'voided',
        entity: 'expense',
        entityId: id,
        projectId: data['projectId'] as String?,
        summary: 'Voided ${data['payee']} expense: ${reason.trim()}',
      ).addToTransaction(tx, _db);
    });
  }
}

final financeRepositoryProvider = Provider<FinanceRepository>(
  (ref) => FinanceRepository(ref.watch(firestoreProvider)),
);

final projectExpensesProvider =
    StreamProvider.family<List<Expense>, String>(
      (ref, projectId) =>
          ref.watch(financeRepositoryProvider).watchExpenses(projectId),
    );

final projectBudgetProvider =
    StreamProvider.family<List<BudgetLine>, String>(
      (ref, projectId) =>
          ref.watch(financeRepositoryProvider).watchBudget(projectId),
    );

/// Pending expenses on projects the current user can see (their own for
/// managers/supervisors, everything for admin/CEO). Used by the CEO's
/// approvals inbox and the "Needs you" panel.
final visiblePendingExpensesProvider = Provider<AsyncValue<List<Expense>>>((ref) {
  final pending = ref.watch(_rawPendingExpensesProvider);
  final projects = ref.watch(visibleProjectsProvider);
  if (!pending.hasValue) return pending;
  if (!projects.hasValue) return const AsyncLoading();
  final visible = {for (final p in projects.requireValue) p.id};
  return AsyncData(
    pending.requireValue.where((e) => visible.contains(e.projectId)).toList()
      ..sort((a, b) => (b.submittedAt ?? DateTime(0)).compareTo(a.submittedAt ?? DateTime(0))),
  );
});

final _rawPendingExpensesProvider = StreamProvider<List<Expense>>(
  (ref) => ref.watch(financeRepositoryProvider).watchPending(),
);

/// Everything the Money tab needs for one project, recomputed at read time.
final projectFinanceProvider = Provider.family<AsyncValue<ProjectFinance>, String>((ref, projectId) {
  final expenses = ref.watch(projectExpensesProvider(projectId));
  final budget = ref.watch(projectBudgetProvider(projectId));
  final project = ref.watch(projectProvider(projectId));
  final phases = ref.watch(projectPhasesProvider(projectId));
  final config = ref.watch(appConfigProvider);
  if (expenses.hasError) return AsyncError(expenses.error!, expenses.stackTrace ?? StackTrace.current);
  if (budget.hasError) return AsyncError(budget.error!, budget.stackTrace ?? StackTrace.current);
  if (!expenses.hasValue || !budget.hasValue || !project.hasValue || !phases.hasValue) {
    return const AsyncLoading();
  }
  final proj = project.requireValue;
  if (proj == null) return const AsyncLoading();
  final today = WorkDay.today(utcOffsetMinutes: config.company.utcOffsetMinutes);
  // Stored actualPct is never written (no Functions), so derive it from phases.
  final analysis = ProjectAnalysis.calculate(
    proj,
    phases.requireValue,
    config.stageOfStatus(proj.statusId),
    today,
  );
  return AsyncData(
    ProjectFinance(
      expenses: expenses.requireValue,
      budget: budget.requireValue,
      today: today,
      actualPct: analysis.actual,
    ),
  );
});

class ProjectFinance {
  const ProjectFinance({
    required this.expenses,
    required this.budget,
    required this.today,
    required this.actualPct,
  });

  final List<Expense> expenses;
  final List<BudgetLine> budget;
  final String today;
  final double actualPct;
}
