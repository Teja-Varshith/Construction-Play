import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/common.dart';
import '../../auth/data/session.dart';
import '../../users/data/user_repository.dart';
import '../data/crm_repository.dart';
import '../domain/lead_model.dart';
import '../domain/sales_target_model.dart';

class SalesPerformanceScreen extends ConsumerStatefulWidget {
  const SalesPerformanceScreen({super.key});

  @override
  ConsumerState<SalesPerformanceScreen> createState() => _SalesPerformanceScreenState();
}

class _SalesPerformanceScreenState extends ConsumerState<SalesPerformanceScreen> {
  late final String _selectedMonth = DateFormat('yyyy-MM').format(DateTime.now());

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(currentUserProvider);
    final leadsAsync = ref.watch(allLeadsProvider);
    final targetsAsync = ref.watch(salesTargetsProvider(_selectedMonth));

    return PageScaffold(
      title: 'Chairman\'s Sales Dashboard',
      maxWidth: 1100,
      actions: [
        if (me.isCeo || me.isAdmin)
          FilledButton.icon(
            onPressed: () => _openSetTargetDialog(context),
            icon: const Icon(Icons.track_changes),
            label: const Text('Set Employee Target'),
          ),
      ],
      body: AsyncView(
        value: leadsAsync,
        data: (leads) {
          return AsyncView(
            value: targetsAsync,
            data: (targets) {
              return _buildDashboard(context, leads, targets);
            },
          );
        },
      ),
    );
  }

  Widget _buildDashboard(BuildContext context, List<Lead> allLeads, List<SalesTarget> targets) {
    // Analytics calculations
    final totalEnquiries = allLeads.length;
    final confirmedLeads = allLeads.where((l) => l.stage == LeadStage.confirmed).toList();
    final lostLeads = allLeads.where((l) => l.stage == LeadStage.lost).toList();
    final quotesSent = allLeads.where((l) => l.quotationValuePaise > 0).toList();

    int totalFollowUpsPending = 0;
    int totalFollowUpsCompleted = 0;
    for (final l in allLeads) {
      for (final f in l.followUps) {
        if (f.done) {
          totalFollowUpsCompleted++;
        } else {
          totalFollowUpsPending++;
        }
      }
    }

    final confirmedSalesPaise = confirmedLeads.fold<int>(
      0,
      (sum, l) => sum + (l.quotationValuePaise > 0 ? l.quotationValuePaise : l.estimatedValuePaise),
    );

    final totalTargetPaise = targets.fold<int>(0, (sum, t) => sum + t.targetPaise);

    final conversionRate = totalEnquiries > 0
        ? ((confirmedLeads.length / totalEnquiries) * 100).toStringAsFixed(1)
        : '0.0';

    final targetVsActualPct = totalTargetPaise > 0
        ? ((confirmedSalesPaise / totalTargetPaise) * 100).clamp(0, 100).toDouble()
        : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Target vs Actual Company Card
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Company Sales Performance ($_selectedMonth)',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '${targetVsActualPct.toStringAsFixed(1)}% of Target',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: targetVsActualPct >= 80 ? Colors.green : (targetVsActualPct >= 50 ? Colors.orange : Colors.red),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: targetVsActualPct / 100,
                    minHeight: 12,
                    backgroundColor: Colors.grey.shade200,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      targetVsActualPct >= 80 ? Colors.green : (targetVsActualPct >= 50 ? Colors.orange : AppColors.blue),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _StatTile(
                      label: 'Target Sales',
                      value: Money.compact(totalTargetPaise),
                      color: AppColors.inkSoft,
                    ),
                    _StatTile(
                      label: 'Confirmed Sales',
                      value: Money.compact(confirmedSalesPaise),
                      color: Colors.green.shade700,
                    ),
                    _StatTile(
                      label: 'Deals Confirmed',
                      value: '${confirmedLeads.length}',
                      color: AppColors.blue,
                    ),
                    _StatTile(
                      label: 'Conversion Rate',
                      value: '$conversionRate%',
                      color: Colors.purple,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // 4 KPI Summary Grid
        Row(
          children: [
            Expanded(
              child: _KpiTile(
                title: 'Enquiries Received',
                value: '$totalEnquiries',
                subtitle: '${allLeads.where((l) => l.stage.isActive).length} in active pipeline',
                icon: Icons.mark_email_read_outlined,
                color: Colors.blue,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _KpiTile(
                title: 'Customer Follow-ups',
                value: '$totalFollowUpsCompleted done',
                subtitle: '$totalFollowUpsPending pending attention',
                icon: Icons.phone_callback_outlined,
                color: Colors.amber.shade900,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _KpiTile(
                title: 'Quotations Sent',
                value: '${quotesSent.length}',
                subtitle: Money.compact(quotesSent.fold<int>(0, (s, l) => s + l.quotationValuePaise)),
                icon: Icons.description_outlined,
                color: Colors.teal,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _KpiTile(
                title: 'Lost Enquiries',
                value: '${lostLeads.length}',
                subtitle: lostLeads.isNotEmpty ? lostLeads.first.lostReason : 'None',
                icon: Icons.cancel_outlined,
                color: Colors.red.shade700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Employee-wise Sales Performance Table
        SectionCard(
          title: 'Employee-wise Sales Performance',
          subtitle: 'Compare individual sales reps: target vs actual and deals closed',
          child: targets.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      'No individual employee targets set for this month.\nClick "Set Employee Target" to establish quotas.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Sales Executive')),
                      DataColumn(label: Text('Target (₹)')),
                      DataColumn(label: Text('Achieved (₹)')),
                      DataColumn(label: Text('% Achieved')),
                      DataColumn(label: Text('Won / Target Deals')),
                    ],
                    rows: targets.map((t) {
                      // Calculate employee's actual achieved from leads assigned
                      final empLeads = allLeads.where((l) => l.assignedToUid == t.employeeUid).toList();
                      final empWon = empLeads.where((l) => l.stage == LeadStage.confirmed).toList();
                      final empAchievedPaise = empWon.fold<int>(
                        0,
                        (sum, l) => sum + (l.quotationValuePaise > 0 ? l.quotationValuePaise : l.estimatedValuePaise),
                      );
                      final pct = t.targetPaise > 0
                          ? ((empAchievedPaise / t.targetPaise) * 100).toStringAsFixed(1)
                          : '0.0';

                      return DataRow(
                        cells: [
                          DataCell(
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: 14,
                                  backgroundColor: AppColors.surfaceAlt,
                                  child: Text(
                                    t.employeeName.isNotEmpty ? t.employeeName[0].toUpperCase() : '?',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(t.employeeName, style: const TextStyle(fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                          DataCell(Text(Money.format(t.targetPaise))),
                          DataCell(Text(Money.format(empAchievedPaise), style: const TextStyle(fontWeight: FontWeight.bold))),
                          DataCell(
                            Text(
                              '$pct%',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: double.parse(pct) >= 100 ? Colors.green : Colors.orange,
                              ),
                            ),
                          ),
                          DataCell(Text('${empWon.length} / ${t.targetWonCount}')),
                        ],
                      );
                    }).toList(),
                  ),
                ),
        ),
        const SizedBox(height: 20),

        // Lost Reasons Analysis
        if (lostLeads.isNotEmpty)
          SectionCard(
            title: 'Lost Enquiries & Root Cause Analysis',
            subtitle: 'Understanding why prospective clients did not proceed',
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: lostLeads.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final lead = lostLeads[index];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.report_problem_outlined, color: Colors.red),
                  title: Text('${lead.clientName} (${lead.vertical.label})'),
                  subtitle: Text(lead.lostReason.isNotEmpty ? 'Reason: ${lead.lostReason}' : 'No reason recorded'),
                  trailing: Text(
                    lead.estimatedValuePaise > 0 ? Money.format(lead.estimatedValuePaise) : '',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  void _openSetTargetDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => _SetTargetDialog(yearMonth: _selectedMonth),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }
}

class _KpiTile extends StatelessWidget {
  const _KpiTile({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.inkSoft)),
                Icon(icon, size: 18, color: color),
              ],
            ),
            const SizedBox(height: 8),
            Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(subtitle, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

class _SetTargetDialog extends ConsumerStatefulWidget {
  const _SetTargetDialog({required this.yearMonth});

  final String yearMonth;

  @override
  ConsumerState<_SetTargetDialog> createState() => _SetTargetDialogState();
}

class _SetTargetDialogState extends ConsumerState<_SetTargetDialog> {
  final _targetPaise = TextEditingController();
  final _targetLeads = TextEditingController(text: '15');
  final _targetWon = TextEditingController(text: '3');

  String? _selectedEmployeeUid;
  String _selectedEmployeeName = '';
  bool _busy = false;

  @override
  void dispose() {
    _targetPaise.dispose();
    _targetLeads.dispose();
    _targetWon.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final usersAsync = ref.watch(allUsersProvider);

    return AlertDialog(
      title: Text('Set Quota for ${widget.yearMonth}'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AsyncView(
              value: usersAsync,
              data: (users) {
                final salesUsers = users.where((u) => u.active && (u.isSales || u.isManager || u.isAdmin)).toList();
                return DropdownButtonFormField<String>(
                  initialValue: _selectedEmployeeUid,
                  decoration: const InputDecoration(labelText: 'Employee *'),
                  onChanged: (uid) {
                    setState(() {
                      _selectedEmployeeUid = uid;
                      _selectedEmployeeName = salesUsers.firstWhere((u) => u.uid == uid).name;
                    });
                  },
                  items: salesUsers
                      .map((u) => DropdownMenuItem(value: u.uid, child: Text('${u.name} (${u.role.label})')))
                      .toList(),
                );
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _targetPaise,
              decoration: const InputDecoration(labelText: 'Sales Revenue Target (₹) *', hintText: 'e.g. 50,00,000'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _targetLeads,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Target Leads'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _targetWon,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Target Deals Won'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: Text(_busy ? 'Saving...' : 'Set Target'),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    if (_selectedEmployeeUid == null) return;
    final paise = Money.parse(_targetPaise.text.trim());
    if (paise == null || paise <= 0) return;

    setState(() => _busy = true);
    final me = ref.read(currentUserProvider);
    try {
      await ref.read(crmRepositoryProvider).saveSalesTarget(
            uid: me.uid,
            yearMonth: widget.yearMonth,
            employeeUid: _selectedEmployeeUid!,
            employeeName: _selectedEmployeeName,
            targetPaise: paise,
            targetLeadsCount: int.tryParse(_targetLeads.text.trim()) ?? 15,
            targetWonCount: int.tryParse(_targetWon.text.trim()) ?? 3,
          );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showMessage(context, 'Failed to save target: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
