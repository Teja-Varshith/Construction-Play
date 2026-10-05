import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../core/config/app_config.dart';
import '../../../core/config/config_models.dart';
import '../../../core/config/config_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/work_day.dart';
import '../../../core/widgets/common.dart';
import '../../auth/data/session.dart';
import '../../auth/domain/app_user.dart';
import '../../finance/data/finance_repository.dart';
import '../../finance/domain/expense.dart';
import '../../users/data/user_repository.dart';
import '../data/project_detail_repository.dart';
import '../data/project_insight_provider.dart';
import '../domain/project.dart';
import '../domain/project_detail.dart';
import '../domain/project_insight.dart';
import 'project_dashboard.dart' show ProjectTabPage;

/// The reports a project can produce. Every figure comes from the same
/// source records and calculations as the dashboard, so a report always
/// matches what the CEO sees on screen.
enum ReportKind {
  status(
    'Project status report',
    'The whole picture for a review meeting.',
    Icons.assessment_outlined,
    ['Progress, schedule and forecast finish', 'Cost overrun, payables and speed', 'What is affecting the project', 'Every phase with its budget', 'Open issues'],
    money: false,
  ),
  cost(
    'Cost & payables report',
    'Where the money has gone and what is owed.',
    Icons.account_balance_wallet_outlined,
    ['Budget vs spend vs value of work done', 'Forecast cost at completion', 'Spend by phase and by category', 'Unpaid bills with their age', 'Bills awaiting approval'],
    money: true,
  ),
  daily(
    'Daily progress report',
    'What the site reported over a period.',
    Icons.event_note_outlined,
    ['Reports submitted and days missed', 'Output against daily targets', 'Each day’s quantities and notes'],
    money: false,
  ),
  issues(
    'Issues report',
    'Every site issue and who owns it.',
    Icons.flag_outlined,
    ['Open, in progress and resolved', 'Priority and age of each issue', 'Owner and details'],
    money: false,
  );

  const ReportKind(this.title, this.summary, this.icon, this.includes, {required this.money});
  final String title;
  final String summary;
  final IconData icon;
  final List<String> includes;

  /// Only people who can see the project's money may generate it.
  final bool money;
}

enum ReportPeriod {
  week('Last 7 days', 7),
  fortnight('Last 14 days', 14),
  month('Last 30 days', 30),
  all('Since start', null);

  const ReportPeriod(this.label, this.days);
  final String label;
  final int? days;
}

/// Project → Reports: pick a report and a period, preview it, download or print.
class ProjectReportsSection extends ConsumerStatefulWidget {
  const ProjectReportsSection({super.key, required this.project, required this.seeMoney});

  final Project project;
  final bool seeMoney;

  @override
  ConsumerState<ProjectReportsSection> createState() => _ProjectReportsSectionState();
}

class _ProjectReportsSectionState extends ConsumerState<ProjectReportsSection> {
  var _period = ReportPeriod.fortnight;

  @override
  Widget build(BuildContext context) {
    final kinds = ReportKind.values.where((k) => !k.money || widget.seeMoney).toList();
    return ProjectTabPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Reports', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          const Text(
            'Generate a PDF from the live project data, to download, print or share.',
            style: TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text('Period for daily reports and issues:', style: TextStyle(color: AppColors.muted)),
              for (final p in ReportPeriod.values)
                ChoiceChip(
                  label: Text(p.label),
                  selected: _period == p,
                  onSelected: (_) => setState(() => _period = p),
                ),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, c) {
              final columns = c.maxWidth >= 760 ? 2 : 1;
              final width = (c.maxWidth - (columns - 1) * 16) / columns;
              return Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  for (final k in kinds)
                    SizedBox(
                      width: width,
                      child: _ReportCard(kind: k, onGenerate: () => _generate(k)),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _generate(ReportKind kind) async {
    final id = widget.project.id;
    // Everything here is already loaded by the project screen.
    T need<T>(AsyncValue<T> v) => v.value ?? (throw StateError('Still loading. Try again in a moment.'));
    try {
      final data = ReportData(
        kind: kind,
        period: _period,
        insight: need(ref.read(projectInsightProvider(id))),
        expenses: need(ref.read(projectExpensesProvider(id))),
        budget: need(ref.read(projectBudgetProvider(id))),
        issues: need(ref.read(projectIssuesProvider(id))),
        reports: need(ref.read(projectDprsProvider(id))),
        users: ref.read(allUsersProvider).value ?? const [],
        config: ref.read(appConfigProvider),
        generatedBy: ref.read(currentUserProvider).name,
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => _ReportPreview(data: data),
        ),
      );
    } catch (e) {
      if (mounted) showMessage(context, 'Could not build the report: $e', error: true);
    }
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.kind, required this.onGenerate});

  final ReportKind kind;
  final VoidCallback onGenerate;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: AppRadius.card,
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: primary.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(10)),
                child: Icon(kind.icon, color: primary, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(kind.title, style: Theme.of(context).textTheme.titleMedium),
                    Text(kind.summary, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (final line in kind.includes)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.check, size: 15, color: context.statusColors.ok),
                  const SizedBox(width: 8),
                  Expanded(child: Text(line, style: const TextStyle(fontSize: 13, color: AppColors.inkSoft))),
                ],
              ),
            ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onGenerate,
            icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
            label: const Text('Generate PDF'),
          ),
        ],
      ),
    );
  }
}

class _ReportPreview extends StatelessWidget {
  const _ReportPreview({required this.data});

  final ReportData data;

  @override
  Widget build(BuildContext context) {
    final p = data.insight.project;
    final file = '${(p.code.isNotEmpty ? p.code : p.name).replaceAll(RegExp(r'[^A-Za-z0-9-]+'), '_')}'
        '_${data.kind.name}_${data.today}.pdf';
    return Scaffold(
      appBar: AppBar(title: Text('${data.kind.title} · ${p.name}')),
      body: PdfPreview(
        build: (format) => buildProjectReport(data, format),
        pdfFileName: file,
        canChangeOrientation: false,
        canChangePageFormat: false,
        canDebug: false,
        initialPageFormat: PdfPageFormat.a4,
        loadingWidget: const LoadingView(message: 'Building report…'),
      ),
    );
  }
}

/// Everything a report needs, captured at the moment it is generated.
class ReportData {
  ReportData({
    required this.kind,
    required this.period,
    required this.insight,
    required this.expenses,
    required this.budget,
    required this.issues,
    required this.reports,
    required this.users,
    required this.config,
    required this.generatedBy,
  });

  final ReportKind kind;
  final ReportPeriod period;
  final ProjectInsight insight;
  final List<Expense> expenses;
  final List<BudgetLine> budget;
  final List<ProjectIssue> issues;
  final List<DailyProgressReport> reports;
  final List<AppUser> users;
  final AppConfig config;
  final String generatedBy;

  String get today => insight.today;

  String person(String? uid) => users.where((u) => u.uid == uid).firstOrNull?.name ?? 'Unassigned';

  /// Keys on or after the period start.
  bool inPeriod(String dayKey) {
    final days = period.days;
    if (days == null) return true;
    final t = WorkDay.tryParse(today);
    final d = WorkDay.tryParse(dayKey);
    return t != null && d != null && t.difference(d).inDays < days;
  }

  bool dateInPeriod(DateTime? at) => at == null || inPeriod(WorkDay.fromDate(at));
}

// ---------------------------------------------------------------------------
// PDF
// ---------------------------------------------------------------------------

const _ink = PdfColor.fromInt(0xFF16202A);
const _muted = PdfColor.fromInt(0xFF5E6B78);
const _line = PdfColor.fromInt(0xFFE3E8EE);
const _brand = PdfColor.fromInt(0xFF1E4F8A);
const _bad = PdfColor.fromInt(0xFFB83A32);
const _warn = PdfColor.fromInt(0xFFB7791F);
const _soft = PdfColor.fromInt(0xFFF4F6F9);

/// Builds the PDF for [data]. Uses Noto Sans (for ₹ and Indian names) and
/// falls back to the built-in font when offline.
Future<Uint8List> buildProjectReport(ReportData data, PdfPageFormat format) async {
  pw.ThemeData theme;
  var rupee = '₹';
  try {
    final base = await PdfGoogleFonts.notoSansRegular();
    final bold = await PdfGoogleFonts.notoSansBold();
    // Offline, the download quietly falls back to Helvetica, which has no ₹.
    if (base is! pw.TtfFont) rupee = 'Rs ';
    theme = pw.ThemeData.withFont(base: base, bold: bold);
  } catch (_) {
    theme = pw.ThemeData.base();
    rupee = 'Rs ';
  }
  String money(int paise) => Money.compact(paise).replaceAll('₹', rupee);
  String moneyFull(int paise) => Money.format(paise).replaceAll('₹', rupee);

  final i = data.insight;
  final p = i.project;
  final company = data.config.company.name;
  final doc = pw.Document(title: '${data.kind.title} – ${p.name}', author: company);

  pw.Widget header(pw.Context ctx) => pw.Container(
    padding: const pw.EdgeInsets.only(bottom: 10),
    margin: const pw.EdgeInsets.only(bottom: 14),
    decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _line))),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(company.toUpperCase(), style: const pw.TextStyle(fontSize: 8, color: _muted, letterSpacing: 1.2)),
              pw.SizedBox(height: 3),
              pw.Text(data.kind.title, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: _ink)),
              pw.Text(
                [p.name, if (p.code.isNotEmpty) p.code, if (p.clientName.isNotEmpty) p.clientName].join('  ·  '),
                style: const pw.TextStyle(fontSize: 9.5, color: _muted),
              ),
            ],
          ),
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text('Generated ${WorkDay.display(data.today)}', style: const pw.TextStyle(fontSize: 8.5, color: _muted)),
            pw.Text('by ${data.generatedBy}', style: const pw.TextStyle(fontSize: 8.5, color: _muted)),
            if (data.kind == ReportKind.daily || data.kind == ReportKind.issues)
              pw.Text('Period: ${data.period.label}', style: const pw.TextStyle(fontSize: 8.5, color: _muted)),
          ],
        ),
      ],
    ),
  );

  pw.Widget footer(pw.Context ctx) => pw.Row(
    children: [
      pw.Expanded(
        child: pw.Text(
          "Figures are calculated from the project's records at the time of generation.",
          style: const pw.TextStyle(fontSize: 7.5, color: _muted),
        ),
      ),
      pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}', style: const pw.TextStyle(fontSize: 7.5, color: _muted)),
    ],
  );

  pw.Widget section(String title) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 14, bottom: 6),
    child: pw.Text(title, style: pw.TextStyle(fontSize: 11.5, fontWeight: pw.FontWeight.bold, color: _brand)),
  );

  pw.Widget kpis(List<(String, String, String?, PdfColor?)> items) => pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      for (var n = 0; n < items.length; n++) ...[
        if (n > 0) pw.SizedBox(width: 8),
        pw.Expanded(
          child: pw.Container(
            padding: const pw.EdgeInsets.all(9),
            decoration: pw.BoxDecoration(
              color: _soft,
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(items[n].$1, style: const pw.TextStyle(fontSize: 8, color: _muted)),
                pw.SizedBox(height: 2),
                pw.Text(items[n].$2, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: items[n].$4 ?? _ink)),
                if (items[n].$3 != null) ...[
                  pw.SizedBox(height: 2),
                  pw.Text(items[n].$3!, style: const pw.TextStyle(fontSize: 7.5, color: _muted)),
                ],
              ],
            ),
          ),
        ),
      ],
    ],
  );

  pw.Widget table(List<String> head, List<List<String>> rows, {Map<int, pw.Alignment>? align, Map<int, pw.TableColumnWidth>? widths}) {
    if (rows.isEmpty) {
      return pw.Text('None.', style: const pw.TextStyle(fontSize: 9, color: _muted));
    }
    return pw.TableHelper.fromTextArray(
      headers: head,
      data: rows,
      border: null,
      headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: _muted),
      headerDecoration: const pw.BoxDecoration(color: _soft),
      cellStyle: const pw.TextStyle(fontSize: 8.5, color: _ink),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
      rowDecoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _line, width: 0.5))),
      cellAlignments: align ?? const {},
      columnWidths: widths,
    );
  }

  String pct(double v) => '${v.toStringAsFixed(0)}%';
  PdfColor? badIf(bool b) => b ? _bad : null;
  final overrunBad = i.budgetPaise > 0 && i.earnedPaise > 0 && i.costOverrunPaise > i.earnedPaise * 0.05;
  String category(String id) => data.config.labelOf(ConfigList.expenseCategories, id);
  String priority(String id) => data.config.labelOf(ConfigList.issuePriorities, id);
  final phaseName = {for (final ph in i.phases) ph.phase.id: ph.phase.name};

  final pillars = kpis([
    (
      'Cost overrun',
      i.budgetPaise == 0 ? 'No budget' : (i.costOverrunPaise > 0 ? money(i.costOverrunPaise) : 'None'),
      i.budgetPaise == 0 ? null : 'Spent ${money(i.spentPaise)} for work worth ${money(i.earnedPaise)}',
      badIf(overrunBad),
    ),
    (
      'Payables',
      i.payablesPaise == 0 ? 'None' : money(i.payablesPaise),
      i.overduePayablesCount > 0 ? '${money(i.overduePayablesPaise)} over ${ProjectInsight.payableDueDays} days' : '${i.payablesCount} unpaid bills',
      badIf(i.overduePayablesCount > 0),
    ),
    (
      'Speed',
      i.speedPerWeek == null ? '-' : '${i.speedPerWeek!.toStringAsFixed(1)}% / week',
      i.requiredPerWeek == null ? null : 'Needs ${i.requiredPerWeek!.toStringAsFixed(1)}% / week',
      badIf((i.paceRatio ?? 1) < 0.85),
    ),
    (
      'Forecast finish',
      i.forecastFinish == null ? 'Not ready' : WorkDay.display(WorkDay.fromDate(i.forecastFinish!)),
      'Target ${WorkDay.display(p.endDate)}${i.finishSlipDays > 0 ? ' · ${i.finishSlipDays} days late' : ''}',
      badIf(i.finishSlipDays > 0),
    ),
  ]);

  final body = <pw.Widget>[];
  switch (data.kind) {
    case ReportKind.status:
      body.addAll([
        kpis([
          ('Work done', i.scheduleReady ? pct(i.analysis.actual) : '-', 'Planned by today ${pct(i.analysis.planned)}', null),
          ('Schedule', i.scheduleLabel, null, badIf(i.analysis.daysBehind > 0)),
          ('Phases', '${i.phasesDone} / ${i.phases.length} done', i.phasesLate > 0 ? '${i.phasesLate} running late' : null, badIf(i.phasesLate > 0)),
          ('Open issues', '${i.openIssues}', i.urgentIssues > 0 ? '${i.urgentIssues} high priority' : null, badIf(i.urgentIssues > 0)),
        ]),
        pw.SizedBox(height: 8),
        pillars,
        section('What is affecting the project'),
        if (i.factors.isEmpty)
          pw.Text('Nothing is slowing the project down or pushing costs up.', style: const pw.TextStyle(fontSize: 9.5))
        else
          for (final f in i.factors)
            pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 5),
              padding: const pw.EdgeInsets.only(left: 7),
              decoration: pw.BoxDecoration(
                border: pw.Border(left: pw.BorderSide(color: f.severe ? _bad : _warn, width: 2)),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(f.title, style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
                  pw.Text(f.detail, style: const pw.TextStyle(fontSize: 8.5, color: _muted)),
                ],
              ),
            ),
        section('Phases'),
        table(
          ['Phase', 'Planned window', 'Done', 'Planned', 'Status', 'Budget', 'Spent', 'Left'],
          [
            for (final ph in i.phases)
              [
                ph.phase.name,
                ph.phase.hasValidDates ? '${WorkDay.display(ph.phase.plannedStart)} – ${WorkDay.display(ph.phase.plannedEnd)}' : '-',
                pct(ph.phase.actualPct),
                pct(ph.plannedPct),
                ph.state.late && ph.daysLate > 0 ? '${ph.state.label} (${ph.daysLate}d)' : ph.state.label,
                ph.hasBudget ? money(ph.budgetPaise) : '-',
                money(ph.spentPaise),
                ph.hasBudget ? money(ph.remainingPaise) : '-',
              ],
          ],
          align: {2: pw.Alignment.centerRight, 3: pw.Alignment.centerRight, 5: pw.Alignment.centerRight, 6: pw.Alignment.centerRight, 7: pw.Alignment.centerRight},
        ),
        section('Open issues'),
        table(
          ['Issue', 'Priority', 'Status', 'Owner'],
          [
            for (final issue in data.issues.where((x) => x.isOpen))
              [issue.title, priority(issue.priorityId), issue.status == 'in-progress' ? 'In progress' : 'Open', data.person(issue.assigneeId)],
          ],
        ),
      ]);
    case ReportKind.cost:
      final payables = data.expenses.where((e) => e.isPayable).toList()..sort((a, b) => a.date.compareTo(b.date));
      final pending = data.expenses.where((e) => e.isPending).toList();
      final now = WorkDay.tryParse(data.today) ?? DateTime.now();
      final byCategory = <String, (int, int)>{};
      for (final b in data.budget) {
        byCategory[b.categoryId] = (b.plannedPaise, 0);
      }
      for (final e in data.expenses.where((e) => e.isApproved)) {
        final cur = byCategory[e.categoryId] ?? (0, 0);
        byCategory[e.categoryId] = (cur.$1, cur.$2 + e.amountPaise);
      }
      body.addAll([
        kpis([
          ('Budget', i.budgetPaise == 0 ? 'Not set' : money(i.budgetPaise), null, null),
          ('Spent (approved)', money(i.spentPaise), i.budgetUsedPct == null ? null : '${i.budgetUsedPct!.toStringAsFixed(0)}% of budget', null),
          ('Value of work done', money(i.earnedPaise), '${pct(i.analysis.actual)} complete', null),
          (
            'Forecast at completion',
            i.forecastCostPaise == null ? 'Too early' : money(i.forecastCostPaise!),
            i.forecastOverrunPaise == null ? null : (i.forecastOverrunPaise! > 0 ? '${money(i.forecastOverrunPaise!)} over budget' : 'Within budget'),
            badIf((i.forecastOverrunPaise ?? 0) > 0),
          ),
        ]),
        pw.SizedBox(height: 8),
        pillars,
        section('By phase'),
        table(
          ['Phase', 'Done', 'Budget', 'Spent', 'Awaiting approval', 'Left'],
          [
            for (final ph in i.phases)
              [
                ph.phase.name,
                pct(ph.phase.actualPct),
                ph.hasBudget ? money(ph.budgetPaise) : '-',
                money(ph.spentPaise),
                money(ph.pendingPaise),
                ph.hasBudget ? (ph.overBudget ? '${money(-ph.remainingPaise)} over' : money(ph.remainingPaise)) : '-',
              ],
          ],
          align: {1: pw.Alignment.centerRight, 2: pw.Alignment.centerRight, 3: pw.Alignment.centerRight, 4: pw.Alignment.centerRight, 5: pw.Alignment.centerRight},
        ),
        section('By category'),
        table(
          ['Category', 'Budget', 'Spent', 'Left'],
          [
            for (final e in byCategory.entries)
              [
                category(e.key),
                e.value.$1 == 0 ? '-' : money(e.value.$1),
                money(e.value.$2),
                e.value.$1 == 0 ? '-' : money(e.value.$1 - e.value.$2),
              ],
          ],
          align: {1: pw.Alignment.centerRight, 2: pw.Alignment.centerRight, 3: pw.Alignment.centerRight},
        ),
        section('Payables · approved bills not yet paid'),
        table(
          ['Paid to', 'Bill date', 'Phase', 'Days waiting', 'Amount'],
          [
            for (final e in payables)
              [e.payee, WorkDay.display(e.date), phaseName[e.phaseId] ?? '-', '${e.payableAgeDays(now)}', moneyFull(e.amountPaise)],
          ],
          align: {3: pw.Alignment.centerRight, 4: pw.Alignment.centerRight},
        ),
        section('Awaiting approval'),
        table(
          ['Paid to', 'Bill date', 'Category', 'Amount'],
          [for (final e in pending) [e.payee, WorkDay.display(e.date), category(e.categoryId), moneyFull(e.amountPaise)]],
          align: {3: pw.Alignment.centerRight},
        ),
      ]);
    case ReportKind.daily:
      final shown = data.reports.where((r) => data.inPeriod(r.date)).toList()..sort((a, b) => a.date.compareTo(b.date));
      final withPct = shown.where((r) => r.achievedPercent != null).toList();
      final avg = withPct.isEmpty ? null : withPct.fold(0.0, (s, r) => s + r.achievedPercent!) / withPct.length;
      final missing = i.missingReportDates.where(data.inPeriod).toList();
      String qty(num? v) => v == null ? '-' : (v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1));
      body.addAll([
        kpis([
          ('Reports submitted', '${shown.length}', data.period.label, null),
          ('Working days missed', '${missing.length}', 'Last two weeks, Sundays off', badIf(missing.length >= 3)),
          ('Average output', avg == null ? '-' : pct(avg), 'of the daily target', badIf(avg != null && avg < 85)),
          ('Work done', i.scheduleReady ? pct(i.analysis.actual) : '-', 'Planned ${pct(i.analysis.planned)}', null),
        ]),
        if (missing.isNotEmpty) ...[
          section('Days with no report'),
          pw.Text(missing.map(WorkDay.display).join(',  '), style: const pw.TextStyle(fontSize: 9)),
        ],
        section('Reports'),
        table(
          ['Date', 'Target', 'Achieved', 'Output', 'Notes'],
          [
            for (final r in shown)
              [
                WorkDay.display(r.date),
                '${qty(r.targetQuantity)} ${r.unit}',
                '${qty(r.achievedQuantity)} ${r.unit}',
                r.achievedPercent == null ? '-' : pct(r.achievedPercent!),
                r.notes,
              ],
          ],
          align: {3: pw.Alignment.centerRight},
          widths: {4: const pw.FlexColumnWidth(3)},
        ),
      ]);
    case ReportKind.issues:
      final shown = data.issues.where((x) => x.isOpen || data.dateInPeriod(x.reportedAt)).toList()
        ..sort((a, b) {
          int rank(ProjectIssue x) => switch (x.priorityId) { 'critical' => 0, 'high' => 1, 'medium' => 2, _ => 3 };
          final open = (b.isOpen ? 1 : 0) - (a.isOpen ? 1 : 0);
          return open != 0 ? open : rank(a).compareTo(rank(b));
        });
      final today = DateTime.now();
      body.addAll([
        kpis([
          ('Open', '${data.issues.where((x) => x.isOpen).length}', null, null),
          ('High priority open', '${i.urgentIssues}', null, badIf(i.urgentIssues > 0)),
          ('Resolved in period', '${shown.where((x) => !x.isOpen).length}', data.period.label, null),
        ]),
        section('Issues'),
        table(
          ['Issue', 'Priority', 'Status', 'Raised', 'Days open', 'Owner', 'Details'],
          [
            for (final x in shown)
              [
                x.title,
                priority(x.priorityId),
                switch (x.status) { 'in-progress' => 'In progress', 'resolved' || 'closed' => 'Resolved', _ => 'Open' },
                x.reportedAt == null ? '-' : WorkDay.display(WorkDay.fromDate(x.reportedAt!)),
                x.reportedAt == null || !x.isOpen ? '-' : '${today.difference(x.reportedAt!).inDays}',
                data.person(x.assigneeId),
                x.description,
              ],
          ],
          widths: {0: const pw.FlexColumnWidth(2), 6: const pw.FlexColumnWidth(3)},
        ),
      ]);
  }

  doc.addPage(
    pw.MultiPage(
      pageFormat: format,
      theme: theme,
      margin: const pw.EdgeInsets.fromLTRB(32, 30, 32, 28),
      header: header,
      footer: footer,
      build: (_) => body,
    ),
  );
  return doc.save();
}
