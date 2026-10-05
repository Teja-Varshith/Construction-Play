import '../../../core/utils/work_day.dart';
import '../../finance/domain/expense.dart';
import '../../inventory/domain/inventory.dart';
import '../../../core/config/config_models.dart';
import '../../projects/domain/project.dart';
import '../../projects/domain/project_detail.dart';
import '../../projects/domain/project_insight.dart';
import '../../projects/domain/project_nav.dart';

/// How soon a task needs doing. Always shown with its text label.
enum DayUrgency {
  now('Now'),
  today('Today'),
  soon('This week');

  const DayUrgency(this.label);
  final String label;
}

enum DayTaskKind { report, backfill, issue, approve, delivery, reorder, delay, book, expense }

/// One thing a site person or manager should do, with the single action that
/// does it. Built from records at read time; nothing is stored.
class DayTask {
  const DayTask({
    required this.kind,
    required this.project,
    required this.title,
    required this.action,
    required this.urgency,
    this.detail = '',
    this.link,
  });

  final DayTaskKind kind;
  final Project project;
  final String title;
  final String detail;

  /// Button label, e.g. "Submit report".
  final String action;
  final DayUrgency urgency;

  /// Where the action goes. Null for [DayTaskKind.report], which opens
  /// today's report form directly.
  final ProjectLink? link;
}

/// What one person can do on one project.
class DayAccess {
  const DayAccess({required this.report, required this.manage, required this.seeMoney});

  /// Daily reports, issues, indents (manager or supervisor on the project).
  final bool report;

  /// Approve indents, record deliveries, phases and expenses (manager).
  final bool manage;
  final bool seeMoney;
}

class MyDay {
  MyDay._();

  /// Everything [uid] should act on for one project, most urgent first.
  static List<DayTask> forProject({
    required String uid,
    required Project project,
    required ProjectStage stage,
    required DayAccess access,
    required String today,
    required int backdateDays,
    List<DailyProgressReport> reports = const [],
    List<ProjectIssue> issues = const [],
    ProjectInsight? insight,
    InventorySummary? inventory,
    List<Grn> grns = const [],
    List<Expense> expenses = const [],
    DateTime? now,
  }) {
    if (stage != ProjectStage.ongoing) return const [];
    final clock = now ?? DateTime.now();
    final tasks = <DayTask>[];
    final t = WorkDay.tryParse(today);
    final sunday = t != null && t.weekday == DateTime.sunday;

    if (access.report) {
      // Today's report: the one job every site does daily.
      if (!sunday && !reports.any((r) => r.date == today)) {
        tasks.add(DayTask(
          kind: DayTaskKind.report,
          project: project,
          title: 'Submit today\'s daily report',
          detail: 'Work done, quantity against target and at least one photo.',
          action: 'Submit report',
          urgency: DayUrgency.now,
        ));
      }
      // Past days that can still be filled in (inside the backdate window).
      final oldest = t == null ? null : WorkDay.fromDate(t.subtract(Duration(days: backdateDays)));
      final fillable = (insight?.missingReportDates ?? const <String>[])
          .where((d) => d != today && (oldest == null || d.compareTo(oldest) >= 0))
          .toList();
      if (fillable.isNotEmpty) {
        tasks.add(DayTask(
          kind: DayTaskKind.backfill,
          project: project,
          title: '${fillable.length} earlier day${fillable.length == 1 ? '' : 's'} without a report',
          detail: '${fillable.take(4).map(WorkDay.display).join(', ')}${fillable.length > 4 ? '…' : ''}. '
              'These can still be filled in for $backdateDays days.',
          action: 'Fill in',
          urgency: DayUrgency.today,
          link: const ProjectLink(ProjectTab.daily, 'missing'),
        ));
      }
    }

    // Issues assigned to me; for a manager also urgent ones nobody owns.
    for (final i in issues.where((i) => i.isOpen && !i.deleted)) {
      final urgent = i.priorityId == 'critical' || i.priorityId == 'high';
      final mine = i.assigneeId == uid;
      if (!mine && !(access.manage && urgent && i.assigneeId == null)) continue;
      final age = i.reportedAt == null ? 0 : clock.difference(i.reportedAt!).inDays;
      tasks.add(DayTask(
        kind: DayTaskKind.issue,
        project: project,
        title: mine ? i.title : 'Unassigned: ${i.title}',
        detail: [
          if (urgent) '${i.priorityId[0].toUpperCase()}${i.priorityId.substring(1)} priority',
          age == 0 ? 'raised today' : 'open $age day${age == 1 ? '' : 's'}',
          if (!mine) 'give it an owner',
        ].join(' · '),
        action: mine ? 'Open issue' : 'Assign',
        urgency: urgent ? DayUrgency.now : DayUrgency.soon,
        link: ProjectLink(ProjectTab.issues, 'issue:${i.id}'),
      ));
    }

    final inv = inventory;
    if (inv != null) {
      if (access.manage && inv.pending.isNotEmpty) {
        final oldest = inv.pending.first.waitingDays(clock);
        tasks.add(DayTask(
          kind: DayTaskKind.approve,
          project: project,
          title: 'Approve ${inv.pending.length} material request${inv.pending.length == 1 ? '' : 's'}',
          detail: '${inv.pending.take(2).map((x) => x.summary).join('; ')}'
              '${oldest > 0 ? ' · oldest waiting $oldest day${oldest == 1 ? '' : 's'}' : ''}',
          action: 'Review',
          urgency: oldest >= 1 ? DayUrgency.now : DayUrgency.today,
          link: inv.pending.length == 1
              ? ProjectLink(ProjectTab.materials, 'indent:${inv.pending.first.id}')
              : const ProjectLink(ProjectTab.materials, 'pending'),
        ));
      }
      if (access.manage && inv.late.isNotEmpty) {
        final worst = inv.late.first;
        tasks.add(DayTask(
          kind: DayTaskKind.delivery,
          project: project,
          title: '${inv.late.length} material deliver${inv.late.length == 1 ? 'y is' : 'ies are'} late',
          detail: '${worst.number} is ${worst.daysLate(today)} days late. Call the vendor, or record it if it came.',
          action: 'See deliveries',
          urgency: DayUrgency.now,
          link: inv.late.length == 1
              ? ProjectLink(ProjectTab.materials, 'indent:${worst.id}')
              : const ProjectLink(ProjectTab.materials, 'late'),
        ));
      }
      final dueToday = inv.open.where((x) => x.neededBy == today).toList();
      if (access.manage && dueToday.isNotEmpty) {
        tasks.add(DayTask(
          kind: DayTaskKind.delivery,
          project: project,
          title: '${dueToday.length} deliver${dueToday.length == 1 ? 'y' : 'ies'} expected today',
          detail: 'Record it when it arrives so stock stays right: ${dueToday.first.summary}',
          action: 'Open',
          urgency: DayUrgency.today,
          link: ProjectLink(ProjectTab.materials, 'indent:${dueToday.first.id}'),
        ));
      }
      final reorder = inv.stock.where((l) => l.needsReorder).toList();
      if (access.report && reorder.isNotEmpty) {
        tasks.add(DayTask(
          kind: DayTaskKind.reorder,
          project: project,
          title: reorder.length == 1 ? '${reorder.first.material} is running low' : '${reorder.length} materials running low',
          detail: '${reorder.take(3).map((l) => l.out ? '${l.material}: out' : '${l.material}: ${formatQty(l.inStock)} ${l.unit}${l.daysLeft == null ? '' : ' (~${l.daysLeft!.floor()}d)'}').join(' · ')}. Nothing ordered yet.',
          action: 'Reorder',
          urgency: reorder.any((l) => l.out || (l.daysLeft ?? 99) <= 2) ? DayUrgency.now : DayUrgency.today,
          link: const ProjectLink(ProjectTab.materials, 'low'),
        ));
      }
    }

    if (access.manage && insight != null) {
      // Late phases need a reason, or the CEO sees a delay with no story.
      for (final p in insight.phases.where((p) => p.state.late && p.phase.delayReason.trim().isEmpty)) {
        tasks.add(DayTask(
          kind: DayTaskKind.delay,
          project: project,
          title: '${p.phase.name} is ${p.state.label.toLowerCase()}',
          detail: '${p.daysLate > 0 ? '${p.daysLate} days late · ' : ''}update its progress or say why it is late.',
          action: 'Update',
          urgency: DayUrgency.today,
          link: ProjectLink(ProjectTab.timeline, 'phase:${p.phase.id}'),
        ));
      }
    }

    if (access.manage && access.seeMoney) {
      final booked = {for (final e in expenses) if (e.grnId != null && e.status != ExpenseStatus.voided) e.grnId};
      final unbooked = grns.where((g) => g.valuePaise > 0 && !booked.contains(g.id)).toList();
      if (unbooked.isNotEmpty) {
        tasks.add(DayTask(
          kind: DayTaskKind.book,
          project: project,
          title: 'Book ${unbooked.length} deliver${unbooked.length == 1 ? 'y' : 'ies'} as expense${unbooked.length == 1 ? '' : 's'}',
          detail: 'So the vendor bill is approved and paid on time: ${unbooked.take(2).map((g) => g.vendor).join(', ')}.',
          action: 'Book',
          urgency: DayUrgency.soon,
          link: const ProjectLink(ProjectTab.materials, 'unbooked'),
        ));
      }
      final rejected = expenses.where((e) => e.status == ExpenseStatus.rejected && e.submittedBy == uid).toList();
      if (rejected.isNotEmpty) {
        tasks.add(DayTask(
          kind: DayTaskKind.expense,
          project: project,
          title: '${rejected.length} expense${rejected.length == 1 ? ' was' : 's were'} sent back',
          detail: rejected.first.rejectReason.isEmpty
              ? 'Fix and resubmit.'
              : 'Reason: ${rejected.first.rejectReason}',
          action: 'Fix',
          urgency: DayUrgency.today,
          link: const ProjectLink(ProjectTab.money),
        ));
      }
    }
    return tasks;
  }

  /// Most urgent first; stable within the same urgency.
  static List<DayTask> sorted(Iterable<DayTask> tasks) {
    final list = tasks.toList();
    final out = <DayTask>[];
    for (final u in DayUrgency.values) {
      out.addAll(list.where((t) => t.urgency == u));
    }
    return out;
  }
}
