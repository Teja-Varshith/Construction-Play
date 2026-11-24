import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../auth/data/session.dart';
import '../data/design_repository.dart';
import '../domain/design_model.dart';

class DrawingsTab extends ConsumerStatefulWidget {
  const DrawingsTab({super.key, required this.projectId});

  final String projectId;

  @override
  ConsumerState<DrawingsTab> createState() => _DrawingsTabState();
}

class _DrawingsTabState extends ConsumerState<DrawingsTab> {
  DrawingCategory? _selectedCategory;

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(currentUserProvider);
    final drawingsAsync = ref.watch(projectDrawingsProvider(widget.projectId));

    final canManageDrawings = me.isDesigner || me.isManager || me.isAdmin || me.isCeo;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.architecture, color: AppColors.blue),
                  const SizedBox(width: 8),
                  Text(
                    'Drawings & Design Revisions',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              if (canManageDrawings)
                FilledButton.icon(
                  onPressed: () => _openAddDrawingDialog(),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add Drawing Sheet'),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // Category filter
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                FilterChip(
                  selected: _selectedCategory == null,
                  label: const Text('All Categories'),
                  onSelected: (_) => setState(() => _selectedCategory = null),
                ),
                const SizedBox(width: 6),
                ...DrawingCategory.values.map(
                  (cat) => Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: FilterChip(
                      selected: _selectedCategory == cat,
                      label: Text(cat.label),
                      onSelected: (sel) => setState(() => _selectedCategory = sel ? cat : null),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          AsyncView(
            value: drawingsAsync,
            data: (drawings) {
              final filtered = _selectedCategory != null
                  ? drawings.where((d) => d.category == _selectedCategory).toList()
                  : drawings;

              if (filtered.isEmpty) {
                return const Card(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(
                      child: Text(
                        'No design drawings added for this project yet.\nDesigners can add 2D architectural sheets, 3D renders, and structural layouts.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                );
              }

              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: filtered.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final drawing = filtered[index];
                  return _DrawingCard(
                    drawing: drawing,
                    canManage: canManageDrawings,
                    onUploadRevision: () => _openUploadRevisionDialog(drawing),
                    onStatusChange: (status) => _updateStatus(drawing, status),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  void _openAddDrawingDialog() {
    DrawingCategory cat = DrawingCategory.architecture2D;
    DrawingStatus status = DrawingStatus.draft;
    final title = TextEditingController();
    final version = TextEditingController(text: 'v1.0');
    final file = TextEditingController();
    final notes = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Add Drawing Sheet'),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 480,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<DrawingCategory>(
                    initialValue: cat,
                    decoration: const InputDecoration(labelText: 'Drawing Category *'),
                    onChanged: (c) => setDialogState(() => cat = c!),
                    items: DrawingCategory.values
                        .map((c) => DropdownMenuItem(value: c, child: Text(c.label)))
                        .toList(),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: title,
                    decoration: const InputDecoration(
                      labelText: 'Sheet Title *',
                      hintText: 'e.g. Ground Floor Working Plan',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: version,
                          decoration: const InputDecoration(labelText: 'Version Code'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<DrawingStatus>(
                          initialValue: status,
                          decoration: const InputDecoration(labelText: 'Initial Status'),
                          onChanged: (s) => setDialogState(() => status = s!),
                          items: DrawingStatus.values
                              .map((s) => DropdownMenuItem(value: s, child: Text(s.label)))
                              .toList(),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: file,
                    decoration: const InputDecoration(
                      labelText: 'File / Drive Link (optional)',
                      hintText: 'https://...',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: notes,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: 'Notes / Change Log'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                if (title.text.trim().isEmpty) return;
                final me = ref.read(currentUserProvider);
                await ref.read(designRepositoryProvider).addDrawing(
                      uid: me.uid,
                      designerName: me.name,
                      projectId: widget.projectId,
                      title: title.text.trim(),
                      category: cat,
                      version: version.text.trim(),
                      status: status,
                      fileUrl: file.text.trim(),
                      notes: notes.text.trim(),
                    );
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Add Drawing'),
            ),
          ],
        ),
      ),
    );
  }

  void _openUploadRevisionDialog(DesignDrawing drawing) {
    final nextVersion = _suggestNextVersion(drawing.currentVersion);
    final version = TextEditingController(text: nextVersion);
    final file = TextEditingController();
    final notes = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Upload Revision for ${drawing.title}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: version,
              decoration: const InputDecoration(labelText: 'New Version Code *'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: file,
              decoration: const InputDecoration(
                labelText: 'Updated Drawing Link',
                hintText: 'https://...',
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: notes,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Revision Notes (What changed?) *',
                hintText: 'e.g. Enlarged master bedroom window per client request',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              if (version.text.trim().isEmpty) return;
              final me = ref.read(currentUserProvider);
              await ref.read(designRepositoryProvider).uploadRevision(
                    uid: me.uid,
                    designerName: me.name,
                    projectId: widget.projectId,
                    drawing: drawing,
                    newVersion: version.text.trim(),
                    fileUrl: file.text.trim(),
                    notes: notes.text.trim(),
                  );
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Save Revision'),
          ),
        ],
      ),
    );
  }

  Future<void> _updateStatus(DesignDrawing drawing, DrawingStatus newStatus) async {
    final me = ref.read(currentUserProvider);
    await ref.read(designRepositoryProvider).updateStatus(
          uid: me.uid,
          projectId: widget.projectId,
          drawing: drawing,
          newStatus: newStatus,
        );
  }

  String _suggestNextVersion(String current) {
    if (current.startsWith('v')) {
      final parts = current.substring(1).split('.');
      if (parts.length == 2) {
        final major = int.tryParse(parts[0]) ?? 1;
        final minor = int.tryParse(parts[1]) ?? 0;
        return 'v$major.${minor + 1}';
      }
    }
    return '${current}_rev';
  }
}

class _DrawingCard extends StatelessWidget {
  const _DrawingCard({
    required this.drawing,
    required this.canManage,
    required this.onUploadRevision,
    required this.onStatusChange,
  });

  final DesignDrawing drawing;
  final bool canManage;
  final VoidCallback onUploadRevision;
  final ValueChanged<DrawingStatus> onStatusChange;

  Color _statusColor(DrawingStatus status) {
    switch (status) {
      case DrawingStatus.draft:
        return Colors.blueGrey;
      case DrawingStatus.inReview:
        return Colors.blue;
      case DrawingStatus.clientReview:
        return Colors.amber.shade900;
      case DrawingStatus.revisionRequested:
        return Colors.red.shade700;
      case DrawingStatus.clientApproved:
        return Colors.teal;
      case DrawingStatus.gfc:
        return Colors.green.shade700;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            drawing.title,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceAlt,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              drawing.currentVersion,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: _statusColor(drawing.status).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              drawing.status.label,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: _statusColor(drawing.status),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${drawing.category.label} • Designer: ${drawing.designerName.isNotEmpty ? drawing.designerName : 'Design Team'}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted),
                      ),
                      if (drawing.notes.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          drawing.notes,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.inkSoft),
                        ),
                      ],
                    ],
                  ),
                ),
                if (canManage) ...[
                  PopupMenuButton<DrawingStatus>(
                    icon: const Icon(Icons.more_vert),
                    tooltip: 'Change Status',
                    onSelected: onStatusChange,
                    itemBuilder: (_) => DrawingStatus.values
                        .map((s) => PopupMenuItem(value: s, child: Text(s.label)))
                        .toList(),
                  ),
                ],
              ],
            ),
            const Divider(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${drawing.revisions.length} revision(s) logged',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted),
                ),
                Row(
                  children: [
                    if (drawing.fileUrl.isNotEmpty)
                      TextButton.icon(
                        onPressed: () {},
                        icon: const Icon(Icons.open_in_new, size: 16),
                        label: const Text('Open Drawing'),
                      ),
                    if (canManage)
                      FilledButton.tonalIcon(
                        onPressed: onUploadRevision,
                        icon: const Icon(Icons.upload_file, size: 16),
                        label: const Text('New Revision'),
                      ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
