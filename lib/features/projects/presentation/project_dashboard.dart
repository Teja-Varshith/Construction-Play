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
import 'insight_charts.dart';
import 'insight_widgets.dart';
import 'project_plain.dart';
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
              _Summary(
                plain: PlainProject(i, seeMoney: seeMoney),
                statusLabel: config.labelOf(ConfigList.projectStatuses, project.statusId),
                open: open,
              ),
              const SizedBox(height: 16),
              SectionCard(
                title: factors.isEmpty ? 'What needs attention' : 'What needs attention · ${factors.length}',
                subtitle: 'Most serious first. Tap any to see the detail.',
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

/// The top of a project in plain words: the verdict, how much is built
/// against the plan, then time, money and bills as sentences that each open
/// the detail. Uses the same [PlainProject] wording as the home tiles.
class _Summary extends StatelessWidget {
  const _Summary({required this.plain, required this.statusLabel, required this.open});

  final PlainProject plain;
  final String statusLabel;
  final void Function(ProjectLink link) open;

  @override
  Widget build(BuildContext context) {
    final i = plain.insight;
    final a = i.analysis;
    final p = i.project;
    final colors = context.statusColors;
    final color = toneColor(context, plain.tone == Tone.none ? Tone.ok : plain.tone);
    final daysLeft = i.daysLeft;
    final problem = plain.mainProblem;
    final lines = [
      ...plain.lines,
      if (!plain.seeMoney && i.active)
        PlainLine(
          Icons.flag_outlined,
          i.openIssues == 0
              ? 'No open site issues'
              : '${i.openIssues} open site issue${i.openIssues == 1 ? '' : 's'}'
                  '${i.urgentIssues > 0 ? ' · ${i.urgentIssues} high priority' : ''}',
          i.urgentIssues > 0 ? Tone.bad : Tone.ok,
          link: ProjectLink(ProjectTab.issues, i.urgentIssues > 0 ? 'urgent' : 'open'),
        ),
    ];

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
            spacing: 10,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (plain.tone == Tone.none) Pill(statusLabel) else VerdictPill(plain: plain),
              Text(
                [
                  if (p.clientName.isNotEmpty) p.clientName,
                  if (p.city.isNotEmpty) p.city,
                  if (p.contractValuePaise > 0 && plain.seeMoney) 'contract ${Money.compact(p.contractValuePaise)}',
                  if (daysLeft != null && plain.running)
                    daysLeft >= 0 ? '$daysLeft days to the promised date' : 'promised date passed ${-daysLeft} days ago',
                ].join(' · '),
                style: const TextStyle(color: _muted, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (plain.running && i.scheduleReady) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${a.actual.toStringAsFixed(0)}%',
                  style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, height: 1, letterSpacing: -0.5),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(
                      plain.progress.replaceFirst(RegExp(r'^\d+% built · '), 'built · '),
                      style: const TextStyle(color: _muted, fontSize: 14),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ProgressMeter(actual: a.actual, planned: a.planned, color: color, height: 10),
            const SizedBox(height: 4),
            const Text('The dark mark shows where the work should be today.', style: TextStyle(color: _muted, fontSize: 11.5)),
            const SizedBox(height: 14),
          ] else if (plain.running) ...[
            const Text(
              'Add planned dates and weights to every phase so progress and delay can be measured.',
              style: TextStyle(color: _muted),
            ),
            const SizedBox(height: 12),
          ],
          if (i.active) ...[
            const Divider(height: 1),
            const SizedBox(height: 8),
            for (final line in lines)
              PlainLineRow(line: line, onTap: line.link == null ? null : () => open(line.link!)),
          ],
          if (problem != null) ...[
            const SizedBox(height: 10),
            Material(
              color: problem.severe ? colors.badSoft : colors.warnSoft,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                onTap: () => open(problem.link),
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      Icon(factorIcon(problem.kind), size: 18, color: problem.severe ? colors.bad : colors.warn),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              const TextSpan(text: 'Biggest problem: ', style: TextStyle(fontWeight: FontWeight.w800)),
                              TextSpan(text: problem.title),
                            ],
                          ),
                        ),
                      ),
                      Text(problem.action, style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w700, fontSize: 13)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
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
