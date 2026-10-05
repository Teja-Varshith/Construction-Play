import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/work_day.dart';
import '../../../core/widgets/common.dart';
import '../../auth/data/session.dart';
import '../../finance/presentation/expense_editor.dart';
import '../../inventory/presentation/material_actions.dart';
import '../../projects/domain/project.dart';
import '../../projects/presentation/ceo_ui.dart';
import '../../projects/presentation/project_editors.dart';
import '../../projects/presentation/project_plain.dart';
import '../data/my_day_provider.dart';
import '../domain/my_day.dart';

/// Home for managers, supervisors and staff: what needs doing today across
/// their projects, each with the one button that does it, plus the everyday
/// entries (daily report, issue, material, expense) one tap away.
class MyDayScreen extends ConsumerStatefulWidget {
  const MyDayScreen({super.key});

  @override
  ConsumerState<MyDayScreen> createState() => _MyDayScreenState();
}

class _MyDayScreenState extends ConsumerState<MyDayScreen> {
  var _showAllLater = false;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final day = ref.watch(myDayProvider);
    final hour = DateTime.now().hour;
    final greeting = hour < 12 ? 'Good morning' : (hour < 17 ? 'Good afternoon' : 'Good evening');
    return PageScaffold(
      // The banner greets the person; the bar only shows a title on phones.
      title: MediaQuery.sizeOf(context).width < 900 ? 'My day' : '',
      body: AsyncView(
        value: day,
        data: (d) {
          if (d.projects.isEmpty) {
            return const MessageView(
              icon: Icons.apartment_outlined,
              title: 'You are not on a project yet',
              message: 'Ask the office to add you to your site. Your daily work will show up here.',
            );
          }
          final now = d.tasks.where((t) => t.urgency == DayUrgency.now).length;
          final today = d.tasks.where((t) => t.urgency == DayUrgency.today).length;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              HeroBanner(
                title: '$greeting, ${user.name.split(' ').first}',
                subtitle: '${WorkDay.display(d.today)} · ${now + today == 0 ? 'nothing urgent today' : 'here is what needs you today'}',
                stats: [
                  HeroStat('$now', 'to do now', alert: now > 0),
                  HeroStat('$today', 'later today'),
                  HeroStat('${d.projects.length}', 'project${d.projects.length == 1 ? '' : 's'}'),
                ],
              ),
              const SizedBox(height: 20),
              _QuickActions(data: d),
              const SizedBox(height: 28),
              if (d.tasks.isEmpty)
                const _AllClear()
              else
                for (final u in DayUrgency.values)
                  if (d.tasks.any((t) => t.urgency == u)) ...[
                    _Heading(
                      u == DayUrgency.soon ? 'Later this week' : (u == DayUrgency.now ? 'Do now' : 'Today'),
                      count: d.tasks.where((t) => t.urgency == u).length,
                      color: _urgencyColor(context, u),
                    ),
                    const SizedBox(height: 10),
                    ...() {
                      final list = d.tasks.where((t) => t.urgency == u).toList();
                      final shown = u == DayUrgency.soon && !_showAllLater ? list.take(3).toList() : list;
                      return [
                        for (final t in shown)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _TaskCard(task: t, showProject: d.projects.length > 1),
                          ),
                        if (shown.length < list.length)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton(
                              onPressed: () => setState(() => _showAllLater = true),
                              child: Text('Show ${list.length - shown.length} more'),
                            ),
                          ),
                      ];
                    }(),
                    const SizedBox(height: 18),
                  ],
              const SizedBox(height: 10),
              _Heading('My projects', count: d.projects.length),
              const SizedBox(height: 10),
              for (final p in d.projects)
                Padding(padding: const EdgeInsets.only(bottom: 10), child: _ProjectRow(project: p)),
            ],
          );
        },
      ),
    );
  }
}

Color _urgencyColor(BuildContext context, DayUrgency u) => switch (u) {
  DayUrgency.now => context.statusColors.bad,
  DayUrgency.today => context.statusColors.warn,
  DayUrgency.soon => Theme.of(context).colorScheme.primary,
};

IconData _icon(DayTaskKind k) => switch (k) {
  DayTaskKind.report => Icons.add_task,
  DayTaskKind.backfill => Icons.event_busy_outlined,
  DayTaskKind.issue => Icons.flag_outlined,
  DayTaskKind.approve => Icons.fact_check_outlined,
  DayTaskKind.delivery => Icons.local_shipping_outlined,
  DayTaskKind.reorder => Icons.inventory_2_outlined,
  DayTaskKind.delay => Icons.schedule_outlined,
  DayTaskKind.book => Icons.receipt_long_outlined,
  DayTaskKind.expense => Icons.undo_outlined,
};

/// Runs a task's action: today's report opens the form directly, everything
/// else opens the right tab of the project already focused on the item.
void _runTask(BuildContext context, DayTask t) {
  if (t.kind == DayTaskKind.report) {
    showProjectEditor(context, project: t.project, kind: 'dprs');
  } else if (t.link != null) {
    context.push(t.link!.path(t.project.id));
  }
}

/// Picks one project when an action applies to several.
Future<Project?> _pickProject(BuildContext context, String title, List<MyProject> options, String Function(MyProject) note) {
  if (options.length == 1) return Future.value(options.first.insight.project);
  return showModalBottomSheet<Project>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          ),
          for (final p in options)
            ListTile(
              leading: const Icon(Icons.apartment_outlined),
              title: Text(p.insight.project.name),
              subtitle: Text(note(p)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pop(context, p.insight.project),
            ),
        ],
      ),
    ),
  );
}

class _QuickActions extends ConsumerWidget {
  const _QuickActions({required this.data});

  final MyDayData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final open = data.projects.where((p) => p.insight.stage.name == 'ongoing').toList();
    final reporters = open.where((p) => p.access.report).toList();
    final unreported = reporters.where((p) => !p.reportedToday).toList();
    final spenders = open.where((p) => p.access.manage && p.access.seeMoney).toList();
    String reportNote(MyProject p) => p.reportedToday ? 'Today\'s report done · tap to edit' : 'No report yet today';

    final actions = <Widget>[
      if (reporters.isNotEmpty)
        _ActionTile(
          icon: unreported.isEmpty ? Icons.task_alt : Icons.add_task,
          label: 'Daily report',
          caption: unreported.isEmpty
              ? 'Done for today'
              : (reporters.length == 1 ? 'Not sent yet' : '${unreported.length} of ${reporters.length} sites to go'),
          accent: unreported.isEmpty ? context.statusColors.ok : null,
          primary: unreported.isNotEmpty,
          onTap: () async {
            final p = await _pickProject(
              context,
              'Daily report for…',
              unreported.isEmpty ? reporters : unreported,
              reportNote,
            );
            if (p != null && context.mounted) showProjectEditor(context, project: p, kind: 'dprs');
          },
        ),
      if (reporters.isNotEmpty)
        _ActionTile(
          icon: Icons.flag_outlined,
          label: 'Raise issue',
          caption: 'Problem on site',
          onTap: () async {
            final p = await _pickProject(context, 'Raise an issue on…', reporters, (p) => '${p.insight.openIssues} open issues');
            if (p != null && context.mounted) showProjectEditor(context, project: p, kind: 'issues');
          },
        ),
      if (reporters.isNotEmpty)
        _ActionTile(
          icon: Icons.inventory_2_outlined,
          label: 'Request material',
          caption: 'Raise an indent',
          onTap: () async {
            final p = await _pickProject(context, 'Request material for…', reporters, (p) => p.insight.project.city);
            if (p != null && context.mounted) raiseIndentFlow(context, ref, p);
          },
        ),
      if (spenders.isNotEmpty)
        _ActionTile(
          icon: Icons.receipt_long_outlined,
          label: 'Log expense',
          caption: 'Bill or payment',
          onTap: () async {
            final p = await _pickProject(context, 'Log an expense on…', spenders, (p) => p.insight.project.city);
            if (p != null && context.mounted) showExpenseEditor(context, project: p);
          },
        ),
    ];
    if (actions.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, c) {
        final columns = c.maxWidth >= 720 ? actions.length.clamp(1, 4) : 2;
        final w = (c.maxWidth - (columns - 1) * 10) / columns;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [for (final a in actions) SizedBox(width: w, child: a)],
        );
      },
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.caption,
    required this.onTap,
    this.accent,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final String caption;
  final VoidCallback onTap;
  final Color? accent;

  /// The main job of the day: filled with the brand colour.
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = accent ?? scheme.primary;
    final fg = primary ? scheme.onPrimary : AppColors.ink;
    return Material(
      color: primary ? scheme.primary : scheme.surface,
      borderRadius: AppRadius.card,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.card,
        child: Container(
          constraints: const BoxConstraints(minHeight: 92),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: AppRadius.card,
            border: Border.all(color: primary ? scheme.primary : AppColors.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: primary ? Colors.white.withValues(alpha: 0.18) : color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, color: primary ? scheme.onPrimary : color, size: 21),
              ),
              const SizedBox(height: 10),
              Text(label, style: TextStyle(fontWeight: FontWeight.w800, color: fg, fontSize: 15)),
              const SizedBox(height: 2),
              Text(
                caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: primary ? scheme.onPrimary.withValues(alpha: 0.85) : (accent ?? AppColors.muted), fontSize: 12.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text, {required this.count, this.color});

  final String text;
  final int count;
  final Color? color;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      if (color != null) ...[
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
      ],
      Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(width: 8),
      Text('$count', style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600)),
    ],
  );
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({required this.task, required this.showProject});

  final DayTask task;
  final bool showProject;

  @override
  Widget build(BuildContext context) {
    final t = task;
    final color = _urgencyColor(context, t.urgency);
    final button = t.kind == DayTaskKind.report
        ? FilledButton(onPressed: () => _runTask(context, t), child: Text(t.action))
        : FilledButton.tonal(onPressed: () => _runTask(context, t), child: Text(t.action));
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showProject)
          Text(
            t.project.name.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.4),
          ),
        Text(t.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        if (t.detail.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(t.detail, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
        ],
      ],
    );
    final icon = Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(10)),
      child: Icon(_icon(t.kind), color: color, size: 21),
    );
    return HoverCard(
      onTap: () => _runTask(context, t),
      padding: const EdgeInsets.all(14),
      child: LayoutBuilder(
        builder: (context, c) => c.maxWidth < 520
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [icon, const SizedBox(width: 12), Expanded(child: text)]),
                  const SizedBox(height: 10),
                  Align(alignment: Alignment.centerRight, child: button),
                ],
              )
            : Row(
                children: [icon, const SizedBox(width: 12), Expanded(child: text), const SizedBox(width: 12), button],
              ),
      ),
    );
  }
}

class _AllClear extends StatelessWidget {
  const _AllClear();

  @override
  Widget build(BuildContext context) {
    final ok = context.statusColors.ok;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: context.statusColors.okSoft, borderRadius: AppRadius.card),
      child: Row(
        children: [
          Icon(Icons.task_alt, color: ok, size: 30),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('All caught up', style: TextStyle(color: ok, fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 2),
                const Text('Reports are in and nothing is waiting on you.', style: TextStyle(color: AppColors.ink)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProjectRow extends StatelessWidget {
  const _ProjectRow({required this.project});

  final MyProject project;

  @override
  Widget build(BuildContext context) {
    final i = project.insight;
    final a = i.analysis;
    final colors = context.statusColors;
    final ongoing = i.stage.name == 'ongoing';
    final plain = PlainProject(i, seeMoney: project.access.seeMoney);
    final tone = plain.tone == Tone.none ? Theme.of(context).colorScheme.primary : toneColor(context, plain.tone);
    return HoverCard(
      onTap: () => context.push('/projects/${i.project.id}'),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ProjectAvatar(name: i.project.name, color: tone, size: 38),
              const SizedBox(width: 12),
              Expanded(
                child: Text(i.project.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              ),
              if (plain.tone == Tone.none) Pill(i.stage.label) else VerdictPill(plain: plain),
            ],
          ),
          const SizedBox(height: 10),
          ProgressMeter(actual: a.actual, planned: a.planned, color: tone),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              Text(
                '${a.actual.toStringAsFixed(0)}% done · plan ${a.planned.toStringAsFixed(0)}%'
                '${a.daysBehind > 0 ? ' · ${a.daysBehind} days behind' : ''}',
                style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
              ),
              if (ongoing && project.access.report)
                Text(
                  project.reportedToday ? 'Report sent today' : 'No report today',
                  style: TextStyle(
                    color: project.reportedToday ? colors.ok : colors.warn,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              if (project.taskCount > 0)
                Text(
                  '${project.taskCount} to do',
                  style: const TextStyle(color: AppColors.ink, fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
