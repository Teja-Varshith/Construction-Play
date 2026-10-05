import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money.dart';

/// Chart colours. Series colours carry identity only; text stays in ink.
class ChartColors {
  ChartColors._();

  static const actual = AppColors.blue;
  static const planned = Color(0xFFC5CCDA);
  static const pending = Color(0xFFF2A516);
  static const remaining = AppColors.line;
  static const hold = Color(0xFF9A8FD6);
  static const noData = AppColors.subtle;
  static const grid = AppColors.track;
  static const ink = AppColors.ink;
}

const _labelStyle = TextStyle(fontSize: 11, color: AppColors.muted);

FlTitlesData _noTitles() => const FlTitlesData(
  topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
  rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
);

/// One slice of a donut.
class DonutSlice {
  const DonutSlice(this.label, this.value, this.color, {this.display});

  final String label;
  final double value;
  final Color color;

  /// Text shown in the legend next to the label (defaults to the value).
  final String? display;
}

/// A donut with a headline in the hole and a legend that names every slice
/// with its value, so colour is never the only way to read it.
class DonutChart extends StatefulWidget {
  const DonutChart({
    super.key,
    required this.slices,
    required this.centerValue,
    required this.centerLabel,
    this.size = 150,
  });

  final List<DonutSlice> slices;
  final String centerValue;
  final String centerLabel;
  final double size;

  @override
  State<DonutChart> createState() => _DonutChartState();
}

class _DonutChartState extends State<DonutChart> {
  int? _touched;

  @override
  Widget build(BuildContext context) {
    final slices = widget.slices.where((s) => s.value > 0).toList();
    final total = slices.fold(0.0, (a, s) => a + s.value);
    final ring = widget.size * 0.16;
    final chart = SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          PieChart(
            PieChartData(
              startDegreeOffset: -90,
              sectionsSpace: slices.length > 1 ? 2 : 0,
              centerSpaceRadius: widget.size / 2 - ring - 6,
              pieTouchData: PieTouchData(
                touchCallback: (event, response) {
                  final i = response?.touchedSection?.touchedSectionIndex;
                  final next =
                      event.isInterestedForInteractions && i != null && i >= 0
                      ? i
                      : null;
                  if (next != _touched) setState(() => _touched = next);
                },
              ),
              sections: total == 0
                  ? [
                      PieChartSectionData(
                        value: 1,
                        color: ChartColors.remaining,
                        radius: ring,
                        showTitle: false,
                      ),
                    ]
                  : [
                      for (var i = 0; i < slices.length; i++)
                        PieChartSectionData(
                          value: slices[i].value,
                          color: slices[i].color,
                          radius: _touched == i ? ring + 5 : ring,
                          showTitle: false,
                        ),
                    ],
            ),
            duration: const Duration(milliseconds: 250),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _touched != null && _touched! < slices.length
                    ? slices[_touched!].display ?? _fmt(slices[_touched!].value)
                    : widget.centerValue,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: ChartColors.ink,
                ),
              ),
              SizedBox(
                width: widget.size * 0.55,
                child: Text(
                  _touched != null && _touched! < slices.length
                      ? slices[_touched!].label
                      : widget.centerLabel,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: _labelStyle,
                ),
              ),
            ],
          ),
        ],
      ),
    );
    Widget item(DonutSlice s) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: s.color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              s.label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            s.display ?? _fmt(s.value),
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: ChartColors.ink,
            ),
          ),
        ],
      ),
    );
    final legend = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [for (final s in widget.slices) item(s)],
    );
    final wrapped = Wrap(
      alignment: WrapAlignment.center,
      spacing: 14,
      children: [for (final s in widget.slices) item(s)],
    );
    return LayoutBuilder(
      builder: (context, c) => c.maxWidth >= 400
          ? Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                chart,
                const SizedBox(width: 28),
                Flexible(child: legend),
              ],
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [chart, const SizedBox(height: 12), wrapped],
            ),
    );
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
}

/// One pair of bars: where it should be vs where it is.
class PlanActualItem {
  const PlanActualItem(
    this.label,
    this.planned,
    this.actual, {
    this.actualColor,
  });

  final String label;
  final double planned;
  final double actual;

  /// Overrides the actual bar colour (e.g. a status colour for late items).
  final Color? actualColor;
}

/// Grouped bars on a 0–100 % scale: planned (grey) next to actual (blue).
class PlanActualBars extends StatelessWidget {
  const PlanActualBars({super.key, required this.items, this.height = 236});

  final List<PlanActualItem> items;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const SizedBox(
        height: 60,
        child: Center(child: Text('Nothing to chart yet.', style: _labelStyle)),
      );
    }
    return LayoutBuilder(
      builder: (context, c) {
        final minWidth = items.length * 64.0;
        final width = math.max(c.maxWidth, minWidth);
        final rod = (width / items.length / 5).clamp(6, 16).toDouble();
        final chart = SizedBox(
          width: width,
          height: height,
          child: BarChart(
            BarChartData(
              maxY: 100,
              minY: 0,
              alignment: BarChartAlignment.spaceAround,
              borderData: FlBorderData(show: false),
              gridData: FlGridData(
                drawVerticalLine: false,
                horizontalInterval: 25,
                getDrawingHorizontalLine: (_) =>
                    const FlLine(color: ChartColors.grid, strokeWidth: 1),
              ),
              titlesData: _noTitles().copyWith(
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 38,
                    interval: 25,
                    getTitlesWidget: (v, meta) => SideTitleWidget(
                      meta: meta,
                      child: Text('${v.toInt()}%', style: _labelStyle),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 34,
                    getTitlesWidget: (v, meta) {
                      final i = v.toInt();
                      if (i < 0 || i >= items.length) {
                        return const SizedBox.shrink();
                      }
                      return SideTitleWidget(
                        meta: meta,
                        child: SizedBox(
                          width: width / items.length - 6,
                          child: Text(
                            items[i].label,
                            maxLines: 2,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            style: _labelStyle,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) => ChartColors.ink,
                  tooltipBorderRadius: BorderRadius.circular(8),
                  getTooltipItem: (group, _, _, _) {
                    final item = items[group.x];
                    return BarTooltipItem(
                      '${item.label}\n',
                      const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                      children: [
                        TextSpan(
                          text:
                              'Actual ${item.actual.toStringAsFixed(0)}% · Planned ${item.planned.toStringAsFixed(0)}%',
                          style: const TextStyle(
                            color: AppColors.line,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              barGroups: [
                for (var i = 0; i < items.length; i++)
                  BarChartGroupData(
                    x: i,
                    barsSpace: 2,
                    barRods: [
                      BarChartRodData(
                        toY: items[i].planned.clamp(0, 100),
                        width: rod,
                        color: ChartColors.planned,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(4),
                        ),
                      ),
                      BarChartRodData(
                        toY: items[i].actual.clamp(0, 100),
                        width: rod,
                        color: items[i].actualColor ?? ChartColors.actual,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(4),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            duration: const Duration(milliseconds: 300),
          ),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            width > c.maxWidth
                ? SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: chart,
                  )
                : chart,
            const SizedBox(height: 8),
            const ChartLegend(
              items: [
                (ChartColors.planned, 'Planned by today'),
                (ChartColors.actual, 'Actual'),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// Achieved as a share of target, one bar per daily report, against a 100%
/// target line. Low days are coloured by status; tapping a bar opens that day.
class OutputBars extends StatelessWidget {
  const OutputBars({super.key, required this.days, this.onTap});

  /// (work-day key, achieved %) oldest first.
  final List<(String, double)> days;
  final ValueChanged<String>? onTap;

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) {
      return const Center(child: Text('No reports with a target yet.', style: _labelStyle));
    }
    final colors = context.statusColors;
    Color colorOf(double pct) => pct < 70
        ? colors.bad
        : pct < 85
        ? colors.warn
        : ChartColors.actual;
    final maxY = math.max(120.0, days.fold(0.0, (m, d) => math.max(m, d.$2)) + 10);
    return BarChart(
      BarChartData(
        minY: 0,
        maxY: maxY,
        alignment: BarChartAlignment.spaceAround,
        borderData: FlBorderData(show: false),
        gridData: const FlGridData(show: false),
        extraLinesData: ExtraLinesData(
          horizontalLines: [
            HorizontalLine(
              y: 100,
              color: ChartColors.ink.withValues(alpha: 0.5),
              strokeWidth: 1.2,
              dashArray: [5, 4],
              label: HorizontalLineLabel(
                show: true,
                alignment: Alignment.topRight,
                style: const TextStyle(fontSize: 10, color: ChartColors.ink, fontWeight: FontWeight.w700),
                labelResolver: (_) => 'Target',
              ),
            ),
          ],
        ),
        titlesData: _noTitles().copyWith(
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 20,
              getTitlesWidget: (v, meta) {
                final i = v.toInt();
                if (i < 0 || i >= days.length) return const SizedBox.shrink();
                final d = DateTime.tryParse(days[i].$1);
                return SideTitleWidget(
                  meta: meta,
                  child: Text(d == null ? '' : '${d.day}', style: _labelStyle),
                );
              },
            ),
          ),
        ),
        barTouchData: BarTouchData(
          touchCallback: (event, response) {
            final i = response?.spot?.touchedBarGroupIndex;
            if (event is FlTapUpEvent && i != null && i >= 0 && i < days.length) {
              onTap?.call(days[i].$1);
            }
          },
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => ChartColors.ink,
            tooltipBorderRadius: BorderRadius.circular(8),
            getTooltipItem: (group, _, _, _) => BarTooltipItem(
              '${DateFormat('d MMM', 'en_IN').format(DateTime.parse(days[group.x].$1))}\n',
              const TextStyle(color: AppColors.line, fontSize: 11),
              children: [
                TextSpan(
                  text: '${days[group.x].$2.toStringAsFixed(0)}% of target',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < days.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: days[i].$2.clamp(0, maxY).toDouble(),
                  width: 12,
                  color: colorOf(days[i].$2),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                ),
              ],
            ),
        ],
      ),
      duration: const Duration(milliseconds: 300),
    );
  }
}

/// Cumulative approved spend over time against the budget line.
class SpendCurve extends StatelessWidget {
  const SpendCurve({
    super.key,
    required this.points,
    required this.budgetPaise,
    this.start,
    this.end,
    this.height = 226,
  });

  final List<(DateTime, int)> points;
  final int budgetPaise;
  final DateTime? start;
  final DateTime? end;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return const SizedBox(
        height: 60,
        child: Center(
          child: Text('No approved spend yet.', style: _labelStyle),
        ),
      );
    }
    final first = start != null && start!.isBefore(points.first.$1)
        ? start!
        : points.first.$1;
    var last = points.last.$1;
    if (end != null && end!.isAfter(last)) last = end!;
    final spanDays = math.max(1, last.difference(first).inDays).toDouble();
    double x(DateTime d) => d.difference(first).inDays.toDouble();
    final spent = points.last.$2;
    final maxY = math.max(budgetPaise, spent) * 1.12;
    final over = budgetPaise > 0 && spent > budgetPaise;
    final lineColor = over ? context.statusColors.bad : ChartColors.actual;
    final spots = [
      FlSpot(x(first), 0),
      for (final p in points) FlSpot(x(p.$1), p.$2.toDouble()),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: height,
          child: LineChart(
            LineChartData(
              minX: 0,
              maxX: spanDays,
              minY: 0,
              maxY: maxY <= 0 ? 1 : maxY,
              borderData: FlBorderData(show: false),
              gridData: FlGridData(
                drawVerticalLine: false,
                horizontalInterval: maxY <= 0 ? 1 : maxY / 4,
                getDrawingHorizontalLine: (_) =>
                    const FlLine(color: ChartColors.grid, strokeWidth: 1),
              ),
              titlesData: _noTitles().copyWith(
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 58,
                    interval: maxY <= 0 ? 1 : maxY / 4,
                    getTitlesWidget: (v, meta) => v == meta.max
                        ? const SizedBox.shrink()
                        : SideTitleWidget(
                            meta: meta,
                            child: Text(
                              Money.compact(v.round()),
                              style: _labelStyle,
                            ),
                          ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 24,
                    interval: math.max(1, spanDays / 4),
                    getTitlesWidget: (v, meta) => SideTitleWidget(
                      meta: meta,
                      fitInside: SideTitleFitInsideData.fromTitleMeta(
                        meta,
                        distanceFromEdge: 0,
                      ),
                      child: Text(
                        DateFormat(
                          'MMM yy',
                          'en_IN',
                        ).format(first.add(Duration(days: v.round()))),
                        style: _labelStyle,
                      ),
                    ),
                  ),
                ),
              ),
              extraLinesData: ExtraLinesData(
                horizontalLines: [
                  if (budgetPaise > 0)
                    HorizontalLine(
                      y: budgetPaise.toDouble(),
                      color: ChartColors.ink.withValues(alpha: 0.55),
                      strokeWidth: 1.5,
                      dashArray: [6, 4],
                      label: HorizontalLineLabel(
                        show: true,
                        alignment: Alignment.topLeft,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: ChartColors.ink,
                        ),
                        labelResolver: (_) =>
                            'Budget ${Money.compact(budgetPaise)}',
                      ),
                    ),
                ],
              ),
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) => ChartColors.ink,
                  tooltipBorderRadius: BorderRadius.circular(8),
                  getTooltipItems: (spots) => [
                    for (final s in spots)
                      LineTooltipItem(
                        '${DateFormat('d MMM yyyy', 'en_IN').format(first.add(Duration(days: s.x.round())))}\n',
                        const TextStyle(color: AppColors.line, fontSize: 11),
                        children: [
                          TextSpan(
                            text: '${Money.compact(s.y.round())} spent',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isStepLineChart: true,
                  color: lineColor,
                  barWidth: 2,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: true,
                    color: lineColor.withValues(alpha: 0.10),
                  ),
                ),
              ],
            ),
            duration: const Duration(milliseconds: 300),
          ),
        ),
        const SizedBox(height: 8),
        ChartLegend(
          items: [
            (lineColor, 'Approved spend to date'),
            if (budgetPaise > 0)
              (ChartColors.ink.withValues(alpha: 0.55), 'Budget'),
          ],
        ),
      ],
    );
  }
}

/// A stacked bar per row: spent, awaiting approval, then what is left.
class BudgetRow {
  const BudgetRow(
    this.label,
    this.budgetPaise,
    this.spentPaise,
    this.pendingPaise, {
    this.onTap,
  });

  final String label;
  final int budgetPaise;
  final int spentPaise;
  final int pendingPaise;
  final VoidCallback? onTap;
}

class BudgetRowsChart extends StatelessWidget {
  const BudgetRowsChart({super.key, required this.rows});

  final List<BudgetRow> rows;

  @override
  Widget build(BuildContext context) {
    final scale = rows.fold(
      1,
      (m, r) =>
          math.max(m, math.max(r.budgetPaise, r.spentPaise + r.pendingPaise)),
    );
    const legend = ChartLegend(
      items: [
        (ChartColors.actual, 'Spent'),
        (ChartColors.pending, 'Awaiting approval'),
        (ChartColors.remaining, 'Budget left'),
      ],
    );
    final list = [
      for (final r in rows)
        InkWell(
          onTap: r.onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        r.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Text(
                      r.budgetPaise == 0
                          ? '${Money.compact(r.spentPaise)} spent · no budget'
                          : r.spentPaise > r.budgetPaise
                          ? '${Money.compact(r.spentPaise - r.budgetPaise)} over'
                          : '${Money.compact(r.budgetPaise - r.spentPaise)} left of ${Money.compact(r.budgetPaise)}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: r.budgetPaise > 0 && r.spentPaise > r.budgetPaise
                            ? context.statusColors.bad
                            : AppColors.muted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Tooltip(
                  message:
                      'Budget ${Money.compact(r.budgetPaise)} · Spent ${Money.compact(r.spentPaise)} · Awaiting approval ${Money.compact(r.pendingPaise)}',
                  child: LayoutBuilder(
                    builder: (context, c) {
                      final w = c.maxWidth;
                      double width(int v) => v / scale * w;
                      final over =
                          r.budgetPaise > 0 && r.spentPaise > r.budgetPaise;
                      return SizedBox(
                        height: 12,
                        child: Stack(
                          children: [
                            Container(
                              width: width(r.budgetPaise),
                              decoration: BoxDecoration(
                                color: ChartColors.remaining,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            Row(
                              children: [
                                Container(
                                  width: width(r.spentPaise),
                                  decoration: BoxDecoration(
                                    color: over
                                        ? context.statusColors.bad
                                        : ChartColors.actual,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                                if (r.pendingPaise > 0) ...[
                                  const SizedBox(width: 2),
                                  Container(
                                    width: math.max(
                                      0,
                                      width(r.pendingPaise) - 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: ChartColors.pending,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
    ];
    return LayoutBuilder(
      builder: (context, c) => c.hasBoundedHeight
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: ListView(padding: EdgeInsets.zero, children: list),
                ),
                const SizedBox(height: 8),
                legend,
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [...list, const SizedBox(height: 6), legend],
            ),
    );
  }
}

class ChartLegend extends StatelessWidget {
  const ChartLegend({super.key, required this.items});

  final List<(Color, String)> items;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 16,
    runSpacing: 6,
    children: [
      for (final (color, label) in items)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(3),
                border: color == ChartColors.remaining
                    ? Border.all(color: AppColors.subtle)
                    : null,
              ),
            ),
            const SizedBox(width: 6),
            Text(label, style: _labelStyle),
          ],
        ),
    ],
  );
}

/// A titled chart panel with consistent padding, used in dashboard grids.
class ChartCard extends StatelessWidget {
  const ChartCard({
    super.key,
    required this.title,
    this.subtitle,
    required this.child,
    this.trailing,
    this.bodyHeight = 280,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? trailing;

  /// Fixed so cards side by side line up. Null lets the body size itself.
  final double? bodyHeight;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: AppRadius.card,
      border: Border.all(color: AppColors.line),
    ),
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
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.muted,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            ?trailing,
          ],
        ),
        const SizedBox(height: 16),
        if (bodyHeight == null)
          child
        else
          SizedBox(height: bodyHeight, child: child),
      ],
    ),
  );
}

/// Lays chart cards out two (or three) across on wide screens, stacked on phones.
class ChartGrid extends StatelessWidget {
  const ChartGrid({super.key, required this.children, this.minTileWidth = 380});

  final List<Widget> children;
  final double minTileWidth;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final columns = math.max(
        1,
        math.min(children.length, (c.maxWidth + 16) ~/ (minTileWidth + 16)),
      );
      final width = (c.maxWidth - (columns - 1) * 16) / columns;
      return Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          for (final child in children) SizedBox(width: width, child: child),
        ],
      );
    },
  );
}
