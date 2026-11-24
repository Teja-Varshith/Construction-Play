import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/config/config_models.dart';
import '../../../core/config/config_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/common.dart';
import '../../auth/data/session.dart';
import '../../projects/data/project_repository.dart';
import '../../projects/domain/project.dart';
import '../../users/data/user_repository.dart';
import '../data/crm_repository.dart';
import '../domain/lead_model.dart';

class LeadDetailScreen extends ConsumerStatefulWidget {
  const LeadDetailScreen({super.key, required this.leadId});

  final String leadId;

  @override
  ConsumerState<LeadDetailScreen> createState() => _LeadDetailScreenState();
}

class _LeadDetailScreenState extends ConsumerState<LeadDetailScreen> {
  final _quotationController = TextEditingController();
  final _notesController = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _quotationController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final leadAsync = ref.watch(leadProvider(widget.leadId));
    final me = ref.watch(currentUserProvider);

    return AsyncView(
      value: leadAsync,
      data: (lead) {
        if (lead == null) {
          return const Scaffold(
            body: MessageView(
              icon: Icons.person_search_outlined,
              title: 'Lead not found',
            ),
          );
        }

        final estPaise = lead.estimatedValuePaise;
        final quotePaise = lead.quotationValuePaise;

        return PageScaffold(
          title: lead.clientName,
          maxWidth: 960,
          actions: [
            if (lead.stage == LeadStage.agreement || lead.stage == LeadStage.confirmed)
              FilledButton.icon(
                onPressed: _busy
                    ? null
                    : (lead.convertedProjectId != null
                        ? () => context.go('/projects/${lead.convertedProjectId}')
                        : () => _convertLeadToProject(lead)),
                icon: Icon(lead.convertedProjectId != null ? Icons.folder_open : Icons.rocket_launch),
                label: Text(_busy
                    ? 'Creating...'
                    : (lead.convertedProjectId != null ? 'Open Project' : 'Confirm & Create Project')),
              ),
          ],
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  lead.vertical.label,
                                  style: Theme.of(context).textTheme.titleSmall?.copyWith(color: AppColors.blue),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  lead.clientName,
                                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Icon(Icons.phone, size: 14, color: AppColors.muted),
                                    const SizedBox(width: 4),
                                    Text(lead.phone, style: const TextStyle(color: AppColors.inkSoft)),
                                    if (lead.email.isNotEmpty) ...[
                                      const SizedBox(width: 12),
                                      const Icon(Icons.email, size: 14, color: AppColors.muted),
                                      const SizedBox(width: 4),
                                      Text(lead.email, style: const TextStyle(color: AppColors.inkSoft)),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                quotePaise > 0 ? Money.format(quotePaise) : (estPaise > 0 ? Money.format(estPaise) : 'No Quote'),
                                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: quotePaise > 0 ? Colors.teal : AppColors.ink,
                                    ),
                              ),
                              Text(
                                quotePaise > 0 ? 'Quotation Value' : 'Estimated Budget',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const Divider(height: 24),
                      // Sales Assignment
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Sales Rep: ${lead.assignedToName.isNotEmpty ? lead.assignedToName : 'Unassigned'}'),
                          TextButton.icon(
                            onPressed: () => _openReassignDialog(lead),
                            icon: const Icon(Icons.person_add_alt, size: 16),
                            label: const Text('Reassign'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Stage Progression Stepper
              SectionCard(
                title: 'Pipeline Stage',
                subtitle: 'Current: ${lead.stage.label}',
                child: Column(
                  children: [
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: LeadStage.values.map((stage) {
                          final isCurrent = lead.stage == stage;
                          final isPassed = stage.index < lead.stage.index;
                          final isLost = stage == LeadStage.lost;

                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ActionChip(
                              avatar: isCurrent
                                  ? const Icon(Icons.check_circle, size: 16, color: Colors.white)
                                  : (isPassed ? const Icon(Icons.done, size: 16) : null),
                              backgroundColor: isCurrent
                                  ? (isLost ? Colors.red : AppColors.blue)
                                  : (isPassed ? AppColors.surfaceAlt : null),
                              label: Text(
                                stage.label,
                                style: TextStyle(
                                  color: isCurrent ? Colors.white : (isLost ? Colors.red : null),
                                  fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                              onPressed: () => _changeStage(lead, stage),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    if (lead.lostReason.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline, size: 16, color: Colors.red),
                            const SizedBox(width: 8),
                            Expanded(child: Text('Reason Lost: ${lead.lostReason}', style: const TextStyle(color: Colors.red))),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Quotation & Estimation Editor
              SectionCard(
                title: 'Design & Estimation / Quotation',
                subtitle: 'Prepare BOQ, update formal quotation, or log client requirements',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            initialValue: estPaise > 0 ? Money.toInput(estPaise) : '',
                            decoration: const InputDecoration(labelText: 'Estimated Budget (₹)'),
                            onChanged: (v) {
                              final p = Money.parse(v);
                              if (p != null) {
                                ref.read(crmRepositoryProvider).updateQuotationAndEstimation(
                                      uid: me.uid,
                                      lead: lead,
                                      estimatedValuePaise: p,
                                      quotationValuePaise: lead.quotationValuePaise,
                                    );
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextFormField(
                            initialValue: quotePaise > 0 ? Money.toInput(quotePaise) : '',
                            decoration: const InputDecoration(labelText: 'Quotation Submitted (₹)'),
                            onChanged: (v) {
                              final p = Money.parse(v);
                              if (p != null) {
                                ref.read(crmRepositoryProvider).updateQuotationAndEstimation(
                                      uid: me.uid,
                                      lead: lead,
                                      estimatedValuePaise: lead.estimatedValuePaise,
                                      quotationValuePaise: p,
                                    );
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      initialValue: lead.requirementDetails,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Detailed Requirements / Scope of Work',
                        hintText: 'e.g. 3BHK Duplex, 2400 sq.ft, Modular kitchen with Italian marble flooring...',
                      ),
                      onChanged: (v) {
                        ref.read(crmRepositoryProvider).updateQuotationAndEstimation(
                              uid: me.uid,
                              lead: lead,
                              estimatedValuePaise: lead.estimatedValuePaise,
                              quotationValuePaise: lead.quotationValuePaise,
                              requirementDetails: v,
                            );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Customer Follow-ups & Meetings Timeline
              SectionCard(
                title: 'Customer Follow-ups & Meetings',
                subtitle: 'Scheduled touchpoints and site meeting logs',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('${lead.followUps.length} logged follow-ups'),
                        FilledButton.tonalIcon(
                          onPressed: () => _openScheduleFollowUpDialog(lead),
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('Add Follow-Up'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (lead.followUps.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(child: Text('No follow-ups recorded yet.')),
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: lead.followUps.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final f = lead.followUps[index];
                          return CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            value: f.done,
                            title: Text(
                              f.notes,
                              style: TextStyle(
                                decoration: f.done ? TextDecoration.lineThrough : null,
                                fontWeight: f.done ? FontWeight.normal : FontWeight.w600,
                              ),
                            ),
                            subtitle: Text('Due: ${f.scheduledDate} ${f.done ? '• Completed' : ''}'),
                            onChanged: (val) {
                              if (val == true) {
                                final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
                                ref.read(crmRepositoryProvider).markFollowUpDone(
                                      uid: me.uid,
                                      lead: lead,
                                      followUpId: f.id,
                                      completedDate: today,
                                    );
                              }
                            },
                          );
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _changeStage(Lead lead, LeadStage newStage) async {
    final me = ref.read(currentUserProvider);
    if (newStage == LeadStage.lost) {
      final reason = await _promptLostReason();
      if (reason != null && mounted) {
        await ref.read(crmRepositoryProvider).updateLeadStage(
              uid: me.uid,
              lead: lead,
              newStage: newStage,
              lostReason: reason,
            );
      }
      return;
    }

    await ref.read(crmRepositoryProvider).updateLeadStage(
          uid: me.uid,
          lead: lead,
          newStage: newStage,
        );
  }

  Future<String?> _promptLostReason() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reason for Lost Enquiry'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'e.g. Budget mismatch, Went with competitor, Postponed build...',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Confirm')),
        ],
      ),
    );
  }

  void _openScheduleFollowUpDialog(Lead lead) {
    final notes = TextEditingController();
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now().add(const Duration(days: 2)));
    final dateController = TextEditingController(text: today);

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Schedule Follow-Up'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: dateController,
              decoration: const InputDecoration(labelText: 'Follow-up Date (YYYY-MM-DD)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: notes,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Discussion Topic / Meeting Agenda'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              if (notes.text.trim().isEmpty) return;
              final me = ref.read(currentUserProvider);
              await ref.read(crmRepositoryProvider).addFollowUp(
                    uid: me.uid,
                    lead: lead,
                    scheduledDate: dateController.text.trim(),
                    notes: notes.text.trim(),
                    recordedByName: me.name,
                  );
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _openReassignDialog(Lead lead) {
    final usersAsync = ref.read(allUsersProvider);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Assign Sales Representative'),
        content: AsyncView(
          value: usersAsync,
          data: (users) {
            final activeUsers = users.where((u) => u.active).toList();
            return SizedBox(
              width: 320,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: activeUsers.length,
                itemBuilder: (_, index) {
                  final user = activeUsers[index];
                  return ListTile(
                    title: Text(user.name),
                    subtitle: Text(user.role.label),
                    onTap: () async {
                      final me = ref.read(currentUserProvider);
                      await ref.read(crmRepositoryProvider).assignLead(
                            uid: me.uid,
                            lead: lead,
                            assignedToUid: user.uid,
                            assignedToName: user.name,
                          );
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _convertLeadToProject(Lead lead) async {
    final me = ref.read(currentUserProvider);
    final config = ref.read(appConfigProvider);
    final statuses = config.activeOf(ConfigList.projectStatuses);
    final statusId = statuses.where((item) => item.id == 'ongoing').firstOrNull?.id ??
        statuses.firstOrNull?.id ??
        'ongoing';
    final stage = config.stageOfStatus(statusId);
    final statusIndex = config.allOf(ConfigList.projectStatuses).indexWhere((s) => s.id == statusId);

    setState(() => _busy = true);
    try {
      final code = lead.clientName
          .split(' ')
          .map((p) => p.isNotEmpty ? p[0].toUpperCase() : '')
          .take(3)
          .join();

      final valPaise = lead.quotationValuePaise > 0 ? lead.quotationValuePaise : lead.estimatedValuePaise;
      final pid = await ref.read(projectRepositoryProvider).create(
            Project(
              id: '',
              name: '${lead.clientName} Project',
              code: code.isNotEmpty ? code : 'PRJ',
              clientName: lead.clientName,
              city: lead.siteLocation.isNotEmpty ? lead.siteLocation : 'Chennai',
              address: lead.siteLocation,
              typeId: lead.vertical.name,
              statusId: statusId,
              contractValuePaise: valPaise,
              managerId: me.isManager ? me.uid : null,
              memberIds: [me.uid],
            ),
            uid: me.uid,
            stage: stage,
            statusIndex: statusIndex >= 0 ? statusIndex : 0,
          );

      // Link project id to lead and mark confirmed
      await ref.read(crmRepositoryProvider).updateLeadStage(
            uid: me.uid,
            lead: lead,
            newStage: LeadStage.confirmed,
          );

      if (mounted) {
        showMessage(context, 'Project created and confirmed!');
        context.go('/projects/$pid');
      }
    } catch (e) {
      if (mounted) showMessage(context, 'Failed to create project: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
