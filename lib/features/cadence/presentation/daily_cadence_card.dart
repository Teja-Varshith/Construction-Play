import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../auth/data/session.dart';
import '../data/cadence_repository.dart';
import '../domain/daily_cadence_model.dart';

class DailyCadenceCard extends ConsumerStatefulWidget {
  const DailyCadenceCard({super.key, required this.projectId, this.date});

  final String projectId;
  final String? date;

  @override
  ConsumerState<DailyCadenceCard> createState() => _DailyCadenceCardState();
}

class _DailyCadenceCardState extends ConsumerState<DailyCadenceCard> {
  late final String _currentDate = widget.date ?? DateFormat('yyyy-MM-dd').format(DateTime.now());

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(currentUserProvider);
    final cadenceAsync = ref.watch(todayCadenceProvider((projectId: widget.projectId, date: _currentDate)));

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.schedule, color: AppColors.blue),
                    const SizedBox(width: 8),
                    Text(
                      'Daily Management Cadence',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                Text(
                  _currentDate,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 12),
            AsyncView(
              value: cadenceAsync,
              data: (cadence) {
                final c = cadence ?? DailyCadence(id: _currentDate, projectId: widget.projectId, date: _currentDate);
                return Column(
                  children: [
                    _CadenceItem(
                      slot: CadenceTimeSlot.morningPlan,
                      isDone: c.isMorningDone,
                      subtitle: c.isMorningDone
                          ? 'Planned: ${c.morningPlan.targetOutput.isNotEmpty ? c.morningPlan.targetOutput : c.morningPlan.plannedTasks} (${c.morningPlan.plannedLaborCount} workers)'
                          : 'Morning plan pending (Targets, labor muster, materials)',
                      onAction: () => _openMorningPlanDialog(c),
                      actionLabel: c.isMorningDone ? 'Edit Plan' : 'Submit 8:30 Plan',
                    ),
                    const Divider(height: 16),
                    _CadenceItem(
                      slot: CadenceTimeSlot.middayReview,
                      isDone: c.isMiddayDone,
                      subtitle: c.isMiddayDone
                          ? 'Status: ${c.middayReview.status.label} • ${c.middayReview.laborPresentCount} present'
                          : '1:00 PM check pending (Progress check, bottleneck alerts)',
                      onAction: () => _openMiddayDialog(c),
                      actionLabel: c.isMiddayDone ? 'Update Review' : 'Submit 1:00 Review',
                    ),
                    const Divider(height: 16),
                    _CadenceItem(
                      slot: CadenceTimeSlot.dailyClosing,
                      isDone: c.isClosingDone,
                      subtitle: c.isClosingDone
                          ? 'Executed: ${c.dailyClosing.actualOutput} • Signoff: ${c.dailyClosing.managerSignoff.toUpperCase()}'
                          : '9:30 PM closing pending (DPR reconciliation & manager review)',
                      onAction: () => _openClosingDialog(c),
                      actionLabel: c.isClosingDone
                          ? (me.isManager && c.dailyClosing.managerSignoff == 'pending' ? 'Review & Sign Off' : 'View Closing')
                          : 'Submit 9:30 Closing',
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _openMorningPlanDialog(DailyCadence cadence) {
    final tasks = TextEditingController(text: cadence.morningPlan.plannedTasks);
    final output = TextEditingController(text: cadence.morningPlan.targetOutput);
    final labor = TextEditingController(text: cadence.morningPlan.plannedLaborCount > 0 ? '${cadence.morningPlan.plannedLaborCount}' : '');
    final notes = TextEditingController(text: cadence.morningPlan.supervisorNotes);
    bool materialsReady = cadence.morningPlan.materialsReady;

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('8:30 AM – Daily Plan'),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 480,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: tasks,
                    decoration: const InputDecoration(
                      labelText: 'Planned Tasks Today *',
                      hintText: 'e.g. 2nd slab shuttering, 1st floor electrical conduits',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: output,
                          decoration: const InputDecoration(
                            labelText: 'Target Output Quantity',
                            hintText: 'e.g. 1500 sq.ft',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: labor,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Labor Headcount',
                            hintText: 'e.g. 18',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: materialsReady,
                    onChanged: (v) => setDialogState(() => materialsReady = v ?? true),
                    title: const Text('Required materials ready on site'),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: notes,
                    decoration: const InputDecoration(labelText: 'Supervisor Notes / Requests'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                final me = ref.read(currentUserProvider);
                await ref.read(cadenceRepositoryProvider).submitMorningPlan(
                      uid: me.uid,
                      projectId: widget.projectId,
                      date: _currentDate,
                      plannedTasks: tasks.text.trim(),
                      targetOutput: output.text.trim(),
                      plannedLaborCount: int.tryParse(labor.text.trim()) ?? 0,
                      materialsReady: materialsReady,
                      supervisorNotes: notes.text.trim(),
                    );
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Save Plan'),
            ),
          ],
        ),
      ),
    );
  }

  void _openMiddayDialog(DailyCadence cadence) {
    MiddayStatus status = cadence.middayReview.status;
    final notes = TextEditingController(text: cadence.middayReview.progressNotes);
    final labor = TextEditingController(text: cadence.middayReview.laborPresentCount > 0 ? '${cadence.middayReview.laborPresentCount}' : '');
    final bottlenecks = TextEditingController(text: cadence.middayReview.bottlenecks);

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('1:00 PM – Mid-Day Progress Review'),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 480,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<MiddayStatus>(
                    initialValue: status,
                    decoration: const InputDecoration(labelText: 'Progress Status'),
                    onChanged: (v) => setDialogState(() => status = v!),
                    items: MiddayStatus.values
                        .map((s) => DropdownMenuItem(value: s, child: Text(s.label)))
                        .toList(),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: labor,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Labor Present at Mid-Day'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: notes,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: 'Progress So Far'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: bottlenecks,
                    decoration: const InputDecoration(labelText: 'Impediments / Bottlenecks (if any)'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                final me = ref.read(currentUserProvider);
                await ref.read(cadenceRepositoryProvider).submitMiddayReview(
                      uid: me.uid,
                      projectId: widget.projectId,
                      date: _currentDate,
                      status: status,
                      progressNotes: notes.text.trim(),
                      laborPresentCount: int.tryParse(labor.text.trim()) ?? 0,
                      bottlenecks: bottlenecks.text.trim(),
                    );
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Save Review'),
            ),
          ],
        ),
      ),
    );
  }

  void _openClosingDialog(DailyCadence cadence) {
    final me = ref.read(currentUserProvider);
    final output = TextEditingController(text: cadence.dailyClosing.actualOutput);
    final summary = TextEditingController(text: cadence.dailyClosing.workCompletedSummary);
    final delays = TextEditingController(text: cadence.dailyClosing.delaysEncountered);
    final feedback = TextEditingController(text: cadence.dailyClosing.managerFeedback);

    final isManagerSigning = me.isManager && cadence.isClosingDone;

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isManagerSigning ? 'Manager Review & Sign-off' : '9:30 PM – Daily Closing'),
        content: SingleChildScrollView(
          child: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!isManagerSigning) ...[
                  TextFormField(
                    controller: output,
                    decoration: const InputDecoration(
                      labelText: 'Actual Output Achieved *',
                      hintText: 'e.g. 1400 sq.ft shuttering completed',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: summary,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: 'Work Summary'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: delays,
                    decoration: const InputDecoration(labelText: 'Delays / Issues Encountered'),
                  ),
                ] else ...[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Work Completed'),
                    subtitle: Text(cadence.dailyClosing.actualOutput.isNotEmpty ? cadence.dailyClosing.actualOutput : 'No output text'),
                  ),
                  if (cadence.dailyClosing.delaysEncountered.isNotEmpty)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Delays Reported', style: TextStyle(color: Colors.red)),
                      subtitle: Text(cadence.dailyClosing.delaysEncountered),
                    ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: feedback,
                    decoration: const InputDecoration(labelText: 'Manager Feedback / Review Note'),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          if (isManagerSigning) ...[
            TextButton(
              onPressed: () async {
                await ref.read(cadenceRepositoryProvider).signoffDailyClosing(
                      uid: me.uid,
                      projectId: widget.projectId,
                      date: _currentDate,
                      managerSignoff: 'queried',
                      managerFeedback: feedback.text.trim(),
                    );
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Query', style: TextStyle(color: Colors.orange)),
            ),
            FilledButton(
              onPressed: () async {
                await ref.read(cadenceRepositoryProvider).signoffDailyClosing(
                      uid: me.uid,
                      projectId: widget.projectId,
                      date: _currentDate,
                      managerSignoff: 'approved',
                      managerFeedback: feedback.text.trim(),
                    );
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Approve Closing'),
            ),
          ] else
            FilledButton(
              onPressed: () async {
                await ref.read(cadenceRepositoryProvider).submitDailyClosing(
                      uid: me.uid,
                      projectId: widget.projectId,
                      date: _currentDate,
                      actualOutput: output.text.trim(),
                      workCompletedSummary: summary.text.trim(),
                      delaysEncountered: delays.text.trim(),
                    );
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Submit Closing'),
            ),
        ],
      ),
    );
  }
}

class _CadenceItem extends StatelessWidget {
  const _CadenceItem({
    required this.slot,
    required this.isDone,
    required this.subtitle,
    required this.onAction,
    required this.actionLabel,
  });

  final CadenceTimeSlot slot;
  final bool isDone;
  final String subtitle;
  final VoidCallback onAction;
  final String actionLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          isDone ? Icons.check_circle : Icons.radio_button_unchecked,
          color: isDone ? Colors.green : AppColors.muted,
          size: 20,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(slot.label, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: isDone ? AppColors.inkSoft : AppColors.muted),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        TextButton(
          onPressed: onAction,
          child: Text(actionLabel),
        ),
      ],
    );
  }
}
