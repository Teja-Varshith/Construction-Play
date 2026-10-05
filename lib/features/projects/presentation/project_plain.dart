import 'package:flutter/material.dart';

import '../../../core/config/config_models.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money.dart';
import '../domain/project.dart';
import '../domain/project_insight.dart';
import '../domain/project_nav.dart';
import 'insight_widgets.dart';

/// ok / needs attention / at risk. Always shown with its words.
enum Tone { ok, warn, bad, none }

Color toneColor(BuildContext context, Tone t) => switch (t) {
  Tone.ok => context.statusColors.ok,
  Tone.warn => context.statusColors.warn,
  Tone.bad => context.statusColors.bad,
  Tone.none => AppColors.muted,
};

Color toneSoft(BuildContext context, Tone t) => switch (t) {
  Tone.ok => context.statusColors.okSoft,
  Tone.warn => context.statusColors.warnSoft,
  Tone.bad => context.statusColors.badSoft,
  Tone.none => AppColors.concrete,
};

/// One plain sentence about a project, with how good or bad it is and where
/// to go to see more.
class PlainLine {
  const PlainLine(this.icon, this.text, this.tone, {this.link});

  final IconData icon;
  final String text;
  final Tone tone;
  final ProjectLink? link;
}

/// A project in the words a chairman would use: is it on time, is the money
/// fine, are bills being paid, and what is the main problem. The same words
/// are used on the home tiles and at the top of the project, so the two never
/// disagree. Derived from [ProjectInsight]; nothing new is calculated.
class PlainProject {
  PlainProject(this.insight, {required this.seeMoney});

  final ProjectInsight insight;
  final bool seeMoney;

  ProjectInsight get _i => insight;
  bool get running => _i.stage == ProjectStage.ongoing;

  /// Overall verdict: the worst of schedule and the serious problems, so a
  /// project is only "on track" when nothing important is wrong.
  Tone get tone {
    if (!running) return Tone.none;
    if (!_i.scheduleReady) return Tone.warn;
    final factors = _visibleFactors;
    // Only problems that threaten the finish date or the money make a project
    // "at risk"; missing reports or a slow approval only need attention.
    if (_i.analysis.health == ProjectHealth.red || factors.any((f) => f.severe && _critical.contains(f.kind))) {
      return Tone.bad;
    }
    if (_i.analysis.health == ProjectHealth.amber || factors.isNotEmpty) return Tone.warn;
    return Tone.ok;
  }

  static const _critical = {FactorKind.schedule, FactorKind.money, FactorKind.payables, FactorKind.materials, FactorKind.issues};

  String get verdict => switch (_i.stage) {
    ProjectStage.onHold => 'On hold',
    ProjectStage.pipeline => 'Not started',
    ProjectStage.completed => 'Completed',
    ProjectStage.cancelled => 'Cancelled',
    _ => !_i.scheduleReady
        ? 'Plan not set'
        : switch (tone) {
            Tone.bad => 'At risk',
            Tone.warn => 'Needs attention',
            _ => 'On track',
          },
  };

  List<ProjectFactor> get _visibleFactors => seeMoney
      ? _i.factors.where((f) => f.kind != FactorKind.setup).toList()
      : _i.factors
            .where((f) => f.kind != FactorKind.money && f.kind != FactorKind.approvals && f.kind != FactorKind.payables)
            .where((f) => f.kind != FactorKind.setup)
            .toList();

  /// The single most serious problem, if any.
  /// The problem behind the verdict: a serious time or money problem first,
  /// otherwise the first one listed.
  ProjectFactor? get mainProblem {
    if (!_i.active) return null;
    final factors = _visibleFactors;
    return factors.where((f) => f.severe && _critical.contains(f.kind)).firstOrNull ?? factors.firstOrNull;
  }

  int get problemCount => _i.active ? _visibleFactors.length : 0;

  /// "50% built, should be 54% by now."
  String get progress {
    final a = _i.analysis;
    if (!_i.scheduleReady) return 'Progress not measured yet';
    final done = '${a.actual.toStringAsFixed(0)}% built';
    if (_i.finished) return 'All planned work done';
    if ((a.planned - a.actual).abs() < 1) return '$done · right on plan';
    return a.actual > a.planned
        ? '$done · ahead of the ${a.planned.toStringAsFixed(0)}% planned'
        : '$done · should be ${a.planned.toStringAsFixed(0)}% by now';
  }

  /// When it will finish, against the promise.
  PlainLine get time {
    final i = _i;
    const link = ProjectLink(ProjectTab.timeline);
    if (i.stage == ProjectStage.onHold) {
      return PlainLine(Icons.pause_circle_outline, 'On hold · the schedule clock is paused', Tone.warn, link: const ProjectLink(ProjectTab.info, 'holds'));
    }
    if (i.stage == ProjectStage.pipeline) {
      return PlainLine(Icons.event_outlined, 'Planned to start ${displayDateKey(i.project.startDate)}', Tone.none, link: link);
    }
    if (!i.scheduleReady || i.forecastFinish == null) {
      return const PlainLine(Icons.schedule, 'Finish date can\'t be predicted until the plan is set', Tone.warn, link: link);
    }
    final slip = i.finishSlipDays;
    final slow = (i.paceRatio ?? 1) < 0.85 && i.requiredPerWeek != null;
    if (slip <= 0) {
      return PlainLine(
        Icons.schedule,
        'On time · finishing ${displayDate(i.forecastFinish)}${slow ? ' · but work is slowing down' : ''}',
        slow ? Tone.warn : Tone.ok,
        link: link,
      );
    }
    return PlainLine(
      Icons.schedule,
      '$slip day${slip == 1 ? '' : 's'} late · now finishing ${displayDate(i.forecastFinish)} '
      '(promised ${displayDateKey(i.project.endDate)})',
      slip > 14 ? Tone.bad : Tone.warn,
      link: link,
    );
  }

  /// Spend against the budget for the work actually done.
  PlainLine? get money {
    if (!seeMoney) return null;
    final i = _i;
    const link = ProjectLink(ProjectTab.money, 'overspend');
    if (i.budgetPaise <= 0) {
      return PlainLine(
        Icons.account_balance_wallet_outlined,
        i.spentPaise > 0 ? '${Money.compact(i.spentPaise)} spent · no budget set to compare' : 'No budget set yet',
        Tone.warn,
        link: link,
      );
    }
    final over = i.costOverrunPaise;
    final bad = i.earnedPaise > 0 && over > i.earnedPaise * 0.05;
    final spent = '${Money.compact(i.spentPaise)} of ${Money.compact(i.budgetPaise)} spent';
    if (bad) {
      return PlainLine(
        Icons.account_balance_wallet_outlined,
        'Over budget by ${Money.compact(over)} for the work done · $spent',
        over > i.earnedPaise * 0.15 ? Tone.bad : Tone.warn,
        link: link,
      );
    }
    return PlainLine(Icons.account_balance_wallet_outlined, 'Within budget · $spent', Tone.ok, link: link);
  }

  /// Approved bills not yet paid.
  PlainLine? get bills {
    if (!seeMoney) return null;
    final i = _i;
    const link = ProjectLink(ProjectTab.money, 'payables');
    if (i.payablesPaise <= 0) {
      return const PlainLine(Icons.receipt_long_outlined, 'All approved bills are paid', Tone.ok, link: link);
    }
    if (i.overduePayablesCount > 0) {
      return PlainLine(
        Icons.receipt_long_outlined,
        i.overduePayablesPaise >= i.payablesPaise
            ? '${Money.compact(i.payablesPaise)} of bills unpaid · all overdue (over ${ProjectInsight.payableDueDays} days)'
            : '${Money.compact(i.payablesPaise)} of bills unpaid · ${Money.compact(i.overduePayablesPaise)} '
                'overdue (over ${ProjectInsight.payableDueDays} days)',
        Tone.bad,
        link: link,
      );
    }
    return PlainLine(
      Icons.receipt_long_outlined,
      '${Money.compact(i.payablesPaise)} of bills unpaid · none overdue',
      Tone.ok,
      link: link,
    );
  }

  /// Time, money and bills, in that order (money lines only when allowed).
  List<PlainLine> get lines => [time, ?money, ?bills];
}

/// A plain sentence with a coloured icon. Tappable when it has [onTap].
class PlainLineRow extends StatelessWidget {
  const PlainLineRow({super.key, required this.line, this.onTap, this.dense = false});

  final PlainLine line;
  final VoidCallback? onTap;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final color = toneColor(context, line.tone);
    final row = Padding(
      padding: EdgeInsets.symmetric(vertical: dense ? 3 : 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(line.icon, size: dense ? 17 : 19, color: color),
          SizedBox(width: dense ? 8 : 10),
          Expanded(
            child: Text(
              line.text,
              maxLines: dense ? 2 : 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: dense ? 13 : 14,
                height: 1.3,
                color: line.tone == Tone.bad ? color : AppColors.ink,
                fontWeight: line.tone == Tone.bad ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
          if (onTap != null && !dense) const Icon(Icons.chevron_right, size: 18, color: AppColors.muted),
        ],
      ),
    );
    return onTap == null ? row : InkWell(onTap: onTap, borderRadius: BorderRadius.circular(8), child: row);
  }
}

/// The verdict pill: "At risk", "Needs attention", "On track"...
class VerdictPill extends StatelessWidget {
  const VerdictPill({super.key, required this.plain});

  final PlainProject plain;

  @override
  Widget build(BuildContext context) {
    final color = toneColor(context, plain.tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: toneSoft(context, plain.tone), borderRadius: BorderRadius.circular(99)),
      child: Text(plain.verdict, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
    );
  }
}

/// Work done as a bar, with a marker where it should be by now. The words
/// next to it ([PlainProject.progress]) say the same thing.
class ProgressMeter extends StatelessWidget {
  const ProgressMeter({super.key, required this.actual, required this.planned, required this.color, this.height = 8});

  final double actual;
  final double planned;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final w = c.maxWidth;
      final done = (actual / 100).clamp(0, 1) * w;
      final plan = (planned / 100).clamp(0, 1) * w;
      return SizedBox(
        height: height + 6,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: 3,
              height: height,
              child: Container(decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(99))),
            ),
            Positioned(
              left: 0,
              top: 3,
              height: height,
              width: done.toDouble(),
              child: Container(decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(99))),
            ),
            if (planned > actual + 1)
              Positioned(
                left: (plan - 1).clamp(0, w - 2).toDouble(),
                top: 0,
                width: 2,
                height: height + 6,
                child: Container(color: AppColors.ink),
              ),
          ],
        ),
      );
    },
  );
}
