import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_config.dart';
import '../../../core/config/config_models.dart';
import '../../../core/config/config_repository.dart';
import '../../../core/dynamic_form/field_values.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/brand_mark.dart';
import '../../../core/widgets/common.dart';
import '../../auth/data/session.dart';
import '../../auth/domain/app_user.dart';
import '../../finance/data/finance_repository.dart';
import '../../inventory/data/inventory_repository.dart';
import '../../users/data/user_repository.dart';
import '../data/project_insight_provider.dart';
import '../data/project_repository.dart';
import '../domain/project.dart';
import '../domain/project_insight.dart';
import '../domain/project_nav.dart';
import 'ceo_ui.dart';
import 'insight_charts.dart';
import 'insight_widgets.dart';
import 'project_plain.dart';
import 'project_record_actions.dart';

/// The CEO landing page: the whole portfolio's schedule and money at a glance,
/// then every live project in one tracker, before any project detail.
class CeoPortfolioScreen extends ConsumerWidget {
  const CeoPortfolioScreen({super.key, this.sort});

  /// Initial sort, from `/home?sort=<name>` (e.g. overrun, payables, speed).
  final String? sort;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final portfolio = ref.watch(portfolioInsightProvider);
    final company = ref.watch(appConfigProvider).company.name;
    // Wide screens show the brand in the sidebar; phones show it here.
    final phone = MediaQuery.sizeOf(context).width < 900;
    return PageScaffold(
      title: phone ? company : '',
      titleWidget: phone ? BrandLockup(name: company, size: 30) : null,
      maxWidth: 1240,
      body: AsyncView(
        value: portfolio,
        data: (p) => _PortfolioBody(
          portfolio: p,
          initialSort: _HomeSort.values.where((s) => s.name == sort).firstOrNull,
          config: ref.watch(appConfigProvider),
          firstName: user.name.split(' ').first,
        ),
      ),
    );
  }
}

/// Schedule buckets for the portfolio donut. Status colours, always labelled.
enum _Bucket { onSchedule, slipping, delayed, onHold, notReady }

_Bucket _bucketOf(ProjectInsight i) {
  if (i.stage == ProjectStage.onHold) return _Bucket.onHold;
  if (!i.scheduleReady) return _Bucket.notReady;
  return switch (i.analysis.health) {
    ProjectHealth.red => _Bucket.delayed,
    ProjectHealth.amber => _Bucket.slipping,
    _ => _Bucket.onSchedule,
  };
}

/// Home, top to bottom: what needs the CEO, the people who run the company,
/// then the projects themselves (filter, sort, search), then portfolio charts
/// and the delay watchlist.
class _PortfolioBody extends ConsumerStatefulWidget {
  const _PortfolioBody({
    required this.portfolio,
    required this.config,
    required this.firstName,
    this.initialSort,
  });

  final _HomeSort? initialSort;
  final PortfolioInsight portfolio;
  final AppConfig config;
  final String firstName;

  @override
  ConsumerState<_PortfolioBody> createState() => _PortfolioBodyState();
}

enum _StageFilter {
  all('All', null),
  ongoing('Ongoing', ProjectStage.ongoing),
  pipeline('Pipeline', ProjectStage.pipeline),
  onHold('On hold', ProjectStage.onHold),
  completed('Completed', ProjectStage.completed);

  const _StageFilter(this.label, this.stage);
  final String label;
  final ProjectStage? stage;
}

enum _HomeSort {
  attention('Needs attention first'),
  overrun('Cost overrun'),
  payables('Payables'),
  speed('Slowest first'),
  finish('Finish date'),
  progress('Progress'),
  value('Contract value'),
  name('Name');

  const _HomeSort(this.label);
  final String label;
}

class _PortfolioBodyState extends ConsumerState<_PortfolioBody> {
  var _stage = _StageFilter.all;
  late var _sort = widget.initialSort ?? _HomeSort.attention;
  var _query = '';
  String? _managerId;

  List<ProjectInsight> _filtered(List<ProjectInsight> all) {
    final q = _query.trim().toLowerCase();
    final list = all.where((i) {
      if (_stage.stage != null && i.stage != _stage.stage) return false;
      if (_managerId != null && i.project.managerId != _managerId) return false;
      if (q.isEmpty) return true;
      final p = i.project;
      return '${p.name} ${p.code} ${p.clientName} ${p.city}'.toLowerCase().contains(q);
    }).toList();
    int byName(ProjectInsight a, ProjectInsight b) =>
        a.project.name.toLowerCase().compareTo(b.project.name.toLowerCase());
    list.sort((a, b) {
      final c = switch (_sort) {
        _HomeSort.attention => (() {
          final h = healthRank(a.analysis.health).compareTo(healthRank(b.analysis.health));
          return h != 0 ? h : b.factors.length.compareTo(a.factors.length);
        })(),
        _HomeSort.overrun => b.costOverrunPaise.compareTo(a.costOverrunPaise),
        _HomeSort.payables => b.payablesPaise.compareTo(a.payablesPaise),
        _HomeSort.speed => (a.paceRatio ?? 99).compareTo(b.paceRatio ?? 99),
        _HomeSort.finish => (a.forecastFinish ?? DateTime(9999)).compareTo(b.forecastFinish ?? DateTime(9999)),
        _HomeSort.progress => b.analysis.actual.compareTo(a.analysis.actual),
        _HomeSort.value => b.project.contractValuePaise.compareTo(a.project.contractValuePaise),
        _HomeSort.name => 0,
      };
      return c != 0 ? c : byName(a, b);
    });
    return list;
  }

  bool get _filtering => _stage != _StageFilter.all || _managerId != null || _sort != _HomeSort.attention || _query.trim().isNotEmpty;

  void _clearFilters() {
    _stage = _StageFilter.all;
    _managerId = null;
    _sort = _HomeSort.attention;
  }

  /// Stage, manager and sort in one sheet, so the home page itself stays a
  /// plain list of projects.
  Future<void> _showFilters(List<AppUser> managers, int Function(_StageFilter) countFor) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheet) => StatefulBuilder(
      builder: (sheet, setSheet) {
        void update(VoidCallback f) {
          setState(f);
          setSheet(() {});
        }

        Widget label(String t) => Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 8),
          child: Text(t, style: const TextStyle(fontWeight: FontWeight.w800)),
        );
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text('Filter and sort', style: Theme.of(sheet).textTheme.titleMedium),
                    const Spacer(),
                    TextButton(onPressed: () => update(_clearFilters), child: const Text('Reset')),
                  ],
                ),
                label('Stage'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final f in _StageFilter.values)
                      ChoiceChip(
                        label: Text('${f.label} · ${countFor(f)}'),
                        selected: _stage == f,
                        onSelected: (_) => update(() => _stage = f),
                      ),
                  ],
                ),
                if (managers.isNotEmpty) ...[
                  label('Project manager'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('Everyone'),
                        selected: _managerId == null,
                        onSelected: (_) => update(() => _managerId = null),
                      ),
                      for (final m in managers)
                        ChoiceChip(
                          label: Text(m.name),
                          selected: _managerId == m.uid,
                          onSelected: (_) => update(() => _managerId = m.uid),
                        ),
                    ],
                  ),
                ],
                label('Sort by'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final s in _HomeSort.values)
                      ChoiceChip(label: Text(s.label), selected: _sort == s, onSelected: (_) => update(() => _sort = s)),
                  ],
                ),
                const SizedBox(height: 20),
                FilledButton(onPressed: () => Navigator.pop(sheet), child: const Text('Show projects')),
              ],
            ),
          ),
        );
      },
    ),
  );

  @override
  Widget build(BuildContext context) {
    final portfolio = widget.portfolio;
    final all = portfolio.projects;
    final user = ref.watch(currentUserProvider);
    final users = ref.watch(allUsersProvider).value ?? const <AppUser>[];
    final managers = users.where((u) => u.active && u.role == UserRole.manager).toList();
    int countFor(_StageFilter f) => all
        .where((i) => (f.stage == null || i.stage == f.stage) && (_managerId == null || i.project.managerId == _managerId))
        .length;
    final shown = _filtered(all);
    final plains = {for (final i in all) i.project.id: PlainProject(i, seeMoney: canSeeMoney(user, i.project, i.stage))};
    PlainProject plain(ProjectInsight i) => plains[i.project.id]!;

    Widget grid(List<ProjectInsight> list) => LayoutBuilder(
      builder: (context, c) {
        final columns = c.maxWidth >= 1000 ? 3 : c.maxWidth >= 640 ? 2 : 1;
        final width = (c.maxWidth - (columns - 1) * 16) / columns;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            for (final i in list)
              SizedBox(
                width: width,
                child: _ProjectTile(
                  plain: plain(i),
                  statusLabel: widget.config.labelOf(ConfigList.projectStatuses, i.project.statusId),
                  manager: users.where((u) => u.uid == i.project.managerId).firstOrNull?.name,
                ),
              ),
          ],
        );
      },
    );

    // Unfiltered: projects grouped by what the chairman should do about them.
    Widget groups() {
      final running = shown.where((i) => i.stage == ProjectStage.ongoing).toList();
      final attention = running.where((i) => plain(i).tone == Tone.bad || plain(i).tone == Tone.warn).toList();
      mergeSort(attention, compare: (a, b) => (plain(a).tone == Tone.bad ? 0 : 1).compareTo(plain(b).tone == Tone.bad ? 0 : 1));
      final fine = running.where((i) => plain(i).tone == Tone.ok).toList();
      final paused = shown.where((i) => i.stage == ProjectStage.onHold || i.stage == ProjectStage.pipeline).toList();
      final done = shown.where((i) => i.stage == ProjectStage.completed || i.stage == ProjectStage.cancelled).toList();
      Widget section(String title, String note, List<ProjectInsight> list, {Color? dot}) => Padding(
        padding: const EdgeInsets.only(bottom: 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (dot != null) ...[
                  Container(width: 10, height: 10, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 8),
                Text('${list.length}', style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 2),
            Text(note, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
            const SizedBox(height: 12),
            grid(list),
          ],
        ),
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (attention.isNotEmpty)
            section('Needs your attention', 'Late, over budget, or with a serious problem. Tap one to see why.', attention,
                dot: context.statusColors.bad),
          if (fine.isNotEmpty)
            section('On track', 'On time and within budget. Nothing needs you here.', fine, dot: context.statusColors.ok),
          if (paused.isNotEmpty) section('On hold and not started', 'Not being built right now.', paused),
          if (done.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _stage = _StageFilter.completed),
                icon: const Icon(Icons.inventory_outlined, size: 18),
                label: Text('Show ${done.length} finished project${done.length == 1 ? '' : 's'}'),
              ),
            ),
        ],
      );
    }

    final filters = [
      if (_stage != _StageFilter.all) _stage.label,
      if (_managerId != null) managers.where((m) => m.uid == _managerId).firstOrNull?.name ?? 'Manager',
      if (_sort != _HomeSort.attention) _sort.label,
    ];
    final leader = user.isCeo || user.isAdmin;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (leader) ...[
          _LeaderBrief(portfolio: portfolio, firstName: widget.firstName),
          const SizedBox(height: 32),
        ],
        Text('Projects', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 2),
        Text(
          '${portfolio.active.length} live · ${all.where((i) => i.stage == ProjectStage.pipeline).length} not started',
          style: const TextStyle(color: AppColors.muted),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: SizedBox(
                    height: 42,
                    child: TextField(
                      onChanged: (v) => setState(() => _query = v),
                      decoration: const InputDecoration(
                        isDense: true,
                        prefixIcon: Icon(Icons.search, size: 20),
                        hintText: 'Find a project, client or city',
                        contentPadding: EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Badge(
              isLabelVisible: filters.isNotEmpty,
              label: Text('${filters.length}'),
              child: OutlinedButton.icon(
                onPressed: () => _showFilters(managers, countFor),
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 42)),
                icon: const Icon(Icons.tune, size: 18),
                label: const Text('Filter'),
              ),
            ),
          ],
        ),
        if (filters.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final f in filters) Chip(label: Text(f), visualDensity: VisualDensity.compact),
              TextButton(onPressed: () => setState(_clearFilters), child: const Text('Clear')),
            ],
          ),
        ],
        const SizedBox(height: 22),
        if (all.isEmpty)
          const _EmptyPortfolio()
        else if (shown.isEmpty)
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(borderRadius: AppRadius.card, border: Border.all(color: AppColors.line)),
            child: const Column(
              children: [
                Icon(Icons.search_off, color: AppColors.muted, size: 32),
                SizedBox(height: 8),
                Text('No projects match. Clear the search or the filters.', style: TextStyle(color: AppColors.muted)),
              ],
            ),
          )
        else if (_filtering)
          grid(shown)
        else
          groups(),
        const SizedBox(height: 48),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Sidebar pages: Insights, Delay watchlist, Organisation
// ---------------------------------------------------------------------------

/// Portfolio → Insights: the three pillars and the charts.
class PortfolioInsightsScreen extends ConsumerWidget {
  const PortfolioInsightsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => PageScaffold(
    title: 'Insights',
    maxWidth: 1240,
    body: AsyncView(
      value: ref.watch(portfolioInsightProvider),
      data: (p) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Cost overrun, payables and speed across every live project. Tap a number to see the projects behind it.',
            style: TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 16),
          _Pillars(
            portfolio: p,
            // Only the CEO's home is the portfolio; managers have it at /portfolio.
            onPick: (sort) => context.go(
              '${ref.read(currentUserProvider).isCeo ? '/home' : '/portfolio'}?sort=${sort.name}',
            ),
          ),
          const SizedBox(height: 24),
          if (p.active.isEmpty)
            const _EmptyPortfolio()
          else
            _PortfolioCharts(portfolio: p, active: p.active.toList()),
          const SizedBox(height: 48),
        ],
      ),
    ),
  );
}

/// Portfolio → Delay watchlist: every factor across projects, each a link.
class DelayWatchlistScreen extends ConsumerWidget {
  const DelayWatchlistScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => PageScaffold(
    title: 'Delay watchlist',
    maxWidth: 1100,
    body: AsyncView(
      value: ref.watch(portfolioInsightProvider),
      data: (p) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Everything slowing a project down or pushing its cost up. Open any item to go straight to it.',
            style: TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 16),
          _Watchlist(projects: p.active.toList(), showAllByDefault: true),
          const SizedBox(height: 48),
        ],
      ),
    ),
  );
}

/// Portfolio → Organisation: who runs the company and how their projects are doing.
class OrganisationScreen extends ConsumerWidget {
  const OrganisationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final users = ref.watch(allUsersProvider).value ?? const <AppUser>[];
    return PageScaffold(
      title: 'Organisation',
      maxWidth: 1240,
      body: AsyncView(
        value: ref.watch(portfolioInsightProvider),
        data: (p) {
          final people = users.where((u) => u.active).toList();
          List<AppUser> of(UserRole r) => people.where((u) => u.role == r).toList();
          int projectsOf(AppUser u) => p.projects.where((i) => i.project.memberIds.contains(u.uid)).length;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _OrgHeads(portfolio: p, users: users, selected: null, onSelect: (_) {}),
              const SizedBox(height: 28),
              for (final (role, title) in [
                (UserRole.ceo, 'Leadership'),
                (UserRole.manager, 'Project managers'),
                (UserRole.supervisor, 'Site supervisors'),
                (UserRole.staff, 'Staff'),
                (UserRole.admin, 'Office'),
              ])
                if (of(role).isNotEmpty) ...[
                  Text('$title · ${of(role).length}', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 10),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: AppRadius.card,
                      border: Border.all(color: AppColors.line),
                    ),
                    child: Column(
                      children: [
                        for (var n = 0; n < of(role).length; n++) ...[
                          if (n > 0) const Divider(height: 1),
                          ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.10),
                              foregroundColor: Theme.of(context).colorScheme.primary,
                              child: Text(of(role)[n].initials, style: const TextStyle(fontWeight: FontWeight.w800)),
                            ),
                            title: Text(of(role)[n].name, style: const TextStyle(fontWeight: FontWeight.w700)),
                            subtitle: Text(
                              [
                                if (of(role)[n].designation.isNotEmpty) of(role)[n].designation,
                                of(role)[n].email,
                                if (of(role)[n].phone.isNotEmpty) of(role)[n].phone,
                              ].join(' · '),
                            ),
                            trailing: role == UserRole.ceo || role == UserRole.admin
                                ? null
                                : Text(
                                    '${projectsOf(of(role)[n])} project${projectsOf(of(role)[n]) == 1 ? '' : 's'}',
                                    style: const TextStyle(fontWeight: FontWeight.w700),
                                  ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }
}

/// The people who run the company: office heads and project managers, each
/// with how their projects are doing. Tapping a manager filters the projects.
class _OrgHeads extends StatelessWidget {
  const _OrgHeads({
    required this.portfolio,
    required this.users,
    required this.selected,
    required this.onSelect,
  });

  final PortfolioInsight portfolio;
  final List<AppUser> users;
  final String? selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final people = users.where((u) => u.active).toList();
    int count(UserRole r) => people.where((u) => u.role == r).length;
    final heads = [
      ...people.where((u) => u.role == UserRole.admin),
      ...people.where((u) => u.role == UserRole.manager),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Organisation', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(
          [
            '${people.length} people',
            if (count(UserRole.admin) > 0) '${count(UserRole.admin)} office',
            '${count(UserRole.manager)} project manager${count(UserRole.manager) == 1 ? '' : 's'}',
            '${count(UserRole.supervisor)} supervisor${count(UserRole.supervisor) == 1 ? '' : 's'}',
            if (count(UserRole.staff) > 0) '${count(UserRole.staff)} staff',
          ].join(' · '),
          style: const TextStyle(color: AppColors.muted),
        ),
        const SizedBox(height: 12),
        if (heads.isEmpty)
          const Text('No managers added yet. The office adds them under Users.', style: TextStyle(color: AppColors.muted))
        else
          SizedBox(
            height: 132,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: heads.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, n) => SizedBox(
                width: 250,
                child: _HeadCard(
                  person: heads[n],
                  projects: portfolio.projects.where((i) => i.project.managerId == heads[n].uid).toList(),
                  selected: selected == heads[n].uid,
                  onTap: heads[n].role == UserRole.manager ? () => onSelect(heads[n].uid) : null,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _HeadCard extends StatelessWidget {
  const _HeadCard({
    required this.person,
    required this.projects,
    required this.selected,
    required this.onTap,
  });

  final AppUser person;
  final List<ProjectInsight> projects;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final live = projects.where((i) => i.active).toList();
    final late = live.where((i) => i.finishSlipDays > 0 || i.analysis.health == ProjectHealth.red).length;
    final isManager = person.role == UserRole.manager;
    final avg = live.where((i) => i.scheduleReady).toList();
    final progress = avg.isEmpty ? null : avg.fold(0.0, (s, i) => s + i.analysis.actual) / avg.length;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        borderRadius: AppRadius.card,
        border: Border.all(color: selected ? primary : AppColors.line, width: selected ? 1.5 : 1),
        color: selected ? primary.withValues(alpha: 0.04) : Theme.of(context).colorScheme.surface,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.card,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: primary.withValues(alpha: 0.10),
                      foregroundColor: primary,
                      child: Text(person.initials, style: const TextStyle(fontWeight: FontWeight.w800)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            person.name.isEmpty ? person.email : person.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          Text(
                            person.designation.isNotEmpty ? person.designation : person.role.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, color: AppColors.muted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                if (isManager) ...[
                  Row(
                    children: [
                      Text(
                        '${live.length} live project${live.length == 1 ? '' : 's'}',
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                      ),
                      const Spacer(),
                      if (late > 0)
                        Text(
                          '$late running late',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: context.statusColors.bad),
                        )
                      else if (live.isNotEmpty)
                        Text(
                          'All on track',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: context.statusColors.ok),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      minHeight: 6,
                      value: (progress ?? 0) / 100,
                      valueColor: AlwaysStoppedAnimation(late > 0 ? context.statusColors.warn : primary),
                    ),
                  ),
                ] else
                  Text(
                    person.role == UserRole.admin ? 'Office · users, settings and approvals' : person.role.label,
                    style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One project on the home screen, in plain words: how far it is, whether it
/// is on time, whether the money is fine, and the main problem (a link).
class _ProjectTile extends StatelessWidget {
  const _ProjectTile({required this.plain, required this.statusLabel, required this.manager});

  final PlainProject plain;
  final String statusLabel;
  final String? manager;

  @override
  Widget build(BuildContext context) {
    final i = plain.insight;
    final p = i.project;
    final a = i.analysis;
    final color = toneColor(context, plain.tone == Tone.none ? Tone.ok : plain.tone);
    final problem = plain.mainProblem;
    final measured = plain.running && i.scheduleReady;

    return HoverCard(
      onTap: () => context.push('/projects/${p.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ProjectAvatar(
                name: p.name,
                color: plain.tone == Tone.none ? Theme.of(context).colorScheme.primary : toneColor(context, plain.tone),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      [if (p.city.isNotEmpty) p.city, ?manager].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (plain.tone == Tone.none) Pill(statusLabel) else VerdictPill(plain: plain),
              if (plain.problemCount > 0 && plain.running) ...[
                const SizedBox(width: 8),
                Text(
                  '${plain.problemCount} thing${plain.problemCount == 1 ? '' : 's'} to look at',
                  style: const TextStyle(fontSize: 12, color: AppColors.muted, fontWeight: FontWeight.w600),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          if (measured) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${a.actual.toStringAsFixed(0)}%',
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, height: 1),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    plain.progress.replaceFirst(RegExp(r'^\d+% built · '), 'built · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ProgressMeter(actual: a.actual, planned: a.planned, color: color),
            const SizedBox(height: 10),
          ],
          if (i.stage == ProjectStage.pipeline)
            Text(
              [
                if (p.contractValuePaise > 0) 'Contract ${Money.compact(p.contractValuePaise)}',
                'starts ${displayDateKey(p.startDate)}',
              ].join(' · '),
              style: const TextStyle(fontSize: 13, color: AppColors.ink),
            )
          else if (i.active)
            for (final line in plain.lines) PlainLineRow(line: line, dense: true)
          else
            Text('$statusLabel · ${displayDateKey(p.endDate)}', style: const TextStyle(fontSize: 13, color: AppColors.muted)),
          if (i.active && problem != null) ...[
            const SizedBox(height: 10),
            Material(
              color: problem.severe ? context.statusColors.badSoft : context.statusColors.warnSoft,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                onTap: () => context.push(problem.link.path(p.id)),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Row(
                    children: [
                      Icon(
                        factorIcon(problem.kind),
                        size: 16,
                        color: problem.severe ? context.statusColors.bad : context.statusColors.warn,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          problem.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.ink),
                        ),
                      ),
                      if (plain.problemCount > 1)
                        Text('+${plain.problemCount - 1} more', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                    ],
                  ),
                ),
              ),
            ),
          ] else if (plain.running) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.check_circle_outline, size: 16, color: context.statusColors.ok),
                const SizedBox(width: 6),
                const Text('No problems flagged', style: TextStyle(fontSize: 12.5, color: AppColors.muted)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}


/// The three numbers the CEO runs the company on, across all live projects.
/// Tapping one sorts the project list by it.
class _Pillars extends StatelessWidget {
  const _Pillars({required this.portfolio, required this.onPick});

  final PortfolioInsight portfolio;
  final ValueChanged<_HomeSort> onPick;

  @override
  Widget build(BuildContext context) {
    final p = portfolio;
    final colors = context.statusColors;
    return LayoutBuilder(
      builder: (context, c) {
        final columns = c.maxWidth >= 760 ? 3 : 1;
        final width = (c.maxWidth - (columns - 1) * 14) / columns;
        return Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            SizedBox(
              width: width,
              child: NeoMetricCard(
                label: 'Cost overrun',
                value: p.budgetPaise == 0 ? 'No budgets' : Money.compact(p.costOverrunPaise),
                caption: p.overrunCount == 0
                    ? 'No project is spending beyond its work done'
                    : '${p.overrunCount} project${p.overrunCount == 1 ? '' : 's'} spending beyond work done',
                icon: Icons.trending_up,
                accent: p.overrunCount > 0 ? colors.bad : colors.ok,
                onTap: () => onPick(_HomeSort.overrun),
              ),
            ),
            SizedBox(
              width: width,
              child: NeoMetricCard(
                label: 'Payables',
                value: Money.compact(p.payablesPaise),
                caption: p.overduePayablesCount == 0
                    ? 'Nothing unpaid past ${ProjectInsight.payableDueDays} days'
                    : '${Money.compact(p.overduePayablesPaise)} overdue · ${p.overduePayablesCount} bill${p.overduePayablesCount == 1 ? '' : 's'}',
                icon: Icons.receipt_long_outlined,
                accent: p.overduePayablesCount > 0 ? colors.bad : const Color(0xFF6C4BA5),
                onTap: () => onPick(_HomeSort.payables),
              ),
            ),
            SizedBox(
              width: width,
              child: NeoMetricCard(
                label: 'Speed',
                value: p.tooSlowCount == 0 ? 'On pace' : '${p.tooSlowCount} too slow',
                caption: p.tooSlowCount == 0
                    ? 'Every live project is moving fast enough to finish on time'
                    : 'Moving slower than needed to finish on time',
                icon: Icons.speed,
                accent: p.tooSlowCount > 0 ? colors.warn : colors.ok,
                onTap: () => onPick(_HomeSort.speed),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PortfolioCharts extends StatelessWidget {
  const _PortfolioCharts({required this.portfolio, required this.active});

  final PortfolioInsight portfolio;
  final List<ProjectInsight> active;

  @override
  Widget build(BuildContext context) {
    final counts = <_Bucket, int>{};
    for (final i in active) {
      counts.update(_bucketOf(i), (v) => v + 1, ifAbsent: () => 1);
    }
    final colors = context.statusColors;
    final slices = [
      DonutSlice('On schedule', (counts[_Bucket.onSchedule] ?? 0).toDouble(), colors.ok),
      DonutSlice('Slipping', (counts[_Bucket.slipping] ?? 0).toDouble(), colors.warn),
      DonutSlice('Delayed', (counts[_Bucket.delayed] ?? 0).toDouble(), colors.bad),
      DonutSlice('On hold', (counts[_Bucket.onHold] ?? 0).toDouble(), ChartColors.hold),
      DonutSlice('Schedule not set', (counts[_Bucket.notReady] ?? 0).toDouble(), ChartColors.noData),
    ].where((s) => s.value > 0).toList();
    final tracked = active.where((i) => i.scheduleReady).toList();
    final budgeted = [...active]..sort((a, b) => b.budgetPaise.compareTo(a.budgetPaise));
    final totalSlip = tracked.fold(0, (s, i) => s + i.finishSlipDays);

    return ChartGrid(
      minTileWidth: 340,
      children: [
        ChartCard(
          title: 'Schedule health',
          subtitle: totalSlip == 0
              ? 'All tracked projects on time'
              : '${portfolio.delayed} project${portfolio.delayed == 1 ? '' : 's'} late · $totalSlip days of slip in total',
          child: DonutChart(
            centerValue: '${active.length}',
            centerLabel: 'live projects',
            slices: slices,
          ),
        ),
        ChartCard(
          title: 'Progress vs plan',
          subtitle: 'Where each project should be today, and where it is',
          child: PlanActualBars(
            items: [
              for (final i in tracked)
                PlanActualItem(
                  i.project.code.isNotEmpty ? i.project.code : i.project.name,
                  i.analysis.planned,
                  i.analysis.actual,
                  actualColor: i.analysis.health == ProjectHealth.red
                      ? colors.bad
                      : i.analysis.health == ProjectHealth.amber
                      ? colors.warn
                      : null,
                ),
            ],
          ),
        ),
        ChartCard(
          title: 'Budget by project',
          subtitle: portfolio.budgetPaise == 0
              ? 'No budgets set yet'
              : '${Money.compact(portfolio.spentPaise)} spent · ${Money.compact(portfolio.pendingPaise)} awaiting approval · ${Money.compact(portfolio.remainingPaise)} left',
          child: BudgetRowsChart(
            rows: [
              for (final i in budgeted)
                BudgetRow(
                  i.project.name,
                  i.budgetPaise,
                  i.spentPaise,
                  i.pendingPaise,
                  onTap: () => context.push('/projects/${i.project.id}'),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EmptyPortfolio extends StatelessWidget {
  const _EmptyPortfolio();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(32),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: AppRadius.card,
      border: Border.all(color: AppColors.line),
    ),
    child: Column(
      children: [
        const Icon(Icons.domain_add_outlined, size: 42, color: AppColors.muted),
        const SizedBox(height: 12),
        Text(
          'No live projects yet',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 5),
        const Text(
          'Projects appear here once they are ongoing. An admin can load demo data from Settings to try the dashboard.',
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );
}

/// A searchable drill-down list. Filters use the company's own statuses and
/// custom fields, rather than imposing a second CRM taxonomy on the business.
class ProjectListScreen extends ConsumerStatefulWidget {
  const ProjectListScreen({super.key, this.stage, this.initialAtRisk = false});

  final ProjectStage? stage;
  final bool initialAtRisk;

  @override
  ConsumerState<ProjectListScreen> createState() => _ProjectListScreenState();
}

class _ProjectListScreenState extends ConsumerState<ProjectListScreen> {
  final _search = TextEditingController();
  String _query = '';
  String? _managerId;
  String? _city;
  String? _statusId;
  late ProjectStage? _stage;
  late _ProjectFeedHealth? _health;
  _ProjectFeedSort _sort = _ProjectFeedSort.attention;

  @override
  void initState() {
    super.initState();
    _stage = widget.stage;
    _health = widget.initialAtRisk ? _ProjectFeedHealth.attention : null;
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ProjectListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stage != widget.stage ||
        oldWidget.initialAtRisk != widget.initialAtRisk) {
      _stage = widget.stage;
      _health = widget.initialAtRisk ? _ProjectFeedHealth.attention : null;
      _statusId = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(appConfigProvider);
    final projects = ref.watch(visibleProjectsProvider);
    final users = ref.watch(allUsersProvider).value ?? const <AppUser>[];
    final canCreate = ref.watch(currentUserProvider).role == UserRole.admin;
    final title = _stage?.label ?? 'Projects';
    return PageScaffold(
      title: title,
      maxWidth: 1180,
      actions: canCreate
          ? [
              IconButton(
                tooltip: 'Create project',
                onPressed: () => context.go('/projects/new'),
                icon: const Icon(Icons.add),
              ),
            ]
          : null,
      body: AsyncView(
        value: projects,
        data: (all) {
          final stages = ProjectStage.values
              .where(
                (stage) => config
                    .activeOf(ConfigList.projectStatuses)
                    .any((status) => status.stage == stage),
              )
              .toList();
          final statuses = config
              .activeOf(ConfigList.projectStatuses)
              .where((status) => _stage == null || status.stage == _stage)
              .toList();
          final selectedStatusId =
              statuses.any((status) => status.id == _statusId)
              ? _statusId
              : null;
          final result = _filtered(all, config, selectedStatusId);
          final cities =
              all
                  .map((p) => p.city)
                  .where((city) => city.isNotEmpty)
                  .toSet()
                  .toList()
                ..sort();
          final managers = users
              .where((u) => u.role == UserRole.manager && u.active)
              .toList();
          final hasFilters =
              _query.isNotEmpty ||
              _stage != null ||
              selectedStatusId != null ||
              _health != null ||
              _managerId != null ||
              _city != null ||
              _sort != _ProjectFeedSort.attention;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _stage == null ? 'Find a project' : '${_stage!.label} projects',
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 5),
              Text(
                '${result.length} matching project${result.length == 1 ? '' : 's'}',
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: AppColors.muted),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _search,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search by project, code, client or city',
                ),
                onChanged: (value) =>
                    setState(() => _query = value.trim().toLowerCase()),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('All stages'),
                    selected: _stage == null,
                    onSelected: (_) => _selectStage(null),
                  ),
                  for (final stage in stages)
                    ChoiceChip(
                      label: Text(stage.label),
                      selected: _stage == stage,
                      onSelected: (_) => _selectStage(stage),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Any health'),
                    selected: _health == null,
                    onSelected: (_) => setState(() => _health = null),
                  ),
                  for (final health in _ProjectFeedHealth.values)
                    ChoiceChip(
                      label: Text(health.label),
                      selected: _health == health,
                      onSelected: (_) => setState(() => _health = health),
                    ),
                  if (statuses.length > 1)
                    DropdownButton<String?>(
                      value: selectedStatusId,
                      hint: const Text('All statuses'),
                      underline: const SizedBox(),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('All statuses'),
                        ),
                        for (final status in statuses)
                          DropdownMenuItem<String?>(
                            value: status.id,
                            child: Text(status.label),
                          ),
                      ],
                      onChanged: (value) => setState(() => _statusId = value),
                    ),
                  if (cities.isNotEmpty)
                    DropdownButton<String?>(
                      value: _city,
                      hint: const Text('All cities'),
                      underline: const SizedBox(),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('All cities'),
                        ),
                        for (final city in cities)
                          DropdownMenuItem<String?>(
                            value: city,
                            child: Text(city),
                          ),
                      ],
                      onChanged: (value) => setState(() => _city = value),
                    ),
                  if (managers.isNotEmpty)
                    DropdownButton<String?>(
                      value: _managerId,
                      hint: const Text('All managers'),
                      underline: const SizedBox(),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('All managers'),
                        ),
                        for (final manager in managers)
                          DropdownMenuItem<String?>(
                            value: manager.uid,
                            child: Text(manager.name),
                          ),
                      ],
                      onChanged: (value) => setState(() => _managerId = value),
                    ),
                  DropdownButton<_ProjectFeedSort>(
                    value: _sort,
                    underline: const SizedBox(),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    items: [
                      for (final sort in _ProjectFeedSort.values)
                        DropdownMenuItem(value: sort, child: Text(sort.label)),
                    ],
                    onChanged: (value) =>
                        setState(() => _sort = value ?? _sort),
                  ),
                  if (hasFilters)
                    TextButton.icon(
                      onPressed: _clearFilters,
                      icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
                      label: const Text('Clear filters'),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              if (result.isEmpty)
                const MessageView(
                  icon: Icons.search_off_outlined,
                  title: 'No matching projects',
                  message: 'Try clearing a filter or changing the search.',
                )
              else
                for (final project in result)
                  ProjectCard(
                    project: project,
                    config: config,
                    onTap: () => context.push('/projects/${project.id}'),
                  ),
              const SizedBox(height: 72),
            ],
          );
        },
      ),
    );
  }

  void _selectStage(ProjectStage? stage) => setState(() {
    _stage = stage;
    _statusId = null;
  });

  void _clearFilters() {
    _search.clear();
    setState(() {
      _query = '';
      _stage = null;
      _statusId = null;
      _health = null;
      _managerId = null;
      _city = null;
      _sort = _ProjectFeedSort.attention;
    });
  }

  List<Project> _filtered(
    List<Project> projects,
    AppConfig config,
    String? selectedStatusId,
  ) {
    final result = projects.where((project) {
      if (_stage != null && config.stageOfStatus(project.statusId) != _stage) {
        return false;
      }
      if (selectedStatusId != null && project.statusId != selectedStatusId) {
        return false;
      }
      if (!_matchesHealth(project.health)) return false;
      if (_managerId != null && project.managerId != _managerId) return false;
      if (_city != null && project.city != _city) return false;
      if (_query.isEmpty) return true;
      final custom = config
          .activeFieldsFor(FieldEntity.project)
          .map((field) => FieldValues.display(field, project.custom[field.id]))
          .join(' ');
      return '${project.name} ${project.code} ${project.clientName} ${project.city} ${config.labelOf(ConfigList.projectStatuses, project.statusId)} $custom'
          .toLowerCase()
          .contains(_query);
    }).toList();
    result.sort(_compareProjects);
    return result;
  }

  bool _matchesHealth(ProjectHealth health) => switch (_health) {
    null => true,
    _ProjectFeedHealth.attention =>
      health == ProjectHealth.red || health == ProjectHealth.amber,
    _ProjectFeedHealth.onTrack => health == ProjectHealth.green,
    _ProjectFeedHealth.noTimeline => health == ProjectHealth.noData,
  };

  int _compareProjects(Project a, Project b) {
    int byName() => a.name.toLowerCase().compareTo(b.name.toLowerCase());
    int byAttention() {
      final health = healthRank(a.health).compareTo(healthRank(b.health));
      return health != 0 ? health : byName();
    }

    return switch (_sort) {
      _ProjectFeedSort.attention => byAttention(),
      _ProjectFeedSort.name => byName(),
      _ProjectFeedSort.progress =>
        b.actualPct.compareTo(a.actualPct) != 0
            ? b.actualPct.compareTo(a.actualPct)
            : byAttention(),
      _ProjectFeedSort.value =>
        b.contractValuePaise.compareTo(a.contractValuePaise) != 0
            ? b.contractValuePaise.compareTo(a.contractValuePaise)
            : byName(),
      _ProjectFeedSort.dueDate => _compareDueDates(a, b),
      _ProjectFeedSort.recentlyUpdated => _compareUpdatedAt(a, b),
    };
  }

  int _compareDueDates(Project a, Project b) {
    final aDate = a.endDate;
    final bDate = b.endDate;
    if (aDate == null && bDate == null) return _compareProjectsByName(a, b);
    if (aDate == null) return 1;
    if (bDate == null) return -1;
    final compare = aDate.compareTo(bDate);
    return compare != 0 ? compare : _compareProjectsByName(a, b);
  }

  int _compareUpdatedAt(Project a, Project b) {
    final aDate = a.updatedAt;
    final bDate = b.updatedAt;
    if (aDate == null && bDate == null) return _compareProjectsByName(a, b);
    if (aDate == null) return 1;
    if (bDate == null) return -1;
    final compare = bDate.compareTo(aDate);
    return compare != 0 ? compare : _compareProjectsByName(a, b);
  }

  int _compareProjectsByName(Project a, Project b) =>
      a.name.toLowerCase().compareTo(b.name.toLowerCase());
}

enum _ProjectFeedHealth {
  attention('Needs attention'),
  onTrack('On track'),
  noTimeline('No timeline data');

  const _ProjectFeedHealth(this.label);
  final String label;
}

enum _ProjectFeedSort {
  attention('Attention first'),
  dueDate('Target date'),
  recentlyUpdated('Recently updated'),
  progress('Progress: high to low'),
  value('Value: high to low'),
  name('Name: A to Z');

  const _ProjectFeedSort(this.label);
  final String label;
}

/// The portfolio's delay framework: every factor from every live project, in
/// one list, grouped by what kind of problem it is. Each row links straight to
/// the tab and item to investigate (see [ProjectLink]).
class _Watchlist extends StatefulWidget {
  const _Watchlist({required this.projects, this.showAllByDefault = false});

  final List<ProjectInsight> projects;
  final bool showAllByDefault;

  @override
  State<_Watchlist> createState() => _WatchlistState();
}

enum _WatchGroup {
  all('All', null),
  cost('Cost overrun', {FactorKind.money}),
  payables('Payables', {FactorKind.payables, FactorKind.approvals}),
  speed('Speed & schedule', {FactorKind.speed, FactorKind.schedule, FactorKind.setup, FactorKind.hold}),
  reports('Site reports', {FactorKind.reports, FactorKind.output}),
  materials('Materials', {FactorKind.materials}),
  issues('Issues', {FactorKind.issues});

  const _WatchGroup(this.label, this.kinds);
  final String label;
  final Set<FactorKind>? kinds;

  bool matches(ProjectFactor f) => kinds == null || kinds!.contains(f.kind);
}

class _WatchlistState extends State<_Watchlist> {
  var _group = _WatchGroup.all;
  late var _showAll = widget.showAllByDefault;

  @override
  Widget build(BuildContext context) {
    final entries = [
      for (final i in widget.projects)
        for (final f in i.factors) (i, f),
    ]..sort((a, b) {
        final s = (b.$2.severe ? 1 : 0) - (a.$2.severe ? 1 : 0);
        return s != 0 ? s : healthRank(a.$1.analysis.health).compareTo(healthRank(b.$1.analysis.health));
      });
    int count(_WatchGroup g) => entries.where((e) => g.matches(e.$2)).length;
    final shown = entries.where((e) => _group.matches(e.$2)).toList();
    const limit = 8;
    final visible = _showAll ? shown : shown.take(limit).toList();

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: AppRadius.card,
        border: Border.all(color: AppColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final g in _WatchGroup.values)
                  if (g == _WatchGroup.all || count(g) > 0)
                    ChoiceChip(
                      label: Text('${g.label} · ${count(g)}'),
                      selected: _group == g,
                      onSelected: (_) => setState(() {
                        _group = g;
                        _showAll = false;
                      }),
                    ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Icon(Icons.check_circle_outline, color: context.statusColors.ok),
                  const SizedBox(width: 10),
                  const Expanded(child: Text('Nothing flagged. Every live project is running clean.')),
                ],
              ),
            )
          else
            for (var n = 0; n < visible.length; n++) ...[
              if (n > 0) const Divider(height: 1, indent: 16, endIndent: 16),
              _WatchRow(insight: visible[n].$1, factor: visible[n].$2),
            ],
          if (shown.length > limit) ...[
            const Divider(height: 1),
            TextButton(
              onPressed: () => setState(() => _showAll = !_showAll),
              child: Text(_showAll ? 'Show fewer' : 'Show all ${shown.length}'),
            ),
          ],
        ],
      ),
    );
  }
}

class _WatchRow extends StatelessWidget {
  const _WatchRow({required this.insight, required this.factor});

  final ProjectInsight insight;
  final ProjectFactor factor;

  @override
  Widget build(BuildContext context) {
    final color = factor.severe ? context.statusColors.bad : context.statusColors.warn;
    final primary = Theme.of(context).colorScheme.primary;
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return InkWell(
      onTap: () => context.push(factor.link.path(insight.project.id)),
      hoverColor: AppColors.surfaceAlt,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: factor.severe ? context.statusColors.badSoft : context.statusColors.warnSoft,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(factorIcon(factor.kind), size: 17, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    insight.project.name.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, letterSpacing: 0.6, fontWeight: FontWeight.w700, color: AppColors.muted),
                  ),
                  const SizedBox(height: 2),
                  Text(factor.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                    factor.detail,
                    maxLines: wide ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  factor.severe ? 'HIGH' : 'WATCH',
                  style: TextStyle(fontSize: 10, letterSpacing: 0.6, fontWeight: FontWeight.w800, color: color),
                ),
                const SizedBox(height: 6),
                if (wide)
                  Text(
                    '${factor.action} →',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: primary),
                  )
                else
                  Icon(Icons.chevron_right, color: primary),
              ],
            ),
          ],
        ),
      ),
    );
  }
}


/// The top of the CEO's home: one sentence on the portfolio, the decisions
/// waiting on them, and the few risks worth a look today. Everything else is
/// further down for when there is time.
class _LeaderBrief extends ConsumerWidget {
  const _LeaderBrief({required this.portfolio, required this.firstName});

  final PortfolioInsight portfolio;
  final String firstName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.statusColors;
    final expenses = ref.watch(visiblePendingExpensesProvider).value ?? const [];
    final indents = ref.watch(visiblePendingIndentsProvider).value ?? const [];
    final now = DateTime.now();
    final oldest = [
      for (final e in expenses)
        if (e.submittedAt != null) now.difference(e.submittedAt!).inDays,
      for (final (_, x) in indents) x.waitingDays(now),
    ].fold(0, (m, d) => d > m ? d : m);
    final decisions = expenses.length + indents.length;
    // Same verdict as the project tiles below, so the numbers agree.
    final atRisk = portfolio.active.where((i) => PlainProject(i, seeMoney: true).tone == Tone.bad).length;
    // The severe problems, worst projects first, one per project.
    final risks = <(ProjectInsight, ProjectFactor)>[
      for (final i in portfolio.active.toList()..sort((a, b) => healthRank(a.analysis.health).compareTo(healthRank(b.analysis.health))))
        if (i.factors.where((f) => f.severe).firstOrNull case final f?) (i, f),
    ].take(3).toList();
    final narrow = MediaQuery.sizeOf(context).width < 600;
    final hour = now.hour;
    final greeting = hour < 12 ? 'Good morning' : (hour < 17 ? 'Good afternoon' : 'Good evening');

    final decisionCard = HoverCard(
      onTap: decisions == 0 ? null : () => context.go('/approvals'),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: (decisions == 0 ? colors.ok : (oldest >= 3 ? colors.bad : colors.warn)).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              decisions == 0 ? Icons.task_alt : Icons.fact_check_outlined,
              color: decisions == 0 ? colors.ok : (oldest >= 3 ? colors.bad : colors.warn),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  decisions == 0 ? 'No approvals waiting' : '$decisions decision${decisions == 1 ? '' : 's'} waiting on you',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
                const SizedBox(height: 2),
                Text(
                  decisions == 0
                      ? 'Expenses and material requests that need you will show here.'
                      : [
                          if (expenses.isNotEmpty)
                            '${expenses.length} expense${expenses.length == 1 ? '' : 's'} · ${Money.compact(expenses.fold(0, (s, e) => s + e.amountPaise))}',
                          if (indents.isNotEmpty) '${indents.length} material request${indents.length == 1 ? '' : 's'}',
                          if (oldest > 0) 'oldest $oldest day${oldest == 1 ? '' : 's'}',
                        ].join(' · '),
                  style: const TextStyle(color: AppColors.muted, fontSize: 13),
                ),
              ],
            ),
          ),
          if (decisions > 0 && !narrow) ...[
            const SizedBox(width: 12),
            FilledButton(onPressed: () => context.go('/approvals'), child: const Text('Review')),
          ],
        ],
      ),
    );
    // On phones the button goes under the card, so the sentence has room.
    final decisionBlock = decisions > 0 && narrow
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              decisionCard,
              const SizedBox(height: 8),
              FilledButton(onPressed: () => context.go('/approvals'), child: const Text('Review approvals')),
            ],
          )
        : decisionCard;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HeroBanner(
          title: '$greeting, $firstName',
          subtitle: 'Here is how your projects are doing today.',
          stats: [
            HeroStat('${portfolio.active.length}', 'live project${portfolio.active.length == 1 ? '' : 's'}'),
            HeroStat(atRisk == 0 ? 'None' : '$atRisk', 'at risk', alert: atRisk > 0),
            if (portfolio.overduePayablesPaise > 0)
              HeroStat(Money.compact(portfolio.overduePayablesPaise), 'bills overdue', alert: true),
          ],
        ),
        const SizedBox(height: 14),
        decisionBlock,
        if (risks.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: AppRadius.card,
              border: Border.all(color: AppColors.line),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                  child: Row(
                    children: [
                      const Expanded(child: Text('Worth a look today', style: TextStyle(fontWeight: FontWeight.w800))),
                      TextButton(onPressed: () => context.go('/watchlist'), child: const Text('All risks')),
                    ],
                  ),
                ),
                for (final (i, f) in risks)
                  InkWell(
                    onTap: () => context.push(f.link.path(i.project.id)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline, color: colors.bad, size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${i.project.name}: ${f.title}', style: const TextStyle(fontWeight: FontWeight.w600)),
                                Text(
                                  f.detail,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right, color: AppColors.muted),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 6),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
