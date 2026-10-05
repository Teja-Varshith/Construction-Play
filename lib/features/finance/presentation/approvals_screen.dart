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
import '../../projects/data/project_media.dart';
import '../../projects/data/project_repository.dart';
import '../../settings/presentation/settings_common.dart';
import '../data/finance_repository.dart';
import '../domain/expense.dart';
import 'package:go_router/go_router.dart';
import '../../auth/domain/app_user.dart';
import '../../inventory/data/inventory_repository.dart';
import '../../inventory/domain/inventory.dart';
import '../../inventory/presentation/indent_dialogs.dart';
import '../../projects/domain/project_nav.dart';
import '../../users/data/user_repository.dart';

/// Everything waiting on the CEO or admin across the whole portfolio:
/// material indents first (they hold up work on site), then expenses.
class ApprovalsScreen extends ConsumerWidget {
  const ApprovalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(visiblePendingExpensesProvider);
    final indents = ref.watch(visiblePendingIndentsProvider).value ?? const <(String, Indent)>[];
    final projects = ref.watch(visibleProjectsProvider).value ?? const [];
    final projectsById = {for (final p in projects) p.id: p};
    final config = ref.watch(appConfigProvider);
    final people = ref.watch(allUsersProvider).value ?? const <AppUser>[];
    return PageScaffold(
      title: 'Approvals',
      maxWidth: 820,
      body: AsyncView(
        value: pending,
        data: (items) => items.isEmpty && indents.isEmpty
            ? const MessageView(
                icon: Icons.check_circle_outline,
                title: 'Nothing waiting for you',
                message: 'Material indents and expenses that need approval will show up here.',
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (indents.isNotEmpty) ...[
                    Text(
                      '${indents.length} material indent${indents.length == 1 ? '' : 's'} waiting',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    const Text('Site cannot order until these are approved.', style: TextStyle(color: AppColors.muted)),
                    const SizedBox(height: 12),
                    for (final entry in indents)
                      _IndentApproval(
                        projectId: entry.$1,
                        projectName: projectsById[entry.$1]?.name ?? 'Project',
                        indent: entry.$2,
                        requestedBy: people.where((u) => u.uid == entry.$2.requestedBy).firstOrNull?.name ?? 'Site',
                      ),
                    const SizedBox(height: 24),
                  ],
                  if (items.isNotEmpty) ...[
                    Text(
                      '${items.length} expense${items.length == 1 ? '' : 's'} pending approval',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    for (final e in items)
                      _ApprovalCard(
                        expense: e,
                        projectName: projectsById[e.projectId]?.name ?? 'Unknown project',
                        config: config,
                      ),
                  ],
                ],
              ),
      ),
    );
  }
}

class _IndentApproval extends ConsumerStatefulWidget {
  const _IndentApproval({
    required this.projectId,
    required this.projectName,
    required this.indent,
    required this.requestedBy,
  });

  final String projectId;
  final String projectName;
  final Indent indent;
  final String requestedBy;

  @override
  ConsumerState<_IndentApproval> createState() => _IndentApprovalState();
}

class _IndentApprovalState extends ConsumerState<_IndentApproval> {
  bool _busy = false;

  Future<void> _decide(bool approve) async {
    final note = await askIndentDecision(context, widget.indent, approve: approve);
    if (note == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(inventoryRepositoryProvider).decideIndent(
        widget.projectId,
        widget.indent.id,
        approve,
        note,
        ref.read(currentUserProvider).uid,
      );
      if (mounted) showMessage(context, '${widget.indent.number} ${approve ? 'approved' : 'rejected'}');
    } catch (e) {
      if (mounted) showMessage(context, '$e'.replaceFirst(RegExp(r'^(Bad state|Invalid argument\(s\)): '), ''), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final x = widget.indent;
    final waited = x.waitingDays(DateTime.now());
    final stock = ref.watch(projectInventoryProvider(widget.projectId)).value;
    // What the site already has of each requested material, so the approver
    // can tell a real shortage from an over-order.
    final onSite = [
      for (final l in x.items)
        if (stock?.line(l.key) case final s?)
          '${s.material}: ${formatQty(s.inStock)} ${s.unit} in stock'
              '${s.daysLeft == null ? '' : ' (~${s.daysLeft!.floor()} days)'}'
              '${s.onOrder > 0 ? ', ${formatQty(s.onOrder)} on order' : ''}',
    ];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: AppRadius.card,
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.inventory_2_outlined, size: 20, color: AppColors.muted),
              const SizedBox(width: 8),
              Expanded(
                child: Text('${x.number} · ${widget.projectName}', style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
              if (waited > 0)
                Pill(
                  'Waiting $waited day${waited == 1 ? '' : 's'}',
                  color: waited >= 3 ? context.statusColors.bad : context.statusColors.warn,
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            [
              'By ${widget.requestedBy}',
              if (x.neededBy != null) 'needed by ${WorkDay.display(x.neededBy)}',
            ].join(' · '),
            style: const TextStyle(color: AppColors.muted, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Text(x.items.map((l) => '${formatQty(l.qty)} ${l.unit} ${l.material}').join(' · ')),
          if (x.note.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(x.note, style: const TextStyle(color: AppColors.muted)),
          ],
          if (onSite.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(onSite.join(' · '), style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
          ],
          const SizedBox(height: 10),
          DecisionButtons(
            busy: _busy,
            onApprove: () => _decide(true),
            onReject: () => _decide(false),
            secondary: TextButton(
              onPressed: () => context.push(ProjectLink(ProjectTab.materials, 'indent:${x.id}').path(widget.projectId)),
              child: const Text('Open in project'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ApprovalCard extends ConsumerStatefulWidget {
  const _ApprovalCard({required this.expense, required this.projectName, required this.config});

  final Expense expense;
  final String projectName;
  final AppConfig config;

  @override
  ConsumerState<_ApprovalCard> createState() => _ApprovalCardState();
}

class _ApprovalCardState extends ConsumerState<_ApprovalCard> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final e = widget.expense;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.line)),
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
                    Text(
                      widget.projectName,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(color: AppColors.muted),
                    ),
                    Text(e.payee, style: const TextStyle(fontWeight: FontWeight.w900)),
                    Text(
                      '${widget.config.labelOf(ConfigList.expenseCategories, e.categoryId)} · ${WorkDay.display(e.date)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              Text(Money.format(e.amountPaise), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            ],
          ),
          if (e.description.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(e.description),
          ],
          if (e.flags.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: [
                for (final flag in e.flags)
                  if (ExpenseFlag.fromValue(flag) != null)
                    Pill(ExpenseFlag.fromValue(flag)!.label, color: context.statusColors.warn),
              ],
            ),
          ],
          if (e.billPath != null) ...[
            const SizedBox(height: 10),
            SizedBox(height: 140, width: 140, child: ProjectPhoto(path: e.billPath!)),
          ],
          const SizedBox(height: 10),
          DecisionButtons(busy: _busy, onApprove: () => _decide(true), onReject: () => _decide(false)),
        ],
      ),
    );
  }

  Future<void> _decide(bool approve) async {
    String reason = '';
    if (!approve) {
      final entered = await askText(context, title: 'Reject expense', label: 'Reason');
      if (entered == null) return;
      reason = entered;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(financeRepositoryProvider)
          .decide(widget.expense.id, approve, reason, ref.read(currentUserProvider).uid);
    } catch (e) {
      if (mounted) showMessage(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
