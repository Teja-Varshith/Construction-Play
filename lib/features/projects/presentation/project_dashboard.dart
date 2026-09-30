import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/config_models.dart';
import '../../../core/config/config_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/work_day.dart';
import '../../../core/widgets/common.dart';
import '../../auth/data/session.dart';
import '../data/project_insight_provider.dart';
import '../domain/project.dart';
import '../domain/project_analysis.dart';
import '../domain/project_insight.dart';
import '../domain/project_nav.dart';
import 'ceo_ui.dart';
import 'insight_charts.dart';
import 'insight_widgets.dart';
import 'project_nav_scope.dart';
import 'project_record_actions.dart';

const _muted = AppColors.muted;

/// The CEO's first view of a project: where it stands, the numbers that
/// matter, three charts, what is holding it back, and each phase's progress
/// and budget. Each section links to the tab with the detail.
class ProjectDashboard extends ConsumerWidget {
  const ProjectDashboard({super.key, required this.project});
  final Project project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(appConfigProvider);
    final user = ref.watch(currentUserProvider);
    final stage = config.stageOfStatus(project.statusId);
    final insight = ref.watch(projectInsightProvider(project.id));
    final seeMoney = canSeeMoney(user, project, stage);
    void open(ProjectLink link) => openProjectLink(context, project.id, link);

    return ProjectTabPage(
      child: AsyncView(
        value: insight,
        data: (i) {
          final factors = seeMoney
              ? i.factors
              : i.factors.where((f) => f.kind != FactorKind.money && f.kind != FactorKind.approvals).toList();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(insight: i, statusLabel: config.labelOf(ConfigList.projectStatuses, project.statusId)),
              const SizedBox(height: 16),
              _Kpis(insight: i, seeMoney: seeMoney, open: open),
              const SizedBox(height: 16),
              SectionCard(
                title: factors.isEmpty ? 'What’s affecting this project' : 'What’s affecting this project · ${factors.length}',
                subtitle: 'Reasons behind delays and cost pressure, most serious first. Open any to investigate.',
                trailing: TextButton.icon(
                  onPressed: () => open(const ProjectLink(ProjectTab.reports)),
                  icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                  label: const Text('Generate report'),
                ),
                child: i.active
                    ? FactorList(factors: factors, onOpen: (f) => open(f.link))
                    : const Text('Tracking starts when the project is ongoing.', style: TextStyle(color: _muted)),
              ),
              if (i.phases.isNotEmpty || (seeMoney && i.budgetPaise > 0)) ...[
                const SizedBox(height: 16),
                _ProjectCharts(insight: i, seeMoney: seeMoney),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Standard page body for every project tab: white background, centred,
/// same width and padding everywhere.
class ProjectTabPage extends StatelessWidget {
  const ProjectTabPage({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 48),
    children: [
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: child,
        ),
      ),
    ],
  );
}

class _Header extends StatelessWidget {
  const _Header({required this.insight, required this.statusLabel});

  final ProjectInsight insight;
  final String statusLabel;

  @override
  Widget build(BuildContext context) {
    final i = insight;
    final a = i.analysis;
    final p = i.project;
    final stage = i.stage;
    final health = stage == ProjectStage.ongoing && !a.incomplete ? a.health : ProjectHealth.noData;
    final accent = healthColor(context, health);
    final headline = switch (stage) {
      ProjectStage.onHold => 'On hold · schedule clock paused',
      ProjectStage.completed => 'Completed',
      ProjectStage.cancelled => 'Cancelled',
      ProjectStage.pipeline => 'In the pipeline',
      _ =>
        a.incomplete
            ? 'Schedule needs setting up'
            : i.finished
            ? 'All planned work is complete'
            : a.health == ProjectHealth.green
            ? 'Work is on track'
            : a.daysBehind > 0
            ? '${a.daysBehind} day${a.daysBehind == 1 ? '' : 's'} behind plan'
            : 'Slightly behind plan',
    };
    final topFactor = i.active ? i.factors.where((f) => f.kind != FactorKind.setup).firstOrNull : null;
    final daysLeft = i.daysLeft;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: AppRadius.card,
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 24,
            runSpacing: 16,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.start,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Pill(statusLabel, color: accent, background: healthSoftColor(context, health)),
                        Text(
                          [if (p.clientName.isNotEmpty) p.clientName, if (p.city.isNotEmpty) p.city].join(' · '),
                          style: const TextStyle(color: _muted, fontSize: 13),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(headline, style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 4),
                    Text(
                      a.incomplete
                          ? 'Add planned dates and weights to every phase to measure progress and delay.'
                          : '${a.actual.toStringAsFixed(0)}% complete · ${a.planned.toStringAsFixed(0)}% planned by today'
                              '${i.timeUsedPct == null ? '' : ' · ${i.timeUsedPct!.clamp(0, 999).toStringAsFixed(0)}% of the time used'}',
                      style: const TextStyle(color: _muted),
                    ),
                  ],
                ),
              ),
              Wrap(
                spacing: 28,
                runSpacing: 12,
                children: [
                  _HeaderFact(label: 'Target finish', value: p.endDate == null ? 'Not set' : WorkDay.display(p.endDate)),
                  if (i.forecastFinish != null && i.active)
                    _HeaderFact(
                      label: i.finishSlipDays > 0 ? 'Forecast (+${i.finishSlipDays} days)' : 'Forecast finish',
                      value: displayDate(i.forecastFinish),
                      color: i.finishSlipDays > 0 ? context.statusColors.bad : context.statusColors.ok,
                    ),
                  if (daysLeft != null && stage == ProjectStage.ongoing)
                    _HeaderFact(
                      label: daysLeft < 0 ? 'Overdue by' : 'Days left',
                      value: '${daysLeft.abs()}',
                      color: daysLeft < 0 ? context.statusColors.bad : null,
                    ),
                  if (p.contractValuePaise > 0)
                    _HeaderFact(label: 'Contract value', value: Money.compact(p.contractValuePaise)),
                ],
              ),
            ],
          ),
          if (!a.incomplete) ...[
            const SizedBox(height: 18),
            PlanVsActualBar(actual: a.actual, planned: a.planned, color: accent, height: 10),
            const SizedBox(height: 6),
            BarLegend(items: [(accent, 'Work done ${a.actual.toStringAsFixed(0)}%'), (AppColors.ink, 'Planned by today ${a.planned.toStringAsFixed(0)}%')]),
          ],
          if (topFactor != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: topFactor.severe ? context.statusColors.badSoft : context.statusColors.warnSoft,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(
                    factorIcon(topFactor.kind),
                    size: 18,
                    color: topFactor.severe ? context.statusColors.bad : context.statusColors.warn,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          const TextSpan(text: 'Main factor: ', style: TextStyle(fontWeight: FontWeight.w800)),
                          TextSpan(text: topFactor.title),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HeaderFact extends StatelessWidget {
  const _HeaderFact({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(color: _muted, fontSize: 12)),
      const SizedBox(height: 2),
      Text(
        value,
        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: color ?? AppColors.ink),
      ),
    ],
  );
}

/// The three things every project is judged on — cost overrun, payables and
/// speed — plus the forecast finish. Each opens the place to act on it.
class _Kpis extends StatelessWidget {
  const _Kpis({required this.insight, required this.seeMoney, required this.open});

  final ProjectInsight insight;
  final bool seeMoney;
  final void Function(ProjectLink link) open;

  @override
  Widget build(BuildContext context) {
    final i = insight;
    final colors = context.statusColors;
    final pace = i.paceRatio;
    final overrun = i.costOverrunPaise;
    final overrunBad = i.budgetPaise > 0 && i.earnedPaise > 0 && overrun > i.earnedPaise * 0.05;
    final eacOver = i.forecastOverrunPaise;
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900 ? 4 : constraints.maxWidth >= 520 ? 2 : 1;
        final width = (constraints.maxWidth - (columns - 1) * 14) / columns;
        Widget tile(Widget child) => SizedBox(width: width, child: child);
        return Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            if (seeMoney) ...[
              tile(NeoMetricCard(
                label: 'Cost overrun',
                value: i.budgetPaise == 0
                    ? 'No budget'
                    : overrun > 0
                    ? Money.compact(overrun)
                    : 'None',
                caption: i.budgetPaise == 0
                    ? 'Set a budget to track overrun'
                    : 'Spent ${Money.compact(i.spentPaise)} for work worth ${Money.compact(i.earnedPaise)}'
                        '${eacOver != null && eacOver > 0 ? ' · ${Money.compact(eacOver)} over at finish' : ''}',
                icon: Icons.trending_up,
                accent: overrunBad ? colors.bad : colors.ok,
                onTap: () => open(const ProjectLink(ProjectTab.money, 'overspend')),
              )),
              tile(NeoMetricCard(
                label: 'Payables',
                value: i.payablesPaise == 0 ? 'None' : Money.compact(i.payablesPaise),
                caption: i.payablesCount == 0
                    ? 'All approved bills are paid'
                    : '${i.payablesCount} unpaid bill${i.payablesCount == 1 ? '' : 's'}'
                        '${i.overduePayablesCount > 0 ? ' · ${Money.compact(i.overduePayablesPaise)} over ${ProjectInsight.payableDueDays} days' : ''}',
                icon: Icons.receipt_long_outlined,
                accent: i.overduePayablesCount > 0 ? colors.bad : const Color(0xFF6C4BA5),
                onTap: () => open(const ProjectLink(ProjectTab.money, 'payables')),
              )),
            ],
            tile(NeoMetricCard(
              label: 'Speed',
              value: i.speedPerWeek == null ? '—' : '${i.speedPerWeek!.toStringAsFixed(1)}% / week',
              caption: i.requiredPerWeek == null
                  ? (i.scheduleReady ? 'No target date ahead' : 'Schedule not set')
                  : 'Needs ${i.requiredPerWeek!.toStringAsFixed(1)}% / week to finish on time',
              icon: Icons.speed,
              accent: pace == null
                  ? null
                  : pace < 0.6
                  ? colors.bad
                  : pace < 0.85
                  ? colors.warn
                  : colors.ok,
              onTap: () => open(const ProjectLink(ProjectTab.timeline)),
            )),
            tile(NeoMetricCard(
              label: i.finishSlipDays > 0 ? 'Forecast finish · ${i.finishSlipDays} days late' : 'Forecast finish',
              value: i.forecastFinish == null ? 'Not ready' : displayDate(i.forecastFinish),
              caption: 'Target ${displayDateKey(i.project.endDate)}',
              icon: Icons.flag_outlined,
              accent: !i.scheduleReady
                  ? null
                  : i.finishSlipDays > 14
                  ? colors.bad
                  : i.finishSlipDays > 0
                  ? colors.warn
                  : colors.ok,
              onTap: () => open(const ProjectLink(ProjectTab.timeline)),
            )),
            if (!seeMoney)
              tile(NeoMetricCard(
                label: 'Open issues',
                value: '${i.openIssues}',
                caption: i.urgentIssues > 0 ? '${i.urgentIssues} high priority' : 'None high priority',
                icon: Icons.flag_outlined,
                accent: i.urgentIssues > 0 ? colors.bad : null,
                onTap: () => open(ProjectLink(ProjectTab.issues, i.urgentIssues > 0 ? 'urgent' : 'open')),
              )),
          ],
        );
      },
    );
  }
}

class _ProjectCharts extends StatelessWidget {
  const _ProjectCharts({required this.insight, required this.seeMoney});

  final ProjectInsight insight;
  final bool seeMoney;

  @override
  Widget build(BuildContext context) {
    final i = insight;
    final over = i.budgetPaise > 0 && i.spentPaise > i.budgetPaise;
    final used = i.budgetUsedPct;
    DateTime? day(String? key) => WorkDay.tryParse(key) == null ? null : ProjectAnalysis.day(key!);
    final byState = <PhaseState, int>{};
    for (final p in i.phases) {
      byState.update(p.state, (v) => v + 1, ifAbsent: () => 1);
    }
    return ChartGrid(
      minTileWidth: 330,
      children: [
        if (seeMoney && i.budgetPaise > 0)
          ChartCard(
            title: 'Budget',
            subtitle: 'Where the ${Money.compact(i.budgetPaise)} stands',
            child: DonutChart(
              centerValue: used == null ? '—' : '${used.toStringAsFixed(0)}%',
              centerLabel: 'of budget spent',
              slices: [
                DonutSlice('Spent', i.spentPaise.toDouble(), over ? context.statusColors.bad : ChartColors.actual,
                    display: Money.compact(i.spentPaise)),
                DonutSlice('Awaiting approval', i.pendingPaise.toDouble(), ChartColors.pending,
                    display: Money.compact(i.pendingPaise)),
                if (over)
                  DonutSlice('Over budget', 0, context.statusColors.bad, display: Money.compact(i.spentPaise - i.budgetPaise))
                else
                  DonutSlice('Left', math.max(0, i.remainingPaise - i.pendingPaise).toDouble(), ChartColors.remaining,
                      display: Money.compact(i.remainingPaise)),
              ],
            ),
          )
        else if (i.phases.isNotEmpty)
          ChartCard(
            title: 'Phases by status',
            subtitle: '${i.phasesDone} of ${i.phases.length} phases done',
            child: DonutChart(
              centerValue: '${i.phases.length}',
              centerLabel: 'phases',
              slices: [
                for (final s in PhaseState.values)
                  if ((byState[s] ?? 0) > 0) DonutSlice(s.label, byState[s]!.toDouble(), phaseStateColor(context, s)),
              ],
            ),
          ),
        if (i.phases.isNotEmpty)
          ChartCard(
            title: 'Progress by phase',
            subtitle: 'Planned by today vs actual work done',
            child: PlanActualBars(
              items: [
                for (final p in i.phases)
                  PlanActualItem(
                    p.phase.name,
                    p.plannedPct,
                    p.phase.actualPct,
                    actualColor: p.state.late ? phaseStateColor(context, p.state) : null,
                  ),
              ],
            ),
          ),
        if (seeMoney)
          ChartCard(
            title: 'Spend over time',
            subtitle: 'Approved spend to date against the budget',
            child: SpendCurve(
              points: i.spendCurve,
              budgetPaise: i.budgetPaise,
              start: day(i.project.startDate),
              end: day(i.today),
            ),
          ),
      ],
    );
  }
}
