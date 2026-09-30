import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/config_models.dart';
import '../../../core/config/config_repository.dart';
import '../../../core/widgets/common.dart';
import '../../../core/firebase/firebase_providers.dart';
import '../../auth/data/session.dart';
import '../../auth/domain/app_user.dart';
import '../data/project_detail_repository.dart';
import '../domain/project.dart';
import '../domain/project_detail.dart';
import 'project_editors.dart';

bool canManageProject(AppUser user, Project project) =>
    user.isAdmin ||
    (user.role == UserRole.manager && project.memberIds.contains(user.uid));
bool canReportProject(AppUser user, Project project) =>
    canManageProject(user, project) ||
    (user.role == UserRole.supervisor && project.memberIds.contains(user.uid));

/// Leaders always see the Money tab; a manager sees it while the project is open.
bool canSeeMoney(AppUser user, Project project, ProjectStage stage) =>
    user.isCeo ||
    user.isAdmin ||
    (canManageProject(user, project) &&
        stage != ProjectStage.completed &&
        stage != ProjectStage.cancelled);

class ProjectRecordActions extends ConsumerStatefulWidget {
  const ProjectRecordActions({
    super.key,
    required this.project,
    required this.kind,
    required this.record,
    this.previous,
  });
  final Project project;
  final String kind;
  final Object record;
  final ProjectPhase? previous;
  @override
  ConsumerState<ProjectRecordActions> createState() =>
      _ProjectRecordActionsState();
}

class _ProjectRecordActionsState extends ConsumerState<ProjectRecordActions> {
  bool _busy = false;
  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final stage = ref
        .watch(appConfigProvider)
        .stageOfStatus(widget.project.statusId);
    final canEdit = !const [
          ProjectStage.completed,
          ProjectStage.cancelled,
        ].contains(stage) &&
        (widget.kind == 'phases'
            ? canManageProject(user, widget.project)
            : canReportProject(user, widget.project));
    return Wrap(
      spacing: 8,
      children: [
        if (canEdit && widget.kind != 'documents')
          TextButton.icon(
            onPressed: _busy
                ? null
                : () => showProjectEditor(
                    context,
                    project: widget.project,
                    kind: widget.kind,
                    record: widget.record,
                  ),
            icon: const Icon(Icons.edit_outlined, size: 16),
            label: const Text('Update'),
          ),
        if (canEdit && widget.previous != null)
          TextButton.icon(
            onPressed: _busy
                ? null
                : () => _run(
                    () => ref
                        .read(projectDetailRepositoryProvider)
                        .movePhase(
                          widget.project.id,
                          widget.record as ProjectPhase,
                          widget.previous!,
                          user.uid,
                        ),
                  ),
            icon: const Icon(Icons.arrow_upward, size: 16),
            label: const Text('Move up'),
          ),
        if (canEdit && (widget.kind == 'phases' || widget.kind == 'documents'))
          TextButton(
            onPressed: _busy
                ? null
                : () async {
                    if (!await confirmAction(
                      context,
                      title: 'Archive this record?',
                      message: 'It will be removed from the active view. Its history is retained.',
                      confirmLabel: 'Archive',
                    )) {
                      return;
                    }
                    final r = widget.record;
                    final id = r is ProjectPhase
                        ? r.id
                        : (r as ProjectDocument).id;
                    final revision = r is ProjectPhase
                        ? r.revision
                        : (r as ProjectDocument).revision;
                    await _run(
                      () => ref
                          .read(projectDetailRepositoryProvider)
                          .save(
                            widget.project.id,
                            widget.kind,
                            {'deleted': true},
                            uid: user.uid,
                            id: id,
                            expectedRevision: revision,
                          ),
                    );
                  },
            child: const Text('Archive'),
          ),
        if (widget.record is DailyProgressReport && (widget.record as DailyProgressReport).revision > 1)
          TextButton.icon(icon: const Icon(Icons.history, size: 16), label: const Text('Report history'),
            onPressed: () => showDialog<void>(context: context, builder: (_) => AlertDialog(
              title: const Text('Earlier report versions'),
              content: SizedBox(width: 520, height: 400, child: StreamBuilder(
                stream: ref.read(firestoreProvider).collection('projects').doc(widget.project.id)
                  .collection('dprs').doc((widget.record as DailyProgressReport).id).collection('revisions').orderBy('revision', descending: true).snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) return const Text('Could not load report history.');
                  if (!snapshot.hasData) return const LoadingView();
                  return ListView(children: [for (final doc in snapshot.data!.docs) ListTile(
                    title: Text('Version ${doc.data()['revision'] ?? 0}'),
                    subtitle: Text('${doc.data()['notes'] ?? ''}\nTarget ${doc.data()['targetQuantity']} · Achieved ${doc.data()['achievedQuantity']} ${doc.data()['unit'] ?? ''}'),
                  )]);
                })),
              actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
            ))),
      ],
    );
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) showMessage(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
