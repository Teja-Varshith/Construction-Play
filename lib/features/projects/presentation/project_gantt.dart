import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/project_analysis.dart';
import '../domain/project_detail.dart';

const _line = AppColors.line;
const _muted = AppColors.muted;
const _planned = AppColors.line;

/// Planned vs actual, one row per phase. The grey bar is the planned window;
/// the coloured fill is actual completion, coloured by how far it trails the
/// plan for today. The red line is today.
class ProjectGantt extends StatelessWidget {
  const ProjectGantt({super.key, required this.phases, required this.today});

  final List<ProjectPhase> phases;

  /// Working-day key (YYYY-MM-DD).
  final String today;

  @override
  Widget build(BuildContext context) {
    final dated = phases.where((p) => p.hasValidDates).toList();
    if (dated.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('Add planned dates to phases to see the schedule chart.', style: TextStyle(color: _muted)),
      );
    }
    final now = ProjectAnalysis.day(today);
    var start = dated.map((p) => ProjectAnalysis.day(p.plannedStart!)).reduce((a, b) => a.isBefore(b) ? a : b);
    var end = dated.map((p) => ProjectAnalysis.day(p.plannedEnd!)).reduce((a, b) => a.isAfter(b) ? a : b);
    // Keep today visible when it is just outside the plan.
    if (now.isBefore(start) && start.difference(now).inDays < 60) start = now;
    if (now.isAfter(end) && now.difference(end).inDays < 60) end = now;
    final totalDays = end.difference(start).inDays.clamp(1, 100000);

    return LayoutBuilder(
      builder: (context, constraints) {
        final labelWidth = constraints.maxWidth < 520 ? 96.0 : 150.0;
        final chartWidth = constraints.maxWidth - labelWidth - 12;
        double x(DateTime d) => (d.difference(start).inDays / totalDays * chartWidth).clamp(0, chartWidth);
        final showToday = !now.isBefore(start) && !now.isAfter(end);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                SizedBox(width: labelWidth + 12),
                SizedBox(
                  width: chartWidth,
                  height: 20,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      for (final m in _monthTicks(start, end, chartWidth))
                        Positioned(
                          left: x(m),
                          child: Text(
                            DateFormat(m.month == 1 ? 'MMM yy' : 'MMM', 'en_IN').format(m),
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: _muted),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Stack(
              children: [
                Column(
                  children: [
                    for (final p in phases)
                      SizedBox(
                        height: 38,
                        child: Row(
                          children: [
                            SizedBox(
                              width: labelWidth,
                              child: Text(
                                p.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                            const SizedBox(width: 12),
                            SizedBox(
                              width: chartWidth,
                              child: p.hasValidDates
                                  ? _PhaseBar(
                                      left: x(ProjectAnalysis.day(p.plannedStart!)),
                                      width: (x(ProjectAnalysis.day(p.plannedEnd!)) -
                                              x(ProjectAnalysis.day(p.plannedStart!)))
                                          .clamp(4, chartWidth),
                                      actual: p.actualPct,
                                      color: _barColor(context, p, now),
                                    )
                                  : const Text('Dates not set', style: TextStyle(color: _muted, fontSize: 12)),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                if (showToday)
                  Positioned(
                    left: labelWidth + 12 + x(now) - 1,
                    top: 0,
                    bottom: 0,
                    child: Container(width: 2, color: context.statusColors.bad),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 14,
              runSpacing: 6,
              children: [
                const _Legend(color: _planned, label: 'Planned window'),
                _Legend(color: Theme.of(context).colorScheme.primary, label: 'On plan'),
                _Legend(color: context.statusColors.warn, label: 'Slipping'),
                _Legend(color: context.statusColors.bad, label: 'Behind'),
                _Legend(color: context.statusColors.ok, label: 'Done'),
                if (showToday) _Legend(color: context.statusColors.bad, label: 'Today', thin: true),
              ],
            ),
          ],
        );
      },
    );
  }

  static Color _barColor(BuildContext context, ProjectPhase p, DateTime now) {
    if (p.actualPct >= 100) return context.statusColors.ok;
    final gap = ProjectAnalysis.plannedFor(p, now) - p.actualPct;
    if (gap > 10) return context.statusColors.bad;
    if (gap > 3) return context.statusColors.warn;
    return Theme.of(context).colorScheme.primary;
  }

  /// First day of each month in range, thinned so labels don't collide.
  static List<DateTime> _monthTicks(DateTime start, DateTime end, double width) {
    final months = <DateTime>[];
    var m = DateTime.utc(start.year, start.month + 1, 1);
    if (start.day == 1) m = DateTime.utc(start.year, start.month, 1);
    while (!m.isAfter(end)) {
      months.add(m);
      m = DateTime.utc(m.year, m.month + 1, 1);
    }
    final fit = (width / 56).floor().clamp(1, 1000);
    final step = (months.length / fit).ceil().clamp(1, 1000);
    return [for (var i = 0; i < months.length; i += step) months[i]];
  }
}

class _PhaseBar extends StatelessWidget {
  const _PhaseBar({required this.left, required this.width, required this.actual, required this.color});

  final double left;
  final double width;
  final double actual;
  final Color color;

  @override
  Widget build(BuildContext context) => Stack(
    alignment: Alignment.centerLeft,
    children: [
      Positioned(
        left: left,
        width: width,
        top: 10,
        bottom: 10,
        child: Container(
          decoration: BoxDecoration(color: _planned, borderRadius: BorderRadius.circular(3)),
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: (actual / 100).clamp(0, 1),
            heightFactor: 1,
            child: Container(decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
          ),
        ),
      ),
    ],
  );
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label, this.thin = false});

  final Color color;
  final String label;
  final bool thin;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: thin ? 2 : 14,
        height: thin ? 14 : 8,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(2),
          border: color == _planned ? Border.all(color: _line) : null,
        ),
      ),
      const SizedBox(width: 6),
      Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: _muted)),
    ],
  );
}
