import 'package:flutter/material.dart';

import '../../../core/config/app_config.dart';
import '../../../core/config/config_models.dart';
import '../../../core/dynamic_form/field_values.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/work_day.dart';
import '../../../core/widgets/common.dart';
import '../domain/project.dart';

const _ink = AppColors.ink;
const _line = AppColors.line;
const _muted = AppColors.muted;

Color healthColor(BuildContext context, ProjectHealth health) =>
    switch (health) {
      ProjectHealth.green => context.statusColors.ok,
      ProjectHealth.amber => context.statusColors.warn,
      ProjectHealth.red => context.statusColors.bad,
      ProjectHealth.noData => Theme.of(context).colorScheme.outline,
    };

Color healthSoftColor(BuildContext context, ProjectHealth health) =>
    switch (health) {
      ProjectHealth.green => context.statusColors.okSoft,
      ProjectHealth.amber => context.statusColors.warnSoft,
      ProjectHealth.red => context.statusColors.badSoft,
      ProjectHealth.noData => Theme.of(
        context,
      ).colorScheme.surfaceContainerHighest,
    };

String healthLabel(ProjectHealth health) => switch (health) {
  ProjectHealth.green => 'On track',
  ProjectHealth.amber => 'Needs attention',
  ProjectHealth.red => 'At risk',
  ProjectHealth.noData => 'No timeline data',
};

int healthRank(ProjectHealth health) => switch (health) {
  ProjectHealth.red => 0,
  ProjectHealth.amber => 1,
  ProjectHealth.green => 2,
  ProjectHealth.noData => 3,
};

/// A white rounded surface that lifts slightly on hover when it is tappable.
class HoverCard extends StatefulWidget {
  const HoverCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  @override
  State<HoverCard> createState() => _HoverCardState();
}

class _HoverCardState extends State<HoverCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final interactive = widget.onTap != null;
    final lifted = interactive && _hover;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: interactive ? SystemMouseCursors.click : MouseCursor.defer,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        transform: Matrix4.translationValues(0, lifted ? -2 : 0, 0),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: AppRadius.card,
          border: Border.all(
            color: lifted ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.35) : _line,
          ),
          boxShadow: lifted ? appSoftShadow : const [],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: AppRadius.card,
            child: Padding(padding: widget.padding, child: widget.child),
          ),
        ),
      ),
    );
  }
}

/// A KPI tile: icon, label, big value and an optional one-line caption.
class NeoMetricCard extends StatelessWidget {
  const NeoMetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.caption,
    this.accent,
    this.onTap,
  });

  final String label;
  final String value;
  final String? caption;
  final IconData icon;
  final Color? accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = accent ?? Theme.of(context).colorScheme.primary;
    return HoverCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(16, 15, 14, 15),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 40,
            width: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(color: _muted),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: _ink,
                    letterSpacing: -0.3,
                  ),
                ),
                if (caption != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    caption!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(color: _muted),
                  ),
                ],
              ],
            ),
          ),
          if (onTap != null)
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Icon(Icons.chevron_right, size: 20, color: _muted),
            ),
        ],
      ),
    );
  }
}

/// Primary call to action. A plain filled button, kept as its own widget so
/// screens don't restyle it one by one.
class NeoActionButton extends StatelessWidget {
  const NeoActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.compact = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final style = FilledButton.styleFrom(
      minimumSize: Size(64, compact ? 40 : 48),
      padding: EdgeInsets.symmetric(horizontal: compact ? 14 : 20),
    );
    return icon == null
        ? FilledButton(onPressed: onPressed, style: style, child: Text(label))
        : FilledButton.icon(
            onPressed: onPressed,
            style: style,
            icon: Icon(icon, size: 18),
            label: Text(label),
          );
  }
}

class ProjectHealthPill extends StatelessWidget {
  const ProjectHealthPill({super.key, required this.health});

  final ProjectHealth health;

  @override
  Widget build(BuildContext context) => Pill(
    healthLabel(health),
    color: healthColor(context, health),
    background: healthSoftColor(context, health),
  );
}

class ProjectCard extends StatelessWidget {
  const ProjectCard({
    super.key,
    required this.project,
    required this.config,
    required this.onTap,
  });

  final Project project;
  final AppConfig config;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final stage = config.stageOfStatus(project.statusId);
    final status = config.labelOf(ConfigList.projectStatuses, project.statusId);
    final progress = stage == ProjectStage.pipeline
        ? 0.0
        : project.actualPct.clamp(0, 100) / 100;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: HoverCard(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        project.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800, color: _ink),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        [
                          if (project.code.isNotEmpty) project.code,
                          if (project.city.isNotEmpty) project.city,
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: _muted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (stage == ProjectStage.ongoing)
                  ProjectHealthPill(health: project.health)
                else
                  Pill(stage.label),
              ],
            ),
            const SizedBox(height: 15),
            if (stage == ProjectStage.pipeline)
              _PipelineDetail(project: project, status: status)
            else ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      status,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(color: _muted),
                    ),
                  ),
                  Text(
                    '${project.actualPct.toStringAsFixed(0)}%',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: progress.toDouble()),
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, _) => LinearProgressIndicator(
                    minHeight: 7,
                    value: value,
                    valueColor: AlwaysStoppedAnimation(healthColor(context, project.health)),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              _ProjectFacts(project: project),
            ],
            _ProjectCardFields(project: project, config: config),
          ],
        ),
      ),
    );
  }
}

/// Administrators choose these fields in Settings. Keeping them on the card
/// lets each company see the handful of facts it actually uses to run work.
class _ProjectCardFields extends StatelessWidget {
  const _ProjectCardFields({required this.project, required this.config});

  final Project project;
  final AppConfig config;

  @override
  Widget build(BuildContext context) {
    final fields = config
        .activeFieldsFor(FieldEntity.project)
        .where(
          (field) =>
              field.showOnCard &&
              !FieldValues.isEmpty(project.custom[field.id]),
        )
        .take(3)
        .toList();
    if (fields.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          for (final field in fields)
            Container(
              constraints: const BoxConstraints(maxWidth: 220),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: _line),
              ),
              child: Text(
                '${field.label}: ${FieldValues.display(field, project.custom[field.id])}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.inkSoft,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PipelineDetail extends StatelessWidget {
  const _PipelineDetail({required this.project, required this.status});

  final Project project;
  final String status;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          status,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(color: _muted),
        ),
      ),
      if (project.contractValuePaise > 0)
        Text(
          Money.compact(project.contractValuePaise),
          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
      if (project.startDate != null) ...[
        const SizedBox(width: 10),
        Text(
          'Starts ${WorkDay.display(project.startDate)}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ],
  );
}

class _ProjectFacts extends StatelessWidget {
  const _ProjectFacts({required this.project});

  final Project project;

  @override
  Widget build(BuildContext context) {
    final facts = <String>[
      if (project.endDate != null) 'Due ${WorkDay.display(project.endDate)}',
      if (project.contractValuePaise > 0) Money.compact(project.contractValuePaise),
    ];
    return Text(
      facts.isEmpty ? 'Timeline not set' : facts.join('  ·  '),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: _muted),
    );
  }
}

class StageTile extends StatelessWidget {
  const StageTile({
    super.key,
    required this.stage,
    required this.count,
    required this.atRiskCount,
    required this.onTap,
  });

  final ProjectStage stage;
  final int count;
  final int atRiskCount;
  final VoidCallback onTap;

  static IconData _icon(ProjectStage stage) => switch (stage) {
    ProjectStage.pipeline => Icons.lightbulb_outline,
    ProjectStage.ongoing => Icons.construction_outlined,
    ProjectStage.onHold => Icons.pause_circle_outline,
    ProjectStage.completed => Icons.verified_outlined,
    ProjectStage.cancelled => Icons.block_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final isRisky = atRiskCount > 0;
    final accent = isRisky ? context.statusColors.bad : Theme.of(context).colorScheme.primary;
    return HoverCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(_icon(stage), color: accent, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stage.label,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  isRisky
                      ? '$count project${count == 1 ? '' : 's'} · $atRiskCount at risk'
                      : '$count project${count == 1 ? '' : 's'}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: isRisky ? context.statusColors.bad : _muted,
                    fontWeight: isRisky ? FontWeight.w700 : null,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, size: 20, color: _muted),
        ],
      ),
    );
  }
}

/// A small stat on the [HeroBanner]: a number and what it counts.
class HeroStat {
  const HeroStat(this.value, this.label, {this.alert = false});

  final String value;
  final String label;

  /// Draws the chip in warm amber to catch the eye.
  final bool alert;
}

/// The friendly top of a home screen: greeting, one line of context and a
/// few stat chips on a soft brand gradient.
class HeroBanner extends StatelessWidget {
  const HeroBanner({super.key, required this.title, required this.subtitle, this.stats = const []});

  final String title;
  final String subtitle;
  final List<HeroStat> stats;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      gradient: const LinearGradient(
        colors: [Color(0xFF3557D6), Color(0xFF4B49C8), Color(0xFF6A4CC9)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      boxShadow: const [BoxShadow(color: Color(0x223557D6), blurRadius: 18, offset: Offset(0, 6))],
    ),
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        // Soft decorative circles, purely visual.
        Positioned(
          right: -30,
          top: -40,
          child: Container(
            width: 150,
            height: 150,
            decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.07)),
          ),
        ),
        Positioned(
          right: 70,
          bottom: -60,
          child: Container(
            width: 110,
            height: 110,
            decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.05)),
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.5),
            ),
            const SizedBox(height: 4),
            Text(subtitle, style: TextStyle(color: Colors.white.withValues(alpha: 0.82), fontSize: 14)),
            if (stats.isNotEmpty) ...[
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in stats)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: s.alert ? const Color(0xFFFFC94D) : Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: s.value, style: const TextStyle(fontWeight: FontWeight.w800)),
                            TextSpan(text: ' ${s.label}'),
                          ],
                        ),
                        style: TextStyle(
                          color: s.alert ? const Color(0xFF3B2A00) : Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ],
    ),
  );
}

/// A project's monogram ("LR" for Lakeview Residency) on a soft tile, so
/// projects are recognisable at a glance. [color] is usually the verdict's.
class ProjectAvatar extends StatelessWidget {
  const ProjectAvatar({super.key, required this.name, required this.color, this.size = 42});

  final String name;
  final Color color;
  final double size;

  static String initialsOf(String name) {
    final words = name.split(RegExp(r'[^A-Za-z0-9]+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return '?';
    return (words.length == 1 ? words.first.substring(0, words.first.length.clamp(1, 2)) : '${words[0][0]}${words[1][0]}')
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(size * 0.3),
    ),
    child: Text(
      initialsOf(name),
      style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: size * 0.36, letterSpacing: -0.3),
    ),
  );
}
