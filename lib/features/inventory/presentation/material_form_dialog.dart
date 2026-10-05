import 'package:flutter/material.dart';

import '../../../core/dynamic_form/dynamic_fields.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/work_day.dart';
import '../../projects/domain/project_detail.dart';
import '../domain/inventory.dart';

enum MaterialFormKind { indent, grn, issue }

class MaterialFormResult {
  MaterialFormResult({
    required this.lines,
    this.date,
    this.phaseId,
    this.note = '',
    this.vendor = '',
    this.invoiceNo = '',
    this.issuedTo = '',
    this.indentId,
    this.completesIndent = true,
  });

  final List<MaterialLine> lines;
  final String? date;
  final String? phaseId;
  final String note;
  final String vendor;
  final String invoiceNo;
  final String issuedTo;
  final String? indentId;

  /// For a GRN against an indent: everything ordered has now arrived.
  final bool completesIndent;
}

/// One dialog for raising an indent, recording a delivery (GRN) and issuing
/// material: a list of material lines plus the fields each needs. It reads the
/// current [summary] to suggest materials, units, vendors and last rates, and
/// to show what is in stock while typing.
Future<MaterialFormResult?> showMaterialForm(
  BuildContext context, {
  required MaterialFormKind kind,
  required InventorySummary summary,
  required String today,
  List<ProjectPhase> phases = const [],
  List<Indent> openIndents = const [],
  Indent? against,
  List<MaterialLine> prefill = const [],
  String? phaseId,
  List<String> issuedToSuggestions = const [],
}) {
  final narrow = MediaQuery.sizeOf(context).width < 600;
  return showDialog<MaterialFormResult>(
    context: context,
    barrierDismissible: false,
    builder: (_) => Dialog(
      insetPadding: EdgeInsets.symmetric(horizontal: narrow ? 12 : 40, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: _MaterialForm(
          kind: kind,
          summary: summary,
          today: today,
          phases: phases,
          openIndents: openIndents,
          against: against,
          prefill: prefill,
          phaseId: phaseId,
          issuedToSuggestions: issuedToSuggestions,
        ),
      ),
    ),
  );
}

class _Line {
  _Line({String material = '', String unit = '', String qty = '', String rate = ''})
    : material = TextEditingController(text: material),
      unit = TextEditingController(text: unit),
      qty = TextEditingController(text: qty),
      rate = TextEditingController(text: rate),
      id = _next++;

  static var _next = 0;
  final int id;
  final TextEditingController material;
  final TextEditingController unit;
  final TextEditingController qty;
  final TextEditingController rate;
  final focus = FocusNode();

  String get key => '${material.text.trim().toLowerCase()}|${unit.text.trim().toLowerCase()}';
  double? get qtyValue => double.tryParse(qty.text.trim());
  int? get ratePaise => rate.text.trim().isEmpty ? null : Money.parse(rate.text);

  void dispose() {
    material.dispose();
    unit.dispose();
    qty.dispose();
    rate.dispose();
    focus.dispose();
  }
}

class _MaterialForm extends StatefulWidget {
  const _MaterialForm({
    required this.kind,
    required this.summary,
    required this.today,
    required this.phases,
    required this.openIndents,
    required this.against,
    required this.prefill,
    required this.phaseId,
    required this.issuedToSuggestions,
  });

  final MaterialFormKind kind;
  final InventorySummary summary;
  final String today;
  final List<ProjectPhase> phases;
  final List<Indent> openIndents;
  final Indent? against;
  final List<MaterialLine> prefill;
  final String? phaseId;
  final List<String> issuedToSuggestions;

  @override
  State<_MaterialForm> createState() => _MaterialFormState();
}

class _MaterialFormState extends State<_MaterialForm> {
  final _form = GlobalKey<FormState>();
  final _lines = <_Line>[];
  String? _date;
  String? _phaseId;
  String? _indentId;
  String _note = '';
  String _vendor = '';
  String _invoice = '';
  String _issuedTo = '';

  bool get _grn => widget.kind == MaterialFormKind.grn;
  bool get _issue => widget.kind == MaterialFormKind.issue;
  bool get _indent => widget.kind == MaterialFormKind.indent;

  /// Material name → usual unit. Materials already on the project first.
  late final Map<String, String> _suggestions = {
    for (final l in widget.summary.stock) l.material: l.unit,
    for (final m in commonMaterials)
      if (!widget.summary.stock.any((l) => l.material.toLowerCase() == m.$1.toLowerCase())) m.$1: m.$2,
  };

  List<StockLine> get _inStock => widget.summary.stock.where((l) => l.inStock > 1e-9).toList();

  Indent? get _selectedIndent =>
      widget.against ?? widget.openIndents.where((x) => x.id == _indentId).firstOrNull;

  @override
  void initState() {
    super.initState();
    _date = _indent ? null : widget.today;
    _phaseId = widget.phaseId;
    if (widget.against != null) {
      _useIndent(widget.against!);
    } else if (widget.prefill.isNotEmpty) {
      _lines.addAll([for (final l in widget.prefill) _lineFrom(l)]);
    } else {
      _lines.add(_Line());
    }
  }

  @override
  void dispose() {
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  /// Controllers of removed lines are still attached to their fields until
  /// the next frame, so they are disposed after it.
  void _disposeLater(List<_Line> lines) => WidgetsBinding.instance.addPostFrameCallback((_) {
    for (final l in lines) {
      l.dispose();
    }
  });

  _Line _lineFrom(MaterialLine l) {
    final rate = _grn ? (l.ratePaise ?? widget.summary.lastRate(l.key)) : null;
    return _Line(
      material: l.material,
      unit: l.unit,
      qty: l.qty > 0 ? formatQty(l.qty) : '',
      rate: rate == null ? '' : Money.toInput(rate),
    );
  }

  /// Fills the lines with what is still to arrive on [x].
  void _useIndent(Indent x) {
    _indentId = x.id;
    _phaseId = x.phaseId;
    final left = widget.summary.remaining(x);
    _disposeLater([..._lines]);
    _lines
      ..clear()
      ..addAll([for (final l in left.isEmpty ? x.items : left) _lineFrom(l)]);
  }

  /// Whether this delivery, with what came before, covers the whole indent.
  bool _completes(Indent x) {
    for (final l in x.items) {
      final now = _lines.where((f) => f.key == l.key).fold<double>(0, (s, f) => s + (f.qtyValue ?? 0));
      if (widget.summary.receivedFor(x, l) + now < l.qty - 1e-9) return false;
    }
    return true;
  }

  int get _totalPaise => _lines.fold(0, (s, l) {
    final q = l.qtyValue, r = l.ratePaise;
    return q == null || r == null ? s : s + (r * q).round();
  });

  String get _title => switch (widget.kind) {
    MaterialFormKind.indent => 'Raise indent',
    MaterialFormKind.grn => widget.against == null ? 'Record delivery (GRN)' : 'Record delivery · ${widget.against!.number}',
    MaterialFormKind.issue => 'Issue material to site',
  };

  String get _subtitle => switch (widget.kind) {
    MaterialFormKind.indent => 'Ask for material. The project manager or CEO approves it before it is ordered.',
    MaterialFormKind.grn => 'What arrived on site, from whom and at what rate. It is added to stock.',
    MaterialFormKind.issue => 'Material handed over from the site store to the work. It is taken out of stock.',
  };

  void _save() {
    if (!_form.currentState!.validate()) return;
    final x = _selectedIndent;
    Navigator.pop(
      context,
      MaterialFormResult(
        lines: [
          for (final l in _lines)
            MaterialLine(
              material: l.material.text.trim(),
              unit: l.unit.text.trim(),
              qty: l.qtyValue!,
              ratePaise: _grn ? l.ratePaise : null,
            ),
        ],
        date: _date,
        phaseId: _phaseId,
        note: _note,
        vendor: _vendor,
        invoiceNo: _invoice,
        issuedTo: _issuedTo,
        indentId: _grn ? x?.id : null,
        completesIndent: x == null || _completes(x),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final x = _selectedIndent;
    return Form(
      key: _form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 22, 12, 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text(_subtitle, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_grn && widget.against == null && widget.openIndents.isNotEmpty) ...[
                    DropdownButtonFormField<String?>(
                      initialValue: _indentId,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Against indent'),
                      items: [
                        const DropdownMenuItem<String?>(value: null, child: Text('Direct purchase (no indent)')),
                        for (final i in widget.openIndents)
                          DropdownMenuItem<String?>(
                            value: i.id,
                            child: Text(
                              '${i.number} · ${i.items.map((l) => l.material).join(', ')}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (v) => setState(() {
                        final i = widget.openIndents.where((i) => i.id == v).firstOrNull;
                        if (i == null) {
                          _indentId = null;
                        } else {
                          _useIndent(i);
                        }
                      }),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (_grn) ...[
                    _Wrap2(
                      first: _SuggestField(
                        label: 'Vendor',
                        initial: _vendor,
                        options: widget.summary.vendors,
                        validator: (v) => v.trim().isEmpty ? 'Required' : null,
                        onChanged: (v) => _vendor = v,
                      ),
                      second: TextFormField(
                        initialValue: _invoice,
                        decoration: const InputDecoration(labelText: 'Invoice / DC no.'),
                        onChanged: (v) => _invoice = v,
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                  Row(
                    children: [
                      Text('Materials', style: theme.textTheme.titleSmall),
                      const Spacer(),
                      if (_grn && _totalPaise > 0)
                        Flexible(
                          child: Text(
                            'Total ${Money.format(_totalPaise)}',
                            textAlign: TextAlign.right,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  for (var n = 0; n < _lines.length; n++) _lineRow(n),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => setState(() => _lines.add(_Line())),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add another material'),
                    ),
                  ),
                  if (_grn && x != null) ...[
                    const SizedBox(height: 4),
                    _InfoBox(
                      icon: _completes(x) ? Icons.task_alt : Icons.timelapse,
                      color: _completes(x) ? context.statusColors.ok : context.statusColors.warn,
                      text: _completes(x)
                          ? 'This completes ${x.number}. It will be marked received.'
                          : 'Part delivery. ${x.number} stays open for the rest; close it short later if the rest is not coming.',
                    ),
                  ],
                  const SizedBox(height: 16),
                  _Wrap2(
                    first: DateFormField(
                      label: _indent ? 'Needed on site by' : (_grn ? 'Received on' : 'Issued on'),
                      initialKey: _date,
                      firstDate: _indent ? WorkDay.tryParse(widget.today) : null,
                      lastDate: _indent ? null : WorkDay.tryParse(widget.today),
                      onChanged: (v) => _date = v,
                      validator: (v) => v == null ? 'Choose a date' : null,
                    ),
                    second: _issue
                        ? _SuggestField(
                            label: 'Issued to (contractor / crew)',
                            initial: _issuedTo,
                            options: widget.issuedToSuggestions,
                            onChanged: (v) => _issuedTo = v,
                          )
                        : (!_grn && widget.phases.isNotEmpty ? _phaseField() : null),
                  ),
                  if (_issue && widget.phases.isNotEmpty) ...[const SizedBox(height: 16), _phaseField()],
                  const SizedBox(height: 16),
                  TextFormField(
                    initialValue: _note,
                    minLines: 1,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: _indent ? 'Note (optional) — why it is needed, brand, size…' : 'Note (optional)',
                    ),
                    onChanged: (v) => _note = v,
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
            child: OverflowBar(
              alignment: MainAxisAlignment.end,
              spacing: 8,
              overflowSpacing: 8,
              overflowAlignment: OverflowBarAlignment.end,
              children: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                FilledButton(
                  onPressed: _save,
                  child: Text(switch (widget.kind) {
                    MaterialFormKind.indent => 'Send for approval',
                    MaterialFormKind.grn => 'Add to stock',
                    MaterialFormKind.issue => 'Issue',
                  }),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _phaseField() => DropdownButtonFormField<String?>(
    initialValue: widget.phases.any((p) => p.id == _phaseId) ? _phaseId : null,
    isExpanded: true,
    decoration: const InputDecoration(labelText: 'For phase'),
    items: [
      const DropdownMenuItem<String?>(value: null, child: Text('No specific phase')),
      for (final p in widget.phases) DropdownMenuItem<String?>(value: p.id, child: Text(p.name, overflow: TextOverflow.ellipsis)),
    ],
    onChanged: (v) => _phaseId = v,
  );

  /// Stock context under a line: what the site has, and for a GRN against an
  /// indent, what was ordered and already received.
  String? _hint(_Line l) {
    if (l.material.text.trim().isEmpty) return null;
    final s = widget.summary.line(l.key);
    final x = _selectedIndent;
    final ordered = x?.items.where((i) => i.key == l.key).firstOrNull;
    final parts = <String>[
      if (ordered != null)
        'Ordered ${formatQty(ordered.qty)}, received ${formatQty(widget.summary.receivedFor(x!, ordered))}',
      if (s != null) '${formatQty(s.inStock)} ${s.unit} in stock',
      if (s != null && s.daysLeft != null && !_grn) '~${s.daysLeft!.floor()} days of use',
      if (s != null && s.onOrder > 0 && _indent) '${formatQty(s.onOrder)} on order',
      if (_grn && l.qtyValue != null && l.ratePaise != null) '= ${Money.format((l.ratePaise! * l.qtyValue!).round())}',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  Widget _lineRow(int n) {
    final l = _lines[n];
    final material = _issue
        ? DropdownButtonFormField<String>(
            initialValue: _inStock.any((s) => s.key == l.key) ? l.key : null,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Material'),
            items: [
              for (final s in _inStock)
                DropdownMenuItem(
                  value: s.key,
                  child: Text('${s.material} · ${formatQty(s.inStock)} ${s.unit}', overflow: TextOverflow.ellipsis),
                ),
            ],
            validator: (v) => v == null ? 'Choose' : null,
            onChanged: (v) => setState(() {
              final s = _inStock.firstWhere((s) => s.key == v);
              l.material.text = s.material;
              l.unit.text = s.unit;
            }),
          )
        : RawAutocomplete<String>(
            textEditingController: l.material,
            focusNode: l.focus,
            optionsBuilder: (v) {
              final q = v.text.trim().toLowerCase();
              return _suggestions.keys.where((m) => q.isEmpty || m.toLowerCase().contains(q)).take(12);
            },
            onSelected: (m) => setState(() {
              l.unit.text = _suggestions[m] ?? l.unit.text;
              if (_grn && l.rate.text.trim().isEmpty) {
                final r = widget.summary.lastRate('${m.toLowerCase()}|${l.unit.text.trim().toLowerCase()}');
                if (r != null) l.rate.text = Money.toInput(r);
              }
            }),
            fieldViewBuilder: (context, controller, focus, submit) => TextFormField(
              controller: controller,
              focusNode: focus,
              decoration: const InputDecoration(labelText: 'Material'),
              validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
              onChanged: (_) => setState(() {}),
            ),
            optionsViewBuilder: (context, onSelected, options) => _Options(
              options: options.toList(),
              onSelected: onSelected,
              describe: (m) {
                final s = widget.summary.stock.where((s) => s.material == m).firstOrNull;
                return s == null ? _suggestions[m] ?? '' : '${formatQty(s.inStock)} ${s.unit} in stock';
              },
            ),
          );
    final unit = TextFormField(
      controller: l.unit,
      readOnly: _issue,
      decoration: const InputDecoration(labelText: 'Unit'),
      validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
      onChanged: (_) => setState(() {}),
    );
    final qty = TextFormField(
      controller: l.qty,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: const InputDecoration(labelText: 'Qty'),
      onChanged: (_) => setState(() {}),
      validator: (v) {
        final q = double.tryParse((v ?? '').trim());
        if (q == null || q <= 0) return 'Qty';
        if (_issue) {
          final s = widget.summary.line(l.key);
          final total = _lines.where((o) => o.key == l.key).fold<double>(0, (t, o) => t + (o.qtyValue ?? 0));
          if (s != null && total > s.inStock + 1e-9) return 'Max ${formatQty(s.inStock)}';
        }
        return null;
      },
    );
    final rate = _grn
        ? TextFormField(
            controller: l.rate,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Rate ₹/unit'),
            onChanged: (_) => setState(() {}),
            validator: (v) => (v ?? '').trim().isEmpty || Money.parse(v!) != null ? null : 'Amount',
          )
        : null;
    final remove = IconButton(
      tooltip: 'Remove line',
      onPressed: _lines.length == 1
          ? null
          : () => setState(() {
              _disposeLater([_lines.removeAt(n)]);
            }),
      icon: const Icon(Icons.delete_outline, size: 20),
    );
    final hint = _hint(l);
    return Container(
      key: ValueKey(l.id),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 12, 4, 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.line),
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          final stacked = c.maxWidth < 480;
          final numbers = [
            if (!_issue) Expanded(flex: 2, child: unit),
            if (!_issue) const SizedBox(width: 8),
            Expanded(flex: 2, child: qty),
            if (rate != null) ...[const SizedBox(width: 8), Expanded(flex: 3, child: rate)],
          ];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (stacked) ...[
                Row(children: [Expanded(child: material), remove]),
                const SizedBox(height: 8),
                Padding(padding: const EdgeInsets.only(right: 8), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: numbers)),
              ] else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 5, child: material),
                    const SizedBox(width: 8),
                    ...numbers,
                    remove,
                  ],
                ),
              if (hint != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6, right: 8),
                  child: Text(hint, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Two fields side by side, stacked on narrow screens. [second] may be null.
class _Wrap2 extends StatelessWidget {
  const _Wrap2({required this.first, this.second});

  final Widget first;
  final Widget? second;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      if (second == null) return first;
      if (c.maxWidth < 480) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [first, const SizedBox(height: 16), second!]);
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [Expanded(child: first), const SizedBox(width: 12), Expanded(child: second!)],
      );
    },
  );
}

class _InfoBox extends StatelessWidget {
  const _InfoBox({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(AppRadius.sm)),
    child: Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600))),
      ],
    ),
  );
}

/// A text field with typed-ahead suggestions (vendors, crews).
class _SuggestField extends StatefulWidget {
  const _SuggestField({
    required this.label,
    required this.initial,
    required this.options,
    required this.onChanged,
    this.validator,
  });

  final String label;
  final String initial;
  final List<String> options;
  final ValueChanged<String> onChanged;
  final String? Function(String value)? validator;

  @override
  State<_SuggestField> createState() => _SuggestFieldState();
}

class _SuggestFieldState extends State<_SuggestField> {
  late final _controller = TextEditingController(text: widget.initial);
  final _focus = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RawAutocomplete<String>(
    textEditingController: _controller,
    focusNode: _focus,
    optionsBuilder: (v) {
      final q = v.text.trim().toLowerCase();
      if (q.isEmpty) return widget.options.take(8);
      return widget.options.where((o) => o.toLowerCase().contains(q) && o.toLowerCase() != q).take(8);
    },
    onSelected: widget.onChanged,
    fieldViewBuilder: (context, controller, focus, submit) => TextFormField(
      controller: controller,
      focusNode: focus,
      decoration: InputDecoration(labelText: widget.label),
      validator: widget.validator == null ? null : (v) => widget.validator!(v ?? ''),
      onChanged: widget.onChanged,
    ),
    optionsViewBuilder: (context, onSelected, options) =>
        _Options(options: options.toList(), onSelected: onSelected),
  );
}

class _Options extends StatelessWidget {
  const _Options({required this.options, required this.onSelected, this.describe});

  final List<String> options;
  final AutocompleteOnSelected<String> onSelected;
  final String Function(String option)? describe;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topLeft,
    child: Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 260, maxWidth: 360),
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 4),
          shrinkWrap: true,
          children: [
            for (final o in options)
              ListTile(
                dense: true,
                title: Text(o),
                subtitle: describe == null ? null : Text(describe!(o), style: const TextStyle(fontSize: 12)),
                onTap: () => onSelected(o),
              ),
          ],
        ),
      ),
    ),
  );
}
