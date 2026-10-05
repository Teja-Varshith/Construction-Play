import '../../../core/data/json_read.dart';

/// System states of an expense. Only [approved] counts towards spend.
enum ExpenseStatus {
  pending('pending', 'Waiting for approval'),
  approved('approved', 'Approved'),
  rejected('rejected', 'Rejected'),
  voided('void', 'Void');

  const ExpenseStatus(this.value, this.label);
  final String value;
  final String label;

  static ExpenseStatus fromValue(String? value) => ExpenseStatus.values
      .firstWhere((s) => s.value == value, orElse: () => ExpenseStatus.pending);
}

/// Reasons an expense is sent to the CEO even when it is under the threshold.
enum ExpenseFlag {
  duplicateBill('duplicateBill', 'Same bill photo used before'),
  possibleDuplicate('possibleDuplicate', 'Possible duplicate'),
  possibleSplit('possibleSplit', 'Possible split bill'),
  lockedPeriod('lockedPeriod', 'Dated in a closed period');

  const ExpenseFlag(this.value, this.label);
  final String value;
  final String label;

  static ExpenseFlag? fromValue(String value) =>
      ExpenseFlag.values.where((f) => f.value == value).firstOrNull;
}

class Expense {
  const Expense({
    required this.id,
    required this.projectId,
    required this.amountPaise,
    required this.categoryId,
    required this.payee,
    required this.date,
    this.phaseId,
    this.description = '',
    this.billPath,
    this.billHash,
    this.status = ExpenseStatus.pending,
    this.thresholdAtSubmit = 0,
    this.flags = const [],
    this.approvedBy,
    this.decidedBy,
    this.decidedAt,
    this.rejectReason = '',
    this.voidReason = '',
    this.lockOverrideReason = '',
    this.submittedBy,
    this.submittedAt,
    this.custom = const {},
    this.revision = 0,
    this.paidAt,
    this.paidBy,
    this.paymentRef = '',
    this.grnId,
  });

  final String id;
  final String projectId;
  final int amountPaise;
  final String categoryId;
  final String payee;

  /// Bill date, a working-day key (YYYY-MM-DD).
  final String date;

  /// The schedule phase this spend belongs to, if any. Drives phase budgets.
  final String? phaseId;
  final String description;
  final String? billPath;
  final String? billHash;
  final ExpenseStatus status;
  final int thresholdAtSubmit;
  final List<String> flags;

  /// "system" for automatic approvals, otherwise the approver's uid.
  final String? approvedBy;
  final String? decidedBy;
  final DateTime? decidedAt;
  final String rejectReason;
  final String voidReason;
  final String lockOverrideReason;
  final String? submittedBy;
  final DateTime? submittedAt;
  final Map<String, dynamic> custom;
  final int revision;

  /// When the vendor was paid. An approved bill with no [paidAt] is a payable.
  final DateTime? paidAt;
  final String? paidBy;

  /// Cheque / UTR / transfer reference.
  final String paymentRef;

  /// The goods received note (Materials) this bill was booked from.
  final String? grnId;

  bool get isPaid => paidAt != null;

  /// Approved but not yet paid: money the company owes.
  bool get isPayable => isApproved && !isPaid;

  /// Days a payable has been waiting since the bill date.
  int payableAgeDays(DateTime today) {
    final d = DateTime.tryParse(date);
    return d == null ? 0 : today.difference(d).inDays;
  }

  bool get isApproved => status == ExpenseStatus.approved;
  bool get isPending => status == ExpenseStatus.pending;
  bool get autoApproved => isApproved && approvedBy == 'system';

  /// Normalised payee, used for duplicate and split matching.
  String get payeeKey => normalisePayee(payee);

  static String normalisePayee(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  factory Expense.fromMap(String projectId, String id, Map<String, dynamic> m) =>
      Expense(
        id: id,
        projectId: projectId,
        amountPaise: m.readInt('amountPaise'),
        categoryId: m.readString('categoryId', 'other'),
        payee: m.readString('payee'),
        date: m.readString('date'),
        phaseId: m.readStringOrNull('phaseId'),
        description: m.readString('description'),
        billPath: m.readStringOrNull('billPath'),
        billHash: m.readStringOrNull('billHash'),
        status: ExpenseStatus.fromValue(m.readStringOrNull('status')),
        thresholdAtSubmit: m.readInt('thresholdAtSubmit'),
        flags: m.readStringList('flags'),
        approvedBy: m.readStringOrNull('approvedBy'),
        decidedBy: m.readStringOrNull('decidedBy'),
        decidedAt: m.readDateTime('decidedAt'),
        rejectReason: m.readString('rejectReason'),
        voidReason: m.readString('voidReason'),
        lockOverrideReason: m.readString('lockOverrideReason'),
        submittedBy: m.readStringOrNull('submittedBy'),
        submittedAt: m.readDateTime('submittedAt'),
        custom: m.readMap('custom'),
        revision: m.readInt('revision'),
        paidAt: m.readDateTime('paidAt'),
        paidBy: m.readStringOrNull('paidBy'),
        paymentRef: m.readString('paymentRef'),
        grnId: m.readStringOrNull('grnId'),
      );
}

/// Planned amount for one expense category on one project. Spend is never
/// stored here; it is summed from approved expenses when read.
class BudgetLine {
  const BudgetLine({
    required this.categoryId,
    required this.plannedPaise,
    this.originalPaise,
    this.revisions = const [],
    this.revision = 0,
  });

  final String categoryId;
  final int plannedPaise;

  /// The first budget set for this category, so the CEO can compare.
  final int? originalPaise;
  final List<BudgetRevision> revisions;
  final int revision;

  factory BudgetLine.fromMap(String id, Map<String, dynamic> m) => BudgetLine(
    categoryId: id,
    plannedPaise: m.readInt('plannedPaise'),
    originalPaise: m.readIntOrNull('originalPaise'),
    revisions: m.readMapList('revisions').map(BudgetRevision.fromMap).toList(),
    revision: m.readInt('revision'),
  );
}

class BudgetRevision {
  const BudgetRevision({
    required this.oldPaise,
    required this.newPaise,
    required this.reason,
    required this.by,
    this.at,
  });

  final int oldPaise;
  final int newPaise;
  final String reason;
  final String by;
  final DateTime? at;

  factory BudgetRevision.fromMap(Map<String, dynamic> m) => BudgetRevision(
    oldPaise: m.readInt('oldPaise'),
    newPaise: m.readInt('newPaise'),
    reason: m.readString('reason'),
    by: m.readString('by'),
    at: m.readDateTime('at'),
  );
}
