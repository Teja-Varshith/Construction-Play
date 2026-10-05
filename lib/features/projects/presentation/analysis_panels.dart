import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/config/config_models.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/work_day.dart';
import '../../finance/data/finance_repository.dart';
import '../../finance/domain/expense.dart';
import '../domain/project_insight.dart';
import '../domain/project_nav.dart';

/// Plain analysis cards for the three numbers a project is run on: cost
/// overrun, payables and schedule. Each is a light panel with a heading,
/// two or three number boxes (only the bad one turns red), a small table of
/// what is behind the number, and one button to the detail.
class AnalysisPanel extends StatelessWidget {
  const AnalysisPanel({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.children,
    this.cta,
    this.onCta,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final List<Widget> children;
  final String? cta;
  final VoidCallback? onCta;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: const Color(0xFFEFF3FA), borderRadius: BorderRadius.circular(AppRadius.lg)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.14), shape: BoxShape.circle),
              child: Icon(icon, color: iconColor, size: 21),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.inkSoft),
              ),
            ),
          ],
        ),
        const Padding(padding: EdgeInsets.symmetric(vertical: 14), child: Divider(height: 1, color: Color(0xFFDDE3EE))),
        ...children,
        if (cta != null) ...[
          const SizedBox(height: 14),
          FilledButton(
            onPressed: onCta,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [Text(cta!), const SizedBox(width: 8), const Icon(Icons.arrow_forward_rounded, size: 20)],
            ),
          ),
        ],
      ],
    ),
  );
}

/// A number in a white box; [bad] fills it red with an up arrow.
class StatBox extends StatelessWidget {
  const StatBox({super.key, required this.label, required this.value, this.bad = false});

  final String label;
  final String value;
  final bool bad;

  @override
  Widget build(BuildContext context) {
    final red = context.statusColors.bad;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 10, 11),
      decoration: BoxDecoration(color: bad ? red : Colors.white, borderRadius: BorderRadius.circular(AppRadius.sm)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12.5, color: bad ? Colors.white.withValues(alpha: 0.9) : AppColors.muted),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: bad ? Colors.white : AppColors.ink),
                ),
              ),
              if (bad) ...[const SizedBox(width: 6), const Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 20)],
            ],
          ),
        ],
      ),
    );
  }
}

/// Number boxes side by side (stacked two-up on narrow screens).
class StatRow extends StatelessWidget {
  const StatRow({super.key, required this.boxes});

  final List<StatBox> boxes;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final gap = c.maxWidth < 420 ? 6.0 : 10.0;
      final w = (c.maxWidth - (boxes.length - 1) * gap) / boxes.length;
      return MediaQuery(
        // Smaller numbers when three boxes share a phone's width.
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(w < 120 ? 0.86 : 1)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var n = 0; n < boxes.length; n++) ...[
              if (n > 0) SizedBox(width: gap),
              Expanded(child: boxes[n]),
            ],
          ],
        ),
      );
    },
  );
}

/// One table cell: main text, optional small line under it, optional colour.
class Cell {
  const Cell(this.text, {this.sub, this.color, this.bold = false});

  final String text;
  final String? sub;
  final Color? color;
  final bool bold;
}

/// A small white table with a header row. [alert] outlines it in red, for
/// "what is causing this" tables.
class SimpleTable extends StatelessWidget {
  const SimpleTable({super.key, required this.headers, required this.rows, this.alert = false, this.footer, this.flex});

  final List<String> headers;
  final List<List<Cell>> rows;
  final bool alert;
  final (String, String)? footer;

  /// Column widths; the first column gets more by default.
  final List<int>? flex;

  @override
  Widget build(BuildContext context) {
    final red = context.statusColors.bad;
    final border = alert ? red : Colors.white;
    final widths = flex ?? [3, for (var n = 1; n < headers.length; n++) 2];
    Widget row(List<Widget> cells, {bool header = false}) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [for (var n = 0; n < cells.length; n++) Expanded(flex: widths[n], child: cells[n])],
      ),
    );
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: border, width: alert ? 1.2 : 0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          row([
            for (final h in headers)
              Text(h, style: const TextStyle(color: AppColors.inkSoft, fontWeight: FontWeight.w600, fontSize: 13.5)),
          ], header: true),
          Divider(height: 1, color: alert ? red : AppColors.line),
          for (final r in rows)
            row([
              for (final c in r)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.text,
                      style: TextStyle(
                        color: c.color ?? AppColors.ink,
                        fontWeight: c.bold || c.color != null ? FontWeight.w700 : FontWeight.w500,
                        fontSize: 14,
                      ),
                    ),
                    if (c.sub != null)
                      Text(c.sub!, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                  ],
                ),
            ]),
          if (footer != null) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text('${footer!.$1}  ', style: const TextStyle(color: AppColors.inkSoft)),
                  Text(footer!.$2, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The three panels for one project, in a responsive grid.
class ProjectAnalysisPanels extends ConsumerWidget {
  const ProjectAnalysisPanels({
    super.key,
    required this.insight,
    required this.config,
    required this.seeMoney,
    required this.open,
  });

  final ProjectInsight insight;
  final AppConfig config;
  final bool seeMoney;
  final void Function(ProjectLink link) open;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final i = insight;
    final panels = <Widget>[
      if (seeMoney && i.budgetPaise > 0) _costPanel(context, i),
      if (seeMoney) _payablesPanel(context, ref, i),
      if (i.scheduleReady) _schedulePanel(context, i),
    ];
    if (panels.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, c) {
        final columns = c.maxWidth >= 1000 ? 2 : 1;
        final w = (c.maxWidth - (columns - 1) * 16) / columns;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [for (final p in panels) SizedBox(width: w, child: p)],
        );
      },
    );
  }

  Widget _costPanel(BuildContext context, ProjectInsight i) {
    final red = context.statusColors.bad;
    final over = i.costOverrunPaise;
    final bad = i.earnedPaise > 0 && over > i.earnedPaise * 0.05;
    // Phases spending more than the work they have done is worth.
    final rows = <(PhaseInsight, int)>[
      for (final p in i.phases)
        if (p.budgetPaise > 0 && p.spentPaise > (p.budgetPaise * p.phase.actualPct / 100).round())
          (p, p.spentPaise - (p.budgetPaise * p.phase.actualPct / 100).round()),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    return AnalysisPanel(
      icon: Icons.currency_rupee_rounded,
      iconColor: const Color(0xFFB66A00),
      title: 'Cost overrun',
      cta: 'See detailed analysis',
      onCta: () => open(const ProjectLink(ProjectTab.money, 'overspend')),
      children: [
        StatRow(
          boxes: [
            StatBox(label: 'Budget for work done', value: Money.compact(i.earnedPaise)),
            StatBox(label: 'Actual cost', value: Money.compact(i.spentPaise)),
            StatBox(label: bad ? 'Cost overrun' : 'Overrun', value: over > 0 ? Money.compact(over) : 'None', bad: bad),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '${i.analysis.actual.toStringAsFixed(0)}% of the work is done, worth ${Money.compact(i.earnedPaise)} '
          'of the ${Money.compact(i.budgetPaise)} budget.',
          style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
        ),
        const SizedBox(height: 14),
        if (rows.isEmpty)
          const _Plain('No phase is spending more than its work done.')
        else ...[
          Text('Work contributing to cost overrun', style: TextStyle(color: red, fontSize: 13.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          SimpleTable(
            alert: true,
            headers: const ['Work', 'Spent', 'Over by'],
            rows: [
              for (final (p, by) in rows.take(4))
                [
                  Cell(p.phase.name, sub: _dates(p.phase.plannedStart, p.phase.plannedEnd)),
                  Cell(Money.compact(p.spentPaise), sub: 'of ${Money.compact(p.budgetPaise)}'),
                  Cell(Money.compact(by), color: red),
                ],
            ],
          ),
        ],
      ],
    );
  }

  Widget _payablesPanel(BuildContext context, WidgetRef ref, ProjectInsight i) {
    final expenses = ref.watch(projectExpensesProvider(i.project.id)).value ?? const <Expense>[];
    final byCategory = <String, (int, int)>{};
    for (final e in expenses.where((e) => e.isApproved)) {
      final (total, unpaid) = byCategory[e.categoryId] ?? (0, 0);
      byCategory[e.categoryId] = (total + e.amountPaise, unpaid + (e.isPaid ? 0 : e.amountPaise));
    }
    // Only categories with money still owed; the total covers everything.
    final rows = byCategory.entries.where((e) => e.value.$2 > 0).toList()..sort((a, b) => b.value.$2.compareTo(a.value.$2));
    final balance = rows.fold(0, (s, e) => s + e.value.$2);
    final red = context.statusColors.bad;
    return AnalysisPanel(
      icon: Icons.account_balance_wallet_outlined,
      iconColor: const Color(0xFF12855A),
      title: 'Payables',
      cta: 'See detailed payables',
      onCta: () => open(const ProjectLink(ProjectTab.money, 'payables')),
      children: [
        StatRow(
          boxes: [
            StatBox(label: 'Unpaid bills', value: Money.compact(i.payablesPaise)),
            StatBox(
              label: 'Overdue (30+ days)',
              value: i.overduePayablesPaise > 0 ? Money.compact(i.overduePayablesPaise) : 'None',
              bad: i.overduePayablesPaise > 0,
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (rows.isEmpty)
          _Plain(byCategory.isEmpty ? 'No approved bills yet.' : 'Every approved bill is paid.')
        else
          SimpleTable(
            headers: const ['Category', 'Total', 'Balance'],
            rows: [
              for (final e in rows.take(5))
                [
                  Cell(config.labelOf(ConfigList.expenseCategories, e.key)),
                  Cell(Money.compact(e.value.$1)),
                  Cell(Money.compact(e.value.$2), bold: e.value.$2 > 0),
                ],
            ],
            footer: ('Total balance', Money.compact(balance)),
          ),
        if (i.overduePayablesCount > 0) ...[
          const SizedBox(height: 8),
          Text(
            '${i.overduePayablesCount} bill${i.overduePayablesCount == 1 ? '' : 's'} unpaid for over '
            '${ProjectInsight.payableDueDays} days. Vendors may slow supply.',
            style: TextStyle(color: red, fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
        ],
      ],
    );
  }

  Widget _schedulePanel(BuildContext context, ProjectInsight i) {
    final red = context.statusColors.bad;
    final a = i.analysis;
    final late = i.phases.where((p) => p.state.late).toList()..sort((x, y) => y.daysLate.compareTo(x.daysLate));
    final behind = a.daysBehind > 0;
    return AnalysisPanel(
      icon: Icons.schedule_rounded,
      iconColor: const Color(0xFF3557D6),
      title: 'Schedule',
      cta: 'See timeline',
      onCta: () => open(const ProjectLink(ProjectTab.timeline)),
      children: [
        StatRow(
          boxes: [
            StatBox(label: 'Planned by today', value: '${a.planned.toStringAsFixed(0)}%'),
            StatBox(label: 'Work done', value: '${a.actual.toStringAsFixed(0)}%'),
            StatBox(label: behind ? 'Behind by' : 'Delay', value: behind ? '${a.daysBehind} days' : 'None', bad: behind),
          ],
        ),
        if (i.requiredPerWeek != null && i.speedPerWeek != null) ...[
          const SizedBox(height: 6),
          Text(
            'Doing ${i.speedPerWeek!.toStringAsFixed(1)}% a week; needs ${i.requiredPerWeek!.toStringAsFixed(1)}% a week to finish on '
            '${WorkDay.display(i.project.endDate)}.',
            style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
          ),
        ],
        const SizedBox(height: 14),
        if (late.isEmpty)
          const _Plain('Every phase is on time.')
        else ...[
          Text('Work running late', style: TextStyle(color: red, fontSize: 13.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          SimpleTable(
            alert: true,
            headers: const ['Work', 'Done', 'Late by'],
            rows: [
              for (final p in late.take(4))
                [
                  Cell(p.phase.name, sub: 'due ${WorkDay.display(p.phase.plannedEnd)}'),
                  Cell('${p.phase.actualPct.toStringAsFixed(0)}%', sub: 'plan ${p.plannedPct.toStringAsFixed(0)}%'),
                  Cell(p.daysLate > 0 ? '${p.daysLate} days' : p.state.label, color: red),
                ],
            ],
          ),
        ],
      ],
    );
  }

  static String _dates(String? start, String? end) {
    if (start == null && end == null) return '';
    String short(String? k) {
      final d = WorkDay.tryParse(k);
      if (d == null) return '?';
      const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${d.day} ${m[d.month - 1]}';
    }

    return '${short(start)} – ${short(end)}';
  }
}

class _Plain extends StatelessWidget {
  const _Plain(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AppRadius.sm)),
    child: Row(
      children: [
        Icon(Icons.check_circle_outline, color: context.statusColors.ok, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: const TextStyle(color: AppColors.inkSoft))),
      ],
    ),
  );
}
