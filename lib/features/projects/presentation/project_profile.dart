import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/app_config.dart';
import '../../../core/config/config_models.dart';
import '../../../core/dynamic_form/field_values.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/work_day.dart';
import '../../../core/widgets/art.dart';
import '../../../core/widgets/common.dart';
import '../../auth/domain/app_user.dart';
import '../../inventory/data/inventory_repository.dart';
import '../../users/data/user_repository.dart';
import '../data/project_detail_repository.dart';
import '../data/project_insight_provider.dart';
import '../domain/project.dart';
import '../domain/project_insight.dart';
import '../domain/project_nav.dart';
import 'ceo_ui.dart';
import 'project_dashboard.dart' show ProjectTabPage;
import 'project_plain.dart';

/// One place for a site: who it is for and where, who works on it, and a
/// tile for every part of the project with how it is doing, so anything is
/// one tap away (on phones too, where the section bar scrolls).
class ProjectProfile extends ConsumerWidget {
  const ProjectProfile({
    super.key,
    required this.project,
    required this.config,
    required this.seeMoney,
    required this.visible,
    required this.icon,
    required this.onOpen,
    this.onEditTeam,
  });

  final Project project;
  final AppConfig config;
  final bool seeMoney;
  final bool Function(ProjectTab) visible;
  final IconData Function(ProjectTab) icon;
  final ValueChanged<ProjectTab> onOpen;

  /// Admin only: opens the project details form (team, manager, dates).
  final VoidCallback? onEditTeam;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final insight = ref.watch(projectInsightProvider(project.id)).value;
    final people = ref.watch(allUsersProvider).value ?? const <AppUser>[];
    final byId = {for (final p in people) p.uid: p};
    final members = project.memberIds.map((id) => byId[id]).whereType<AppUser>().toList()
      ..sort((a, b) => (a.uid == project.managerId ? 0 : 1).compareTo(b.uid == project.managerId ? 0 : 1));
    final manager = byId[project.managerId];

    return ProjectTabPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Cover(project: project, insight: insight, seeMoney: seeMoney, manager: manager),
          const SizedBox(height: 28),
          const _Heading('Go to', 'Every part of this site, with how it is doing right now.'),
          const SizedBox(height: 12),
          _SectionHub(project: project, insight: insight, seeMoney: seeMoney, visible: visible, icon: icon, onOpen: onOpen),
          const SizedBox(height: 28),
          Row(
            children: [
              Expanded(child: _Heading('Team · ${members.length}', 'People who work on this site and can see it.')),
              if (onEditTeam != null)
                OutlinedButton.icon(
                  onPressed: onEditTeam,
                  icon: const Icon(Icons.group_add_outlined, size: 18),
                  label: const Text('Edit team'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (members.isEmpty)
            const _Note('No one is assigned yet. The office adds the manager and supervisors.')
          else
            _Grid(
              minWidth: 300,
              children: [for (final m in members) _MemberCard(person: m, manager: m.uid == project.managerId)],
            ),
          const SizedBox(height: 28),
          Row(
            children: [
              const Expanded(child: _Heading('Key details', 'From the project record.')),
              if (visible(ProjectTab.info))
                TextButton(onPressed: () => onOpen(ProjectTab.info), child: const Text('Details & history')),
            ],
          ),
          const SizedBox(height: 12),
          _Details(project: project, config: config, seeMoney: seeMoney),
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.title, this.subtitle);

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 2),
      Text(subtitle, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
    ],
  );
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: AppRadius.card),
    child: Text(text, style: const TextStyle(color: AppColors.muted)),
  );
}

/// Children in equal columns that wrap, at least [minWidth] wide each.
class _Grid extends StatelessWidget {
  const _Grid({required this.children, this.minWidth = 220, this.gap = 12});

  final List<Widget> children;
  final double minWidth;
  final double gap;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final columns = (c.maxWidth / minWidth).floor().clamp(1, 4);
      final width = (c.maxWidth - (columns - 1) * gap) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [for (final child in children) SizedBox(width: width, child: child)],
      );
    },
  );
}

/// The site at a glance: picture, name, status, where, and the key facts.
class _Cover extends StatelessWidget {
  const _Cover({required this.project, required this.insight, required this.seeMoney, required this.manager});

  final Project project;
  final ProjectInsight? insight;
  final bool seeMoney;
  final AppUser? manager;

  @override
  Widget build(BuildContext context) {
    final p = project;
    final plain = insight == null ? null : PlainProject(insight!, seeMoney: seeMoney);
    final tone = plain == null || plain.tone == Tone.none ? Theme.of(context).colorScheme.primary : toneColor(context, plain.tone);
    final facts = <(IconData, String, String)>[
      if (p.clientName.isNotEmpty) (Icons.business_outlined, 'Client', p.clientName),
      if (manager != null) (Icons.engineering_outlined, 'Project manager', manager!.name),
      if (p.startDate != null) (Icons.flag_outlined, 'Started', WorkDay.display(p.startDate)),
      if (p.endDate != null) (Icons.event_outlined, 'Promised finish', WorkDay.display(p.endDate)),
      if (seeMoney && p.contractValuePaise > 0) (Icons.payments_outlined, 'Contract value', Money.compact(p.contractValuePaise)),
    ];
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.line),
        boxShadow: appCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 112,
            color: AppColors.blue,
            alignment: Alignment.bottomRight,
            padding: const EdgeInsets.only(right: 12),
            child: const Illustration(Art.heroLines, height: 104),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Transform.translate(
                  offset: const Offset(0, -28),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: ProjectAvatar(name: p.name, color: tone, size: 60),
                      ),
                      const Spacer(),
                      if (plain != null && plain.tone != Tone.none) VerdictPill(plain: plain),
                    ],
                  ),
                ),
                Transform.translate(
                  offset: const Offset(0, -16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.name, style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          const Icon(Icons.place_outlined, size: 16, color: AppColors.muted),
                          Text(
                            [
                              if (p.address.isNotEmpty) p.address,
                              if (p.city.isNotEmpty && !p.address.toLowerCase().contains(p.city.toLowerCase())) p.city,
                            ].join(', ').ifEmpty('Address not added'),
                            style: const TextStyle(color: AppColors.muted),
                          ),
                          if (p.code.isNotEmpty) Pill(p.code),
                        ],
                      ),
                    ],
                  ),
                ),
                _Grid(
                  minWidth: 150,
                  gap: 8,
                  children: [
                    for (final (i, label, value) in facts)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(AppRadius.sm + 2)),
                        child: Row(
                          children: [
                            Icon(i, size: 20, color: Theme.of(context).colorScheme.primary),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                                  Text(
                                    value,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.w700),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A tile per project section with a live one-line status.
class _SectionHub extends ConsumerWidget {
  const _SectionHub({
    required this.project,
    required this.insight,
    required this.seeMoney,
    required this.visible,
    required this.icon,
    required this.onOpen,
  });

  final Project project;
  final ProjectInsight? insight;
  final bool seeMoney;
  final bool Function(ProjectTab) visible;
  final IconData Function(ProjectTab) icon;
  final ValueChanged<ProjectTab> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final i = insight;
    final colors = context.statusColors;
    final inventory = ref.watch(projectInventoryProvider(project.id)).value;
    final documents = ref.watch(projectDocumentsProvider(project.id)).value;
    final reports = ref.watch(projectDprsProvider(project.id)).value;
    final today = i?.today;
    final reportedToday = today != null && (reports?.any((r) => r.date == today) ?? false);
    final latePhases = i?.phases.where((p) => p.state.late).length ?? 0;

    (String, Tone) status(ProjectTab t) => switch (t) {
      ProjectTab.timeline => i == null || i.phases.isEmpty
          ? ('No phases yet', Tone.none)
          : ('${i.phasesDone} of ${i.phases.length} phases done${latePhases > 0 ? ' · $latePhases late' : ''}',
              latePhases > 0 ? Tone.bad : Tone.ok),
      ProjectTab.daily => i == null
          ? ('', Tone.none)
          : reportedToday
          ? ('Today\'s report is in${i.missingReports > 0 ? ' · ${i.missingReports} missing' : ''}',
              i.missingReports > 2 ? Tone.warn : Tone.ok)
          : ('No report today${i.missingReports > 0 ? ' · ${i.missingReports} missing' : ''}', Tone.warn),
      ProjectTab.materials => inventory == null
          ? ('', Tone.none)
          : inventory.late.isNotEmpty
          ? ('${inventory.late.length} delivery late · ${inventory.pending.length} waiting', Tone.bad)
          : inventory.pending.isNotEmpty
          ? ('${inventory.pending.length} request${inventory.pending.length == 1 ? '' : 's'} waiting', Tone.warn)
          : inventory.lowCount > 0
          ? ('${inventory.lowCount} running low', Tone.warn)
          : ('${inventory.stock.length} materials tracked', Tone.ok),
      ProjectTab.issues => i == null
          ? ('', Tone.none)
          : i.openIssues == 0
          ? ('No open issues', Tone.ok)
          : ('${i.openIssues} open${i.urgentIssues > 0 ? ' · ${i.urgentIssues} urgent' : ''}', i.urgentIssues > 0 ? Tone.bad : Tone.warn),
      ProjectTab.documents => documents == null
          ? ('', Tone.none)
          : ('${documents.length} file${documents.length == 1 ? '' : 's'}', Tone.none),
      ProjectTab.money => i == null
          ? ('', Tone.none)
          : i.payablesPaise > 0
          ? ('${Money.compact(i.payablesPaise)} unpaid${i.pendingCount > 0 ? ' · ${i.pendingCount} to approve' : ''}',
              i.overduePayablesCount > 0 ? Tone.bad : Tone.warn)
          : ('${Money.compact(i.spentPaise)} spent', Tone.ok),
      ProjectTab.reports => ('Make a PDF report', Tone.none),
      ProjectTab.info => ('Holds, status changes, all fields', Tone.none),
      ProjectTab.activity => ('Every change, who and when', Tone.none),
      ProjectTab.overview => ('Summary and problems', Tone.none),
      ProjectTab.profile => ('', Tone.none),
    };

    const order = [
      ProjectTab.overview,
      ProjectTab.daily,
      ProjectTab.issues,
      ProjectTab.materials,
      ProjectTab.money,
      ProjectTab.timeline,
      ProjectTab.documents,
      ProjectTab.reports,
      ProjectTab.info,
      ProjectTab.activity,
    ];
    return _Grid(
      minWidth: 160,
      gap: 10,
      children: [
        for (final t in order.where(visible))
          Builder(
            builder: (context) {
              final (text, tone) = status(t);
              final color = tone == Tone.none ? Theme.of(context).colorScheme.primary : toneColor(context, tone);
              final badge = Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(12)),
                child: Icon(icon(t), color: color, size: 21),
              );
              final label = Text(t.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5));
              final line = text.isEmpty
                  ? null
                  : Text(
                      text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: tone == Tone.bad ? colors.bad : AppColors.muted,
                        fontWeight: tone == Tone.bad ? FontWeight.w600 : FontWeight.w500,
                      ),
                    );
              return HoverCard(
                onTap: () => onOpen(t),
                padding: const EdgeInsets.all(14),
                child: LayoutBuilder(
                  // Two-up on phones: icon above the words.
                  builder: (context, c) => c.maxWidth < 200
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [badge, const SizedBox(height: 10), label, ?line],
                        )
                      : Row(
                          children: [
                            badge,
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [label, ?line]),
                            ),
                            const Icon(Icons.chevron_right, color: AppColors.subtle),
                          ],
                        ),
                ),
              );
            },
          ),
      ],
    );
  }
}

class _MemberCard extends StatelessWidget {
  const _MemberCard({required this.person, required this.manager});

  final AppUser person;
  final bool manager;

  @override
  Widget build(BuildContext context) {
    final p = person;
    Widget contact(IconData icon, String tooltip, Uri uri) => IconButton.filledTonal(
      tooltip: tooltip,
      onPressed: () => launchUrl(uri),
      icon: Icon(icon, size: 18),
      style: IconButton.styleFrom(minimumSize: const Size(36, 36), padding: EdgeInsets.zero),
    );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: AppRadius.card,
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: manager
                    ? const [Color(0xFFFFC94D), Color(0xFFFF8A4C)]
                    : const [Color(0xFF8DA4FF), Color(0xFF3557D6)],
              ),
            ),
            child: Text(
              p.initials,
              style: TextStyle(fontWeight: FontWeight.w800, color: manager ? AppColors.navy : Colors.white),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.name.isEmpty ? p.email : p.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  manager ? 'Project manager' : [p.role.label, if (p.designation.isNotEmpty) p.designation].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
                ),
              ],
            ),
          ),
          if (p.phone.isNotEmpty) ...[
            const SizedBox(width: 6),
            contact(Icons.call_outlined, 'Call ${p.phone}', Uri(scheme: 'tel', path: p.phone)),
          ],
          if (p.email.isNotEmpty) ...[
            const SizedBox(width: 6),
            contact(Icons.mail_outline, 'Email ${p.email}', Uri(scheme: 'mailto', path: p.email)),
          ],
        ],
      ),
    );
  }
}

class _Details extends StatelessWidget {
  const _Details({required this.project, required this.config, required this.seeMoney});

  final Project project;
  final AppConfig config;
  final bool seeMoney;

  @override
  Widget build(BuildContext context) {
    final p = project;
    final fields = config.fieldsFor(FieldEntity.project).where((f) => !f.archived).toList();
    final items = <(String, String)>[
      ('Client', p.clientName),
      ('Project code', p.code),
      ('Project type', config.labelOf(ConfigList.projectTypes, p.typeId)),
      ('Status', config.labelOf(ConfigList.projectStatuses, p.statusId)),
      ('Address', p.address.toLowerCase().contains(p.city.toLowerCase()) ? p.address : [p.address, p.city].where((s) => s.isNotEmpty).join(', ')),
      ('Start', WorkDay.display(p.startDate)),
      ('Promised finish', WorkDay.display(p.endDate)),
      if (seeMoney) ('Contract value', p.contractValuePaise == 0 ? '' : Money.format(p.contractValuePaise)),
      for (final f in fields) (f.label, FieldValues.display(f, p.custom[f.id])),
    ].where((e) => e.$2.isNotEmpty && e.$2 != '—').toList();
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: AppRadius.card,
        border: Border.all(color: AppColors.line),
      ),
      child: _Grid(
        minWidth: 150,
        gap: 18,
        children: [
          for (final (label, value) in items)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
        ],
      ),
    );
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}
