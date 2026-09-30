import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/config/config_models.dart';
import '../../../core/config/config_repository.dart';
import '../../../core/dynamic_form/field_values.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/work_day.dart';
import '../../../core/widgets/common.dart';
import '../../auth/data/session.dart';
import '../../auth/domain/app_user.dart';
import '../../finance/presentation/expense_editor.dart';
import '../../finance/presentation/money_tab.dart';
import '../../users/data/user_repository.dart';
import '../data/project_detail_repository.dart';
import '../data/project_insight_provider.dart';
import '../data/project_media.dart';
import '../data/project_repository.dart';
import '../domain/project.dart';
import '../domain/project_detail.dart';
import '../domain/project_insight.dart';
import '../domain/project_nav.dart';
import 'dpr_calendar.dart';
import 'insight_charts.dart';
import 'insight_widgets.dart';
import 'project_activity.dart';
import 'project_dashboard.dart';
import 'project_editors.dart';
import 'project_gantt.dart';
import 'project_nav_scope.dart';
import 'project_record_actions.dart';
import 'project_reports.dart';
import '../../inventory/data/inventory_repository.dart';
import '../../inventory/presentation/materials_section.dart';
import '../../inventory/domain/inventory.dart';
import 'ceo_ui.dart';

const _muted = AppColors.muted;

/// One project, in tabs. The URL chooses the tab and what to focus on
/// (`/projects/:id?tab=reports&focus=missing`), so every delay factor, KPI or
/// dashboard row can link straight to the place to investigate it.
class ProjectOverviewScreen extends ConsumerWidget {
  const ProjectOverviewScreen({
    super.key,
    required this.projectId,
    this.tab,
    this.focus,
  });

  final String projectId;
  final String? tab;
  final String? focus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final project = ref.watch(projectProvider(projectId));
    return project.when(
      loading: () => const Scaffold(body: LoadingView(message: 'Loading project…')),
      error: (error, _) => Scaffold(
        appBar: AppBar(title: const Text('Project')),
        body: MessageView(
          icon: Icons.cloud_off_outlined,
          title: 'Couldn’t load this project',
          message: '$error',
        ),
      ),
      data: (value) {
        if (value == null || value.deleted) {
          return Scaffold(
            appBar: AppBar(title: const Text('Project')),
            body: const MessageView(
              icon: Icons.domain_disabled_outlined,
              title: 'Project not found',
              message: 'It may have been archived or you may no longer have access.',
            ),
          );
        }
        return _ProjectScreen(
          project: value,
          config: ref.watch(appConfigProvider),
          link: ProjectLink(ProjectTab.fromSlug(tab), focus),
        );
      },
    );
  }
}

class _ProjectScreen extends ConsumerStatefulWidget {
  const _ProjectScreen({required this.project, required this.config, required this.link});

  final Project project;
  final AppConfig config;
  final ProjectLink link;

  @override
  ConsumerState<_ProjectScreen> createState() => _ProjectScreenState();
}

/// Sections of the project sidebar, grouped. The first group is the
/// project's summary; the rest is the detail behind it.
const _sectionGroups = <(String?, List<ProjectTab>)>[
  (null, [ProjectTab.overview, ProjectTab.reports]),
  ('Work', [ProjectTab.timeline, ProjectTab.daily, ProjectTab.materials, ProjectTab.issues, ProjectTab.documents]),
  ('Money', [ProjectTab.money]),
  ('Project', [ProjectTab.team, ProjectTab.info, ProjectTab.activity]),
];

IconData _sectionIcon(ProjectTab t) => switch (t) {
  ProjectTab.overview => Icons.insights_outlined,
  ProjectTab.reports => Icons.summarize_outlined,
  ProjectTab.timeline => Icons.view_timeline_outlined,
  ProjectTab.daily => Icons.event_note_outlined,
  ProjectTab.materials => Icons.inventory_2_outlined,
  ProjectTab.issues => Icons.flag_outlined,
  ProjectTab.documents => Icons.folder_outlined,
  ProjectTab.money => Icons.account_balance_wallet_outlined,
  ProjectTab.team => Icons.groups_outlined,
  ProjectTab.info => Icons.info_outline,
  ProjectTab.activity => Icons.history,
};

class _ProjectScreenState extends ConsumerState<_ProjectScreen> {
  late ProjectLink _link = widget.link;
  var _seq = 0;

  @override
  void didUpdateWidget(covariant _ProjectScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final l = widget.link;
    if (l.tab != oldWidget.link.tab || l.focus != oldWidget.link.focus) _open(l);
  }

  void _open(ProjectLink link) => setState(() {
    _link = link;
    _seq++;
  });

  @override
  Widget build(BuildContext context) {
    final project = widget.project;
    final config = widget.config;
    final stage = config.stageOfStatus(project.statusId);
    final user = ref.watch(currentUserProvider);
    final closed = stage == ProjectStage.completed || stage == ProjectStage.cancelled;
    final manage = canManageProject(user, project) && !closed;
    final report = canReportProject(user, project) && !closed;
    final phases = ref.watch(projectPhasesProvider(project.id));
    final insight = ref.watch(projectInsightProvider(project.id)).value;
    final seeMoney = canSeeMoney(user, project, stage);
    final approveMaterials = !closed && (user.isCeo || user.isAdmin || canManageProject(user, project));
    final inventory = ref.watch(projectInventoryProvider(project.id)).value;
    bool visible(ProjectTab t) => t != ProjectTab.money || seeMoney;
    final current = visible(_link.tab) ? _link.tab : ProjectTab.overview;
    int? badge(ProjectTab t) => switch (t) {
      ProjectTab.issues => insight?.urgentIssues,
      ProjectTab.daily => insight?.missingReports,
      ProjectTab.money => insight?.overduePayablesCount,
      ProjectTab.materials => inventory == null ? null : inventory.late.length + (approveMaterials ? inventory.pending.length : 0),
      _ => null,
    };
    final subtitle = [
      if (project.code.isNotEmpty) project.code,
      if (project.clientName.isNotEmpty) project.clientName,
      if (project.city.isNotEmpty) project.city,
    ].join(' · ');
    void add(String kind) => kind == 'expense'
        ? showExpenseEditor(context, project: project)
        : showProjectEditor(
            context,
            project: project,
            kind: kind,
            nextOrder: (phases.value ?? []).fold<int>(-1, (order, phase) => phase.order > order ? phase.order : order) + 1,
          );
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 1000;

    Widget page(ProjectTab tab) => switch (tab) {
      ProjectTab.overview => ProjectDashboard(project: project),
      ProjectTab.reports => ProjectReportsSection(project: project, seeMoney: seeMoney),
      ProjectTab.timeline => _TimelineTab(project: project),
      ProjectTab.team => _TeamTab(project: project),
      ProjectTab.daily => _DailyProgressTab(project: project),
      ProjectTab.materials => MaterialsSection(
        project: project,
        canRequest: report,
        canReceive: manage,
        canApprove: approveMaterials,
      ),
      ProjectTab.issues => _IssuesTab(project: project, config: config),
      ProjectTab.documents => _DocumentsTab(project: project, config: config),
      ProjectTab.money => MoneyTab(project: project, canManage: manage || user.isAdmin),
      ProjectTab.info => _InfoTab(project: project, config: config),
      ProjectTab.activity => ProjectActivity(projectId: project.id),
    };

    final content = AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      switchInCurve: Curves.easeOutCubic,
      transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
      child: KeyedSubtree(key: ValueKey(current), child: page(current)),
    );

    return ProjectNavScope(
      projectId: project.id,
      current: _link,
      seq: _seq,
      onOpen: _open,
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 64,
          titleSpacing: 8,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(project.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              if (subtitle.isNotEmpty)
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: _muted),
                ),
            ],
          ),
          actions: [
            if (report && width >= 700) ...[
              OutlinedButton.icon(
                onPressed: () => add('issues'),
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 38)),
                icon: const Icon(Icons.flag_outlined, size: 18),
                label: const Text('Raise issue'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: () => add('dprs'),
                style: FilledButton.styleFrom(minimumSize: const Size(0, 38)),
                icon: const Icon(Icons.add_task, size: 18),
                label: const Text('Daily report'),
              ),
              const SizedBox(width: 4),
            ],
            if (manage || report || user.isAdmin)
              PopupMenuButton<String>(
                tooltip: 'More actions',
                icon: const Icon(Icons.more_vert),
                onSelected: add,
                itemBuilder: (_) => [
                  if (report && width < 700) const PopupMenuItem(value: 'dprs', child: Text('Submit daily report')),
                  if (report && width < 700) const PopupMenuItem(value: 'issues', child: Text('Raise an issue')),
                  if (manage) const PopupMenuItem(value: 'details', child: Text('Edit project details')),
                  if (manage) const PopupMenuItem(value: 'phases', child: Text('Add phase')),
                  if (manage) const PopupMenuItem(value: 'expense', child: Text('Log expense')),
                  if (report) const PopupMenuItem(value: 'documents', child: Text('Upload document')),
                  if (user.isAdmin) const PopupMenuItem(value: 'status', child: Text('Change status / reopen')),
                ],
              ),
            const SizedBox(width: 8),
          ],
          bottom: wide
              ? null
              : PreferredSize(
                  preferredSize: const Size.fromHeight(52),
                  child: _SectionBar(
                    current: current,
                    visible: visible,
                    badge: badge,
                    onSelect: (t) => _open(ProjectLink(t)),
                  ),
                ),
        ),
        body: SafeArea(
          top: false,
          child: wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _ProjectSideNav(
                      insight: insight,
                      statusLabel: config.labelOf(ConfigList.projectStatuses, project.statusId),
                      current: current,
                      visible: visible,
                      badge: badge,
                      onSelect: (t) => _open(ProjectLink(t)),
                    ),
                    Expanded(child: content),
                  ],
                )
              : content,
        ),
      ),
    );
  }
}

/// The project's own sidebar on wide screens: status at the top, then
/// sections in groups, with a count where something needs attention.
class _ProjectSideNav extends StatelessWidget {
  const _ProjectSideNav({
    required this.insight,
    required this.statusLabel,
    required this.current,
    required this.visible,
    required this.badge,
    required this.onSelect,
  });

  final ProjectInsight? insight;
  final String statusLabel;
  final ProjectTab current;
  final bool Function(ProjectTab) visible;
  final int? Function(ProjectTab) badge;
  final ValueChanged<ProjectTab> onSelect;

  @override
  Widget build(BuildContext context) {
    final i = insight;
    final health = i == null || i.stage != ProjectStage.ongoing || !i.scheduleReady ? ProjectHealth.noData : i.analysis.health;
    return Container(
      width: 236,
      decoration: const BoxDecoration(
        color: Color(0xFFFAFBFC),
        border: Border(right: BorderSide(color: AppColors.line)),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    Pill(statusLabel),
                    if (health != ProjectHealth.noData) ProjectHealthPill(health: health),
                  ],
                ),
                if (i != null && i.scheduleReady) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Text(
                        '${i.analysis.actual.toStringAsFixed(0)}%',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(width: 6),
                      const Text('complete', style: TextStyle(color: _muted, fontSize: 12.5)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  PlanVsActualBar(
                    actual: i.analysis.actual,
                    planned: i.analysis.planned,
                    color: healthColor(context, health),
                    height: 6,
                  ),
                ],
              ],
            ),
          ),
          for (final (title, tabs) in _sectionGroups) ...[
            if (title != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 14, 10, 6),
                child: Text(
                  title.toUpperCase(),
                  style: const TextStyle(fontSize: 11, letterSpacing: 0.8, fontWeight: FontWeight.w700, color: _muted),
                ),
              ),
            for (final t in tabs)
              if (visible(t))
                _SectionItem(
                  tab: t,
                  selected: t == current,
                  badge: badge(t),
                  onTap: () => onSelect(t),
                ),
          ],
        ],
      ),
    );
  }
}

class _SectionItem extends StatefulWidget {
  const _SectionItem({required this.tab, required this.selected, required this.badge, required this.onTap});

  final ProjectTab tab;
  final bool selected;
  final int? badge;
  final VoidCallback onTap;

  @override
  State<_SectionItem> createState() => _SectionItemState();
}

class _SectionItemState extends State<_SectionItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final selected = widget.selected;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.only(bottom: 2),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: selected
                ? primary.withValues(alpha: 0.10)
                : _hover
                ? const Color(0xFFEFF2F6)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(
            children: [
              Icon(_sectionIcon(widget.tab), size: 19, color: selected ? primary : _muted),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.tab.label,
                  style: TextStyle(
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? primary : const Color(0xFF2B3743),
                  ),
                ),
              ),
              if ((widget.badge ?? 0) > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                  decoration: BoxDecoration(
                    color: context.statusColors.badSoft,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    '${widget.badge}',
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: context.statusColors.bad),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Narrow screens: the same sections as a scrollable row under the title.
class _SectionBar extends StatelessWidget {
  const _SectionBar({required this.current, required this.visible, required this.badge, required this.onSelect});

  final ProjectTab current;
  final bool Function(ProjectTab) visible;
  final int? Function(ProjectTab) badge;
  final ValueChanged<ProjectTab> onSelect;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 52,
    child: ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
      children: [
        for (final (_, tabs) in _sectionGroups)
          for (final t in tabs)
            if (visible(t))
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  avatar: Icon(_sectionIcon(t), size: 16),
                  label: Text((badge(t) ?? 0) > 0 ? '${t.label} · ${badge(t)}' : t.label),
                  selected: t == current,
                  showCheckmark: false,
                  onSelected: (_) => onSelect(t),
                ),
              ),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// Timeline
// ---------------------------------------------------------------------------

class _TimelineTab extends ConsumerWidget {
  const _TimelineTab({required this.project});

  final Project project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final insight = ref.watch(projectInsightProvider(project.id));
    final issues = ref.watch(projectIssuesProvider(project.id)).value ?? const <ProjectIssue>[];
    final indents = ref.watch(projectIndentsProvider(project.id)).value ?? const <Indent>[];
    final nav = ProjectNavScope.maybeOf(context);
    final focusPhase = nav?.current.tab == ProjectTab.timeline ? nav!.current.focusId('phase') : null;
    return ProjectTabPage(
      child: AsyncView(
        value: insight,
        data: (i) {
          if (i.phases.isEmpty) {
            return const _TabEmpty(
              icon: Icons.view_timeline_outlined,
              title: 'Timeline not set yet',
              message: 'Phases and planned dates will appear here once the office team adds them.',
            );
          }
          final phases = i.phases.map((p) => p.phase).toList();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TabIntro(
                title: 'Timeline',
                subtitle: '${i.phasesDone} of ${i.phases.length} phases done'
                    '${i.phasesLate > 0 ? ' · ${i.phasesLate} running late' : ''} · planned window vs actual progress',
              ),
              const SizedBox(height: 16),
              _TimelineInsights(insight: i, indents: indents, projectId: project.id),
              const SizedBox(height: 16),
              _Panel(child: ProjectGantt(phases: phases, today: i.today)),
              const SizedBox(height: 24),
              const _SectionLabel('Phases'),
              const SizedBox(height: 10),
              for (var n = 0; n < i.phases.length; n++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: FocusHighlight(
                    active: focusPhase == i.phases[n].phase.id,
                    seq: nav?.seq ?? 0,
                    child: _PhaseCard(
                      project: project,
                      insight: i.phases[n],
                      previous: n == 0 ? null : phases[n - 1],
                      openIssues: issues.where((x) => x.isOpen && x.phaseId == i.phases[n].phase.id).length,
                      indents: indents.where((x) => x.phaseId == i.phases[n].phase.id).toList(),
                      today: i.today,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _PhaseCard extends ConsumerWidget {
  const _PhaseCard({
    required this.project,
    required this.insight,
    required this.openIssues,
    required this.indents,
    required this.today,
    this.previous,
  });

  final Project project;
  final PhaseInsight insight;
  final ProjectPhase? previous;
  final int openIssues;
  final List<Indent> indents;
  final String today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = insight.phase;
    final color = phaseStateColor(context, insight.state);
    final owner = ref.watch(allUsersProvider).value?.where((u) => u.uid == p.ownerId).firstOrNull?.name;
    final seeMoney = canSeeMoney(
      ref.watch(currentUserProvider),
      project,
      ref.watch(appConfigProvider).stageOfStatus(project.statusId),
    );
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.name, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      [
                        p.hasValidDates
                            ? '${WorkDay.display(p.plannedStart)} – ${WorkDay.display(p.plannedEnd)}'
                            : 'Planned dates not set',
                        if (owner != null) 'Owner: $owner',
                        'Weight ${p.weight.toStringAsFixed(p.weight == p.weight.roundToDouble() ? 0 : 1)}',
                      ].join('  ·  '),
                      style: const TextStyle(color: _muted, fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Pill(
                insight.state.late && insight.daysLate > 0
                    ? '${insight.state.label} · ${insight.daysLate}d'
                    : insight.state.label,
                color: color,
                background: color.withValues(alpha: 0.10),
              ),
            ],
          ),
          const SizedBox(height: 14),
          PlanVsActualBar(actual: p.actualPct, planned: insight.plannedPct, color: color, height: 9),
          const SizedBox(height: 4),
          Text(
            '${p.actualPct.toStringAsFixed(0)}% done · ${insight.plannedPct.toStringAsFixed(0)}% planned by today',
            style: const TextStyle(color: _muted, fontSize: 12),
          ),
          if (seeMoney && (insight.hasBudget || insight.spentPaise > 0)) ...[
            const SizedBox(height: 12),
            if (insight.hasBudget)
              BudgetBar(
                budgetPaise: insight.budgetPaise,
                spentPaise: insight.spentPaise,
                pendingPaise: insight.pendingPaise,
                progressPct: p.actualPct,
                height: 8,
              ),
            const SizedBox(height: 4),
            Text(
              insight.hasBudget
                  ? 'Budget ${Money.compact(insight.budgetPaise)} · spent ${Money.compact(insight.spentPaise)} · '
                        '${insight.overBudget ? '${Money.compact(-insight.remainingPaise)} over' : '${Money.compact(insight.remainingPaise)} left'}'
                  : '${Money.compact(insight.spentPaise)} spent · no phase budget',
              style: TextStyle(
                color: insight.overBudget ? context.statusColors.bad : _muted,
                fontSize: 12,
                fontWeight: insight.overBudget ? FontWeight.w700 : null,
              ),
            ),
          ],
          if (p.delayReason.isNotEmpty) ...[
            const SizedBox(height: 12),
            _Callout(
              icon: Icons.info_outline,
              color: context.statusColors.warn,
              background: context.statusColors.warnSoft,
              text: 'Delay reason: ${p.delayReason}',
            ),
          ] else if (insight.state.late) ...[
            const SizedBox(height: 12),
            _Callout(
              icon: Icons.help_outline,
              color: context.statusColors.bad,
              background: context.statusColors.badSoft,
              text: 'This phase is late and no reason has been recorded. Update the phase to add one.',
            ),
          ],
          const SizedBox(height: 12),
          // Everything related to this phase, one tap from here.
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (seeMoney)
                _RelatedChip(
                  icon: Icons.account_balance_wallet_outlined,
                  label: insight.hasBudget
                      ? '${Money.compact(insight.spentPaise)} of ${Money.compact(insight.budgetPaise)} spent'
                      : '${Money.compact(insight.spentPaise)} spent',
                  alert: insight.overBudget,
                  onTap: () => openProjectLink(context, project.id, ProjectLink(ProjectTab.money, 'phase:${p.id}')),
                ),
              _RelatedChip(
                icon: Icons.flag_outlined,
                label: openIssues == 0 ? 'No open issues' : '$openIssues open issue${openIssues == 1 ? '' : 's'}',
                alert: openIssues > 0,
                onTap: () => openProjectLink(context, project.id, ProjectLink(ProjectTab.issues, 'phase:${p.id}')),
              ),
              _RelatedChip(
                icon: Icons.inventory_2_outlined,
                label: indents.isEmpty
                    ? 'No material indents'
                    : [
                        '${indents.length} indent${indents.length == 1 ? '' : 's'}',
                        if (indents.any((x) => x.isLate(today))) '${indents.where((x) => x.isLate(today)).length} late',
                        if (indents.any((x) => x.isPending)) '${indents.where((x) => x.isPending).length} waiting',
                      ].join(' · '),
                alert: indents.any((x) => x.isLate(today)),
                onTap: () => openProjectLink(context, project.id, ProjectLink(ProjectTab.materials, 'phase:${p.id}')),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ProjectRecordActions(project: project, kind: 'phases', record: p, previous: previous),
        ],
      ),
    );
  }
}

class _RelatedChip extends StatelessWidget {
  const _RelatedChip({required this.icon, required this.label, required this.onTap, this.alert = false});

  final IconData icon;
  final String label;
  final bool alert;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = alert ? context.statusColors.bad : const Color(0xFF354657);
    return ActionChip(
      avatar: Icon(icon, size: 16, color: color),
      label: Text(label, style: TextStyle(color: color, fontWeight: alert ? FontWeight.w700 : FontWeight.w500)),
      backgroundColor: alert ? context.statusColors.badSoft : null,
      side: BorderSide(color: alert ? color.withValues(alpha: 0.3) : AppColors.line),
      onPressed: onTap,
    );
  }
}

/// Timeline at a glance: what is being worked on, what is most late, when it
/// will finish, how fast it is moving, and whether material is holding it up.
/// Each tile opens the place to act on it.
class _TimelineInsights extends StatelessWidget {
  const _TimelineInsights({required this.insight, required this.indents, required this.projectId});

  final ProjectInsight insight;
  final List<Indent> indents;
  final String projectId;

  @override
  Widget build(BuildContext context) {
    final i = insight;
    final colors = context.statusColors;
    void open(ProjectLink l) => openProjectLink(context, projectId, l);
    final current = i.phases.where((p) => p.phase.actualPct > 0 && p.phase.actualPct < 100).toList();
    final late = i.phases.where((p) => p.state.late).toList()..sort((a, b) => b.daysLate.compareTo(a.daysLate));
    final next = i.phases.where((p) => p.phase.actualPct == 0).firstOrNull;
    final lateIndents = indents.where((x) => x.isLate(i.today)).length;
    final waiting = indents.where((x) => x.isPending).length;
    final pace = i.paceRatio;
    return LayoutBuilder(
      builder: (context, c) {
        final columns = c.maxWidth >= 1000 ? 5 : c.maxWidth >= 640 ? 3 : 1;
        final w = (c.maxWidth - (columns - 1) * 12) / columns;
        Widget tile(Widget child) => SizedBox(width: w, child: child);
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            tile(NeoMetricCard(
              label: 'Working on',
              value: current.isEmpty ? (next == null ? 'All done' : 'Not started') : current.map((p) => p.phase.name).join(', '),
              caption: current.isEmpty
                  ? (next == null ? null : 'Next: ${next.phase.name}')
                  : '${current.first.phase.actualPct.toStringAsFixed(0)}% of ${current.first.phase.name} done',
              icon: Icons.construction_outlined,
              onTap: current.isEmpty && next == null
                  ? null
                  : () => open(ProjectLink(ProjectTab.timeline, 'phase:${(current.isEmpty ? next! : current.first).phase.id}')),
            )),
            tile(NeoMetricCard(
              label: 'Most late',
              value: late.isEmpty ? 'None' : late.first.phase.name,
              caption: late.isEmpty
                  ? 'Every phase is on plan'
                  : '${late.first.daysLate} days behind${late.length > 1 ? ' · ${late.length} phases late' : ''}',
              icon: Icons.schedule,
              accent: late.isEmpty ? colors.ok : colors.bad,
              onTap: late.isEmpty ? null : () => open(ProjectLink(ProjectTab.timeline, 'phase:${late.first.phase.id}')),
            )),
            tile(NeoMetricCard(
              label: 'Forecast finish',
              value: i.forecastFinish == null ? 'Not ready' : displayDate(i.forecastFinish),
              caption: i.finishSlipDays > 0 ? '${i.finishSlipDays} days after target' : 'Target ${displayDateKey(i.project.endDate)}',
              icon: Icons.flag_outlined,
              accent: i.finishSlipDays > 0 ? colors.bad : colors.ok,
              onTap: i.analysis.pausedDays > 0 ? () => open(const ProjectLink(ProjectTab.info, 'holds')) : null,
            )),
            tile(NeoMetricCard(
              label: 'Speed',
              value: i.speedPerWeek == null ? '—' : '${i.speedPerWeek!.toStringAsFixed(1)}%/wk',
              caption: i.requiredPerWeek == null ? null : 'Needs ${i.requiredPerWeek!.toStringAsFixed(1)}%/wk',
              icon: Icons.speed,
              accent: pace == null ? null : pace < 0.6 ? colors.bad : pace < 0.85 ? colors.warn : colors.ok,
              onTap: () => open(const ProjectLink(ProjectTab.daily, 'output')),
            )),
            tile(NeoMetricCard(
              label: 'Material',
              value: lateIndents > 0 ? '$lateIndents late' : waiting > 0 ? '$waiting waiting' : 'On track',
              caption: lateIndents > 0
                  ? 'Deliveries past the needed-by date'
                  : waiting > 0
                  ? 'Indents waiting for approval'
                  : 'No material holding up work',
              icon: Icons.inventory_2_outlined,
              accent: lateIndents > 0 ? colors.bad : waiting > 0 ? colors.warn : colors.ok,
              onTap: () => open(ProjectLink(ProjectTab.materials, lateIndents > 0 ? 'late' : waiting > 0 ? 'pending' : null)),
            )),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Team
// ---------------------------------------------------------------------------

class _TeamTab extends ConsumerWidget {
  const _TeamTab({required this.project});

  final Project project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final users = ref.watch(allUsersProvider);
    return ProjectTabPage(
      child: AsyncView(
        value: users,
        data: (people) {
          final byId = {for (final person in people) person.uid: person};
          final members = project.memberIds.map((id) => byId[id]).whereType<AppUser>().toList();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _TabIntro(title: 'Team', subtitle: 'People who currently have access to this project.'),
              const SizedBox(height: 16),
              if (members.isEmpty)
                const _TabEmpty(
                  icon: Icons.people_outline,
                  title: 'No project team assigned',
                  message: 'The office team has not assigned anyone yet.',
                )
              else
                _Panel(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (var n = 0; n < members.length; n++) ...[
                        if (n > 0) const Divider(height: 1),
                        ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.10),
                            foregroundColor: Theme.of(context).colorScheme.primary,
                            child: Text(members[n].initials, style: const TextStyle(fontWeight: FontWeight.w800)),
                          ),
                          title: Text(
                            members[n].name.isEmpty ? members[n].email : members[n].name,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            [members[n].role.label, if (members[n].designation.isNotEmpty) members[n].designation].join(' · '),
                          ),
                          trailing: members[n].uid == project.managerId ? const Pill('Project manager') : null,
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Daily progress
// ---------------------------------------------------------------------------

class _DailyProgressTab extends ConsumerStatefulWidget {
  const _DailyProgressTab({required this.project});

  final Project project;

  @override
  ConsumerState<_DailyProgressTab> createState() => _DailyProgressTabState();
}

class _DailyProgressTabState extends ConsumerState<_DailyProgressTab> {
  String? _selected;

  @override
  Widget build(BuildContext context) {
    final project = widget.project;
    final reports = ref.watch(projectDprsProvider(project.id));
    final insight = ref.watch(projectInsightProvider(project.id)).value;
    final config = ref.watch(appConfigProvider);
    final now = ref.watch(projectClockProvider).value ?? DateTime.now();
    final today = WorkDay.key(now, utcOffsetMinutes: config.company.utcOffsetMinutes);
    final ongoing = config.stageOfStatus(project.statusId) == ProjectStage.ongoing;
    final nav = ProjectNavScope.maybeOf(context);
    final focus = nav?.focusFor(ProjectTab.daily);
    return ProjectTabPage(
      child: AsyncView(
        value: reports,
        data: (items) {
          if (items.isEmpty && !ongoing) {
            return const _TabEmpty(
              icon: Icons.calendar_today_outlined,
              title: 'No daily progress reports',
              message: 'Submitted site reports, quantities, notes and photos will appear here.',
            );
          }
          final shown = _selected == null ? items : items.where((r) => r.date == _selected).toList();
          final missing = insight?.missingReportDates ?? const <String>[];
          final withOutput = items.where((r) => r.achievedPercent != null).take(14).toList().reversed.toList();
          final missingCard = FocusHighlight(
            active: focus == 'missing',
            seq: nav?.seq ?? 0,
            child: ChartCard(
              title: 'Missing reports',
              subtitle: missing.isEmpty
                  ? 'Every working day in the last two weeks has a report'
                  : '${missing.length} working day${missing.length == 1 ? '' : 's'} in the last two weeks · tap a day to check it',
              bodyHeight: 150,
              child: missing.isEmpty
                  ? Row(
                      children: [
                        Icon(Icons.check_circle_outline, color: context.statusColors.ok),
                        const SizedBox(width: 8),
                        const Text('Reporting is up to date.'),
                      ],
                    )
                  : SingleChildScrollView(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final d in missing)
                            ActionChip(
                              avatar: Icon(Icons.event_busy_outlined, size: 16, color: context.statusColors.bad),
                              label: Text(WorkDay.display(d)),
                              onPressed: () => setState(() => _selected = d),
                            ),
                        ],
                      ),
                    ),
            ),
          );
          final outputCard = FocusHighlight(
            active: focus == 'output',
            seq: nav?.seq ?? 0,
            child: ChartCard(
              title: 'Output vs target',
              subtitle: insight?.outputPct == null
                  ? 'Achieved as a share of each day’s target'
                  : 'Last ${withOutput.length} reports · average ${insight!.outputPct!.toStringAsFixed(0)}% of target',
              bodyHeight: 150,
              child: OutputBars(
                days: [for (final r in withOutput) (r.date, r.achievedPercent!)],
                onTap: (d) => setState(() => _selected = d),
              ),
            ),
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _TabIntro(
                title: 'Daily progress',
                subtitle: 'What the site reported each day. Red days on the calendar had no report.',
              ),
              const SizedBox(height: 16),
              if (ongoing) ...[
                ChartGrid(minTileWidth: 380, children: [missingCard, outputCard]),
                const SizedBox(height: 20),
              ],
              LayoutBuilder(
                builder: (context, constraints) {
                  final calendar = DprCalendar(
                    reportDays: {for (final r in items) r.date},
                    today: today,
                    selected: _selected,
                    onSelect: (day) => setState(() => _selected = day),
                    expectFrom: project.startDate,
                    expectReports: ongoing,
                  );
                  final list = Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _SectionLabel(
                              _selected == null ? 'All reports · newest first' : WorkDay.display(_selected),
                            ),
                          ),
                          if (_selected != null)
                            TextButton(
                              onPressed: () => setState(() => _selected = null),
                              child: const Text('Show all'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (shown.isEmpty)
                        _Callout(
                          icon: Icons.event_busy_outlined,
                          color: _selected == null ? _muted : context.statusColors.bad,
                          background: _selected == null ? const Color(0xFFF4F6F9) : context.statusColors.badSoft,
                          text: _selected == null
                              ? 'No reports submitted yet.'
                              : 'No report was submitted for this day. Ask the site supervisor what happened.',
                        )
                      else
                        for (final report in shown)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _DprCard(project: project, report: report),
                          ),
                    ],
                  );
                  if (constraints.maxWidth < 760) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [calendar, const SizedBox(height: 20), list],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 320, child: calendar),
                      const SizedBox(width: 24),
                      Expanded(child: list),
                    ],
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DprCard extends StatelessWidget {
  const _DprCard({required this.project, required this.report});

  final DailyProgressReport report;
  final Project project;

  String _quantity(num? value) => value == null
      ? '—'
      : value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final percent = report.achievedPercent;
    final low = percent != null && percent < 85;
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(WorkDay.display(report.date), style: Theme.of(context).textTheme.titleMedium),
              ),
              if (percent != null)
                Pill(
                  '${percent.toStringAsFixed(0)}% of target',
                  color: low ? context.statusColors.warn : context.statusColors.ok,
                  background: low ? context.statusColors.warnSoft : context.statusColors.okSoft,
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Target ${_quantity(report.targetQuantity)} · achieved ${_quantity(report.achievedQuantity)}${report.unit.isEmpty ? '' : ' ${report.unit}'}',
            style: const TextStyle(color: _muted, fontSize: 13),
          ),
          if (report.flaggedAboveTarget || report.submittedLate) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: [
                if (report.flaggedAboveTarget)
                  Pill('Above target', color: context.statusColors.warn, background: context.statusColors.warnSoft),
                if (report.submittedLate)
                  Pill('Submitted late', color: context.statusColors.warn, background: context.statusColors.warnSoft),
              ],
            ),
          ],
          if (report.notes.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(report.notes),
          ],
          if (report.photoUrls.isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 110,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: report.photoUrls.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, i) => ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(width: 150, child: ProjectPhoto(path: report.photoUrls[i])),
                ),
              ),
            ),
          ],
          ProjectRecordActions(project: project, kind: 'dprs', record: report),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Issues
// ---------------------------------------------------------------------------

enum _IssueFilter {
  open('Open'),
  urgent('High priority'),
  resolved('Resolved'),
  all('All');

  const _IssueFilter(this.label);
  final String label;
}

bool _urgent(ProjectIssue i) => i.priorityId == 'critical' || i.priorityId == 'high';

class _IssuesTab extends ConsumerStatefulWidget {
  const _IssuesTab({required this.project, required this.config});

  final Project project;
  final AppConfig config;

  @override
  ConsumerState<_IssuesTab> createState() => _IssuesTabState();
}

class _IssuesTabState extends ConsumerState<_IssuesTab> {
  var _filter = _IssueFilter.open;
  String? _phaseId;
  int? _applied;

  bool _matches(ProjectIssue i) => (_phaseId == null || i.phaseId == _phaseId) && switch (_filter) {
    _IssueFilter.open => i.isOpen,
    _IssueFilter.urgent => i.isOpen && _urgent(i),
    _IssueFilter.resolved => !i.isOpen,
    _IssueFilter.all => true,
  };

  @override
  Widget build(BuildContext context) {
    final issues = ref.watch(projectIssuesProvider(widget.project.id));
    final nav = ProjectNavScope.maybeOf(context);
    final focus = nav?.focusFor(ProjectTab.issues);
    // Apply a new "investigate" request once; the user can change filter after.
    if (nav != null && nav.seq != _applied) {
      _applied = nav.seq;
      if (focus == 'urgent') _filter = _IssueFilter.urgent;
      if (focus == 'open') _filter = _IssueFilter.open;
      if (focus?.startsWith('issue:') ?? false) _filter = _IssueFilter.all;
      final phase = nav.current.tab == ProjectTab.issues ? nav.current.focusId('phase') : null;
      _phaseId = phase;
      if (phase != null) _filter = _IssueFilter.all;
    }
    final focusId = nav?.current.tab == ProjectTab.issues ? nav!.current.focusId('issue') : null;
    return ProjectTabPage(
      child: AsyncView(
        value: issues,
        data: (items) {
          if (items.isEmpty) {
            return const _TabEmpty(
              icon: Icons.report_problem_outlined,
              title: 'No issues logged',
              message: 'Open and resolved site issues will be listed here.',
            );
          }
          int count(_IssueFilter f) => items.where((i) => switch (f) {
            _IssueFilter.open => i.isOpen,
            _IssueFilter.urgent => i.isOpen && _urgent(i),
            _IssueFilter.resolved => !i.isOpen,
            _IssueFilter.all => true,
          }).length;
          final shown = items.where(_matches).toList()
            ..sort((a, b) => (_urgent(b) ? 1 : 0) - (_urgent(a) ? 1 : 0));
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TabIntro(
                title: 'Issues',
                subtitle: '${count(_IssueFilter.open)} open · ${count(_IssueFilter.urgent)} high priority',
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final f in _IssueFilter.values)
                    ChoiceChip(
                      label: Text('${f.label} · ${count(f)}'),
                      selected: _filter == f,
                      onSelected: (_) => setState(() => _filter = f),
                    ),
                  if (_phaseId != null)
                    InputChip(
                      avatar: const Icon(Icons.view_timeline_outlined, size: 16),
                      label: Text(ref.watch(projectPhasesProvider(widget.project.id)).value?.where((p) => p.id == _phaseId).firstOrNull?.name ?? 'Phase'),
                      onDeleted: () => setState(() => _phaseId = null),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              if (shown.isEmpty)
                _Callout(
                  icon: Icons.check_circle_outline,
                  color: context.statusColors.ok,
                  background: context.statusColors.okSoft,
                  text: 'Nothing here.',
                )
              else
                for (final issue in shown)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: FocusHighlight(
                      active: focusId == issue.id || (focus == 'urgent' && issue.isOpen && _urgent(issue)),
                      seq: nav?.seq ?? 0,
                      child: _IssueCard(project: widget.project, issue: issue, config: widget.config),
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }
}

class _IssueCard extends ConsumerWidget {
  const _IssueCard({required this.project, required this.issue, required this.config});

  final ProjectIssue issue;
  final AppConfig config;
  final Project project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final priority = config.labelOf(ConfigList.issuePriorities, issue.priorityId);
    final urgent = _urgent(issue);
    final color = !issue.isOpen
        ? context.statusColors.ok
        : urgent
        ? context.statusColors.bad
        : context.statusColors.warn;
    final owner = ref.watch(allUsersProvider).value?.where((p) => p.uid == issue.assigneeId).firstOrNull?.name;
    final age = issue.reportedAt == null ? null : DateTime.now().difference(issue.reportedAt!).inDays;
    return _Panel(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(9)),
            child: Icon(issue.isOpen ? Icons.flag_outlined : Icons.check, size: 18, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: Text(issue.title, style: Theme.of(context).textTheme.titleMedium)),
                    const SizedBox(width: 8),
                    Pill(
                      priority,
                      color: urgent ? context.statusColors.bad : null,
                      background: urgent ? context.statusColors.badSoft : null,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    switch (issue.status) {
                      'in-progress' => 'In progress',
                      'resolved' || 'closed' => 'Resolved',
                      _ => 'Open',
                    },
                    if (age != null) age == 0 ? 'raised today' : 'raised $age day${age == 1 ? '' : 's'} ago',
                    'Owner: ${owner ?? 'Unassigned'}',
                  ].join('  ·  '),
                  style: const TextStyle(color: _muted, fontSize: 13),
                ),
                if (issue.description.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(issue.description),
                ],
                ProjectRecordActions(project: project, kind: 'issues', record: issue),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Documents
// ---------------------------------------------------------------------------

class _DocumentsTab extends ConsumerWidget {
  const _DocumentsTab({required this.project, required this.config});

  final Project project;
  final AppConfig config;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final documents = ref.watch(projectDocumentsProvider(project.id));
    final reports = ref.watch(projectDprsProvider(project.id));
    if (documents.isLoading || reports.isLoading) return const LoadingView();
    if (documents.hasError || reports.hasError) {
      return const MessageView(icon: Icons.cloud_off_outlined, title: 'Couldn’t load project media');
    }
    final docs = documents.value ?? const <ProjectDocument>[];
    final photos = (reports.value ?? const <DailyProgressReport>[])
        .expand((report) => report.photoUrls)
        .take(8)
        .toList();
    return ProjectTabPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _TabIntro(title: 'Documents & photos', subtitle: 'Latest site photos and all project documents.'),
          const SizedBox(height: 16),
          if (photos.isNotEmpty) ...[
            const _SectionLabel('Latest site photos'),
            const SizedBox(height: 10),
            SizedBox(
              height: 130,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: photos.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, index) => ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(width: 170, child: ProjectPhoto(path: photos[index])),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
          const _SectionLabel('Project documents'),
          const SizedBox(height: 10),
          if (docs.isEmpty)
            const _Callout(
              icon: Icons.folder_open_outlined,
              color: _muted,
              background: Color(0xFFF4F6F9),
              text: 'No documents have been uploaded yet.',
            )
          else
            _Panel(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var n = 0; n < docs.length; n++) ...[
                    if (n > 0) const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 8, 4),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.description_outlined, color: _muted),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  docs[n].name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                              ),
                              Pill(config.labelOf(ConfigList.documentTypes, docs[n].typeId)),
                              IconButton(
                                tooltip: 'Open document',
                                icon: const Icon(Icons.open_in_new, size: 20),
                                onPressed: () async {
                                  try {
                                    await ProjectMedia.open(docs[n].storagePath ?? docs[n].url ?? '');
                                  } catch (e) {
                                    if (context.mounted) showMessage(context, '$e', error: true);
                                  }
                                },
                              ),
                            ],
                          ),
                          ProjectRecordActions(project: project, kind: 'documents', record: docs[n]),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Info: details, status history and hold periods
// ---------------------------------------------------------------------------

class _InfoTab extends ConsumerWidget {
  const _InfoTab({required this.project, required this.config});

  final Project project;
  final AppConfig config;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nav = ProjectNavScope.maybeOf(context);
    final people = ref.watch(allUsersProvider).value ?? const <AppUser>[];
    String who(String uid) => people.where((p) => p.uid == uid).firstOrNull?.name ?? 'Someone';
    final fields = config.fieldsFor(FieldEntity.project).where((field) => !field.archived).toList();
    final info = <(String, String)>[
      ('Client', project.clientName),
      ('Project code', project.code),
      ('Project type', config.labelOf(ConfigList.projectTypes, project.typeId)),
      ('Address', project.address),
      ('City', project.city),
      ('Start date', WorkDay.display(project.startDate)),
      ('Target completion', WorkDay.display(project.endDate)),
      ('Contract value', project.contractValuePaise == 0 ? '—' : Money.format(project.contractValuePaise)),
    ];
    final today = WorkDay.tryParse(WorkDay.today(utcOffsetMinutes: config.company.utcOffsetMinutes))!;
    return ProjectTabPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _TabIntro(title: 'Project information', subtitle: 'Core details, status history and hold periods.'),
          const SizedBox(height: 16),
          _InfoGroup(items: info.where((item) => item.$2.isNotEmpty && item.$2 != '—').toList()),
          if (fields.isNotEmpty) ...[
            const SizedBox(height: 24),
            const _SectionLabel('Additional details'),
            const SizedBox(height: 10),
            _InfoGroup(
              items: [for (final field in fields) (field.label, FieldValues.display(field, project.custom[field.id]))],
            ),
          ],
          const SizedBox(height: 24),
          FocusHighlight(
            active: nav?.focusFor(ProjectTab.info) == 'holds',
            seq: nav?.seq ?? 0,
            child: _Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _SectionLabel('Hold periods'),
                  const SizedBox(height: 4),
                  const Text(
                    'Time on hold pauses the planned schedule and moves the finish date out.',
                    style: TextStyle(color: _muted, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  if (project.holdPeriods.isEmpty)
                    const Text('This project has never been on hold.')
                  else
                    for (final h in project.holdPeriods)
                      Builder(
                        builder: (context) {
                          final start = WorkDay.tryParse(h['start'] as String?);
                          final end = WorkDay.tryParse(h['end'] as String?);
                          final days = start == null ? null : (end ?? today).difference(start).inDays;
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              Icons.pause_circle_outline,
                              color: end == null ? context.statusColors.bad : _muted,
                            ),
                            title: Text(
                              '${WorkDay.display(h['start'] as String?)} – ${end == null ? 'still on hold' : WorkDay.display(h['end'] as String?)}',
                            ),
                            trailing: days == null
                                ? null
                                : Text('$days day${days == 1 ? '' : 's'}', style: const TextStyle(fontWeight: FontWeight.w800)),
                          );
                        },
                      ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _SectionLabel('Status history'),
                const SizedBox(height: 8),
                if (project.statusHistory.isEmpty)
                  const Text('No status changes recorded.')
                else
                  for (final change in project.statusHistory.reversed)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.swap_horiz, color: _muted),
                      title: Text(config.labelOf(ConfigList.projectStatuses, change.statusId)),
                      subtitle: Text(
                        [
                          if (change.at != null) WorkDay.display(WorkDay.fromDate(change.at!)),
                          who(change.by),
                          if (change.note.isNotEmpty) change.note,
                        ].join(' · '),
                      ),
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoGroup extends StatelessWidget {
  const _InfoGroup({required this.items});

  final List<(String, String)> items;

  @override
  Widget build(BuildContext context) => _Panel(
    padding: EdgeInsets.zero,
    child: Column(
      children: [
        for (var index = 0; index < items.length; index++) ...[
          if (index > 0) const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 160,
                  child: Text(items[index].$1, style: const TextStyle(color: _muted, fontSize: 13)),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(items[index].$2, style: const TextStyle(fontWeight: FontWeight.w600))),
              ],
            ),
          ),
        ],
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// Shared bits
// ---------------------------------------------------------------------------

/// The standard white, bordered, rounded surface used by every tab.
class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.padding = const EdgeInsets.all(16)});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: AppRadius.card,
      border: Border.all(color: AppColors.line),
    ),
    child: child,
  );
}

class _Callout extends StatelessWidget {
  const _Callout({required this.icon, required this.color, required this.background, required this.text});

  final IconData icon;
  final Color color;
  final Color background;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(10)),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: const TextStyle(color: Color(0xFF354657)))),
      ],
    ),
  );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800));
}

class _TabIntro extends StatelessWidget {
  const _TabIntro({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 4),
      Text(subtitle, style: const TextStyle(color: _muted)),
    ],
  );
}

class _TabEmpty extends StatelessWidget {
  const _TabEmpty({required this.icon, required this.title, required this.message});

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 72),
    child: MessageView(icon: icon, title: title, message: message),
  );
}
