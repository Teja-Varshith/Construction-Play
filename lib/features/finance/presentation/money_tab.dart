import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/config/config_models.dart';
import '../../../core/config/config_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/work_day.dart';
import '../../../core/widgets/common.dart';
import '../../auth/data/session.dart';
import '../../projects/data/project_detail_repository.dart';
import '../../projects/data/project_insight_provider.dart';
import '../../projects/data/project_media.dart';
import '../../projects/presentation/insight_widgets.dart';
import '../../projects/domain/project.dart';
import '../../projects/domain/project_insight.dart';
import '../../projects/domain/project_nav.dart';
import '../../projects/presentation/project_dashboard.dart' show ProjectTabPage;
import '../../projects/presentation/project_nav_scope.dart';
import '../../settings/presentation/settings_common.dart';
import '../data/finance_repository.dart';
import '../domain/expense.dart';
import '../domain/finance_rules.dart';
import 'budget_editor.dart';
import 'expense_editor.dart';

const _line = AppColors.line;
const _muted = AppColors.muted;

enum _ExpenseFilter { all, pending, payables }

/// Budget against actual, by phase and by category, then every expense.
/// Every total here is summed from source expenses at read time (see
/// [FinanceSummary]) — nothing is stored and incremented, so it can never drift.
///
/// Understands these investigate requests (see ProjectLink): `pending` filters
/// to bills awaiting approval, `payables` to approved bills not yet paid,
/// `phase:<id>` to one phase's spend, and `overspend` highlights the phase
/// budgets.
class MoneyTab extends ConsumerStatefulWidget {
  const MoneyTab({super.key, required this.project, required this.canManage});

  final Project project;
  final bool canManage;

  @override
  ConsumerState<MoneyTab> createState() => _MoneyTabState();
}

class _MoneyTabState extends ConsumerState<MoneyTab> {
  var _filter = _ExpenseFilter.all;
  String? _phaseId;
  int? _applied;
  var _localSeq = 0;
  var _highlightExpenses = false;
  var _highlightPhases = false;

  @override
  Widget build(BuildContext context) {
    final project = widget.project;
    final canManage = widget.canManage;
    final finance = ref.watch(projectFinanceProvider(project.id));
    final config = ref.watch(appConfigProvider);
    final phases = ref.watch(projectPhasesProvider(project.id)).value ?? const [];
    final nav = ProjectNavScope.maybeOf(context);
    // Apply a new "investigate" request once; the user can change filters after.
    if (nav != null && nav.seq != _applied) {
      _applied = nav.seq;
      final focus = nav.focusFor(ProjectTab.money);
      final phase = nav.current.tab == ProjectTab.money ? nav.current.focusId('phase') : null;
      _highlightExpenses = focus == 'pending' || focus == 'payables' || phase != null;
      _highlightPhases = focus == 'overspend';
      if (focus == 'pending') {
        _filter = _ExpenseFilter.pending;
        _phaseId = null;
      }
      if (focus == 'payables') {
        _filter = _ExpenseFilter.payables;
        _phaseId = null;
      }
      if (phase != null) {
        _filter = _ExpenseFilter.all;
        _phaseId = phase;
      }
    }
    final seq = (nav?.seq ?? 0) * 1000 + _localSeq;
    return AsyncView(
      value: finance,
      data: (data) {
        final summary = FinanceSummary.calculate(
          expenses: data.expenses,
          budget: data.budget,
          actualPct: data.actualPct,
          today: data.today,
          labelOf: (id) => config.labelOf(ConfigList.expenseCategories, id),
        );
        final pendingCount = data.expenses.where((e) => e.isPending).length;
        final payables = data.expenses.where((e) => e.isPayable).toList();
        final today = DateTime.tryParse(data.today) ?? DateTime.now();
        final overdue = payables.where((e) => e.payableAgeDays(today) > ProjectInsight.payableDueDays).toList();
        final shown = data.expenses
            .where((e) => switch (_filter) {
              _ExpenseFilter.all => true,
              _ExpenseFilter.pending => e.isPending,
              _ExpenseFilter.payables => e.isPayable,
            })
            .where((e) => _phaseId == null || e.phaseId == _phaseId)
            .toList();
        // Oldest unpaid first, so the most overdue bill is on top.
        if (_filter == _ExpenseFilter.payables) shown.sort((a, b) => a.date.compareTo(b.date));
        final phaseName = phases.where((p) => p.id == _phaseId).firstOrNull?.name;
        final shownTotal = shown.fold(0, (s, e) => s + e.amountPaise);
        return ProjectTabPage(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Money', style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 4),
                        const Text('Budget against spend, by phase and by category.', style: TextStyle(color: _muted)),
                      ],
                    ),
                  ),
                  if (canManage)
                    FilledButton.icon(
                      onPressed: () => showExpenseEditor(context, project: project),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Log expense'),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              _SummaryRow(summary: summary),
              if (summary.alerts.isNotEmpty) ...[
                const SizedBox(height: 14),
                for (final alert in summary.alerts) _AlertBanner(alert: alert),
              ],
              FocusHighlight(
                active: _highlightPhases,
                seq: seq,
                child: _PhaseBudgets(
                  projectId: project.id,
                  onOpen: (phaseId) => setState(() {
                    _phaseId = phaseId;
                    _filter = _ExpenseFilter.all;
                    _highlightExpenses = true;
                    _highlightPhases = false;
                    _localSeq++;
                  }),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(child: Text('By category', style: Theme.of(context).textTheme.titleMedium)),
                  if (canManage)
                    TextButton(
                      onPressed: () => showBudgetEditor(context, project: project, budget: data.budget),
                      child: const Text('Edit budget'),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              if (summary.categories.isEmpty)
                const _EmptyNote(
                  icon: Icons.pie_chart_outline,
                  title: 'No budget or expenses yet',
                  message: 'Set a budget per category, or log the first expense, to see it here.',
                )
              else
                for (final c in summary.categories)
                  _CategoryRow(
                    category: c,
                    label: config.labelOf(ConfigList.expenseCategories, c.categoryId),
                  ),
              const SizedBox(height: 24),
              FocusHighlight(
                active: _highlightExpenses,
                seq: seq,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Expenses', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        ChoiceChip(
                          label: Text('All · ${data.expenses.length}'),
                          selected: _filter == _ExpenseFilter.all,
                          onSelected: (_) => setState(() => _filter = _ExpenseFilter.all),
                        ),
                        ChoiceChip(
                          label: Text('Awaiting approval · $pendingCount'),
                          selected: _filter == _ExpenseFilter.pending,
                          onSelected: (_) => setState(() => _filter = _ExpenseFilter.pending),
                        ),
                        ChoiceChip(
                          label: Text('Payables · ${payables.length}'),
                          selected: _filter == _ExpenseFilter.payables,
                          onSelected: (_) => setState(() => _filter = _ExpenseFilter.payables),
                        ),
                        if (phases.isNotEmpty)
                          DropdownButton<String?>(
                            value: phases.any((p) => p.id == _phaseId) ? _phaseId : null,
                            hint: const Text('All phases'),
                            underline: const SizedBox(),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            borderRadius: BorderRadius.circular(10),
                            items: [
                              const DropdownMenuItem<String?>(value: null, child: Text('All phases')),
                              for (final p in phases) DropdownMenuItem<String?>(value: p.id, child: Text(p.name)),
                            ],
                            onChanged: (v) => setState(() => _phaseId = v),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_filter == _ExpenseFilter.payables && payables.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: overdue.isEmpty ? AppColors.surfaceAlt : context.statusColors.badSoft,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${Money.compact(payables.fold(0, (s, e) => s + e.amountPaise))} owed across ${payables.length} approved bill${payables.length == 1 ? '' : 's'}'
                          '${overdue.isEmpty ? '. None is older than ${ProjectInsight.payableDueDays} days.' : ' · ${Money.compact(overdue.fold(0, (s, e) => s + e.amountPaise))} is more than ${ProjectInsight.payableDueDays} days old.'}',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: overdue.isEmpty ? AppColors.inkSoft : context.statusColors.bad,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (data.expenses.isEmpty)
                      const _EmptyNote(
                        icon: Icons.receipt_long_outlined,
                        title: 'No expenses logged',
                        message: 'Bills, categories and approval status will appear here once one is added.',
                      )
                    else if (shown.isEmpty)
                      _EmptyNote(
                        icon: Icons.filter_alt_off_outlined,
                        title: 'Nothing matches',
                        message: phaseName == null
                            ? 'No expenses for this filter.'
                            : 'No expenses tagged to $phaseName for this filter.',
                      )
                    else ...[
                      Text(
                        [
                          '${shown.length} expense${shown.length == 1 ? '' : 's'}',
                          Money.compact(shownTotal),
                          ?phaseName,
                        ].join(' · '),
                        style: const TextStyle(color: _muted, fontSize: 13),
                      ),
                      const SizedBox(height: 8),
                      for (final e in shown)
                        _ExpenseRow(
                          project: project,
                          expense: e,
                          config: config,
                          canManage: canManage,
                          phaseName: phases.where((p) => p.id == e.phaseId).firstOrNull?.name,
                        ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Budget, spend and what is left for each schedule phase. Phase budgets are
/// set on the phase itself (Timeline → Update); spend comes from expenses
/// tagged to that phase. Tapping a phase filters the expenses below to it.
class _PhaseBudgets extends ConsumerWidget {
  const _PhaseBudgets({required this.projectId, required this.onOpen});

  final String projectId;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final insight = ref.watch(projectInsightProvider(projectId)).value;
    if (insight == null || insight.phases.isEmpty) return const SizedBox.shrink();
    final allocated = insight.phaseBudgetPaise;
    final phaseSpent = insight.spentPaise - insight.unassignedSpentPaise;
    final unassigned = insight.unassignedSpentPaise;
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('By phase', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            allocated == 0
                ? 'No phase budgets yet. Set one on each phase in the Timeline tab, and tag expenses with their phase.'
                : [
                    '${Money.compact(allocated)} allocated to phases',
                    '${Money.compact(phaseSpent)} spent',
                    '${Money.compact(allocated - phaseSpent)} left',
                    if (unassigned > 0) '${Money.compact(unassigned)} spent without a phase',
                    'tap a phase to see its expenses',
                  ].join(' · '),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: _muted),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _line),
            ),
            child: PhaseBreakdown(phases: insight.phases, onOpen: (p) => onOpen(p.phase.id)),
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.summary});

  final FinanceSummary summary;

  @override
  Widget build(BuildContext context) {
    final used = summary.usedPct;
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 720 ? 4 : (constraints.maxWidth >= 420 ? 2 : 1);
        final width = (constraints.maxWidth - (columns - 1) * 10) / columns;
        Widget metric(String label, String value, {Color? accent}) => SizedBox(
          width: width,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: _line)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: _muted)),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: accent,
                  ),
                ),
              ],
            ),
          ),
        );
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            metric('Budget', Money.compact(summary.budgetPaise)),
            metric(
              'Spent',
              used == null ? Money.compact(summary.spentPaise) : '${Money.compact(summary.spentPaise)} (${used.toStringAsFixed(0)}%)',
              accent: used != null && used > 100 ? context.statusColors.bad : null,
            ),
            metric(
              'Pending approval',
              summary.pendingCount == 0 ? '—' : '${summary.pendingCount} · ${Money.compact(summary.pendingPaise)}',
            ),
            metric(
              'Forecast at completion',
              summary.forecastPaise == null ? 'Not enough progress yet' : Money.compact(summary.forecastPaise!),
            ),
          ],
        );
      },
    );
  }
}

class _AlertBanner extends StatelessWidget {
  const _AlertBanner({required this.alert});

  final FinanceAlert alert;

  @override
  Widget build(BuildContext context) {
    final color = alert.severe ? context.statusColors.bad : context.statusColors.warn;
    final soft = alert.severe ? context.statusColors.badSoft : context.statusColors.warnSoft;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: soft, border: Border.all(color: color.withValues(alpha: 0.4))),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(alert.message, style: TextStyle(color: color, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.category, required this.label});

  final CategorySpend category;
  final String label;

  @override
  Widget build(BuildContext context) {
    final used = category.usedPct;
    final over = used != null && used > 100;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: _line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800))),
              if (category.unbudgeted)
                Pill('Unbudgeted spend', color: context.statusColors.bad, background: context.statusColors.badSoft)
              else if (category.pendingPaise > 0)
                Pill('${Money.compact(category.pendingPaise)} pending'),
            ],
          ),
          const SizedBox(height: 8),
          if (!category.unbudgeted)
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                minHeight: 7,
                value: used == null ? 0 : (used / 100).clamp(0, 1),
                backgroundColor: AppColors.track,
                valueColor: AlwaysStoppedAnimation(over ? context.statusColors.bad : Theme.of(context).colorScheme.primary),
              ),
            ),
          const SizedBox(height: 6),
          Text(
            category.unbudgeted
                ? Money.compact(category.spentPaise)
                : '${Money.compact(category.spentPaise)} of ${Money.compact(category.plannedPaise)}'
                    '${category.originalPaise != null && category.originalPaise != category.plannedPaise ? ' (originally ${Money.compact(category.originalPaise!)})' : ''}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: _muted),
          ),
        ],
      ),
    );
  }
}

class _ExpenseRow extends ConsumerStatefulWidget {
  const _ExpenseRow({
    required this.project,
    required this.expense,
    required this.config,
    required this.canManage,
    this.phaseName,
  });

  final Project project;
  final Expense expense;
  final AppConfig config;
  final bool canManage;
  final String? phaseName;

  @override
  ConsumerState<_ExpenseRow> createState() => _ExpenseRowState();
}

class _ExpenseRowState extends ConsumerState<_ExpenseRow> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final e = widget.expense;
    final user = ref.watch(currentUserProvider);
    final canDecide = user.isCeo || user.isAdmin;
    final statusColor = switch (e.status) {
      ExpenseStatus.approved => context.statusColors.ok,
      ExpenseStatus.pending => context.statusColors.warn,
      ExpenseStatus.rejected => context.statusColors.bad,
      ExpenseStatus.voided => _muted,
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: _line)),
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
                    Text(e.payee, style: const TextStyle(fontWeight: FontWeight.w800)),
                    Text(
                      [
                        widget.config.labelOf(ConfigList.expenseCategories, e.categoryId),
                        ?widget.phaseName,
                        WorkDay.display(e.date),
                      ].join(' · '),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: _muted),
                    ),
                  ],
                ),
              ),
              Text(Money.format(e.amountPaise), style: const TextStyle(fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              Pill(
                e.status == ExpenseStatus.approved && e.autoApproved ? 'Auto-approved' : e.status.label,
                color: statusColor,
              ),
              if (e.isPaid)
                Pill('Paid${e.paymentRef.isEmpty ? '' : ' · ${e.paymentRef}'}', color: context.statusColors.ok)
              else if (e.isApproved)
                Pill(
                  'Unpaid · ${e.payableAgeDays(DateTime.now())} days',
                  color: e.payableAgeDays(DateTime.now()) > ProjectInsight.payableDueDays
                      ? context.statusColors.bad
                      : context.statusColors.warn,
                ),
              for (final flag in e.flags)
                if (ExpenseFlag.fromValue(flag) != null)
                  Pill(ExpenseFlag.fromValue(flag)!.label, color: context.statusColors.warn),
            ],
          ),
          if (e.description.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(e.description, style: Theme.of(context).textTheme.bodySmall),
          ],
          if (e.status == ExpenseStatus.rejected && e.rejectReason.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Rejected: ${e.rejectReason}', style: TextStyle(color: context.statusColors.bad)),
          ],
          if (e.status == ExpenseStatus.voided && e.voidReason.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Voided: ${e.voidReason}', style: const TextStyle(color: _muted)),
          ],
          if (e.billPath != null) ...[
            const SizedBox(height: 8),
            SizedBox(height: 90, width: 90, child: ProjectPhoto(path: e.billPath!)),
          ],
          Wrap(
            spacing: 8,
            children: [
              if (widget.canManage && e.status != ExpenseStatus.voided)
                TextButton.icon(
                  onPressed: _busy ? null : () => showExpenseEditor(context, project: widget.project, expense: e),
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('Update'),
                ),
              if (canDecide && e.isPending) ...[
                TextButton(
                  onPressed: _busy ? null : () => _decide(true),
                  child: const Text('Approve'),
                ),
                TextButton(
                  onPressed: _busy ? null : () => _decide(false),
                  child: Text('Reject', style: TextStyle(color: context.statusColors.bad)),
                ),
              ],
              if (canDecide && e.isPayable)
                TextButton.icon(
                  onPressed: _busy ? null : _markPaid,
                  icon: const Icon(Icons.payments_outlined, size: 16),
                  label: const Text('Mark paid'),
                ),
              if (user.isAdmin && e.isApproved)
                TextButton(
                  onPressed: _busy ? null : _void,
                  child: Text('Void', style: TextStyle(color: context.statusColors.bad)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _decide(bool approve) async {
    String reason = '';
    if (!approve) {
      final entered = await askText(
        context,
        title: 'Reject expense',
        label: 'Reason',
      );
      if (entered == null) return;
      reason = entered;
    }
    await _run(() => ref
        .read(financeRepositoryProvider)
        .decide(widget.expense.id, approve, reason, ref.read(currentUserProvider).uid));
  }

  Future<void> _markPaid() async {
    final paymentRef = await askText(
      context,
      title: 'Mark ${widget.expense.payee} paid',
      label: 'Payment reference (cheque no. / UTR)',
    );
    if (paymentRef == null) return;
    await _run(() => ref
        .read(financeRepositoryProvider)
        .markPaid(widget.expense.id, paymentRef, ref.read(currentUserProvider).uid));
  }

  Future<void> _void() async {
    final reason = await askText(context, title: 'Void expense', label: 'Reason');
    if (reason == null) return;
    await _run(() => ref
        .read(financeRepositoryProvider)
        .voidExpense(widget.expense.id, reason, ref.read(currentUserProvider).uid));
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) showMessage(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _EmptyNote extends StatelessWidget {
  const _EmptyNote({required this.icon, required this.title, required this.message});

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: _line)),
    child: Column(
      children: [
        Icon(icon, size: 40, color: Theme.of(context).colorScheme.outline),
        const SizedBox(height: 12),
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: _muted),
        ),
      ],
    ),
  );
}
