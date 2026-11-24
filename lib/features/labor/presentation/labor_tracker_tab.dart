import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/common.dart';
import '../../auth/data/session.dart';
import '../data/labor_repository.dart';
import '../domain/labor_model.dart';

class LaborTrackerTab extends ConsumerStatefulWidget {
  const LaborTrackerTab({super.key, required this.projectId});

  final String projectId;

  @override
  ConsumerState<LaborTrackerTab> createState() => _LaborTrackerTabState();
}

class _LaborTrackerTabState extends ConsumerState<LaborTrackerTab> {
  late final String _selectedDate = DateFormat('yyyy-MM-dd').format(DateTime.now());

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(currentUserProvider);
    final musterAsync = ref.watch(todayLaborProvider((projectId: widget.projectId, date: _selectedDate)));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Date selection and add muster button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.engineering_outlined, color: AppColors.blue),
                  const SizedBox(width: 8),
                  Text(
                    'Daily Labor & Workforce',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              FilledButton.icon(
                onPressed: () => _openAddEntryDialog(null),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add Worker Crew'),
              ),
            ],
          ),
          const SizedBox(height: 16),

          AsyncView(
            value: musterAsync,
            data: (muster) {
              final entries = muster?.entries ?? [];
              final totalCount = muster?.totalWorkers ?? 0;
              final totalCost = muster?.totalDailyWagePaise ?? 0;
              final isVerified = muster?.verifiedByManager ?? false;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // KPI cards
                  Row(
                    children: [
                      Expanded(
                        child: Card(
                          color: AppColors.blue.withValues(alpha: 0.08),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: BorderSide(color: AppColors.blue.withValues(alpha: 0.2)),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Total Laborers Today', style: TextStyle(color: AppColors.inkSoft)),
                                const SizedBox(height: 6),
                                Text(
                                  '$totalCount workers',
                                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.blue,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Card(
                          color: Colors.teal.withValues(alpha: 0.08),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: BorderSide(color: Colors.teal.withValues(alpha: 0.2)),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Daily Wage Bill', style: TextStyle(color: AppColors.inkSoft)),
                                const SizedBox(height: 6),
                                Text(
                                  Money.format(totalCost),
                                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.teal,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Card(
                          color: (isVerified ? Colors.green : Colors.amber.shade900).withValues(alpha: 0.08),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: BorderSide(color: (isVerified ? Colors.green : Colors.amber.shade900).withValues(alpha: 0.2)),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Manager Verification', style: TextStyle(color: AppColors.inkSoft)),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Icon(
                                      isVerified ? Icons.verified : Icons.pending_actions,
                                      color: isVerified ? Colors.green : Colors.amber.shade900,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      isVerified ? 'Verified' : 'Pending',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: isVerified ? Colors.green : Colors.amber.shade900,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  if (me.isManager && !isVerified && entries.isNotEmpty) ...[
                    OutlinedButton.icon(
                      onPressed: () => _verifyMuster(),
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('Verify Today\'s Labor Muster'),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Muster table / list
                  SectionCard(
                    title: 'Crew Breakdown & Allotted Tasks',
                    subtitle: 'Track headcount, trade category, contractor and daily wages',
                    child: entries.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Center(
                              child: Text(
                                'No worker crews added for today yet.\nClick "Add Worker Crew" to record attendance.',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: entries.length,
                            separatorBuilder: (_, _) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final entry = entries[index];
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: CircleAvatar(
                                  backgroundColor: AppColors.surfaceAlt,
                                  child: Text('${entry.headCount}', style: const TextStyle(fontWeight: FontWeight.bold)),
                                ),
                                title: Text(
                                  '${entry.trade.label} (${entry.contractorName.isNotEmpty ? entry.contractorName : 'Direct'})',
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                                subtitle: Text(
                                  entry.workAllocated.isNotEmpty
                                      ? 'Task: ${entry.workAllocated} • ₹${entry.wagePerDayPaise ~/ 100}/day'
                                      : '₹${entry.wagePerDayPaise ~/ 100}/day per worker',
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      Money.format(entry.computedTotalWagePaise),
                                      style: const TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.edit_outlined, size: 18),
                                      onPressed: () => _openAddEntryDialog(entry),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  void _openAddEntryDialog(LaborEntry? existing) {
    TradeCategory trade = existing?.trade ?? TradeCategory.mason;
    final contractor = TextEditingController(text: existing?.contractorName ?? '');
    final count = TextEditingController(text: existing != null ? '${existing.headCount}' : '4');
    final wage = TextEditingController(text: existing != null && existing.wagePerDayPaise > 0 ? '${existing.wagePerDayPaise ~/ 100}' : '850');
    final task = TextEditingController(text: existing?.workAllocated ?? '');

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(existing == null ? 'Add Worker Crew' : 'Edit Worker Crew'),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 440,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<TradeCategory>(
                    initialValue: trade,
                    decoration: const InputDecoration(labelText: 'Trade / Skill Category *'),
                    onChanged: (t) => setDialogState(() => trade = t!),
                    items: TradeCategory.values
                        .map((t) => DropdownMenuItem(value: t, child: Text(t.label)))
                        .toList(),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: contractor,
                    decoration: const InputDecoration(
                      labelText: 'Contractor / Subcontractor Gang',
                      hintText: 'e.g. Ramesh Masonry Crew or Direct',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: count,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Number of Workers *'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: wage,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Wage / Day (₹)'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: task,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Work Allocated Today',
                      hintText: 'e.g. 2nd floor exterior plastering',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                final headCount = int.tryParse(count.text.trim()) ?? 1;
                final wageRupees = int.tryParse(wage.text.trim()) ?? 850;
                final wagePaise = wageRupees * 100;

                final newEntry = LaborEntry(
                  id: existing?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
                  trade: trade,
                  contractorName: contractor.text.trim(),
                  headCount: headCount,
                  wagePerDayPaise: wagePaise,
                  totalWagePaise: headCount * wagePaise,
                  workAllocated: task.text.trim(),
                );

                final me = ref.read(currentUserProvider);
                final currentMuster = ref.read(todayLaborProvider((projectId: widget.projectId, date: _selectedDate))).value;
                final currentEntries = currentMuster?.entries ?? [];

                final updated = existing == null
                    ? [...currentEntries, newEntry]
                    : currentEntries.map((e) => e.id == existing.id ? newEntry : e).toList();

                await ref.read(laborRepositoryProvider).saveLaborMuster(
                      uid: me.uid,
                      supervisorName: me.name,
                      projectId: widget.projectId,
                      date: _selectedDate,
                      entries: updated,
                    );

                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Save Crew'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _verifyMuster() async {
    final me = ref.read(currentUserProvider);
    await ref.read(laborRepositoryProvider).verifyLaborMuster(
          uid: me.uid,
          projectId: widget.projectId,
          date: _selectedDate,
        );
    if (mounted) showMessage(context, 'Labor muster verified!');
  }
}
