import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/common.dart';
import '../../auth/data/session.dart';
import '../../users/data/user_repository.dart';
import '../data/crm_repository.dart';
import '../domain/lead_model.dart';

class LeadsScreen extends ConsumerStatefulWidget {
  const LeadsScreen({super.key});

  @override
  ConsumerState<LeadsScreen> createState() => _LeadsScreenState();
}

class _LeadsScreenState extends ConsumerState<LeadsScreen> {
  BusinessVertical? _selectedVertical;
  LeadStage? _selectedStage;
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(currentUserProvider);
    final isSalesOnly = me.isSales && !me.isCeo && !me.isAdmin && !me.isManager;
    final leadsAsync = isSalesOnly
        ? ref.watch(myLeadsProvider(me.uid))
        : ref.watch(allLeadsProvider);

    return PageScaffold(
      title: 'Customer CRM & Leads',
      maxWidth: 1100,
      actions: [
        if (me.isCeo || me.isAdmin || me.isManager || me.isSales)
          FilledButton.icon(
            onPressed: () => _openAddLeadDialog(context),
            icon: const Icon(Icons.add),
            label: const Text('New Enquiry'),
          ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Filter Row: Verticals and Search
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          decoration: const InputDecoration(
                            hintText: 'Search by client name, phone or location...',
                            prefixIcon: Icon(Icons.search),
                            isDense: true,
                          ),
                          onChanged: (v) => setState(() => _searchQuery = v.trim().toLowerCase()),
                        ),
                      ),
                      const SizedBox(width: 12),
                      DropdownButton<BusinessVertical?>(
                        value: _selectedVertical,
                        hint: const Text('All Business Verticals'),
                        onChanged: (v) => setState(() => _selectedVertical = v),
                        items: [
                          const DropdownMenuItem(value: null, child: Text('All Business Verticals')),
                          ...BusinessVertical.values.map(
                            (v) => DropdownMenuItem(value: v, child: Text(v.label)),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        FilterChip(
                          selected: _selectedStage == null,
                          label: const Text('All Stages'),
                          onSelected: (_) => setState(() => _selectedStage = null),
                        ),
                        const SizedBox(width: 6),
                        ...LeadStage.values.map(
                          (stage) => Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: FilterChip(
                              selected: _selectedStage == stage,
                              label: Text(stage.label),
                              onSelected: (sel) => setState(() => _selectedStage = sel ? stage : null),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Leads Async View
          AsyncView(
            value: leadsAsync,
            data: (leads) {
              var filtered = leads;
              if (_selectedVertical != null) {
                filtered = filtered.where((l) => l.vertical == _selectedVertical).toList();
              }
              if (_selectedStage != null) {
                filtered = filtered.where((l) => l.stage == _selectedStage).toList();
              }
              if (_searchQuery.isNotEmpty) {
                filtered = filtered.where((l) {
                  return l.clientName.toLowerCase().contains(_searchQuery) ||
                      l.phone.contains(_searchQuery) ||
                      l.siteLocation.toLowerCase().contains(_searchQuery);
                }).toList();
              }

              // Pipeline Metrics Banner
              final totalPipeline = filtered.fold<int>(0, (sum, l) => sum + (l.quotationValuePaise > 0 ? l.quotationValuePaise : l.estimatedValuePaise));
              final activeCount = filtered.where((l) => l.stage.isActive).length;
              final wonCount = filtered.where((l) => l.stage.isWon).length;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _MetricCard(
                          label: 'Total Enquiries',
                          value: '${filtered.length}',
                          icon: Icons.contact_mail_outlined,
                          color: AppColors.blue,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _MetricCard(
                          label: 'Active Pipeline',
                          value: '$activeCount',
                          icon: Icons.trending_up,
                          color: Colors.amber.shade800,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _MetricCard(
                          label: 'Pipeline Value',
                          value: Money.compact(totalPipeline),
                          icon: Icons.currency_rupee,
                          color: Colors.teal,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _MetricCard(
                          label: 'Confirmed Deals',
                          value: '$wonCount',
                          icon: Icons.check_circle_outline,
                          color: Colors.green.shade700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  if (filtered.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(
                          child: Text(
                            'No enquiries found matching filters.\nClick "+ New Enquiry" to add one.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    )
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final lead = filtered[index];
                        return _LeadCard(
                          lead: lead,
                          onTap: () => context.go('/leads/${lead.id}'),
                        );
                      },
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  void _openAddLeadDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => const _AddLeadDialog(),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: color.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: color.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.inkSoft)),
                Icon(icon, size: 18, color: color),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: color),
            ),
          ],
        ),
      ),
    );
  }
}

class _LeadCard extends StatelessWidget {
  const _LeadCard({required this.lead, required this.onTap});

  final Lead lead;
  final VoidCallback onTap;

  Color _stageColor(LeadStage stage) {
    switch (stage) {
      case LeadStage.enquiry:
        return Colors.blueGrey;
      case LeadStage.leadQualification:
        return Colors.indigo;
      case LeadStage.followUp:
        return Colors.amber.shade900;
      case LeadStage.siteVisit:
        return Colors.purple;
      case LeadStage.estimation:
        return Colors.blue;
      case LeadStage.quotation:
        return Colors.teal;
      case LeadStage.agreement:
        return Colors.orange.shade800;
      case LeadStage.confirmed:
        return Colors.green.shade700;
      case LeadStage.lost:
        return Colors.red.shade700;
    }
  }

  @override
  Widget build(BuildContext context) {
    final valuePaise = lead.quotationValuePaise > 0 ? lead.quotationValuePaise : lead.estimatedValuePaise;
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: AppColors.surfaceAlt,
                foregroundColor: AppColors.ink,
                child: Text(lead.clientName.isNotEmpty ? lead.clientName[0].toUpperCase() : '?'),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          lead.clientName,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: _stageColor(lead.stage).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            lead.stage.label,
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _stageColor(lead.stage)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${lead.vertical.label} • ${lead.siteLocation.isNotEmpty ? lead.siteLocation : 'Site unassigned'}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted),
                    ),
                    if (lead.assignedToName.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Assigned to: ${lead.assignedToName}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.inkSoft),
                      ),
                    ],
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    valuePaise > 0 ? Money.format(valuePaise) : 'Amount pending',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: valuePaise > 0 ? AppColors.ink : AppColors.muted,
                        ),
                  ),
                  const SizedBox(height: 4),
                  if (lead.pendingFollowUpsCount > 0)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.alarm, size: 14, color: Colors.orange),
                        const SizedBox(width: 4),
                        Text(
                          '${lead.pendingFollowUpsCount} follow-up pending',
                          style: const TextStyle(fontSize: 11, color: Colors.orange, fontWeight: FontWeight.w600),
                        ),
                      ],
                    )
                  else
                    Text(
                      lead.phone,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted),
                    ),
                ],
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddLeadDialog extends ConsumerStatefulWidget {
  const _AddLeadDialog();

  @override
  ConsumerState<_AddLeadDialog> createState() => _AddLeadDialogState();
}

class _AddLeadDialogState extends ConsumerState<_AddLeadDialog> {
  final _form = GlobalKey<FormState>();
  final _clientName = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _location = TextEditingController();
  final _estimatedValue = TextEditingController();
  final _requirement = TextEditingController();

  BusinessVertical _vertical = BusinessVertical.constructionTurnkey;
  final LeadStage _stage = LeadStage.enquiry;
  String? _assignedUid;
  String _assignedName = '';
  bool _busy = false;

  @override
  void dispose() {
    _clientName.dispose();
    _phone.dispose();
    _email.dispose();
    _location.dispose();
    _estimatedValue.dispose();
    _requirement.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final usersAsync = ref.watch(allUsersProvider);
    final me = ref.watch(currentUserProvider);

    return AlertDialog(
      title: const Text('New Customer Enquiry'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<BusinessVertical>(
                  initialValue: _vertical,
                  decoration: const InputDecoration(labelText: 'Business Vertical *'),
                  onChanged: (v) => setState(() => _vertical = v!),
                  items: BusinessVertical.values
                      .map((v) => DropdownMenuItem(value: v, child: Text(v.label)))
                      .toList(),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _clientName,
                  decoration: const InputDecoration(labelText: 'Client Name *'),
                  validator: (v) => (v ?? '').trim().isEmpty ? 'Enter client name' : null,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _phone,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(labelText: 'Phone Number *'),
                        validator: (v) => (v ?? '').trim().isEmpty ? 'Enter phone number' : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(labelText: 'Email (optional)'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _location,
                        decoration: const InputDecoration(labelText: 'Site / City Location'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _estimatedValue,
                        decoration: const InputDecoration(labelText: 'Est. Budget (₹)'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                AsyncView(
                  value: usersAsync,
                  data: (users) {
                    final assignable = users.where((u) => u.active).toList();
                    return DropdownButtonFormField<String?>(
                      initialValue: _assignedUid,
                      decoration: const InputDecoration(labelText: 'Assign to Sales Rep / Manager'),
                      onChanged: (uid) {
                        setState(() {
                          _assignedUid = uid;
                          _assignedName = assignable.firstWhere((u) => u.uid == uid, orElse: () => me).name;
                        });
                      },
                      items: [
                        const DropdownMenuItem(value: null, child: Text('Unassigned')),
                        ...assignable.map(
                          (u) => DropdownMenuItem(value: u.uid, child: Text('${u.name} (${u.role.label})')),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _requirement,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Requirement Details / Notes'),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: Text(_busy ? 'Saving...' : 'Create Lead'),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final me = ref.read(currentUserProvider);
    final estPaise = Money.parse(_estimatedValue.text.trim()) ?? 0;

    try {
      await ref.read(crmRepositoryProvider).createLead(
            uid: me.uid,
            clientName: _clientName.text.trim(),
            phone: _phone.text.trim(),
            email: _email.text.trim(),
            vertical: _vertical,
            stage: _stage,
            estimatedValuePaise: estPaise,
            siteLocation: _location.text.trim(),
            assignedToUid: _assignedUid ?? (me.isSales ? me.uid : ''),
            assignedToName: _assignedUid != null ? _assignedName : (me.isSales ? me.name : ''),
            requirementDetails: _requirement.text.trim(),
          );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showMessage(context, 'Failed to save lead: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
