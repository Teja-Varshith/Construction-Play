import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/config_models.dart';
import '../../../core/config/config_repository.dart';
import '../../../core/dynamic_form/dynamic_fields.dart';
import '../../../core/utils/work_day.dart';
import '../../../core/widgets/common.dart';
import '../../auth/data/session.dart';
import '../../projects/data/project_detail_repository.dart';
import '../../projects/data/project_media.dart';
import '../../projects/domain/project.dart';
import '../../settings/presentation/settings_common.dart';
import '../data/finance_repository.dart';
import '../domain/expense.dart';
import '../domain/finance_rules.dart';

Future<void> showExpenseEditor(
  BuildContext context, {
  required Project project,
  Expense? expense,
  ExpenseDraft? draft,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => ExpenseEditor(project: project, expense: expense, draft: draft),
  );
}

/// Pre-filled values for a new expense booked from somewhere else (a GRN).
class ExpenseDraft {
  const ExpenseDraft({
    this.amountPaise,
    this.payee = '',
    this.date,
    this.description = '',
    this.phaseId,
    this.categoryHint,
    this.grnId,
  });

  final int? amountPaise;
  final String payee;
  final String? date;
  final String description;
  final String? phaseId;

  /// Picks the first active category whose id or label contains this word.
  final String? categoryHint;
  final String? grnId;
}

/// Logs a new expense, or edits/resubmits an existing one. Duplicate and
/// split-bill checks run against the project's other expenses before save.
class ExpenseEditor extends ConsumerStatefulWidget {
  const ExpenseEditor({super.key, required this.project, this.expense, this.draft});

  final Project project;
  final Expense? expense;

  /// Starting values for a new expense; ignored when editing.
  final ExpenseDraft? draft;

  @override
  ConsumerState<ExpenseEditor> createState() => _ExpenseEditorState();
}

class _ExpenseEditorState extends ConsumerState<ExpenseEditor> {
  final _form = GlobalKey<FormState>();
  final _custom = <String, dynamic>{};
  int? _amountPaise;
  String? _categoryId;
  String? _phaseId;
  String _payee = '';
  String? _date;
  String _description = '';
  PlatformFile? _newBill;
  String? _billPath;
  String? _billHash;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.expense;
    _amountPaise = e?.amountPaise;
    _categoryId = e?.categoryId;
    _phaseId = e?.phaseId;
    _payee = e?.payee ?? '';
    _date = e?.date ??
        WorkDay.today(
          utcOffsetMinutes: ref.read(appConfigProvider).company.utcOffsetMinutes,
        );
    _description = e?.description ?? '';
    _billPath = e?.billPath;
    _billHash = e?.billHash;
    if (e != null) _custom.addAll(e.custom);
    final d = e == null ? widget.draft : null;
    if (d != null) {
      _amountPaise = d.amountPaise;
      _payee = d.payee;
      _date = d.date ?? _date;
      _description = d.description;
      _phaseId = d.phaseId;
      final hint = d.categoryHint?.toLowerCase();
      if (hint != null) {
        _categoryId = ref
            .read(appConfigProvider)
            .activeOf(ConfigList.expenseCategories)
            .where((c) => c.id.toLowerCase().contains(hint) || c.label.toLowerCase().contains(hint))
            .firstOrNull
            ?.id;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(appConfigProvider);
    final categories = {
      for (final c in config.activeOf(ConfigList.expenseCategories)) c.id: c.label,
    };
    if (_categoryId != null && !categories.containsKey(_categoryId)) {
      categories[_categoryId!] = 'Previous: $_categoryId';
    }
    final phases = ref.watch(projectPhasesProvider(widget.project.id)).value ?? const [];
    final phaseChoices = {for (final p in phases) p.id: p.name};
    if (_phaseId != null && !phaseChoices.containsKey(_phaseId)) {
      phaseChoices[_phaseId!] = 'Archived phase';
    }
    final editing = widget.expense != null;
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text(editing ? 'Edit expense' : widget.draft?.grnId != null ? 'Book delivery as expense' : 'Log an expense'),
        content: SizedBox(
          width: 540,
          child: SingleChildScrollView(
            child: Form(
              key: _form,
              child: AbsorbPointer(
                absorbing: _busy,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    MoneyFormField(
                      label: 'Amount',
                      initialPaise: _amountPaise,
                      onChanged: (v) => _amountPaise = v,
                      validator: (v) => v == null || v <= 0 ? 'Enter an amount' : null,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: _categoryId,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Category'),
                      items: [
                        for (final entry in categories.entries)
                          DropdownMenuItem(
                            value: entry.key,
                            child: Text(entry.value, overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      onChanged: (v) => setState(() => _categoryId = v),
                      validator: (v) => v == null ? 'Choose a category' : null,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String?>(
                      initialValue: _phaseId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Project phase',
                        helperText: 'Counts against that phase’s budget',
                      ),
                      items: [
                        const DropdownMenuItem<String?>(value: null, child: Text('Not for a specific phase')),
                        for (final entry in phaseChoices.entries)
                          DropdownMenuItem<String?>(
                            value: entry.key,
                            child: Text(entry.value, overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      onChanged: (v) => setState(() => _phaseId = v),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      initialValue: _payee,
                      decoration: const InputDecoration(labelText: 'Paid to (vendor / person)'),
                      validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
                      onChanged: (v) => _payee = v.trim(),
                    ),
                    const SizedBox(height: 16),
                    DateFormField(
                      label: 'Bill date',
                      initialKey: _date,
                      validator: (v) => v == null ? 'Choose a date' : null,
                      onChanged: (v) => _date = v,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      initialValue: _description,
                      maxLines: 3,
                      decoration: const InputDecoration(labelText: 'Description (optional)'),
                      onChanged: (v) => _description = v.trim(),
                    ),
                    const SizedBox(height: 16),
                    const Text('Bill photo'),
                    if (_newBill != null) Text(_newBill!.name),
                    if (_newBill == null && _billPath != null) const Text('Existing bill photo retained'),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.attach_file),
                      label: const Text('Choose photo'),
                      onPressed: () async {
                        final file = await ProjectMedia.pickDocument();
                        if (file == null || !mounted) return;
                        final bytes = await file.readAsBytes();
                        setState(() {
                          _newBill = file;
                          _billHash = sha256.convert(bytes).toString();
                        });
                      },
                    ),
                    DynamicFields(
                      fields: config.activeFieldsFor(FieldEntity.expense),
                      values: _custom,
                      onChanged: (key, value) => setState(() => _custom[key] = value),
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          _error!,
                          style: TextStyle(color: Theme.of(context).colorScheme.error),
                        ),
                      ),
                    if (_busy) ...[
                      const SizedBox(height: 8),
                      const LinearProgressIndicator(),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final uid = ref.read(currentUserProvider).uid;
    final config = ref.read(appConfigProvider);
    final existing = ref.read(projectExpensesProvider(widget.project.id)).value ?? const [];
    final warnings = ExpenseChecks.check(
      id: widget.expense?.id,
      amountPaise: _amountPaise!,
      categoryId: _categoryId!,
      payee: _payee,
      date: _date!,
      billHash: _billHash,
      thresholdPaise: config.company.approvalThresholdPaise,
      existing: existing,
    );
    if (warnings.isNotEmpty) {
      final proceed = await confirmAction(
        context,
        title: 'Before you save',
        message: warnings.map((w) => w.message).join('\n\n'),
        confirmLabel: 'Save anyway',
      );
      if (!proceed) return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      var billPath = _billPath;
      if (_newBill != null) {
        billPath = await ProjectMedia.upload(widget.project.id, _newBill!);
      }
      String? overrideReason;
      while (true) {
        try {
          await ref.read(financeRepositoryProvider).submit(
                projectId: widget.project.id,
                amountPaise: _amountPaise!,
                categoryId: _categoryId!,
                payee: _payee,
                date: _date!,
                description: _description,
                billPath: billPath,
                billHash: _billHash,
                flags: [for (final w in warnings) w.flag.value],
                custom: _custom,
                thresholdPaise: config.company.approvalThresholdPaise,
                financeLockedUntil: config.company.financeLockedUntil,
                uid: uid,
                phaseId: _phaseId,
                id: widget.expense?.id,
                expectedRevision: widget.expense?.revision,
                lockOverrideReason: overrideReason,
                grnId: widget.expense == null ? widget.draft?.grnId : null,
              );
          break;
        } on StateError catch (e) {
          // Only an admin can override a closed accounting period, and only
          // with a reason (see firestore.rules `validPeriod`).
          if (!e.message.contains('closed for accounting') ||
              !ref.read(currentUserProvider).isAdmin ||
              overrideReason != null) {
            rethrow;
          }
          if (!mounted) return;
          final reason = await askText(
            context,
            title: 'Closed accounting period',
            label: 'Reason to record this expense anyway',
          );
          if (reason == null) return;
          overrideReason = reason;
        }
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
