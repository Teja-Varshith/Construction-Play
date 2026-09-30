import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/config/config_models.dart';
import '../../../core/config/config_repository.dart';
import '../../../core/dynamic_form/dynamic_fields.dart';
import '../../../core/utils/ids.dart';
import '../../../core/widgets/common.dart';
import '../../auth/data/session.dart';
import 'settings_common.dart';

/// Lets the office add fields to a record type without a new app version.
class CustomFieldsScreen extends StatelessWidget {
  const CustomFieldsScreen({super.key, required this.entity});

  final FieldEntity entity;

  @override
  Widget build(BuildContext context) => ConfigGate(
        title: 'Extra fields: ${entity.title}',
        builder: (config) => _FieldsEditor(entity: entity, config: config),
      );
}

String? validateFieldDefs(List<FieldDef> fields) {
  final labels = <String>{};
  for (final f in fields.where((f) => !f.archived)) {
    if (!labels.add(f.label.trim().toLowerCase())) return 'Two fields are called "${f.label}". Use different names.';
    if (f.type.hasOptions && f.activeOptions.isEmpty) return '"${f.label}" needs at least one option.';
  }
  return null;
}

class _FieldsEditor extends ConsumerStatefulWidget {
  const _FieldsEditor({required this.entity, required this.config});

  final FieldEntity entity;
  final AppConfig config;

  @override
  ConsumerState<_FieldsEditor> createState() => _FieldsEditorState();
}

class _FieldsEditorState extends ConsumerState<_FieldsEditor> {
  late List<FieldDef> _fields = [...widget.config.fieldsFor(widget.entity)];
  late int _rev = widget.config.revisions[widget.entity.docId] ?? 0;
  Map<String, dynamic> _preview = {};
  final _previewForm = GlobalKey<FormState>();
  bool _dirty = false;
  bool _busy = false;

  void _load(AppConfig config) => setState(() {
        _fields = [...config.fieldsFor(widget.entity)];
        _rev = config.revisions[widget.entity.docId] ?? 0;
        _dirty = false;
      });

  Future<void> _edit([int? index]) async {
    final original = index == null ? null : _fields[index];
    final result = await showDialog<FieldDef>(context: context, builder: (_) => _FieldDialog(field: original));
    if (result == null) return;
    setState(() {
      if (original == null) {
        _fields.add(FieldDef(
          id: slugId(result.label, _fields.map((f) => f.id)),
          label: result.label,
          type: result.type,
          required: result.required,
          help: result.help,
          showOnCard: result.showOnCard,
          options: result.options,
        ));
      } else {
        _fields[index!] = original.copyWith(
          label: result.label,
          required: result.required,
          help: result.help,
          showOnCard: result.showOnCard,
          options: result.options,
        );
      }
      _dirty = true;
    });
  }

  Future<void> _save() async {
    final error = validateFieldDefs(_fields);
    if (error != null) {
      showMessage(context, error, error: true);
      return;
    }
    setState(() => _busy = true);
    final ok = await runConfigSave(
      context,
      () => ref
          .read(configRepositoryProvider)
          .saveFields(widget.entity, _fields, expectedRev: _rev, uid: ref.read(currentUserProvider).uid),
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
    final active = _fields.where((f) => !f.archived).toList();
    return UnsavedGuard(
      dirty: _dirty,
      child: PageScaffold(
        title: 'Extra fields: ${widget.entity.title}',
        body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(
            'These appear on the ${widget.entity.title.toLowerCase()} form under "More details". '
            'A field\'s type can\'t change after saving; archive it and add a new one instead.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          if (_fields.isEmpty)
            const Card(
              child: MessageView(
                icon: Icons.dashboard_customize_outlined,
                title: 'No extra fields yet',
                message: 'Add fields such as "RERA number", "Plot area (sq ft)" or "Architect".',
              ),
            )
          else
            Card(
              child: ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                itemCount: _fields.length,
                onReorderItem: (from, to) => setState(() {
                  _fields.insert(to, _fields.removeAt(from));
                  _dirty = true;
                }),
                itemBuilder: (context, i) {
                  final f = _fields[i];
                  return ListTile(
                    key: ValueKey(f.id),
                    leading: ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_indicator)),
                    title: Text(
                      f.required ? '${f.label} *' : f.label,
                      style: f.archived ? TextStyle(color: theme.disabledColor, decoration: TextDecoration.lineThrough) : null,
                    ),
                    subtitle: Text([
                      f.type.label,
                      if (f.type.hasOptions) '${f.activeOptions.length} options',
                      if (f.showOnCard) 'shown on cards',
                    ].join(' · ')),
                    trailing: Wrap(children: [
                      IconButton(
                        tooltip: 'Edit',
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: f.archived ? null : () => _edit(i),
                      ),
                      IconButton(
                        tooltip: f.archived ? 'Use again' : 'Archive (keeps saved values)',
                        icon: Icon(f.archived ? Icons.unarchive_outlined : Icons.archive_outlined),
                        onPressed: () => setState(() {
                          _fields[i] = f.copyWith(archived: !f.archived);
                          _dirty = true;
                        }),
                      ),
                    ]),
                  );
                },
              ),
            ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(onPressed: () => _edit(), icon: const Icon(Icons.add), label: const Text('Add field')),
          ),
          SaveBar(dirty: _dirty, busy: _busy, onSave: _save, onDiscard: () => _load(ref.read(appConfigProvider))),
          if (active.isNotEmpty) ...[
            const SizedBox(height: 24),
            SectionCard(
              title: 'Preview',
              subtitle: 'How these fields will look on the form. Nothing here is saved.',
              trailing: TextButton(
                onPressed: () {
                  final ok = _previewForm.currentState!.validate();
                  showMessage(context, ok ? 'Looks good' : 'Some fields need attention', error: !ok);
                },
                child: const Text('Check'),
              ),
              child: Form(
                key: _previewForm,
                child: DynamicFields(
                  key: ValueKey(active.map((f) => '${f.id}${f.type.name}${f.required}').join()),
                  fields: active,
                  values: _preview,
                  onChanged: (id, v) => _preview = {..._preview, id: v},
                ),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}

class _FieldDialog extends StatefulWidget {
  const _FieldDialog({required this.field});

  final FieldDef? field;

  @override
  State<_FieldDialog> createState() => _FieldDialogState();
}

class _FieldDialogState extends State<_FieldDialog> {
  final _form = GlobalKey<FormState>();
  late final _label = TextEditingController(text: widget.field?.label ?? '');
  late final _help = TextEditingController(text: widget.field?.help ?? '');
  final _newOption = TextEditingController();
  late FieldType _type = widget.field?.type ?? FieldType.text;
  late bool _required = widget.field?.required ?? false;
  late bool _showOnCard = widget.field?.showOnCard ?? false;
  late List<ConfigItem> _options = [...?widget.field?.options];

  bool get _isNew => widget.field == null;

  @override
  void dispose() {
    _label.dispose();
    _help.dispose();
    _newOption.dispose();
    super.dispose();
  }

  void _addOption() {
    final label = _newOption.text.trim();
    if (label.isEmpty) return;
    if (_options.any((o) => !o.archived && o.label.toLowerCase() == label.toLowerCase())) {
      showMessage(context, '"$label" is already an option', error: true);
      return;
    }
    setState(() {
      _options = [..._options, ConfigItem(id: slugId(label, _options.map((o) => o.id)), label: label)];
      _newOption.clear();
    });
  }

  void _submit() {
    if (!_form.currentState!.validate()) return;
    if (_type.hasOptions && !_options.any((o) => !o.archived)) {
      showMessage(context, 'Add at least one option', error: true);
      return;
    }
    Navigator.pop(
      context,
      FieldDef(
        id: widget.field?.id ?? '',
        label: _label.text.trim(),
        type: _type,
        required: _required,
        help: _help.text.trim(),
        showOnCard: _showOnCard,
        options: _type.hasOptions ? _options : const [],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isNew ? 'Add field' : 'Edit field'),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextFormField(
                controller: _label,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Field name', hintText: 'e.g. RERA number'),
                validator: (v) => (v ?? '').trim().isEmpty ? 'Enter a name' : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<FieldType>(
                initialValue: _type,
                decoration: InputDecoration(
                  labelText: 'Type',
                  helperText: _isNew ? null : 'Type is fixed after saving',
                ),
                items: [for (final t in FieldType.values) DropdownMenuItem(value: t, child: Text(t.label))],
                onChanged: _isNew ? (t) => setState(() => _type = t ?? _type) : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _help,
                decoration: const InputDecoration(labelText: 'Hint shown under the field (optional)'),
              ),
              if (_type.hasOptions) ...[
                const SizedBox(height: 16),
                Text('Options', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (var i = 0; i < _options.length; i++)
                    InputChip(
                      label: Text(_options[i].label),
                      avatar: _options[i].archived ? const Icon(Icons.archive_outlined, size: 16) : null,
                      tooltip: _options[i].archived ? 'Archived. Tap to use again.' : null,
                      onPressed: _options[i].archived
                          ? () => setState(() => _options[i] = _options[i].copyWith(archived: false))
                          : null,
                      onDeleted: _options[i].archived
                          ? null
                          : () => setState(() => _options[i] = _options[i].copyWith(archived: true)),
                      deleteButtonTooltipMessage: 'Archive option',
                    ),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _newOption,
                      decoration: const InputDecoration(labelText: 'New option'),
                      onSubmitted: (_) => _addOption(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(tooltip: 'Add option', onPressed: _addOption, icon: const Icon(Icons.add)),
                ]),
              ],
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _required,
                onChanged: (v) => setState(() => _required = v),
                title: const Text('Required'),
                subtitle: const Text('Older records without it are still allowed until edited.'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _showOnCard,
                onChanged: (v) => setState(() => _showOnCard = v),
                title: const Text('Show on cards and lists'),
              ),
            ]),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('OK')),
      ],
    );
  }
}
