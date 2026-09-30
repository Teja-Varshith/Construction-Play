import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/work_day.dart';
import '../domain/project_insight.dart';

const _muted = Color(0xFF596775);
const _line = Color(0xFFD7DEE7);
const _track = Color(0xFFE6EBF0);

Color phaseStateColor(BuildContext context, PhaseState state) => switch (state) {
  PhaseState.done => context.statusColors.ok,
  PhaseState.onTrack => Theme.of(context).colorScheme.primary,
  PhaseState.notStarted || PhaseState.noDates => const Color(0xFF8090A2),
  PhaseState.slipping => context.statusColors.warn,
  PhaseState.behind || PhaseState.overdue => context.statusColors.bad,
};

String displayDate(DateTime? d) =>
    d == null ? '—' : WorkDay.display(WorkDay.fromDate(d));

String displayDateKey(String? key) => key == null ? 'not set' : WorkDay.display(key);

/// Actual progress as a fill, with a tick where the plan says we should be.
class PlanVsActualBar extends StatelessWidget {
  const PlanVsActualBar({
    super.key,
    required this.actual,
    required this.planned,
    required this.color,
    this.height = 8,
  });

  final double actual;
  final double planned;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final w = c.maxWidth;
      final p = (planned.clamp(0, 100) / 100) * w;
      return SizedBox(
        height: height + 6,
        child: Stack(
          alignment: Alignment.centerLeft,
          children: [
            Container(
              height: height,
              decoration: BoxDecoration(color: _track, borderRadius: BorderRadius.circular(99)),
            ),
            Container(
              height: height,
              width: (actual.clamp(0, 100) / 100) * w,
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(99)),
            ),
            if (planned > 0)
              Positioned(
                left: (p - 1).clamp(0, w - 2),
                top: 0,
                bottom: 0,
                child: Container(width: 2, color: const Color(0xFF17212B)),
              ),
          ],
        ),
      );
    },
  );
}

/// Budget as a track: approved spend solid, pending approvals hatched lighter.
class BudgetBar extends StatelessWidget {
  const BudgetBar({
    super.key,
    required this.budgetPaise,
    required this.spentPaise,
    this.pendingPaise = 0,
    this.progressPct,
    this.height = 10,
  });

  final int budgetPaise;
  final int spentPaise;
  final int pendingPaise;

  /// Work done; drawn as a tick so spend can be compared to progress.
  final double? progressPct;
  final double height;

  @override
  Widget build(BuildContext context) {
    final over = budgetPaise > 0 && spentPaise > budgetPaise;
    final color = over ? context.statusColors.bad : Theme.of(context).colorScheme.primary;
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        double frac(int v) => budgetPaise <= 0 ? 0 : (v / budgetPaise).clamp(0, 1).toDouble();
        final spentW = frac(spentPaise) * w;
        final pendingW = (frac(spentPaise + pendingPaise) * w - spentW).clamp(0, w).toDouble();
        return SizedBox(
          height: height + 6,
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              Container(
                height: height,
                decoration: BoxDecoration(color: _track, borderRadius: BorderRadius.circular(99)),
              ),
              Positioned(
                left: spentW,
                child: Container(
                  height: height,
                  width: pendingW,
                  color: context.statusColors.warn.withValues(alpha: 0.45),
                ),
              ),
              Container(
                height: height,
                width: spentW,
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(99)),
              ),
              if (progressPct != null && progressPct! > 0)
                Positioned(
                  left: ((progressPct!.clamp(0, 100) / 100) * w - 1).clamp(0, w - 2).toDouble(),
                  top: 0,
                  bottom: 0,
                  child: Container(width: 2, color: const Color(0xFF17212B)),
                ),
            ],
          ),
        );
      },
    );
  }
}

class BarLegend extends StatelessWidget {
  const BarLegend({super.key, required this.items});

  final List<(Color, String)> items;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 14,
    runSpacing: 4,
    children: [
      for (final (color, label) in items)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 12, height: 8, color: color),
            const SizedBox(width: 5),
            Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: _muted)),
          ],
        ),
    ],
  );
}

IconData factorIcon(FactorKind kind) => switch (kind) {
  FactorKind.schedule => Icons.schedule,
  FactorKind.speed => Icons.speed,
  FactorKind.materials => Icons.inventory_2_outlined,
  FactorKind.payables => Icons.receipt_long_outlined,
  FactorKind.hold => Icons.pause_circle_outline,
  FactorKind.issues => Icons.flag_outlined,
  FactorKind.reports => Icons.event_busy_outlined,
  FactorKind.output => Icons.trending_down,
  FactorKind.money => Icons.currency_rupee,
  FactorKind.approvals => Icons.hourglass_bottom,
  FactorKind.setup => Icons.build_outlined,
};

/// The reasons behind a delay or overspend, most serious first. Shows the
/// first few and expands on request, so the page stays calm.
class FactorList extends StatefulWidget {
  const FactorList({super.key, required this.factors, this.limit = 4, this.onOpen});

  final List<ProjectFactor> factors;
  final int limit;

  /// Called when a factor is tapped, to open the place to investigate it.
  final void Function(ProjectFactor factor)? onOpen;

  @override
  State<FactorList> createState() => _FactorListState();
}

class _FactorListState extends State<FactorList> {
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final factors = widget.factors;
    if (factors.isEmpty) {
      return Row(
        children: [
          Icon(Icons.check_circle_outline, color: context.statusColors.ok, size: 20),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Nothing is slowing this project down or pushing costs up right now.',
              style: TextStyle(color: _muted),
            ),
          ),
        ],
      );
    }
    final shown = _all ? factors : factors.take(widget.limit).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var n = 0; n < shown.length; n++) ...[
          if (n > 0) const Divider(height: 1),
          _FactorRow(factor: shown[n], onOpen: widget.onOpen),
        ],
        if (factors.length > widget.limit)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _all = !_all),
              icon: Icon(_all ? Icons.expand_less : Icons.expand_more, size: 18),
              label: Text(_all ? 'Show fewer' : 'Show all ${factors.length}'),
            ),
          ),
      ],
    );
  }
}

class _FactorRow extends StatefulWidget {
  const _FactorRow({required this.factor, this.onOpen});

  final ProjectFactor factor;
  final void Function(ProjectFactor factor)? onOpen;

  @override
  State<_FactorRow> createState() => _FactorRowState();
}

class _FactorRowState extends State<_FactorRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final factor = widget.factor;
    final color = factor.severe ? context.statusColors.bad : context.statusColors.warn;
    final primary = Theme.of(context).colorScheme.primary;
    final tappable = widget.onOpen != null;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: InkWell(
        onTap: tappable ? () => widget.onOpen!(factor) : null,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 8),
          decoration: BoxDecoration(
            color: _hover && tappable ? const Color(0xFFF6F8FB) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
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
                    Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(factor.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                        Text(
                          factor.severe ? 'HIGH' : 'WATCH',
                          style: TextStyle(fontSize: 10, letterSpacing: 0.6, fontWeight: FontWeight.w800, color: color),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      factor.detail,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: _muted, height: 1.4),
                    ),
                    if (tappable) ...[
                      const SizedBox(height: 6),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            factor.action,
                            style: TextStyle(color: primary, fontWeight: FontWeight.w700, fontSize: 12.5),
                          ),
                          const SizedBox(width: 4),
                          AnimatedSlide(
                            duration: const Duration(milliseconds: 150),
                            offset: Offset(_hover ? 0.25 : 0, 0),
                            child: Icon(Icons.arrow_forward, size: 14, color: primary),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Every phase with its schedule position and its own budget.
class PhaseBreakdown extends StatelessWidget {
  const PhaseBreakdown({super.key, required this.phases, this.showMoney = true, this.onOpen});

  final List<PhaseInsight> phases;
  final bool showMoney;

  /// Called when a phase row is tapped.
  final void Function(PhaseInsight phase)? onOpen;

  @override
  Widget build(BuildContext context) {
    if (phases.isEmpty) {
      return const Text('No phases set up yet.', style: TextStyle(color: _muted));
    }
    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= 760;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (wide)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    const Expanded(flex: 3, child: _Head('Phase')),
                    const Expanded(flex: 3, child: _Head('Progress vs plan')),
                    const Expanded(flex: 2, child: _Head('Schedule')),
                    if (showMoney) const Expanded(flex: 4, child: _Head('Budget · spent · left')),
                  ],
                ),
              ),
            for (final p in phases)
              DecoratedBox(
                decoration: const BoxDecoration(border: Border(top: BorderSide(color: _line))),
                child: InkWell(
                  onTap: onOpen == null ? null : () => onOpen!(p),
                  hoverColor: const Color(0xFFF6F8FB),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                    child: wide ? _wideRow(context, p) : _narrowRow(context, p),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            BarLegend(
              items: [
                (Theme.of(context).colorScheme.primary, 'Done / spent'),
                (const Color(0xFF17212B), 'Planned by today'),
                if (showMoney) (context.statusColors.warn.withValues(alpha: 0.45), 'Awaiting approval'),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _name(BuildContext context, PhaseInsight p) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(p.phase.name, style: const TextStyle(fontWeight: FontWeight.w800)),
      Text(
        p.phase.hasValidDates
            ? '${WorkDay.display(p.phase.plannedStart)} – ${WorkDay.display(p.phase.plannedEnd)}'
            : 'Dates not set',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: _muted),
      ),
    ],
  );

  Widget _progress(BuildContext context, PhaseInsight p) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      PlanVsActualBar(
        actual: p.phase.actualPct,
        planned: p.plannedPct,
        color: phaseStateColor(context, p.state),
      ),
      Text(
        '${p.phase.actualPct.toStringAsFixed(0)}% done · ${p.plannedPct.toStringAsFixed(0)}% planned',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: _muted),
      ),
    ],
  );

  Widget _schedule(BuildContext context, PhaseInsight p) {
    final color = phaseStateColor(context, p.state);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(p.state.label, style: TextStyle(color: color, fontWeight: FontWeight.w800)),
        if (p.daysLate > 0 && p.state.late)
          Text(
            '${p.daysLate} day${p.daysLate == 1 ? '' : 's'} late',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
          ),
        if (p.state.late && p.phase.delayReason.isNotEmpty)
          Tooltip(
            message: p.phase.delayReason,
            child: Text(
              p.phase.delayReason,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: _muted),
            ),
          ),
      ],
    );
  }

  Widget _money(BuildContext context, PhaseInsight p) {
    if (!p.hasBudget) {
      return Text(
        p.spentPaise > 0 ? '${Money.compact(p.spentPaise)} spent · no phase budget' : 'No phase budget',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: p.spentPaise > 0 ? context.statusColors.warn : _muted,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BudgetBar(
          budgetPaise: p.budgetPaise,
          spentPaise: p.spentPaise,
          pendingPaise: p.pendingPaise,
          progressPct: p.phase.actualPct,
          height: 8,
        ),
        Text.rich(
          TextSpan(
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: _muted),
            children: [
              TextSpan(text: '${Money.compact(p.budgetPaise)} · ${Money.compact(p.spentPaise)} · '),
              TextSpan(
                text: p.overBudget
                    ? '${Money.compact(-p.remainingPaise)} over'
                    : '${Money.compact(p.remainingPaise)} left',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: p.overBudget ? context.statusColors.bad : const Color(0xFF17212B),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _wideRow(BuildContext context, PhaseInsight p) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(flex: 3, child: _name(context, p)),
      Expanded(flex: 3, child: Padding(padding: const EdgeInsets.only(right: 16), child: _progress(context, p))),
      Expanded(flex: 2, child: _schedule(context, p)),
      if (showMoney) Expanded(flex: 4, child: _money(context, p)),
    ],
  );

  Widget _narrowRow(BuildContext context, PhaseInsight p) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _name(context, p)),
          _schedule(context, p),
        ],
      ),
      const SizedBox(height: 6),
      _progress(context, p),
      if (showMoney) ...[const SizedBox(height: 6), _money(context, p)],
    ],
  );
}

class _Head extends StatelessWidget {
  const _Head(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: Theme.of(context).textTheme.labelSmall?.copyWith(color: _muted, letterSpacing: 1),
  );
}

/// A label over a big value, used in fact rows.
class InsightFact extends StatelessWidget {
  const InsightFact({super.key, required this.label, required this.value, this.note, this.color});

  final String label;
  final String value;
  final String? note;
  final Color? color;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: _muted)),
      const SizedBox(height: 2),
      Text(
        value,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900, color: color),
      ),
      if (note != null)
        Text(note!, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: _muted)),
    ],
  );
}
