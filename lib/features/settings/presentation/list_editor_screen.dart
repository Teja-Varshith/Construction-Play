import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/config/config_models.dart';
import '../../../core/config/config_repository.dart';
import '../../../core/utils/ids.dart';
import '../../../core/widgets/common.dart';
import '../../auth/data/session.dart';
import 'settings_common.dart';

/// Edits one config list. Items can be renamed, reordered and archived, but
/// never deleted, because existing records point at their ids.
class ListEditorScreen extends StatelessWidget {
  const ListEditorScreen({super.key, required this.list});

  final ConfigList list;

  @override
  Widget build(BuildContext context) => ConfigGate(
        title: list.title,
        builder: (config) => _ListEditor(list: list, config: config),
      );
}

/// Checks a list before saving. Returns an error message or null.
String? validateConfigList(ConfigList list, List<ConfigItem> items) {
  final active = items.where((i) => !i.archived).toList();
  if (active.isEmpty) return 'Keep at least one item in use.';
  final labels = <String>{};
  for (final i in active) {
    if (!labels.add(i.label.trim().toLowerCase())) return 'Two items are called "${i.label}". Use different names.';
  }
  if (list == ConfigList.projectStatuses) {
    for (final stage in [ProjectStage.pipeline, ProjectStage.ongoing, ProjectStage.completed]) {
      if (!active.any((i) => i.stage == stage)) {
        return 'Keep at least one stage for "${stage.label}". The dashboard groups projects by it.';
      }
    }
  }
  return null;
}

class _ListEditor extends ConsumerStatefulWidget {
  const _ListEditor({required this.list, required this.config});

  final ConfigList list;
  final AppConfig config;

  @override
  ConsumerState<_ListEditor> createState() => _ListEditorState();
}

class _ListEditorState extends ConsumerState<_ListEditor> {
  late List<ConfigItem> _items = [...widget.config.allOf(widget.list)];
  late int _rev = widget.config.revisions[widget.list.docId] ?? 0;
  bool _dirty = false;
  bool _busy = false;

  bool get _isStatuses => widget.list == ConfigList.projectStatuses;

  void _load(AppConfig config) => setState(() {
        _items = [...config.allOf(widget.list)];
        _rev = config.revisions[widget.list.docId] ?? 0;
        _dirty = false;
      });

  void _update(void Function() change) => setState(() {
        change();
        _dirty = true;
      });

  Future<void> _edit({ConfigItem? item}) async {
    final result = await showDialog<ConfigItem>(
      context: context,
      builder: (_) => _ItemDialog(
        item: item,
        isStatus: _isStatuses,
        takenLabels: _items.where((i) => i.id != item?.id && !i.archived).map((i) => i.label.toLowerCase()).toSet(),
      ),
    );
    if (result == null) return;
    _update(() {
      if (item == null) {
        _items.add(ConfigItem(id: slugId(result.label, _items.map((i) => i.id)), label: result.label, stage: result.stage));
      } else {
        final idx = _items.indexWhere((i) => i.id == item.id);
        _items[idx] = item.copyWith(label: result.label, stage: result.stage);
      }
    });
  }

  Future<void> _save() async {
    final error = validateConfigList(widget.list, _items);
    if (error != null) {
      showMessage(context, error, error: true);
      return;
    }
    setState(() => _busy = true);
    final ok = await runConfigSave(
      context,
      () => ref
          .read(configRepositoryProvider)
          .saveList(widget.list, _items, expectedRev: _rev, uid: ref.read(currentUserProvider).uid),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      setState(() {
        _rev++;
        _dirty = false;
      });
    } else {
      final latest = ref.read(appConfigStreamProvider).value;
      if (latest != null) _load(latest);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return UnsavedGuard(
      dirty: _dirty,
      child: PageScaffold(
        title: widget.list.title,
        body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(widget.list.description, style: theme.textTheme.bodyMedium),
          if (_isStatuses) ...[
            const SizedBox(height: 8),
            Text(
              'Each stage belongs to a group (Pipeline, Ongoing, On hold, Completed or Cancelled), which the CEO dashboard uses.',
              style: theme.textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 16),
          Card(
            child: ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: _items.length,
              onReorderItem: (from, to) => _update(() => _items.insert(to, _items.removeAt(from))),
              itemBuilder: (context, i) {
                final item = _items[i];
                return ListTile(
                  key: ValueKey(item.id),
                  leading: ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_indicator)),
                  title: Text(
                    item.label,
                    style: item.archived
                        ? TextStyle(color: theme.disabledColor, decoration: TextDecoration.lineThrough)
                        : null,
                  ),
                  subtitle: _isStatuses ? Text(item.stage?.label ?? 'No group') : null,
                  trailing: Wrap(children: [
                    if (item.archived) const Padding(padding: EdgeInsets.only(right: 8, top: 12), child: Pill('Archived')),
                    IconButton(
                      tooltip: 'Rename',
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: item.archived ? null : () => _edit(item: item),
                    ),
                    IconButton(
                      tooltip: item.archived ? 'Use again' : 'Archive (hide from new records)',
                      icon: Icon(item.archived ? Icons.unarchive_outlined : Icons.archive_outlined),
                      onPressed: () => _update(() => _items[i] = item.copyWith(archived: !item.archived)),
                    ),
                  ]),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(onPressed: () => _edit(), icon: const Icon(Icons.add), label: const Text('Add item')),
          ),
          SaveBar(
            dirty: _dirty,
            busy: _busy,
            onSave: _save,
            onDiscard: () => _load(ref.read(appConfigProvider)),
          ),
        ]),
      ),
    );
  }
}

class _ItemDialog extends StatefulWidget {
  const _ItemDialog({required this.item, required this.isStatus, required this.takenLabels});

  final ConfigItem? item;
  final bool isStatus;
  final Set<String> takenLabels;

  @override
  State<_ItemDialog> createState() => _ItemDialogState();
}

class _ItemDialogState extends State<_ItemDialog> {
  final _form = GlobalKey<FormState>();
  late final _label = TextEditingController(text: widget.item?.label ?? '');
  late ProjectStage _stage = widget.item?.stage ?? ProjectStage.pipeline;

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_form.currentState!.validate()) return;
    Navigator.pop(context, ConfigItem(id: '', label: _label.text.trim(), stage: widget.isStatus ? _stage : null));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.item == null ? 'Add item' : 'Rename'),
      content: Form(
        key: _form,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextFormField(
            controller: _label,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Name'),
            validator: (v) {
              final s = (v ?? '').trim();
              if (s.isEmpty) return 'Enter a name';
              if (widget.takenLabels.contains(s.toLowerCase())) return 'This name is already used';
              return null;
            },
            onFieldSubmitted: (_) => _submit(),
          ),
          if (widget.isStatus) ...[
            const SizedBox(height: 16),
            DropdownButtonFormField<ProjectStage>(
              initialValue: _stage,
              decoration: const InputDecoration(labelText: 'Dashboard group'),
              items: [for (final s in ProjectStage.values) DropdownMenuItem(value: s, child: Text(s.label))],
              onChanged: (s) => setState(() => _stage = s ?? _stage),
            ),
          ],
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('OK')),
      ],
    );
  }
}
