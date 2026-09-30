import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/config_models.dart';
import '../../../core/config/config_repository.dart';
import '../../../core/dynamic_form/dynamic_fields.dart';
import '../../auth/data/session.dart';
import '../../projects/domain/project.dart';
import '../../settings/presentation/settings_common.dart';
import '../data/finance_repository.dart';
import '../domain/expense.dart';

Future<void> showBudgetEditor(
  BuildContext context, {
  required Project project,
  required List<BudgetLine> budget,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => BudgetEditor(project: project, budget: budget),
  );
}

/// One row per expense category. Revising a category that already has a
/// budget needs a reason, kept in that line's history.
class BudgetEditor extends ConsumerStatefulWidget {
  const BudgetEditor({super.key, required this.project, required this.budget});

  final Project project;
  final List<BudgetLine> budget;

  @override
  ConsumerState<BudgetEditor> createState() => _BudgetEditorState();
}

class _BudgetEditorState extends ConsumerState<BudgetEditor> {
  late final Map<String, int?> _values = {
    for (final b in widget.budget) b.categoryId: b.plannedPaise,
  };
  String? _busyCategory;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(appConfigProvider);
    final categories = config.activeOf(ConfigList.expenseCategories);
    final byId = {for (final b in widget.budget) b.categoryId: b};
    return AlertDialog(
      title: const Text('Edit budget'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final c in categories)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: MoneyFormField(
                    key: ValueKey('budget-${c.id}'),
                    label: c.label,
                    initialPaise: _values[c.id],
                    enabled: _busyCategory == null,
                    onChanged: (v) => _values[c.id] = v,
                    validator: (v) => v != null && v < 0 ? 'Can\'t be negative' : null,
                  ),
                ),
              if (_error != null)
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              if (_busyCategory != null) const LinearProgressIndicator(),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        FilledButton(
          onPressed: _busyCategory != null ? null : () => _saveAll(byId),
          child: const Text('Save all'),
        ),
      ],
    );
  }

  Future<void> _saveAll(Map<String, BudgetLine> byId) async {
    setState(() {
      _error = null;
      _busyCategory = 'all';
    });
    final uid = ref.read(currentUserProvider).uid;
    try {
      for (final entry in _values.entries) {
        final planned = entry.value ?? 0;
        final existing = byId[entry.key];
        if (existing != null && existing.plannedPaise == planned) continue;
        String reason = '';
        if (existing != null) {
          if (!mounted) return;
          final entered = await askText(
            context,
            title: 'Revise ${entry.key} budget',
            label: 'Reason for the change',
          );
          if (entered == null) continue;
          reason = entered;
        }
        await ref
            .read(financeRepositoryProvider)
            .saveBudget(widget.project.id, entry.key, planned, reason, uid);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busyCategory = null);
    }
  }
}
