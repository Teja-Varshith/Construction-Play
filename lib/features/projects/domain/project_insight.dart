import '../../../core/config/config_models.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/work_day.dart';
import '../../finance/domain/expense.dart';
import '../../inventory/domain/inventory.dart';
import 'project.dart';
import 'project_analysis.dart';
import 'project_detail.dart';
import 'project_nav.dart';

/// Where one phase stands against its own planned window.
enum PhaseState {
  done('Done'),
  onTrack('On track'),
  notStarted('Not started'),
  slipping('Slipping'),
  behind('Behind'),
  overdue('Overdue'),
  noDates('No dates');

  const PhaseState(this.label);
  final String label;

  bool get late => this == slipping || this == behind || this == overdue;
}

/// One phase: schedule position plus the money set aside for it.
class PhaseInsight {
  const PhaseInsight({
    required this.phase,
    required this.state,
    required this.plannedPct,
    required this.daysLate,
    required this.spentPaise,
    required this.pendingPaise,
  });

  final ProjectPhase phase;
  final PhaseState state;

  /// How far along the phase should be by today, 0–100.
  final double plannedPct;

  /// Days between today and the day the plan expected today's progress.
  final int daysLate;
  final int spentPaise;
  final int pendingPaise;

  int get budgetPaise => phase.budgetPaise;
  int get remainingPaise => budgetPaise - spentPaise;
  bool get hasBudget => budgetPaise > 0;
  bool get overBudget => hasBudget && spentPaise > budgetPaise;

  /// Null when there is no budget, so nothing is divided by zero.
  double? get usedPct => hasBudget ? spentPaise / budgetPaise * 100 : null;
}

enum FactorKind { schedule, speed, hold, issues, reports, output, materials, money, payables, approvals, setup }

/// One reason a project is late or costing more than planned, in plain words.
class ProjectFactor {
  const ProjectFactor({
    required this.kind,
    required this.title,
    required this.detail,
    required this.link,
    required this.action,
    this.severe = false,
  });

  final FactorKind kind;
  final String title;
  final String detail;
  final bool severe;

  /// Where to look into this factor.
  final ProjectLink link;

  /// Short label for the investigate button, e.g. "See missing days".
  final String action;
}

/// Everything the CEO needs to judge one project, derived from source records
/// at read time: schedule, forecast finish, per-phase budget and the factors
/// behind any delay or overspend.
class ProjectInsight {
  const ProjectInsight({
    required this.project,
    required this.stage,
    required this.analysis,
    required this.today,
    required this.phases,
    required this.forecastFinish,
    required this.finishSlipDays,
    required this.daysLeft,
    required this.timeUsedPct,
    required this.budgetPaise,
    required this.phaseBudgetPaise,
    required this.spentPaise,
    required this.pendingPaise,
    required this.pendingCount,
    required this.unassignedSpentPaise,
    required this.openIssues,
    required this.urgentIssues,
    required this.missingReports,
    this.missingReportDates = const [],
    required this.outputPct,
    required this.factors,
    this.spendCurve = const [],
    this.earnedPaise = 0,
    this.forecastCostPaise,
    this.payablesPaise = 0,
    this.payablesCount = 0,
    this.overduePayablesPaise = 0,
    this.overduePayablesCount = 0,
    this.speedPerWeek,
    this.requiredPerWeek,
  });

  /// Days after the bill date a payable counts as overdue.
  static const payableDueDays = 30;

  /// Budgeted value of the work actually done (budget × % complete).
  final int earnedPaise;

  /// Projected total cost at completion at the current cost rate (spent ÷ %
  /// complete). Null until [FinanceSummary.minProgressForForecast] % is done.
  final int? forecastCostPaise;

  /// Approved bills not yet paid.
  final int payablesPaise;
  final int payablesCount;

  /// Payables older than [payableDueDays] since the bill date.
  final int overduePayablesPaise;
  final int overduePayablesCount;

  /// Progress made per week so far (on the paused clock), in % points.
  final double? speedPerWeek;

  /// Progress needed per week from today to finish by the target date.
  /// Null when there is no target date or it has passed.
  final double? requiredPerWeek;

  /// Spend beyond the value of the work done. Negative means under.
  int get costOverrunPaise => budgetPaise <= 0 ? 0 : spentPaise - earnedPaise;

  /// Forecast total cost minus budget. Negative means under budget.
  int? get forecastOverrunPaise =>
      forecastCostPaise == null || budgetPaise <= 0 ? null : forecastCostPaise! - budgetPaise;

  /// Current pace as a share of the pace needed (1.0 = exactly enough).
  double? get paceRatio =>
      speedPerWeek == null || requiredPerWeek == null || requiredPerWeek! <= 0 ? null : speedPerWeek! / requiredPerWeek!;

  /// Cumulative approved spend by bill date, oldest first.
  final List<(DateTime, int)> spendCurve;

  final Project project;
  final ProjectStage stage;
  final ProjectAnalysis analysis;
  final String today;
  final List<PhaseInsight> phases;

  /// Target date pushed out by days behind plus days on hold. Null when the
  /// project has no target date or no usable schedule.
  final DateTime? forecastFinish;

  /// Days the forecast is past the target date (0 = on time).
  final int finishSlipDays;

  /// Days from today to the target date; negative when overdue.
  final int? daysLeft;

  /// Share of the planned calendar already used, 0–100+.
  final double? timeUsedPct;

  /// Total budget: category budgets, or phase budgets if none are set.
  final int budgetPaise;
  final int phaseBudgetPaise;
  final int spentPaise;
  final int pendingPaise;
  final int pendingCount;

  /// Approved spend not tagged to any phase.
  final int unassignedSpentPaise;
  final int openIssues;
  final int urgentIssues;

  /// Working days (Mon–Sat) in the last two weeks with no daily report.
  final int missingReports;

  /// The working days counted in [missingReports], newest first.
  final List<String> missingReportDates;

  /// Average achieved-vs-target over the last seven reports, if any.
  final double? outputPct;
  final List<ProjectFactor> factors;

  static const recentDays = 14;

  bool get active => stage == ProjectStage.ongoing || stage == ProjectStage.onHold;
  bool get scheduleReady => !analysis.incomplete;
  bool get finished => analysis.actual >= 100;
  bool get onTime => scheduleReady && finishSlipDays == 0;
  int get remainingPaise => budgetPaise - spentPaise;
  double? get budgetUsedPct => budgetPaise <= 0 ? null : spentPaise / budgetPaise * 100;
  int get phasesDone => phases.where((p) => p.state == PhaseState.done).length;
  int get phasesLate => phases.where((p) => p.state.late).length;

  /// A one-line schedule verdict for lists.
  String get scheduleLabel {
    if (stage == ProjectStage.pipeline) return 'Not started';
    if (stage == ProjectStage.completed) return 'Completed';
    if (stage == ProjectStage.cancelled) return 'Cancelled';
    if (!scheduleReady) return 'Schedule incomplete';
    if (finished) return 'Work complete';
    if (stage == ProjectStage.onHold) return 'On hold';
    if (analysis.daysBehind == 0) return 'On schedule';
    return '${analysis.daysBehind} day${analysis.daysBehind == 1 ? '' : 's'} behind';
  }

  static ProjectInsight calculate({
    required Project project,
    required ProjectStage stage,
    required List<ProjectPhase> phases,
    required String today,
    List<Expense> expenses = const [],
    List<BudgetLine> budget = const [],
    List<ProjectIssue> issues = const [],
    List<DailyProgressReport> reports = const [],
    List<Indent> indents = const [],
    List<StockLine> stock = const [],
    String Function(String priorityId)? priorityLabel,
  }) {
    final analysis = ProjectAnalysis.calculate(project, phases, stage, today);
    final now = ProjectAnalysis.day(today);
    // Phases run on the same paused clock as the project.
    final clock = now.subtract(Duration(days: analysis.pausedDays));
    final approved = expenses.where((e) => e.isApproved).toList();
    final pending = expenses.where((e) => e.isPending).toList();
    int sum(Iterable<Expense> list) => list.fold(0, (s, e) => s + e.amountPaise);

    final phaseIds = {for (final p in phases) p.id};
    final phaseInsights = [
      for (final p in phases.where((p) => !p.deleted))
        _phase(
          p,
          clock,
          sum(approved.where((e) => e.phaseId == p.id)),
          sum(pending.where((e) => e.phaseId == p.id)),
        ),
    ];

    // Forecast: the target moves out by every day behind plan and every day on hold.
    final due = WorkDay.tryParse(project.endDate);
    final dueUtc = due == null ? null : DateTime.utc(due.year, due.month, due.day);
    final slip = analysis.incomplete || analysis.actual >= 100
        ? 0
        : analysis.daysBehind + analysis.pausedDays;
    final forecast = dueUtc == null || analysis.incomplete
        ? null
        : dueUtc.add(Duration(days: slip));
    final start = WorkDay.tryParse(project.startDate);
    final startUtc = start == null ? null : DateTime.utc(start.year, start.month, start.day);
    final span = startUtc == null || dueUtc == null ? 0 : dueUtc.difference(startUtc).inDays;
    final timeUsed = span <= 0 ? null : clock.difference(startUtc!).inDays / span * 100;

    final categoryBudget = budget.fold(0, (s, b) => s + b.plannedPaise);
    final phaseBudget = phases.fold(0, (s, p) => s + p.budgetPaise);
    final spent = sum(approved);

    final open = issues.where((i) => i.isOpen).toList();
    final urgent = open
        .where((i) => i.priorityId == 'critical' || i.priorityId == 'high')
        .toList();

    final reportDays = {for (final r in reports) r.date};
    final missingDates = <String>[];
    if (stage == ProjectStage.ongoing) {
      final from = startUtc;
      for (var i = 1; i <= recentDays; i++) {
        final d = now.subtract(Duration(days: i));
        if (from != null && d.isBefore(from)) break;
        if (d.weekday == DateTime.sunday) continue;
        final key = WorkDay.fromDate(d);
        if (!reportDays.contains(key)) missingDates.add(key);
      }
    }
    final missing = missingDates.length;
    final recent = reports
        .where((r) => r.achievedPercent != null)
        .take(7)
        .map((r) => r.achievedPercent!.clamp(0, 200))
        .toList();
    final output = recent.isEmpty ? null : recent.reduce((a, b) => a + b) / recent.length;

    // ---- cost ----
    final totalBudget0 = categoryBudget > 0 ? categoryBudget : phaseBudget;
    final earned = analysis.incomplete ? 0 : (totalBudget0 * analysis.actual / 100).round();
    final forecastCost = analysis.actual >= 10 ? (spent * 100 / analysis.actual).round() : null;

    // ---- payables ----
    final payables = expenses.where((e) => e.isPayable).toList();
    final overdue = payables.where((e) => e.payableAgeDays(now) > payableDueDays).toList();

    // ---- speed ----
    final activeDays = startUtc == null ? 0 : clock.difference(startUtc).inDays;
    final speed = analysis.incomplete || activeDays < 7 ? null : analysis.actual / (activeDays / 7);
    final weeksLeft = dueUtc == null ? null : dueUtc.difference(now).inDays / 7;
    final required = analysis.incomplete || weeksLeft == null || weeksLeft <= 0 || analysis.actual >= 100
        ? null
        : (100 - analysis.actual) / weeksLeft;

    final factors = <ProjectFactor>[];
    final tracking = stage == ProjectStage.ongoing || stage == ProjectStage.onHold;
    if (tracking) {
      final late = phaseInsights.where((p) => p.state.late).toList()
        ..sort((a, b) => b.daysLate.compareTo(a.daysLate));
      for (final p in late) {
        final reason = p.phase.delayReason.trim();
        factors.add(
          ProjectFactor(
            kind: FactorKind.schedule,
            severe: p.state != PhaseState.slipping,
            title: p.state == PhaseState.overdue
                ? '${p.phase.name} is past its finish date'
                : '${p.phase.name} is ${p.daysLate} day${p.daysLate == 1 ? '' : 's'} late',
            detail:
                '${p.phase.actualPct.toStringAsFixed(0)}% done, ${p.plannedPct.toStringAsFixed(0)}% planned by today'
                '${p.state == PhaseState.overdue ? ' (was due ${WorkDay.display(p.phase.plannedEnd)})' : ''}. '
                '${reason.isEmpty ? 'No reason recorded by the site team.' : 'Reason: $reason'}',
            link: ProjectLink(ProjectTab.timeline, 'phase:${p.phase.id}'),
            action: 'Open phase',
          ),
        );
      }
      if (analysis.pausedDays > 0 || stage == ProjectStage.onHold) {
        final periods = project.holdPeriods
            .map((h) => '${WorkDay.display(h['start'] as String?)} – ${h['end'] == null ? 'now' : WorkDay.display(h['end'] as String?)}')
            .join(', ');
        factors.add(
          ProjectFactor(
            kind: FactorKind.hold,
            severe: stage == ProjectStage.onHold,
            title: stage == ProjectStage.onHold
                ? 'Project is on hold'
                : 'On hold for ${analysis.pausedDays} day${analysis.pausedDays == 1 ? '' : 's'}',
            detail: 'Every day on hold moves the finish date out. ${periods.isEmpty ? '' : 'Hold periods: $periods.'}',
            link: const ProjectLink(ProjectTab.info, 'holds'),
            action: 'See hold history',
          ),
        );
      }
      if (urgent.isNotEmpty) {
        factors.add(
          ProjectFactor(
            kind: FactorKind.issues,
            severe: urgent.any((i) => i.priorityId == 'critical'),
            title: '${urgent.length} high-priority site issue${urgent.length == 1 ? '' : 's'} open',
            detail: urgent
                .take(3)
                .map((i) => '${i.title} (${priorityLabel?.call(i.priorityId) ?? i.priorityId})')
                .join(' · '),
            link: const ProjectLink(ProjectTab.issues, 'urgent'),
            action: 'Review issues',
          ),
        );
      }
      if (missing >= 3) {
        factors.add(
          ProjectFactor(
            kind: FactorKind.reports,
            severe: missing >= 6,
            title: '$missing daily reports missing in the last two weeks',
            detail: 'Without site reports, progress and delays are not visible in time.',
            link: const ProjectLink(ProjectTab.daily, 'missing'),
            action: 'See missing days',
          ),
        );
      }
      // Material: late deliveries stop work; requests stuck in approval delay it.
      final lateIndents = indents.where((x) => x.isLate(today)).toList()
        ..sort((a, b) => b.daysLate(today).compareTo(a.daysLate(today)));
      if (lateIndents.isNotEmpty) {
        final worst = lateIndents.first;
        factors.add(
          ProjectFactor(
            kind: FactorKind.materials,
            severe: true,
            title: '${lateIndents.length} material deliver${lateIndents.length == 1 ? 'y' : 'ies'} overdue',
            detail: '${worst.number} (${worst.items.map((l) => l.material).join(', ')}) was needed by '
                '${WorkDay.display(worst.neededBy)}, ${worst.daysLate(today)} days ago, and has not arrived.',
            link: lateIndents.length == 1
                ? ProjectLink(ProjectTab.materials, 'indent:${worst.id}')
                : const ProjectLink(ProjectTab.materials, 'late'),
            action: lateIndents.length == 1 ? 'Open indent' : 'See late deliveries',
          ),
        );
      }
      // Material about to run out with nothing requested or on its way.
      final runningOut = stock.where((l) => l.needsReorder && (l.out || (l.daysLeft ?? 99) <= StockLine.lowDays)).toList()
        ..sort((a, b) => (a.daysLeft ?? 0).compareTo(b.daysLeft ?? 0));
      if (runningOut.isNotEmpty) {
        final names = runningOut.take(3).map((l) => l.out ? '${l.material} (out)' : '${l.material} (~${l.daysLeft!.floor()}d)');
        factors.add(
          ProjectFactor(
            kind: FactorKind.materials,
            severe: runningOut.any((l) => l.out),
            title: '${runningOut.length} material${runningOut.length == 1 ? '' : 's'} about to run out',
            detail: '${names.join(', ')}${runningOut.length > 3 ? ' and more' : ''}. Nothing is requested or on order yet.',
            link: const ProjectLink(ProjectTab.materials, 'low'),
            action: 'See stock',
          ),
        );
      }
      final nowInstant = DateTime.now();
      final stuck = indents.where((x) => x.isPending).toList();
      if (stuck.isNotEmpty) {
        final oldest = stuck.map((x) => x.waitingDays(nowInstant)).reduce((a, b) => a > b ? a : b);
        factors.add(
          ProjectFactor(
            kind: FactorKind.materials,
            severe: oldest >= 3,
            title: '${stuck.length} material request${stuck.length == 1 ? '' : 's'} waiting for approval',
            detail: 'Oldest has waited $oldest day${oldest == 1 ? '' : 's'}. Site cannot order until the manager or CEO approves.',
            link: stuck.length == 1
                ? ProjectLink(ProjectTab.materials, 'indent:${stuck.first.id}')
                : const ProjectLink(ProjectTab.materials, 'pending'),
            action: 'Review indents',
          ),
        );
      }
      if (output != null && output < 85) {
        factors.add(
          ProjectFactor(
            kind: FactorKind.output,
            severe: output < 70,
            title: 'Site output at ${output.toStringAsFixed(0)}% of daily target',
            detail: 'Average of the last ${recent.length} daily reports. Low output usually means labour or material shortfall.',
            link: const ProjectLink(ProjectTab.daily, 'output'),
            action: 'See daily output',
          ),
        );
      }
      for (final p in phaseInsights.where((p) => p.overBudget)) {
        factors.add(
          ProjectFactor(
            kind: FactorKind.money,
            severe: true,
            title: '${p.phase.name} is over budget by ${Money.compact(p.spentPaise - p.budgetPaise)}',
            detail: '${Money.compact(p.spentPaise)} spent of ${Money.compact(p.budgetPaise)} with ${p.phase.actualPct.toStringAsFixed(0)}% of the phase done.',
            link: ProjectLink(ProjectTab.money, 'phase:${p.phase.id}'),
            action: 'See phase spend',
          ),
        );
      }
      final overrun = spent - earned;
      if (totalBudget0 > 0 && earned > 0 && overrun > earned * 0.05) {
        final eacOver = forecastCost == null ? null : forecastCost - totalBudget0;
        factors.add(
          ProjectFactor(
            kind: FactorKind.money,
            severe: overrun > earned * 0.15,
            title: 'Cost overrun of ${Money.compact(overrun)}',
            detail: 'Spent ${Money.compact(spent)} for work worth ${Money.compact(earned)} '
                '(${analysis.actual.toStringAsFixed(0)}% of a ${Money.compact(totalBudget0)} budget).'
                '${eacOver != null && eacOver > 0 ? ' At this rate it will finish ${Money.compact(eacOver)} over budget.' : ''}',
            link: const ProjectLink(ProjectTab.money, 'overspend'),
            action: 'See where money went',
          ),
        );
      }
      if (overdue.isNotEmpty) {
        final owed = sum(overdue);
        factors.add(
          ProjectFactor(
            kind: FactorKind.payables,
            severe: overdue.length >= 3,
            title: '${Money.compact(owed)} owed to vendors for over $payableDueDays days',
            detail: '${overdue.length} unpaid bill${overdue.length == 1 ? '' : 's'} past $payableDueDays days. '
                'Late payments can stop material supply and labour on site.',
            link: const ProjectLink(ProjectTab.money, 'payables'),
            action: 'See payables',
          ),
        );
      }
      if (stage == ProjectStage.ongoing && speed != null && required != null && speed < required * 0.85) {
        factors.add(
          ProjectFactor(
            kind: FactorKind.speed,
            severe: speed < required * 0.6,
            title: 'Too slow to finish on time',
            detail: 'Moving at ${speed.toStringAsFixed(1)}% a week; needs ${required.toStringAsFixed(1)}% a week '
                'to finish by ${WorkDay.display(project.endDate)}.',
            link: const ProjectLink(ProjectTab.timeline),
            action: 'See phases',
          ),
        );
      }
      if (pending.isNotEmpty) {
        final oldest = pending
            .map((e) => e.submittedAt)
            .whereType<DateTime>()
            .fold<DateTime?>(null, (a, b) => a == null || b.isBefore(a) ? b : a);
        final waited = oldest == null ? 0 : DateTime.now().difference(oldest).inDays;
        if (waited >= 2 || pending.length >= 3) {
          factors.add(
            ProjectFactor(
              kind: FactorKind.approvals,
              title: '${pending.length} expense${pending.length == 1 ? '' : 's'} waiting for approval',
              detail: '${Money.compact(sum(pending))} on hold${waited > 0 ? ', oldest $waited day${waited == 1 ? '' : 's'}' : ''}. Unapproved bills can stall purchases on site.',
              link: const ProjectLink(ProjectTab.money, 'pending'),
              action: 'Review approvals',
            ),
          );
        }
      }
      if (analysis.incomplete) {
        final undated = phases.where((p) => !p.hasValidDates).length;
        factors.add(
          ProjectFactor(
            kind: FactorKind.setup,
            title: 'Schedule is incomplete',
            detail: phases.isEmpty
                ? 'No phases are set up, so progress and delay cannot be measured.'
                : '$undated phase${undated == 1 ? '' : 's'} without planned dates.',
            link: const ProjectLink(ProjectTab.timeline),
            action: 'Open timeline',
          ),
        );
      }
    }
    factors.sort((a, b) => (b.severe ? 1 : 0) - (a.severe ? 1 : 0));

    final byDay = <String, int>{};
    for (final e in approved) {
      if (WorkDay.tryParse(e.date) == null) continue;
      byDay.update(e.date, (v) => v + e.amountPaise, ifAbsent: () => e.amountPaise);
    }
    var running = 0;
    final curve = [
      for (final day in byDay.keys.toList()..sort())
        (ProjectAnalysis.day(day), running += byDay[day]!),
    ];

    return ProjectInsight(
      project: project.withProgress(analysis.planned, analysis.actual, analysis.health),
      stage: stage,
      analysis: analysis,
      today: today,
      phases: phaseInsights,
      forecastFinish: forecast,
      finishSlipDays: slip,
      daysLeft: dueUtc?.difference(now).inDays,
      timeUsedPct: timeUsed,
      budgetPaise: categoryBudget > 0 ? categoryBudget : phaseBudget,
      phaseBudgetPaise: phaseBudget,
      spentPaise: spent,
      pendingPaise: sum(pending),
      pendingCount: pending.length,
      unassignedSpentPaise: sum(
        approved.where((e) => e.phaseId == null || !phaseIds.contains(e.phaseId)),
      ),
      openIssues: open.length,
      urgentIssues: urgent.length,
      missingReports: missing,
      missingReportDates: missingDates,
      outputPct: output,
      factors: factors,
      spendCurve: curve,
      earnedPaise: earned,
      forecastCostPaise: forecastCost,
      payablesPaise: sum(payables),
      payablesCount: payables.length,
      overduePayablesPaise: sum(overdue),
      overduePayablesCount: overdue.length,
      speedPerWeek: speed,
      requiredPerWeek: required,
    );
  }

  static PhaseInsight _phase(
    ProjectPhase p,
    DateTime clock,
    int spent,
    int pending,
  ) {
    if (!p.hasValidDates) {
      return PhaseInsight(
        phase: p,
        state: p.actualPct >= 100 ? PhaseState.done : PhaseState.noDates,
        plannedPct: 0,
        daysLate: 0,
        spentPaise: spent,
        pendingPaise: pending,
      );
    }
    final start = ProjectAnalysis.day(p.plannedStart!);
    final end = ProjectAnalysis.day(p.plannedEnd!);
    final planned = ProjectAnalysis.plannedFor(p, clock);
    final duration = end.difference(start).inDays;
    // The day on which the plan expected the progress made so far.
    final expectedAt = start.add(
      Duration(days: (p.actualPct.clamp(0, 100) / 100 * duration).round()),
    );
    final late = p.actualPct >= 100
        ? 0
        : clock.difference(expectedAt).inDays.clamp(0, 100000);
    final gap = planned - p.actualPct;
    final state = p.actualPct >= 100
        ? PhaseState.done
        : clock.isAfter(end)
        ? PhaseState.overdue
        : p.actualPct == 0 && clock.isBefore(start)
        ? PhaseState.notStarted
        : gap > 10 || late > 7
        ? PhaseState.behind
        : gap > 3 || late > 2
        ? PhaseState.slipping
        : PhaseState.onTrack;
    return PhaseInsight(
      phase: p,
      state: state,
      plannedPct: planned,
      daysLate: late,
      spentPaise: spent,
      pendingPaise: pending,
    );
  }
}

/// Totals across the projects a leader can see.
class PortfolioInsight {
  PortfolioInsight(this.projects);

  final List<ProjectInsight> projects;

  Iterable<ProjectInsight> get active => projects.where((p) => p.active);
  int get onSchedule =>
      active.where((p) => p.scheduleReady && p.stage == ProjectStage.ongoing && p.analysis.daysBehind == 0).length;
  int get delayed => active.where((p) => p.scheduleReady && p.finishSlipDays > 0).length;
  int get budgetPaise => active.fold(0, (s, p) => s + p.budgetPaise);
  int get spentPaise => active.fold(0, (s, p) => s + p.spentPaise);
  int get pendingPaise => active.fold(0, (s, p) => s + p.pendingPaise);
  int get remainingPaise => budgetPaise - spentPaise;
  /// Sum of each live project's spend beyond the value of its work done.
  int get costOverrunPaise => active.fold(0, (s, p) => s + (p.costOverrunPaise > 0 ? p.costOverrunPaise : 0));
  int get overrunCount => active.where((p) => p.costOverrunPaise > p.earnedPaise * 0.05 && p.earnedPaise > 0).length;
  int get payablesPaise => projects.fold(0, (s, p) => s + p.payablesPaise);
  int get overduePayablesPaise => projects.fold(0, (s, p) => s + p.overduePayablesPaise);
  int get overduePayablesCount => projects.fold(0, (s, p) => s + p.overduePayablesCount);
  int get tooSlowCount => active.where((p) => (p.paceRatio ?? 1) < 0.85).length;

  int get overBudgetCount =>
      active.where((p) => p.budgetPaise > 0 && p.spentPaise > p.budgetPaise).length;

  /// Progress across active projects, weighted by contract value where known.
  double get progressPct {
    final list = active.where((p) => p.scheduleReady).toList();
    if (list.isEmpty) return 0;
    final weights = list.map((p) => p.project.contractValuePaise > 0 ? p.project.contractValuePaise.toDouble() : 1.0).toList();
    final total = weights.fold(0.0, (a, b) => a + b);
    var sum = 0.0;
    for (var i = 0; i < list.length; i++) {
      sum += list[i].analysis.actual * weights[i];
    }
    return sum / total;
  }
}
