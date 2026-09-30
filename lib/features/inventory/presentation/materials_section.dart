import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/config_repository.dart';
import '../../../core/dynamic_form/dynamic_fields.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/work_day.dart';
import '../../../core/widgets/common.dart';
import '../../auth/data/session.dart';
import '../../auth/domain/app_user.dart';
import '../../projects/data/project_detail_repository.dart';
import '../../projects/domain/project.dart';
import '../../projects/domain/project_detail.dart';
import '../../projects/domain/project_nav.dart';
import '../../projects/presentation/project_dashboard.dart' show ProjectTabPage;
import '../../projects/presentation/project_nav_scope.dart';
import '../../settings/presentation/settings_common.dart';
import '../../users/data/user_repository.dart';
import '../data/inventory_repository.dart';
import '../domain/inventory.dart';

enum _View { stock, indents, received, issued }

enum _IndentFilter {
  waiting('Waiting'),
  late('Late'),
  approved('Approved'),
  received('Received'),
  rejected('Rejected'),
  all('All');

  const _IndentFilter(this.label);
  final String label;
}

/// Project → Materials: site stores with approvals. The site raises indents,
/// the project manager or CEO/admin approves them, the manager records what
/// arrives (GRN), and the site issues material to the work.
class MaterialsSection extends ConsumerStatefulWidget {
  const MaterialsSection({
    super.key,
    required this.project,
    required this.canRequest,
    required this.canReceive,
    required this.canApprove,
  });

  final Project project;
  final bool canRequest;
  final bool canReceive;
  final bool canApprove;

  @override
  ConsumerState<MaterialsSection> createState() => _MaterialsSectionState();
}

class _MaterialsSectionState extends ConsumerState<MaterialsSection> {
  var _view = _View.indents;
  var _filter = _IndentFilter.waiting;
  String? _phaseId;
  int? _applied;

  /// Switch to the indent list with [filter] (and optionally one phase).
  void _show(_IndentFilter filter, {String? phase}) {
    _view = _View.indents;
    _filter = filter;
    _phaseId = phase;
  }

  @override
  Widget build(BuildContext context) {
    final pid = widget.project.id;
    final indents = ref.watch(projectIndentsProvider(pid));
    final grns = ref.watch(projectGrnsProvider(pid));
    final issues = ref.watch(projectMaterialIssuesProvider(pid));
    final summary = ref.watch(projectInventoryProvider(pid));
    final phases = ref.watch(projectPhasesProvider(pid)).value ?? const <ProjectPhase>[];
    final people = ref.watch(allUsersProvider).value ?? const <AppUser>[];
    final config = ref.watch(appConfigProvider);
    final today = WorkDay.today(utcOffsetMinutes: config.company.utcOffsetMinutes);
    final nav = ProjectNavScope.maybeOf(context);
    final focusIndent = nav?.current.tab == ProjectTab.materials ? nav!.current.focusId('indent') : null;
    if (nav != null && nav.seq != _applied) {
      _applied = nav.seq;
      final focus = nav.focusFor(ProjectTab.materials);
      final phase = nav.current.tab == ProjectTab.materials ? nav.current.focusId('phase') : null;
      if (focus == 'pending') _show(_IndentFilter.waiting);
      if (focus == 'late') _show(_IndentFilter.late);
      if (focus == 'low') _view = _View.stock;
      if (focusIndent != null) _show(_IndentFilter.all);
      if (phase != null) _show(_IndentFilter.all, phase: phase);
    }
    String phaseName(String? id) => phases.where((p) => p.id == id).firstOrNull?.name ?? '';
    String person(String? uid) => people.where((u) => u.uid == uid).firstOrNull?.name ?? 'Someone';

    return ProjectTabPage(
      child: AsyncView(
        value: summary,
        data: (s) {
          final allIndents = indents.value ?? const <Indent>[];
          bool match(Indent x) => switch (_filter) {
            _IndentFilter.waiting => x.isPending,
            _IndentFilter.late => x.isLate(today),
            _IndentFilter.approved => x.status == IndentStatus.approved,
            _IndentFilter.received => x.status == IndentStatus.received,
            _IndentFilter.rejected => x.status == IndentStatus.rejected,
            _IndentFilter.all => true,
          };
          int count(_IndentFilter f) {
            final saved = _filter;
            _filter = f;
            final n = allIndents.where(match).where((x) => _phaseId == null || x.phaseId == _phaseId).length;
            _filter = saved;
            return n;
          }

          final shownIndents = allIndents.where(match).where((x) => _phaseId == null || x.phaseId == _phaseId).toList();
          final stockByKey = {for (final l in s.stock) '${l.material.toLowerCase()}|${l.unit.toLowerCase()}': l.inStock};

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Materials', style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 4),
                        const Text(
                          'Indents are approved by the project manager or CEO. Stock = received − issued.',
                          style: TextStyle(color: AppColors.muted),
                        ),
                      ],
                    ),
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (widget.canRequest)
                        FilledButton.icon(
                          onPressed: () => _raise(context, phases, s),
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Raise indent'),
                        ),
                      if (widget.canReceive)
                        OutlinedButton.icon(
                          onPressed: () => _receive(context, allIndents.where((x) => x.status == IndentStatus.approved).toList(), today),
                          icon: const Icon(Icons.move_to_inbox_outlined, size: 18),
                          label: const Text('Record GRN'),
                        ),
                      if (widget.canRequest)
                        OutlinedButton.icon(
                          onPressed: s.stock.any((l) => l.inStock > 0) ? () => _issue(context, s, phases, stockByKey, today) : null,
                          icon: const Icon(Icons.outbox_outlined, size: 18),
                          label: const Text('Issue material'),
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, c) {
                  final columns = c.maxWidth >= 760 ? 4 : 2;
                  final w = (c.maxWidth - (columns - 1) * 12) / columns;
                  Widget stat(String label, String value, IconData icon, Color? color, VoidCallback onTap) => SizedBox(
                    width: w,
                    child: InkWell(
                      onTap: onTap,
                      borderRadius: AppRadius.card,
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          borderRadius: AppRadius.card,
                          border: Border.all(color: AppColors.line),
                        ),
                        child: Row(
                          children: [
                            Icon(icon, color: color ?? AppColors.muted, size: 22),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color ?? AppColors.ink)),
                                  Text(label, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                  final colors = context.statusColors;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      stat('Waiting for approval', '${s.pending.length}', Icons.hourglass_bottom,
                          s.pending.isEmpty ? null : colors.warn,
                          () => setState(() => _show(_IndentFilter.waiting))),
                      stat('Deliveries overdue', '${s.late.length}', Icons.local_shipping_outlined,
                          s.late.isEmpty ? null : colors.bad,
                          () => setState(() => _show(_IndentFilter.late))),
                      stat('Low stock items', '${s.lowCount}', Icons.inventory_2_outlined,
                          s.lowCount == 0 ? null : colors.warn, () => setState(() => _view = _View.stock)),
                      stat('Material received', Money.compact(s.receivedValuePaise), Icons.move_to_inbox_outlined, null,
                          () => setState(() => _view = _View.received)),
                    ],
                  );
                },
              ),
              const SizedBox(height: 20),
              SegmentedButton<_View>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: _View.indents, label: Text('Indents'), icon: Icon(Icons.assignment_outlined, size: 18)),
                  ButtonSegment(value: _View.stock, label: Text('Stock'), icon: Icon(Icons.inventory_2_outlined, size: 18)),
                  ButtonSegment(value: _View.received, label: Text('Received'), icon: Icon(Icons.move_to_inbox_outlined, size: 18)),
                  ButtonSegment(value: _View.issued, label: Text('Issued'), icon: Icon(Icons.outbox_outlined, size: 18)),
                ],
                selected: {_view},
                onSelectionChanged: (v) => setState(() => _view = v.first),
              ),
              const SizedBox(height: 16),
              switch (_view) {
                _View.stock => _StockTable(stock: s.stock, highlightLow: nav?.focusFor(ProjectTab.materials) == 'low'),
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
                            label: Text(phaseName(_phaseId)),
                            onDeleted: () => setState(() => _phaseId = null),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (shownIndents.isEmpty)
                      const _Empty('No indents here.')
                    else
                      for (final x in shownIndents)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: FocusHighlight(
                            active: focusIndent == x.id,
                            seq: nav?.seq ?? 0,
                            child: _IndentCard(
                              indent: x,
                              today: today,
                              phase: phaseName(x.phaseId),
                              requestedBy: person(x.requestedBy),
                              decidedBy: x.decidedBy == null ? null : person(x.decidedBy),
                              canApprove: widget.canApprove,
                              canReceive: widget.canReceive,
                              onDecide: (approve) => _decide(context, x, approve),
                              onReceive: () => _receive(context, [x], today, preselect: x),
                            ),
                          ),
                        ),
                  ],
                ),
                _View.received => (grns.value ?? const <Grn>[]).isEmpty
                    ? const _Empty('Nothing received yet. Record a GRN when material arrives.')
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final g in grns.value!)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _GrnCard(
                                grn: g,
                                indentNumber: allIndents.where((x) => x.id == g.indentId).firstOrNull?.number,
                                receivedBy: person(g.receivedBy),
                              ),
                            ),
                        ],
                      ),
                _View.issued => (issues.value ?? const <MaterialIssue>[]).isEmpty
                    ? const _Empty('Nothing issued from the store yet.')
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final i in issues.value!)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _IssueCard(issue: i, phase: phaseName(i.phaseId), issuedBy: person(i.issuedBy)),
                            ),
                        ],
                      ),
              },
            ],
          );
        },
      ),
    );
  }

  Future<void> _run(BuildContext context, Future<void> Function() action, String done) async {
    try {
      await action();
      if (context.mounted) showMessage(context, done);
    } catch (e) {
      if (context.mounted) showMessage(context, '$e'.replaceFirst(RegExp(r'^(Bad state|Invalid argument\(s\)): '), ''), error: true);
    }
  }

  Future<void> _decide(BuildContext context, Indent x, bool approve) async {
    final note = await askText(
      context,
      title: approve ? 'Approve ${x.number}' : 'Reject ${x.number}',
      label: approve ? 'Note for the site (e.g. vendor, budget head)' : 'Reason for rejecting',
    );
    if (note == null || !context.mounted) return;
    await _run(
      context,
      () => ref.read(inventoryRepositoryProvider).decideIndent(widget.project.id, x.id, approve, note, ref.read(currentUserProvider).uid),
      approve ? '${x.number} approved' : '${x.number} rejected',
    );
  }

  Future<void> _raise(BuildContext context, List<ProjectPhase> phases, InventorySummary s) async {
    final result = await showDialog<_FormResult>(
      context: context,
      builder: (_) => _LinesDialog(
        title: 'Raise indent',
        phases: phases,
        suggestions: {
          for (final m in commonMaterials) m.$1: m.$2,
          for (final l in s.stock) l.material: l.unit,
        },
        askNeededBy: true,
      ),
    );
    if (result == null || !context.mounted) return;
    await _run(
      context,
      () => ref.read(inventoryRepositoryProvider).raiseIndent(
        projectId: widget.project.id,
        items: result.lines,
        neededBy: result.date,
        phaseId: result.phaseId,
        note: result.note,
        uid: ref.read(currentUserProvider).uid,
      ),
      'Indent raised. The project manager or CEO will approve it.',
    );
  }

  Future<void> _receive(BuildContext context, List<Indent> approved, String today, {Indent? preselect}) async {
    final result = await showDialog<_FormResult>(
      context: context,
      builder: (_) => _LinesDialog(
        title: preselect == null ? 'Record goods received (GRN)' : 'Receive ${preselect.number}',
        approvedIndents: approved,
        preselect: preselect,
        withRate: true,
        askVendor: true,
        askDate: true,
        today: today,
        suggestions: {for (final m in commonMaterials) m.$1: m.$2},
      ),
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
        uid: ref.read(currentUserProvider).uid,
      ),
      'Goods received and added to stock.',
    );
  }

  Future<void> _issue(
    BuildContext context,
    InventorySummary s,
    List<ProjectPhase> phases,
    Map<String, double> stockByKey,
    String today,
  ) async {
    final result = await showDialog<_FormResult>(
      context: context,
      builder: (_) => _LinesDialog(
        title: 'Issue material to site',
        phases: phases,
        stock: s.stock.where((l) => l.inStock > 0).toList(),
        askIssuedTo: true,
        askDate: true,
        today: today,
      ),
    );
    if (result == null || !context.mounted) return;
    await _run(
      context,
      () => ref.read(inventoryRepositoryProvider).issueMaterial(
        projectId: widget.project.id,
        items: result.lines,
        available: stockByKey,
        date: result.date ?? today,
        phaseId: result.phaseId,
        issuedTo: result.issuedTo,
        note: result.note,
        uid: ref.read(currentUserProvider).uid,
      ),
      'Material issued.',
    );
  }
}

// ---------------------------------------------------------------------------
// Views
// ---------------------------------------------------------------------------

class _Empty extends StatelessWidget {
  const _Empty(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(borderRadius: AppRadius.card, border: Border.all(color: AppColors.line)),
    child: Text(text, style: const TextStyle(color: AppColors.muted)),
  );
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: AppRadius.card,
      border: Border.all(color: AppColors.line),
    ),
    child: child,
  );
}

Widget _lines(List<MaterialLine> items, {bool rates = false}) => Column(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [
    for (final l in items)
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            const Icon(Icons.circle, size: 6, color: AppColors.muted),
            const SizedBox(width: 8),
            Expanded(child: Text(l.material)),
            Text('${formatQty(l.qty)} ${l.unit}', style: const TextStyle(fontWeight: FontWeight.w700)),
            if (rates && l.ratePaise != null) ...[
              const SizedBox(width: 12),
              SizedBox(
                width: 150,
                child: Text(
                  '@ ${Money.format(l.ratePaise!)} = ${Money.compact(l.valuePaise)}',
                  textAlign: TextAlign.right,
                  style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
                ),
              ),
            ],
          ],
        ),
      ),
  ],
);

class _IndentCard extends StatelessWidget {
  const _IndentCard({
    required this.indent,
    required this.today,
    required this.phase,
    required this.requestedBy,
    required this.decidedBy,
    required this.canApprove,
    required this.canReceive,
    required this.onDecide,
    required this.onReceive,
  });

  final Indent indent;
  final String today;
  final String phase;
  final String requestedBy;
  final String? decidedBy;
  final bool canApprove;
  final bool canReceive;
  final ValueChanged<bool> onDecide;
  final VoidCallback onReceive;

  @override
  Widget build(BuildContext context) {
    final x = indent;
    final colors = context.statusColors;
    final late = x.isLate(today);
    final (color, label) = switch (x.status) {
      IndentStatus.pending => (colors.warn, 'Waiting for approval'),
      IndentStatus.approved => late ? (colors.bad, 'Delivery ${x.daysLate(today)}d late') : (Theme.of(context).colorScheme.primary, 'Approved · awaiting delivery'),
      IndentStatus.received => (colors.ok, 'Received'),
      IndentStatus.rejected => (AppColors.muted, 'Rejected'),
    };
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(x.number, style: Theme.of(context).textTheme.titleMedium)),
              Pill(label, color: color, background: color.withValues(alpha: 0.10)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            [
              'Requested by $requestedBy${x.requestedAt == null ? '' : ' on ${WorkDay.display(WorkDay.fromDate(x.requestedAt!))}'}',
              if (x.neededBy != null) 'needed by ${WorkDay.display(x.neededBy)}',
              if (phase.isNotEmpty) phase,
            ].join(' · '),
            style: TextStyle(color: late ? colors.bad : AppColors.muted, fontSize: 13),
          ),
          const SizedBox(height: 10),
          _lines(x.items),
          if (x.note.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(x.note, style: const TextStyle(color: Color(0xFF354657))),
          ],
          if (decidedBy != null) ...[
            const SizedBox(height: 8),
            Text(
              '${x.status == IndentStatus.rejected ? 'Rejected' : 'Approved'} by $decidedBy'
              '${x.decisionNote.isEmpty ? '' : ': ${x.decisionNote}'}',
              style: TextStyle(
                fontSize: 12.5,
                color: x.status == IndentStatus.rejected ? colors.bad : AppColors.muted,
              ),
            ),
          ],
          if ((canApprove && x.isPending) || (canReceive && x.status == IndentStatus.approved)) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
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
                if (canReceive && x.status == IndentStatus.approved)
                  FilledButton.tonalIcon(
                    onPressed: onReceive,
                    icon: const Icon(Icons.move_to_inbox_outlined, size: 18),
                    label: const Text('Record GRN'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _GrnCard extends StatelessWidget {
  const _GrnCard({required this.grn, required this.indentNumber, required this.receivedBy});

  final Grn grn;
  final String? indentNumber;
  final String receivedBy;

  @override
  Widget build(BuildContext context) => _Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text('${grn.number} · ${grn.vendor}', style: Theme.of(context).textTheme.titleMedium)),
            if (grn.valuePaise > 0) Text(Money.compact(grn.valuePaise), style: const TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          [
            WorkDay.display(grn.date),
            if (grn.invoiceNo.isNotEmpty) 'Invoice ${grn.invoiceNo}',
            if (indentNumber != null) 'against $indentNumber',
            'received by $receivedBy',
          ].join(' · '),
          style: const TextStyle(color: AppColors.muted, fontSize: 13),
        ),
        const SizedBox(height: 10),
        _lines(grn.items, rates: true),
        if (grn.note.isNotEmpty) ...[const SizedBox(height: 8), Text(grn.note)],
      ],
    ),
  );
}

class _IssueCard extends StatelessWidget {
  const _IssueCard({required this.issue, required this.phase, required this.issuedBy});

  final MaterialIssue issue;
  final String phase;
  final String issuedBy;

  @override
  Widget build(BuildContext context) => _Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(issue.number, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          [
            WorkDay.display(issue.date),
            if (issue.issuedTo.isNotEmpty) 'to ${issue.issuedTo}',
            if (phase.isNotEmpty) phase,
            'by $issuedBy',
          ].join(' · '),
          style: const TextStyle(color: AppColors.muted, fontSize: 13),
        ),
        const SizedBox(height: 10),
        _lines(issue.items),
        if (issue.note.isNotEmpty) ...[const SizedBox(height: 8), Text(issue.note)],
      ],
    ),
  );
}

class _StockTable extends StatelessWidget {
  const _StockTable({required this.stock, required this.highlightLow});

  final List<StockLine> stock;
  final bool highlightLow;

  @override
  Widget build(BuildContext context) {
    if (stock.isEmpty) return const _Empty('No material on this project yet. Stock appears once goods are received.');
    const head = TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.muted, letterSpacing: 0.4);
    Widget num(String v, {Color? color, bool bold = false}) => Expanded(
      flex: 2,
      child: Text(
        v,
        textAlign: TextAlign.right,
        style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w500, color: color),
      ),
    );
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: AppRadius.card, border: Border.all(color: AppColors.line)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            color: const Color(0xFFF7F9FB),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: const Row(
              children: [
                Expanded(flex: 4, child: Text('MATERIAL', style: head)),
                Expanded(flex: 2, child: Text('IN STOCK', textAlign: TextAlign.right, style: head)),
                Expanded(flex: 2, child: Text('RECEIVED', textAlign: TextAlign.right, style: head)),
                Expanded(flex: 2, child: Text('ISSUED', textAlign: TextAlign.right, style: head)),
                Expanded(flex: 2, child: Text('ON ORDER', textAlign: TextAlign.right, style: head)),
                Expanded(flex: 2, child: Text('REQUESTED', textAlign: TextAlign.right, style: head)),
              ],
            ),
          ),
          for (final l in stock) ...[
            const Divider(height: 1),
            Container(
              color: highlightLow && l.low ? context.statusColors.warnSoft : null,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: Row(
                      children: [
                        Flexible(child: Text(l.material, style: const TextStyle(fontWeight: FontWeight.w700))),
                        if (l.low) ...[
                          const SizedBox(width: 8),
                          Pill('Low', color: context.statusColors.warn, background: context.statusColors.warnSoft),
                        ],
                      ],
                    ),
                  ),
                  num('${formatQty(l.inStock)} ${l.unit}', bold: true, color: l.low ? context.statusColors.bad : null),
                  num(formatQty(l.received)),
                  num(formatQty(l.issued)),
                  num(l.onOrder == 0 ? '—' : formatQty(l.onOrder)),
                  num(l.requested == 0 ? '—' : formatQty(l.requested)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// One dialog for indents, GRNs and issues: a list of material lines plus the
// fields each needs.
// ---------------------------------------------------------------------------

class _FormResult {
  _FormResult({
    required this.lines,
    this.date,
    this.phaseId,
    this.note = '',
    this.vendor = '',
    this.invoiceNo = '',
    this.issuedTo = '',
    this.indentId,
  });

  final List<MaterialLine> lines;
  final String? date;
  final String? phaseId;
  final String note;
  final String vendor;
  final String invoiceNo;
  final String issuedTo;
  final String? indentId;
}

class _Line {
  _Line({this.material = '', this.unit = '', this.qty = ''});
  String material;
  String unit;
  String qty;
  String rate = '';
}

class _LinesDialog extends StatefulWidget {
  const _LinesDialog({
    required this.title,
    this.phases = const [],
    this.suggestions = const {},
    this.stock,
    this.approvedIndents = const [],
    this.preselect,
    this.withRate = false,
    this.askNeededBy = false,
    this.askVendor = false,
    this.askDate = false,
    this.askIssuedTo = false,
    this.today,
  });

  final String title;
  final List<ProjectPhase> phases;

  /// Material name → usual unit, offered while typing.
  final Map<String, String> suggestions;

  /// When set, lines pick from what is in stock (material issue).
  final List<StockLine>? stock;
  final List<Indent> approvedIndents;
  final Indent? preselect;
  final bool withRate;
  final bool askNeededBy;
  final bool askVendor;
  final bool askDate;
  final bool askIssuedTo;
  final String? today;

  @override
  State<_LinesDialog> createState() => _LinesDialogState();
}

class _LinesDialogState extends State<_LinesDialog> {
  final _form = GlobalKey<FormState>();
  var _lines = <_Line>[_Line()];
  String? _date;
  String? _phaseId;
  String? _indentId;
  String _note = '';
  String _vendor = '';
  String _invoice = '';
  String _issuedTo = '';
  var _version = 0;

  @override
  void initState() {
    super.initState();
    _date = widget.askNeededBy ? null : widget.today;
    if (widget.preselect != null) _useIndent(widget.preselect!);
  }

  void _useIndent(Indent x) {
    _indentId = x.id;
    _phaseId = x.phaseId;
    _lines = [for (final l in x.items) _Line(material: l.material, unit: l.unit, qty: formatQty(l.qty))];
    _version++;
  }

  @override
  Widget build(BuildContext context) {
    final stock = widget.stock;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 620,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              key: ValueKey(_version),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.askVendor && widget.approvedIndents.isNotEmpty && widget.preselect == null) ...[
                  DropdownButtonFormField<String?>(
                    initialValue: _indentId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Against indent (optional)'),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('Direct purchase (no indent)')),
                      for (final x in widget.approvedIndents)
                        DropdownMenuItem<String?>(
                          value: x.id,
                          child: Text('${x.number} · ${x.items.map((l) => l.material).join(', ')}', overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (v) => setState(() {
                      final x = widget.approvedIndents.where((i) => i.id == v).firstOrNull;
                      if (x == null) {
                        _indentId = null;
                      } else {
                        _useIndent(x);
                      }
                    }),
                  ),
                  const SizedBox(height: 16),
                ],
                if (widget.askVendor) ...[
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextFormField(
                          decoration: const InputDecoration(labelText: 'Vendor'),
                          validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
                          onChanged: (v) => _vendor = v,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          decoration: const InputDecoration(labelText: 'Invoice / DC no.'),
                          onChanged: (v) => _invoice = v,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
                Text('Materials', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                for (var n = 0; n < _lines.length; n++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 5,
                          child: stock != null
                              ? DropdownButtonFormField<String>(
                                  initialValue: _lines[n].material.isEmpty ? null : '${_lines[n].material}|${_lines[n].unit}',
                                  isExpanded: true,
                                  decoration: const InputDecoration(labelText: 'Material'),
                                  items: [
                                    for (final s in stock)
                                      DropdownMenuItem(
                                        value: '${s.material}|${s.unit}',
                                        child: Text('${s.material} · ${formatQty(s.inStock)} ${s.unit} in stock', overflow: TextOverflow.ellipsis),
                                      ),
                                  ],
                                  validator: (v) => v == null ? 'Choose' : null,
                                  onChanged: (v) => setState(() {
                                    final parts = v!.split('|');
                                    _lines[n].material = parts[0];
                                    _lines[n].unit = parts[1];
                                  }),
                                )
                              : Autocomplete<String>(
                                  initialValue: TextEditingValue(text: _lines[n].material),
                                  optionsBuilder: (v) => widget.suggestions.keys.where(
                                    (m) => v.text.isEmpty || m.toLowerCase().contains(v.text.toLowerCase()),
                                  ),
                                  onSelected: (m) => setState(() {
                                    _lines[n].material = m;
                                    if (_lines[n].unit.isEmpty) _lines[n].unit = widget.suggestions[m] ?? '';
                                    _version++;
                                  }),
                                  fieldViewBuilder: (context, controller, focus, submit) => TextFormField(
                                    controller: controller,
                                    focusNode: focus,
                                    decoration: const InputDecoration(labelText: 'Material'),
                                    validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
                                    onChanged: (v) => _lines[n].material = v,
                                  ),
                                ),
                        ),
                        if (stock == null) ...[
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: TextFormField(
                              initialValue: _lines[n].unit,
                              decoration: const InputDecoration(labelText: 'Unit'),
                              validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
                              onChanged: (v) => _lines[n].unit = v,
                            ),
                          ),
                        ],
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            initialValue: _lines[n].qty,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(labelText: 'Qty'),
                            validator: (v) {
                              final q = double.tryParse(v ?? '');
                              if (q == null || q <= 0) return 'Qty';
                              if (stock != null) {
                                final s = stock.where((s) => s.material == _lines[n].material && s.unit == _lines[n].unit).firstOrNull;
                                if (s != null && q > s.inStock) return 'Max ${formatQty(s.inStock)}';
                              }
                              return null;
                            },
                            onChanged: (v) => _lines[n].qty = v,
                          ),
                        ),
                        if (widget.withRate) ...[
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 3,
                            child: TextFormField(
                              initialValue: _lines[n].rate,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(labelText: 'Rate ₹ / unit'),
                              validator: (v) => (v ?? '').trim().isEmpty || Money.parse(v!) != null ? null : 'Amount',
                              onChanged: (v) => _lines[n].rate = v,
                            ),
                          ),
                        ],
                        IconButton(
                          tooltip: 'Remove line',
                          onPressed: _lines.length == 1
                              ? null
                              : () => setState(() {
                                  _lines.removeAt(n);
                                  _version++;
                                }),
                          icon: const Icon(Icons.close, size: 18),
                        ),
                      ],
                    ),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setState(() => _lines.add(_Line())),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add material'),
                  ),
                ),
                const SizedBox(height: 8),
                if (widget.askNeededBy)
                  DateFormField(
                    label: 'Needed on site by',
                    initialKey: _date,
                    onChanged: (v) => _date = v,
                    validator: (v) => v == null ? 'Choose a date' : null,
                  ),
                if (widget.askDate)
                  DateFormField(
                    label: widget.askVendor ? 'Received on' : 'Issued on',
                    initialKey: _date,
                    onChanged: (v) => _date = v,
                    validator: (v) => v == null ? 'Choose a date' : null,
                  ),
                if (widget.askIssuedTo) ...[
                  const SizedBox(height: 16),
                  TextFormField(
                    decoration: const InputDecoration(labelText: 'Issued to (contractor / crew)'),
                    onChanged: (v) => _issuedTo = v,
                  ),
                ],
                if (widget.phases.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String?>(
                    initialValue: _phaseId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'For phase'),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('No specific phase')),
                      for (final p in widget.phases) DropdownMenuItem<String?>(value: p.id, child: Text(p.name)),
                    ],
                    onChanged: (v) => _phaseId = v,
                  ),
                ],
                const SizedBox(height: 16),
                TextFormField(
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Note (optional)'),
                  onChanged: (v) => _note = v,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            if (!_form.currentState!.validate()) return;
            Navigator.pop(
              context,
              _FormResult(
                lines: [
                  for (final l in _lines)
                    MaterialLine(
                      material: l.material.trim(),
                      unit: l.unit.trim(),
                      qty: double.parse(l.qty),
                      ratePaise: l.rate.trim().isEmpty ? null : Money.parse(l.rate),
                    ),
                ],
                date: _date,
                phaseId: _phaseId,
                note: _note,
                vendor: _vendor,
                invoiceNo: _invoice,
                issuedTo: _issuedTo,
                indentId: _indentId,
              ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
