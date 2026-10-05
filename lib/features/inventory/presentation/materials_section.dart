import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/config_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/work_day.dart';
import '../../../core/widgets/common.dart';
import '../../auth/data/session.dart';
import '../../auth/domain/app_user.dart';
import '../../finance/data/finance_repository.dart';
import '../../finance/domain/expense.dart';
import '../../finance/presentation/expense_editor.dart';
import '../../projects/data/project_detail_repository.dart';
import '../../projects/domain/project.dart';
import '../../projects/domain/project_detail.dart';
import '../../projects/domain/project_nav.dart';
import '../../projects/presentation/ceo_ui.dart';
import '../../projects/presentation/project_dashboard.dart' show ProjectTabPage;
import '../../projects/presentation/project_nav_scope.dart';
import '../../users/data/user_repository.dart';
import '../data/inventory_repository.dart';
import '../domain/inventory.dart';
import 'indent_dialogs.dart';
import 'material_actions.dart';
import 'material_form_dialog.dart';
import 'stock_ledger_sheet.dart';
import '../../../core/widgets/art.dart';

enum _View {
  indents('Indents', Icons.assignment_outlined),
  stock('Stock', Icons.inventory_2_outlined),
  received('Deliveries', Icons.move_to_inbox_outlined),
  issued('Used on site', Icons.outbox_outlined);

  const _View(this.label, this.icon);
  final String label;
  final IconData icon;
}

enum _IndentFilter {
  active('Active'),
  waiting('Waiting approval'),
  late('Late'),
  open('Awaiting delivery'),
  done('Completed'),
  rejected('Rejected'),
  all('All');

  const _IndentFilter(this.label);
  final String label;
}

/// Project → Materials: site stores with approvals. The site raises indents,
/// the project manager or CEO/admin approves them, the manager records what
/// arrives (GRN, one or more per indent), and the site issues material to the
/// work. Stock, days of stock left and material cost by phase are all worked
/// out here from those records.
class MaterialsSection extends ConsumerStatefulWidget {
  const MaterialsSection({
    super.key,
    required this.project,
    required this.canRequest,
    required this.canReceive,
    required this.canApprove,
    this.seeMoney = false,
  });

  final Project project;

  /// Raise indents and issue material (site team).
  final bool canRequest;

  /// Record deliveries (project manager / admin).
  final bool canReceive;

  /// Approve, reject and close indents (project manager, CEO, admin).
  final bool canApprove;

  /// Show rates and values, and book deliveries as expenses.
  final bool seeMoney;

  @override
  ConsumerState<MaterialsSection> createState() => _MaterialsSectionState();
}

class _MaterialsSectionState extends ConsumerState<MaterialsSection> {
  var _view = _View.indents;
  var _filter = _IndentFilter.active;
  String? _phaseId;
  var _lowOnly = false;
  var _query = '';
  int? _applied;

  /// Switch to the indent list with [filter] (and optionally one phase).
  void _show(_IndentFilter filter, {String? phase}) {
    _view = _View.indents;
    _filter = filter;
    _phaseId = phase;
  }

  bool _matches(String text) => _query.isEmpty || text.toLowerCase().contains(_query.toLowerCase());

  bool _inFilter(Indent x, _IndentFilter f, String today) => switch (f) {
    _IndentFilter.active => x.isPending || x.isOpen,
    _IndentFilter.waiting => x.isPending,
    _IndentFilter.late => x.isLate(today),
    _IndentFilter.open => x.isOpen,
    _IndentFilter.done => x.isDone,
    _IndentFilter.rejected => x.status == IndentStatus.rejected,
    _IndentFilter.all => true,
  };

  @override
  Widget build(BuildContext context) {
    final pid = widget.project.id;
    final indents = ref.watch(projectIndentsProvider(pid)).value ?? const <Indent>[];
    final grns = ref.watch(projectGrnsProvider(pid)).value ?? const <Grn>[];
    final issues = ref.watch(projectMaterialIssuesProvider(pid)).value ?? const <MaterialIssue>[];
    final summary = ref.watch(projectInventoryProvider(pid));
    final phases = ref.watch(projectPhasesProvider(pid)).value ?? const <ProjectPhase>[];
    final people = ref.watch(allUsersProvider).value ?? const <AppUser>[];
    final uid = ref.watch(currentUserProvider).uid;
    final config = ref.watch(appConfigProvider);
    final today = WorkDay.today(utcOffsetMinutes: config.company.utcOffsetMinutes);
    final canBook = widget.canReceive && widget.seeMoney;
    final expenses = canBook ? ref.watch(projectExpensesProvider(pid)).value ?? const <Expense>[] : const <Expense>[];
    final booked = {
      for (final e in expenses)
        if (e.grnId != null && e.status != ExpenseStatus.voided) e.grnId!,
    };

    final nav = ProjectNavScope.maybeOf(context);
    final focusIndent = nav?.current.tab == ProjectTab.materials ? nav!.current.focusId('indent') : null;
    if (nav != null && nav.seq != _applied) {
      _applied = nav.seq;
      final focus = nav.focusFor(ProjectTab.materials);
      final phase = nav.current.tab == ProjectTab.materials ? nav.current.focusId('phase') : null;
      if (focus == 'pending') _show(_IndentFilter.waiting);
      if (focus == 'late') _show(_IndentFilter.late);
      if (focus == 'low') {
        _view = _View.stock;
        _lowOnly = true;
      }
      if (focus == 'unbooked') _view = _View.received;
      if (focusIndent != null) _show(_IndentFilter.all);
      if (phase != null) _show(_IndentFilter.all, phase: phase);
    }
    String phaseName(String? id) => id == null ? '' : phases.where((p) => p.id == id).firstOrNull?.name ?? '';
    String person(String? id) => people.where((u) => u.uid == id).firstOrNull?.name ?? 'Someone';

    return ProjectTabPage(
      child: AsyncView(
        value: summary,
        data: (s) {
          final actions = _Actions(
            raise: widget.canRequest ? ({List<MaterialLine> prefill = const []}) => _raise(context, prefill) : null,
            receive: widget.canReceive ? ({Indent? against}) => _receive(context, s, today, against) : null,
            issue: widget.canRequest && s.stock.any((l) => l.inStock > 1e-9)
                ? ({StockLine? line}) => _issue(context, s, phases, today, issues, line)
                : null,
          );

          bool indentText(Indent x) => _matches('${x.number} ${x.summary} ${x.note} ${phaseName(x.phaseId)}');
          bool inPhase(Indent x) => _phaseId == null || x.phaseId == _phaseId;
          int count(_IndentFilter f) => indents.where((x) => _inFilter(x, f, today) && inPhase(x) && indentText(x)).length;
          final shownIndents = indents.where((x) => _inFilter(x, _filter, today) && inPhase(x) && indentText(x)).toList();
          // Late and waiting first, then the rest; newest first within each (stable sort).
          int rank(Indent x) => x.isLate(today) ? 0 : (x.isPending ? 1 : (x.isOpen ? 2 : 3));
          mergeSort(shownIndents, compare: (a, b) => rank(a).compareTo(rank(b)));

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(project: widget.project, actions: actions),
              const SizedBox(height: 16),
              _Metrics(
                summary: s,
                seeMoney: widget.seeMoney,
                onWaiting: () => setState(() => _show(_IndentFilter.waiting)),
                onLate: () => setState(() => _show(_IndentFilter.late)),
                onLow: () => setState(() {
                  _view = _View.stock;
                  _lowOnly = true;
                }),
                onValue: () => setState(() => _view = _View.stock),
                onOpen: () => setState(() => _show(_IndentFilter.open)),
              ),
              _Attention(
                summary: s,
                today: today,
                canApprove: widget.canApprove,
                actions: actions,
                onWaiting: () => setState(() => _show(_IndentFilter.waiting)),
                onLate: () => setState(() => _show(_IndentFilter.late)),
                onStock: (l) => _ledger(context, l, phaseName, actions),
              ),
              const SizedBox(height: 20),
              _Toolbar(
                view: _view,
                counts: {
                  _View.indents: indents.where((x) => x.isPending || x.isOpen).length,
                  _View.stock: s.stock.length,
                  _View.received: grns.length,
                  _View.issued: issues.length,
                },
                query: _query,
                onView: (v) => setState(() => _view = v),
                onQuery: (q) => setState(() => _query = q),
              ),
              const SizedBox(height: 14),
              switch (_view) {
                _View.indents => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final f in _IndentFilter.values)
                          ChoiceChip(
                            label: Text('${f.label} · ${count(f)}'),
                            selected: _filter == f,
                            onSelected: (_) => setState(() => _filter = f),
                          ),
                        if (_phaseId != null)
                          InputChip(
                            avatar: const Icon(Icons.view_timeline_outlined, size: 16),
                            label: Text(phaseName(_phaseId).isEmpty ? 'Phase' : phaseName(_phaseId)),
                            onDeleted: () => setState(() => _phaseId = null),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (shownIndents.isEmpty)
                      _Empty(
                        icon: Icons.assignment_outlined,
                        text: indents.isEmpty
                            ? 'No indents yet. The site raises one when it needs material.'
                            : 'No indents match this filter.',
                        action: indents.isEmpty && actions.raise != null
                            ? TextButton.icon(
                                onPressed: () => actions.raise!(),
                                icon: const Icon(Icons.add, size: 18),
                                label: const Text('Raise the first indent'),
                              )
                            : null,
                      )
                    else
                      for (final x in shownIndents)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: FocusHighlight(
                            active: focusIndent == x.id,
                            seq: nav?.seq ?? 0,
                            child: _IndentCard(
                              indent: x,
                              summary: s,
                              today: today,
                              phase: phaseName(x.phaseId),
                              person: person,
                              deliveries: grns.where((g) => g.indentId == x.id).toList(),
                              canApprove: widget.canApprove,
                              canWithdraw: x.isPending && x.requestedBy == uid && widget.canRequest,
                              onDecide: (approve) => _decide(context, x, approve),
                              onReceive: actions.receive == null ? null : () => actions.receive!(against: x),
                              onClose: () => _close(context, x),
                              onWithdraw: () => _withdraw(context, x),
                            ),
                          ),
                        ),
                  ],
                ),
                _View.stock => _StockView(
                  stock: s.stock.where((l) => _matches(l.material) && (!_lowOnly || l.low)).toList(),
                  total: s.stock.length,
                  lowOnly: _lowOnly,
                  seeMoney: widget.seeMoney,
                  onLowOnly: (v) => setState(() => _lowOnly = v),
                  onOpen: (l) => _ledger(context, l, phaseName, actions),
                ),
                _View.received => _Deliveries(
                  grns: grns
                      .where((g) => _matches('${g.number} ${g.vendor} ${g.invoiceNo} ${g.items.map((l) => l.material).join(' ')}'))
                      .toList(),
                  indents: indents,
                  seeMoney: widget.seeMoney,
                  booked: booked,
                  person: person,
                  onBook: canBook ? (g) => _book(context, g, indents) : null,
                  onRecord: actions.receive == null ? null : () => actions.receive!(),
                ),
                _View.issued => _Usage(
                  summary: s,
                  issues: issues
                      .where((i) => _matches('${i.number} ${i.issuedTo} ${phaseName(i.phaseId)} ${i.items.map((l) => l.material).join(' ')}'))
                      .toList(),
                  seeMoney: widget.seeMoney,
                  phaseName: phaseName,
                  person: person,
                  onPhase: (id) => openProjectLink(context, pid, ProjectLink(ProjectTab.timeline, 'phase:$id')),
                ),
              },
            ],
          );
        },
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Actions
  // -------------------------------------------------------------------------

  Future<void> _run(BuildContext context, Future<void> Function() action, String done) async {
    try {
      await action();
      if (context.mounted) showMessage(context, done);
    } catch (e) {
      if (context.mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  void _ledger(BuildContext context, StockLine l, String Function(String?) phaseName, _Actions actions) => showStockLedger(
    context,
    line: l,
    seeMoney: widget.seeMoney,
    phaseName: phaseName,
    onReorder: actions.raise == null
        ? null
        : () => actions.raise!(
            prefill: [MaterialLine(material: l.material, unit: l.unit, qty: l.suggestedReorder)],
          ),
    onIssue: actions.issue == null ? null : () => actions.issue!(line: l),
  );

  Future<void> _decide(BuildContext context, Indent x, bool approve) async {
    final note = await askIndentDecision(context, x, approve: approve);
    if (note == null || !context.mounted) return;
    await _run(
      context,
      () => ref.read(inventoryRepositoryProvider).decideIndent(widget.project.id, x.id, approve, note, ref.read(currentUserProvider).uid),
      approve ? '${x.number} approved. The site can order it now.' : '${x.number} rejected',
    );
  }

  Future<void> _close(BuildContext context, Indent x) async {
    final note = await askNote(
      context,
      title: 'Close ${x.number} short',
      intro: 'The rest of this indent will stop counting as on order or late. Deliveries already recorded stay in stock.',
      label: 'Why is the rest not coming?',
      required: true,
      confirmLabel: 'Close indent',
    );
    if (note == null || !context.mounted) return;
    await _run(
      context,
      () => ref.read(inventoryRepositoryProvider).closeIndent(widget.project.id, x.id, note, ref.read(currentUserProvider).uid),
      '${x.number} closed',
    );
  }

  Future<void> _withdraw(BuildContext context, Indent x) async {
    final ok = await confirmAction(
      context,
      title: 'Withdraw ${x.number}?',
      message: 'It will be removed from the approval queue. You can raise a new indent any time.',
      confirmLabel: 'Withdraw',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    await _run(
      context,
      () => ref.read(inventoryRepositoryProvider).withdrawIndent(widget.project.id, x.id, ref.read(currentUserProvider).uid),
      '${x.number} withdrawn',
    );
  }

  Future<void> _raise(BuildContext context, List<MaterialLine> prefill) =>
      raiseIndentFlow(context, ref, widget.project, prefill: prefill, phaseId: _phaseId);

  Future<void> _receive(BuildContext context, InventorySummary s, String today, Indent? against) async {
    final result = await showMaterialForm(
      context,
      kind: MaterialFormKind.grn,
      summary: s,
      today: today,
      openIndents: s.open,
      against: against,
    );
    if (result == null || !context.mounted) return;
    await _run(
      context,
      () => ref.read(inventoryRepositoryProvider).recordGrn(
        projectId: widget.project.id,
        items: result.lines,
        vendor: result.vendor,
        invoiceNo: result.invoiceNo,
        date: result.date ?? today,
        note: result.note,
        indentId: result.indentId,
        completesIndent: result.completesIndent,
        uid: ref.read(currentUserProvider).uid,
      ),
      result.indentId != null && !result.completesIndent
          ? 'Part delivery added to stock. The indent stays open for the rest.'
          : 'Delivery added to stock',
    );
  }

  Future<void> _issue(
    BuildContext context,
    InventorySummary s,
    List<ProjectPhase> phases,
    String today,
    List<MaterialIssue> issues,
    StockLine? line,
  ) async {
    final crews = <String>[];
    for (final i in issues) {
      final t = i.issuedTo.trim();
      if (t.isNotEmpty && !crews.any((c) => c.toLowerCase() == t.toLowerCase())) crews.add(t);
    }
    final result = await showMaterialForm(
      context,
      kind: MaterialFormKind.issue,
      summary: s,
      today: today,
      phases: phases,
      phaseId: _phaseId,
      issuedToSuggestions: crews,
      prefill: line == null ? const [] : [MaterialLine(material: line.material, unit: line.unit, qty: 0)],
    );
    if (result == null || !context.mounted) return;
    await _run(
      context,
      () => ref.read(inventoryRepositoryProvider).issueMaterial(
        projectId: widget.project.id,
        items: result.lines,
        available: {for (final l in s.stock) l.key: l.inStock},
        date: result.date ?? today,
        phaseId: result.phaseId,
        issuedTo: result.issuedTo,
        note: result.note,
        uid: ref.read(currentUserProvider).uid,
      ),
      'Material issued',
    );
  }

  /// Opens the expense form pre-filled from a delivery, so the bill is
  /// approved and paid through Money like any other.
  Future<void> _book(BuildContext context, Grn g, List<Indent> indents) => showExpenseEditor(
    context,
    project: widget.project,
    draft: ExpenseDraft(
      amountPaise: g.valuePaise > 0 ? g.valuePaise : null,
      payee: g.vendor,
      date: g.date,
      description: [
        'Materials ${g.number}',
        if (g.invoiceNo.isNotEmpty) 'invoice ${g.invoiceNo}',
        g.items.map((l) => '${formatQty(l.qty)} ${l.unit} ${l.material}').join(', '),
      ].join(' · '),
      phaseId: indents.where((x) => x.id == g.indentId).firstOrNull?.phaseId,
      categoryHint: 'material',
      grnId: g.id,
    ),
  );
}

/// What the current user can start from this screen; null = not allowed.
class _Actions {
  const _Actions({this.raise, this.receive, this.issue});

  final void Function({List<MaterialLine> prefill})? raise;
  final void Function({Indent? against})? receive;
  final void Function({StockLine? line})? issue;
}

// ---------------------------------------------------------------------------
// Header, metrics, attention list, toolbar
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({required this.project, required this.actions});

  final Project project;
  final _Actions actions;

  @override
  Widget build(BuildContext context) {
    final buttons = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (actions.raise != null)
          FilledButton.icon(
            onPressed: () => actions.raise!(),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Raise indent'),
          ),
        if (actions.receive != null)
          OutlinedButton.icon(
            onPressed: () => actions.receive!(),
            icon: const Icon(Icons.move_to_inbox_outlined, size: 18),
            label: const Text('Record delivery'),
          ),
        if (actions.issue != null)
          OutlinedButton.icon(
            onPressed: () => actions.issue!(),
            icon: const Icon(Icons.outbox_outlined, size: 18),
            label: const Text('Issue material'),
          ),
      ],
    );
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Materials', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        const Text(
          'Request → approve → receive → issue. Stock is always received minus issued.',
          style: TextStyle(color: AppColors.muted),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, c) => c.maxWidth < 720
          ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [title, const SizedBox(height: 12), buttons])
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [Expanded(child: title), const SizedBox(width: 16), buttons],
            ),
    );
  }
}

class _Metrics extends StatelessWidget {
  const _Metrics({
    required this.summary,
    required this.seeMoney,
    required this.onWaiting,
    required this.onLate,
    required this.onLow,
    required this.onValue,
    required this.onOpen,
  });

  final InventorySummary summary;
  final bool seeMoney;
  final VoidCallback onWaiting;
  final VoidCallback onLate;
  final VoidCallback onLow;
  final VoidCallback onValue;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final colors = context.statusColors;
    final oldestWait = s.pending.isEmpty ? 0 : s.pending.first.waitingDays(DateTime.now());
    final cards = [
      NeoMetricCard(
        label: 'Waiting for approval',
        value: '${s.pending.length}',
        caption: s.pending.isEmpty ? 'Nothing to approve' : 'Oldest waiting $oldestWait day${oldestWait == 1 ? '' : 's'}',
        icon: Icons.hourglass_bottom,
        accent: s.pending.isEmpty ? colors.ok : (oldestWait >= 3 ? colors.bad : colors.warn),
        onTap: onWaiting,
      ),
      NeoMetricCard(
        label: 'Deliveries overdue',
        value: '${s.late.length}',
        caption: s.late.isEmpty
            ? '${s.open.length} awaiting delivery, none late'
            : 'Worst: ${s.late.first.number}',
        icon: Icons.local_shipping_outlined,
        accent: s.late.isEmpty ? colors.ok : colors.bad,
        onTap: s.late.isEmpty ? onOpen : onLate,
      ),
      NeoMetricCard(
        label: 'Running low',
        value: '${s.lowCount}',
        caption: s.lowCount == 0
            ? 'All stock healthy'
            : (s.reorderCount == 0 ? 'All already on order' : '${s.reorderCount} not yet reordered'),
        icon: Icons.inventory_2_outlined,
        accent: s.lowCount == 0 ? colors.ok : (s.reorderCount > 0 ? colors.bad : colors.warn),
        onTap: onLow,
      ),
      seeMoney
          ? NeoMetricCard(
              label: 'Stock value on site',
              value: Money.compact(s.stockValuePaise),
              caption: 'Received ${Money.compact(s.receivedValuePaise)} · used ${Money.compact(s.usedValuePaise)}',
              icon: Icons.account_balance_wallet_outlined,
              onTap: onValue,
            )
          : NeoMetricCard(
              label: 'Materials tracked',
              value: '${s.stock.length}',
              caption: '${s.stock.where((l) => l.inStock > 0).length} in stock now',
              icon: Icons.category_outlined,
              onTap: onValue,
            ),
    ];
    return LayoutBuilder(
      builder: (context, c) {
        final columns = c.maxWidth >= 900 ? 4 : (c.maxWidth >= 420 ? 2 : 1);
        final w = (c.maxWidth - (columns - 1) * 12) / columns;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [for (final card in cards) SizedBox(width: w, child: card)],
        );
      },
    );
  }
}

/// The few things to act on now: late deliveries, the approval queue and
/// materials about to run out with nothing ordered.
class _Attention extends StatelessWidget {
  const _Attention({
    required this.summary,
    required this.today,
    required this.canApprove,
    required this.actions,
    required this.onWaiting,
    required this.onLate,
    required this.onStock,
  });

  final InventorySummary summary;
  final String today;
  final bool canApprove;
  final _Actions actions;
  final VoidCallback onWaiting;
  final VoidCallback onLate;
  final ValueChanged<StockLine> onStock;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final colors = context.statusColors;
    final rows = <Widget>[];
    for (final x in s.late.take(3)) {
      final left = s.remaining(x);
      rows.add(
        _AttentionRow(
          icon: Icons.local_shipping_outlined,
          color: colors.bad,
          title: '${x.number} is ${x.daysLate(today)} day${x.daysLate(today) == 1 ? '' : 's'} late',
          detail: 'Still to come: ${(left.isEmpty ? x.items : left).map((l) => '${formatQty(l.qty)} ${l.unit} ${l.material}').join(', ')}',
          action: actions.receive == null ? 'See' : 'Record delivery',
          onTap: actions.receive == null ? onLate : () => actions.receive!(against: x),
        ),
      );
    }
    if (s.late.length > 3) {
      rows.add(_AttentionRow(
        icon: Icons.more_horiz,
        color: colors.bad,
        title: '${s.late.length - 3} more late deliveries',
        action: 'See all',
        onTap: onLate,
      ));
    }
    if (canApprove && s.pending.isNotEmpty) {
      final oldest = s.pending.first.waitingDays(DateTime.now());
      rows.add(
        _AttentionRow(
          icon: Icons.hourglass_bottom,
          color: oldest >= 3 ? colors.bad : colors.warn,
          title: '${s.pending.length} indent${s.pending.length == 1 ? '' : 's'} waiting for your approval',
          detail: 'Oldest has waited $oldest day${oldest == 1 ? '' : 's'}. The site cannot order until then.',
          action: 'Review',
          onTap: onWaiting,
        ),
      );
    }
    final reorder = s.stock.where((l) => l.needsReorder).toList()
      ..sort((a, b) => (a.daysLeft ?? 999).compareTo(b.daysLeft ?? 999));
    for (final l in reorder.take(3)) {
      rows.add(
        _AttentionRow(
          icon: Icons.inventory_2_outlined,
          color: l.out ? colors.bad : colors.warn,
          title: l.out ? '${l.material} is out of stock' : '${l.material} is running low',
          detail: [
            '${formatQty(l.inStock)} ${l.unit} left',
            if (l.daysLeft != null) '~${l.daysLeft!.floor()} days at current use',
            'nothing on order',
          ].join(' · '),
          action: actions.raise == null ? 'View' : 'Reorder',
          onTap: actions.raise == null
              ? () => onStock(l)
              : () => actions.raise!(prefill: [MaterialLine(material: l.material, unit: l.unit, qty: l.suggestedReorder)]),
        ),
      );
    }
    if (rows.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: AppRadius.card,
          border: Border.all(color: AppColors.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Text('Needs attention', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
              rows[i],
            ],
          ],
        ),
      ),
    );
  }
}

class _AttentionRow extends StatelessWidget {
  const _AttentionRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.action,
    required this.onTap,
    this.detail,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String? detail;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(9)),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                if (detail != null)
                  Text(detail!, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(onPressed: onTap, child: Text(action)),
        ],
      ),
    ),
  );
}

class _Toolbar extends StatefulWidget {
  const _Toolbar({
    required this.view,
    required this.counts,
    required this.query,
    required this.onView,
    required this.onQuery,
  });

  final _View view;
  final Map<_View, int> counts;
  final String query;
  final ValueChanged<_View> onView;
  final ValueChanged<String> onQuery;

  @override
  State<_Toolbar> createState() => _ToolbarState();
}

class _ToolbarState extends State<_Toolbar> {
  late final _search = TextEditingController(text: widget.query);

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    String label(_View v) {
      final n = widget.counts[v] ?? 0;
      return n == 0 ? v.label : '${v.label} · $n';
    }

    final tabs = SegmentedButton<_View>(
      showSelectedIcon: false,
      segments: [
        for (final v in _View.values) ButtonSegment(value: v, icon: Icon(v.icon, size: 18), label: Text(label(v))),
      ],
      selected: {widget.view},
      onSelectionChanged: (v) => widget.onView(v.first),
    );
    // On phones the four segments don't fit in one row; chips wrap instead.
    final chips = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final v in _View.values)
          ChoiceChip(
            avatar: Icon(v.icon, size: 18),
            label: Text(label(v)),
            selected: widget.view == v,
            showCheckmark: false,
            onSelected: (_) => widget.onView(v),
          ),
      ],
    );
    final search = SizedBox(
      height: 42,
      child: TextField(
        controller: _search,
        onChanged: widget.onQuery,
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Search material, number, vendor…',
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: widget.query.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear search',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () {
                    _search.clear();
                    widget.onQuery('');
                  },
                ),
        ),
      ),
    );
    return LayoutBuilder(
      builder: (context, c) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (c.maxWidth < 640) chips else Align(alignment: Alignment.centerLeft, child: tabs),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 480), child: search),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Views
// ---------------------------------------------------------------------------

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
    decoration: BoxDecoration(borderRadius: AppRadius.card, border: Border.all(color: AppColors.line)),
    child: Column(
      children: [
        const Illustration(Art.emptyBlueprint, height: 96),
        const SizedBox(height: 12),
        Text(text, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)),
        if (action != null) ...[const SizedBox(height: 8), action!],
      ],
    ),
  );
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.accent});

  final Widget child;

  /// A coloured stripe on the left, for items that need attention.
  final Color? accent;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: AppRadius.card,
      border: Border.all(color: AppColors.line),
    ),
    clipBehavior: Clip.antiAlias,
    child: Stack(
      children: [
        Padding(padding: EdgeInsets.fromLTRB(accent == null ? 16 : 20, 16, 16, 16), child: child),
        if (accent != null) Positioned(left: 0, top: 0, bottom: 0, width: 4, child: ColoredBox(color: accent!)),
      ],
    ),
  );
}

class _IndentCard extends StatelessWidget {
  const _IndentCard({
    required this.indent,
    required this.summary,
    required this.today,
    required this.phase,
    required this.person,
    required this.deliveries,
    required this.canApprove,
    required this.canWithdraw,
    required this.onDecide,
    required this.onReceive,
    required this.onClose,
    required this.onWithdraw,
  });

  final Indent indent;
  final InventorySummary summary;
  final String today;
  final String phase;
  final String Function(String? uid) person;
  final List<Grn> deliveries;
  final bool canApprove;
  final bool canWithdraw;
  final ValueChanged<bool> onDecide;
  final VoidCallback? onReceive;
  final VoidCallback onClose;
  final VoidCallback onWithdraw;

  @override
  Widget build(BuildContext context) {
    final x = indent;
    final colors = context.statusColors;
    final late = x.isLate(today);
    final share = summary.deliveredShare(x);
    final partial = x.isOpen && share > 0;
    final (color, label) = switch (x.status) {
      IndentStatus.pending => (colors.warn, 'Waiting for approval'),
      IndentStatus.approved when late => (colors.bad, '${x.daysLate(today)}d late'),
      IndentStatus.approved when partial => (Theme.of(context).colorScheme.primary, 'Part delivered'),
      IndentStatus.approved => (Theme.of(context).colorScheme.primary, 'Awaiting delivery'),
      IndentStatus.received => (colors.ok, 'Received'),
      IndentStatus.closed => (AppColors.muted, 'Closed short'),
      IndentStatus.rejected => (AppColors.muted, 'Rejected'),
    };
    final due = x.daysToNeed(today);
    final showProgress = x.status != IndentStatus.pending && x.status != IndentStatus.rejected;
    final buttons = <Widget>[
      if (canApprove && x.isPending) ...[
        FilledButton.icon(
          onPressed: () => onDecide(true),
          icon: const Icon(Icons.check, size: 18),
          label: const Text('Approve'),
        ),
        OutlinedButton(
          onPressed: () => onDecide(false),
          child: Text('Reject', style: TextStyle(color: colors.bad)),
        ),
      ],
      if (canWithdraw) TextButton(onPressed: onWithdraw, child: const Text('Withdraw')),
      if (onReceive != null && x.isOpen)
        FilledButton.tonalIcon(
          onPressed: onReceive,
          icon: const Icon(Icons.move_to_inbox_outlined, size: 18),
          label: Text(partial ? 'Record next delivery' : 'Record delivery'),
        ),
      if (canApprove && x.isOpen) TextButton(onPressed: onClose, child: const Text('Close short')),
    ];
    return _Panel(
      accent: late ? colors.bad : (x.isPending ? colors.warn : null),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(x.number, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    if (phase.isNotEmpty) Pill(phase),
                  ],
                ),
              ),
              Pill(label, color: color, background: color.withValues(alpha: 0.10)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            [
              'By ${person(x.requestedBy)}${x.requestedAt == null ? '' : ' on ${WorkDay.display(WorkDay.fromDate(x.requestedAt!))}'}',
              if (x.neededBy != null)
                (x.isPending || x.isOpen) && due != null && due >= 0
                    ? 'needed ${due == 0 ? 'today' : 'in $due day${due == 1 ? '' : 's'}'} (${WorkDay.display(x.neededBy)})'
                    : 'needed by ${WorkDay.display(x.neededBy)}',
            ].join(' · '),
            style: TextStyle(color: late ? colors.bad : AppColors.muted, fontSize: 13),
          ),
          const SizedBox(height: 12),
          for (final l in x.items)
            _IndentLine(line: l, received: showProgress ? summary.receivedFor(x, l) : null),
          if (x.note.isNotEmpty) ...[
            const SizedBox(height: 8),
            _Quote(text: x.note),
          ],
          if (x.decidedBy != null) ...[
            const SizedBox(height: 8),
            Text(
              '${x.status == IndentStatus.rejected ? 'Rejected' : 'Approved'} by ${person(x.decidedBy)}'
              '${x.decidedAt == null ? '' : ' on ${WorkDay.display(WorkDay.fromDate(x.decidedAt!))}'}'
              '${x.decisionNote.isEmpty ? '' : ': ${x.decisionNote}'}',
              style: TextStyle(fontSize: 12.5, color: x.status == IndentStatus.rejected ? colors.bad : AppColors.muted),
            ),
          ],
          if (x.status == IndentStatus.closed && x.closeNote.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Closed by ${person(x.closedBy)}: ${x.closeNote}',
              style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
            ),
          ],
          if (deliveries.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Deliveries: ${deliveries.map((g) => '${g.number} (${WorkDay.display(g.date)}, ${g.vendor})').join(' · ')}',
              style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
            ),
          ],
          if (buttons.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: buttons),
          ],
        ],
      ),
    );
  }
}

class _IndentLine extends StatelessWidget {
  const _IndentLine({required this.line, this.received});

  final MaterialLine line;

  /// Delivered so far; null before approval (no progress to show).
  final double? received;

  @override
  Widget build(BuildContext context) {
    final l = line;
    final got = received;
    final done = got != null && got >= l.qty - 1e-9;
    final colors = context.statusColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(l.material)),
          if (got != null) ...[
            SizedBox(
              width: 90,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: l.qty <= 0 ? 0 : (got / l.qty).clamp(0, 1).toDouble(),
                  minHeight: 6,
                  backgroundColor: AppColors.line,
                  color: done ? colors.ok : Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(width: 10),
          ],
          SizedBox(
            width: 130,
            child: Text(
              got == null ? '${formatQty(l.qty)} ${l.unit}' : '${formatQty(got)} / ${formatQty(l.qty)} ${l.unit}',
              textAlign: TextAlign.right,
              style: TextStyle(fontWeight: FontWeight.w700, color: done ? colors.ok : null),
            ),
          ),
        ],
      ),
    );
  }
}

class _Quote extends StatelessWidget {
  const _Quote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: AppColors.concrete,
      borderRadius: BorderRadius.circular(AppRadius.sm),
    ),
    child: Text(text, style: const TextStyle(color: AppColors.ink, fontSize: 13)),
  );
}

class _StockView extends StatelessWidget {
  const _StockView({
    required this.stock,
    required this.total,
    required this.lowOnly,
    required this.seeMoney,
    required this.onLowOnly,
    required this.onOpen,
  });

  final List<StockLine> stock;
  final int total;
  final bool lowOnly;
  final bool seeMoney;
  final ValueChanged<bool> onLowOnly;
  final ValueChanged<StockLine> onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = context.statusColors;
    // Most urgent first: out, then fewest days left, then A–Z.
    final rows = [...stock]
      ..sort((a, b) {
        if (a.low != b.low) return a.low ? -1 : 1;
        final d = (a.daysLeft ?? 9999).compareTo(b.daysLeft ?? 9999);
        return d != 0 ? d : a.material.toLowerCase().compareTo(b.material.toLowerCase());
      });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            FilterChip(
              label: const Text('Running low only'),
              selected: lowOnly,
              onSelected: onLowOnly,
            ),
            const Spacer(),
            const Flexible(
              child: Text(
                'Days left use the last ${StockLine.usageWindowDays} days of issues. Tap a material for its history.',
                textAlign: TextAlign.right,
                style: TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (rows.isEmpty)
          _Empty(
            icon: Icons.inventory_2_outlined,
            text: total == 0
                ? 'No material on this project yet. Stock appears once a delivery is recorded.'
                : 'Nothing matches. Clear the search or the “running low” filter.',
          )
        else
          LayoutBuilder(
            builder: (context, c) => c.maxWidth >= 760
                ? _StockTable(rows: rows, seeMoney: seeMoney, onOpen: onOpen)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final l in rows)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: HoverCard(
                            onTap: () => onOpen(l),
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    Expanded(child: Text(l.material, style: const TextStyle(fontWeight: FontWeight.w700))),
                                    Text(
                                      '${formatQty(l.inStock)} ${l.unit}',
                                      style: TextStyle(fontWeight: FontWeight.w800, color: l.low ? colors.bad : null),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                _StockBar(line: l),
                                const SizedBox(height: 6),
                                Text(
                                  [
                                    _daysText(l),
                                    if (l.onOrder > 0) '${formatQty(l.onOrder)} on order',
                                    if (l.requested > 0) '${formatQty(l.requested)} awaiting approval',
                                    if (seeMoney && l.valuePaise > 0) Money.compact(l.valuePaise),
                                  ].join(' · '),
                                  style: TextStyle(color: l.low ? colors.bad : AppColors.muted, fontSize: 12.5),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
      ],
    );
  }
}

String _daysText(StockLine l) {
  if (l.out) return 'Out of stock';
  final d = l.daysLeft;
  if (d == null) return l.received > 0 ? 'Not used lately' : 'Not received yet';
  return '~${d.floor()} day${d.floor() == 1 ? '' : 's'} left';
}

/// Remaining share of everything received, coloured by urgency.
class _StockBar extends StatelessWidget {
  const _StockBar({required this.line});

  final StockLine line;

  @override
  Widget build(BuildContext context) {
    final l = line;
    final colors = context.statusColors;
    final share = l.received <= 0 ? 0.0 : (l.inStock / l.received).clamp(0, 1).toDouble();
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: LinearProgressIndicator(
        value: share,
        minHeight: 6,
        backgroundColor: AppColors.line,
        color: l.low ? colors.bad : colors.ok,
      ),
    );
  }
}

class _StockTable extends StatelessWidget {
  const _StockTable({required this.rows, required this.seeMoney, required this.onOpen});

  final List<StockLine> rows;
  final bool seeMoney;
  final ValueChanged<StockLine> onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = context.statusColors;
    const head = TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.muted, letterSpacing: 0.4);
    Widget cell(String v, {int flex = 2, Color? color, bool bold = false, TextStyle? style}) => Expanded(
      flex: flex,
      child: Text(
        v,
        textAlign: TextAlign.right,
        style: style ?? TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w500, color: color),
      ),
    );
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: AppRadius.card,
        border: Border.all(color: AppColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            color: AppColors.concrete,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                const Expanded(flex: 5, child: Text('MATERIAL', style: head)),
                cell('IN STOCK', style: head),
                cell('LASTS', style: head),
                cell('RECEIVED', style: head),
                cell('ISSUED', style: head),
                cell('ON ORDER', style: head),
                if (seeMoney) cell('VALUE', style: head),
                const SizedBox(width: 28),
              ],
            ),
          ),
          for (final l in rows) ...[
            const Divider(height: 1),
            InkWell(
              onTap: () => onOpen(l),
              child: Container(
                color: l.low ? colors.badSoft.withValues(alpha: 0.5) : null,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Expanded(
                      flex: 5,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l.material, style: const TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 6),
                          SizedBox(width: 160, child: _StockBar(line: l)),
                        ],
                      ),
                    ),
                    cell('${formatQty(l.inStock)} ${l.unit}', bold: true, color: l.low ? colors.bad : null),
                    cell(_daysText(l), color: l.low ? colors.bad : AppColors.muted),
                    cell(formatQty(l.received)),
                    cell(formatQty(l.issued)),
                    cell(
                      [
                        if (l.onOrder > 0) formatQty(l.onOrder),
                        if (l.requested > 0) '+${formatQty(l.requested)} asked',
                      ].join(' ').ifEmpty('—'),
                      color: l.needsReorder ? colors.bad : null,
                    ),
                    if (seeMoney) cell(l.valuePaise > 0 ? Money.compact(l.valuePaise) : '—'),
                    const SizedBox(width: 28, child: Icon(Icons.chevron_right, size: 18, color: AppColors.muted)),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}

class _Deliveries extends StatelessWidget {
  const _Deliveries({
    required this.grns,
    required this.indents,
    required this.seeMoney,
    required this.booked,
    required this.person,
    required this.onBook,
    required this.onRecord,
  });

  final List<Grn> grns;
  final List<Indent> indents;
  final bool seeMoney;
  final Set<String> booked;
  final String Function(String? uid) person;
  final ValueChanged<Grn>? onBook;
  final VoidCallback? onRecord;

  @override
  Widget build(BuildContext context) {
    if (grns.isEmpty) {
      return _Empty(
        icon: Icons.move_to_inbox_outlined,
        text: 'No deliveries recorded. Record one when material arrives on site.',
        action: onRecord == null
            ? null
            : TextButton.icon(
                onPressed: onRecord,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Record delivery'),
              ),
      );
    }
    final unbooked = onBook == null ? const <Grn>[] : grns.where((g) => !booked.contains(g.id) && g.valuePaise > 0).toList();
    final colors = context.statusColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (unbooked.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: colors.warnSoft, borderRadius: AppRadius.card),
            child: Row(
              children: [
                Icon(Icons.receipt_long_outlined, color: colors.warn, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${unbooked.length} deliver${unbooked.length == 1 ? 'y' : 'ies'} worth '
                    '${Money.compact(unbooked.fold(0, (s, g) => s + g.valuePaise))} not yet booked as an expense. '
                    'Book them so the bill is approved and paid through Money.',
                    style: TextStyle(color: colors.warn, fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        for (final g in grns)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${g.vendor} · ${g.number}',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (seeMoney && g.valuePaise > 0)
                        Text(Money.format(g.valuePaise), style: const TextStyle(fontWeight: FontWeight.w800)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      WorkDay.display(g.date),
                      if (g.invoiceNo.isNotEmpty) 'Invoice ${g.invoiceNo}',
                      if (indents.where((x) => x.id == g.indentId).firstOrNull case final x?) 'against ${x.number}'
                      else 'direct purchase',
                      'received by ${person(g.receivedBy)}',
                    ].join(' · '),
                    style: const TextStyle(color: AppColors.muted, fontSize: 13),
                  ),
                  const SizedBox(height: 10),
                  for (final l in g.items)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Expanded(child: Text(l.material)),
                          Text('${formatQty(l.qty)} ${l.unit}', style: const TextStyle(fontWeight: FontWeight.w700)),
                          if (seeMoney && l.ratePaise != null)
                            SizedBox(
                              width: 170,
                              child: Text(
                                '@ ${Money.format(l.ratePaise!)} = ${Money.compact(l.valuePaise)}',
                                textAlign: TextAlign.right,
                                style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
                              ),
                            ),
                        ],
                      ),
                    ),
                  if (g.note.isNotEmpty) ...[const SizedBox(height: 8), _Quote(text: g.note)],
                  if (onBook != null) ...[
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: booked.contains(g.id)
                          ? Pill('Booked as expense', color: colors.ok, background: colors.okSoft)
                          : OutlinedButton.icon(
                              onPressed: () => onBook!(g),
                              icon: const Icon(Icons.receipt_long_outlined, size: 18),
                              label: const Text('Book as expense'),
                            ),
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _Usage extends StatelessWidget {
  const _Usage({
    required this.summary,
    required this.issues,
    required this.seeMoney,
    required this.phaseName,
    required this.person,
    required this.onPhase,
  });

  final InventorySummary summary;
  final List<MaterialIssue> issues;
  final bool seeMoney;
  final String Function(String? id) phaseName;
  final String Function(String? uid) person;
  final ValueChanged<String> onPhase;

  @override
  Widget build(BuildContext context) {
    if (issues.isEmpty) {
      return const _Empty(
        icon: Icons.outbox_outlined,
        text: 'Nothing issued from the store yet. Issue material when it goes to the work, so stock stays true.',
      );
    }
    final usage = summary.usageByPhase;
    final top = usage.fold(0, (m, u) => u.valuePaise > m ? u.valuePaise : m);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Used by phase', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(
                seeMoney ? 'Valued at average purchase rates.' : 'Issue slips per phase.',
                style: const TextStyle(color: AppColors.muted, fontSize: 12),
              ),
              const SizedBox(height: 10),
              for (final u in usage)
                InkWell(
                  onTap: u.phaseId == null ? null : () => onPhase(u.phaseId!),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                u.phaseId == null ? 'No specific phase' : phaseName(u.phaseId).ifEmpty('Archived phase'),
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                            Text(
                              seeMoney && u.valuePaise > 0
                                  ? '${Money.compact(u.valuePaise)} · ${u.slips} slip${u.slips == 1 ? '' : 's'}'
                                  : '${u.slips} slip${u.slips == 1 ? '' : 's'}',
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                        if (seeMoney && top > 0) ...[
                          const SizedBox(height: 4),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(99),
                            child: LinearProgressIndicator(
                              value: u.valuePaise / top,
                              minHeight: 5,
                              backgroundColor: AppColors.line,
                            ),
                          ),
                        ],
                        const SizedBox(height: 3),
                        Text(
                          (u.qtyByMaterial.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
                              .take(4)
                              .map((e) => '${e.key} ${formatQty(e.value)}')
                              .join(' · '),
                          style: const TextStyle(color: AppColors.muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        for (final i in issues)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          i.issuedTo.isEmpty ? i.number : '${i.issuedTo} · ${i.number}',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (phaseName(i.phaseId).isNotEmpty) Pill(phaseName(i.phaseId)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${WorkDay.display(i.date)} · issued by ${person(i.issuedBy)}',
                    style: const TextStyle(color: AppColors.muted, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  for (final l in i.items)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Expanded(child: Text(l.material)),
                          Text('${formatQty(l.qty)} ${l.unit}', style: const TextStyle(fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  if (i.note.isNotEmpty) ...[const SizedBox(height: 8), _Quote(text: i.note)],
                ],
              ),
            ),
          ),
      ],
    );
  }
}
