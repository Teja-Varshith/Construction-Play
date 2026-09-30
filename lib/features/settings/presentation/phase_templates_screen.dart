import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/config/config_models.dart';
import '../../../core/config/config_repository.dart';
import '../../../core/utils/ids.dart';
import '../../../core/widgets/common.dart';
import '../../auth/data/session.dart';
import 'settings_common.dart';

/// Standard phase lists that new projects start from.
class PhaseTemplatesScreen extends StatelessWidget {
  const PhaseTemplatesScreen({super.key});

  @override
  Widget build(BuildContext context) => ConfigGate(
        title: 'Phase templates',
        builder: (config) => _TemplatesEditor(config: config),
      );
}

String? validatePhaseTemplate(PhaseTemplate t) {
  if (t.name.trim().isEmpty) return 'Give the template a name.';
  if (t.phases.isEmpty) return 'Add at least one phase to "${t.name}".';
  if (t.phases.any((p) => p.name.trim().isEmpty)) return 'Every phase in "${t.name}" needs a name.';
  if (t.totalWeight <= 0) return 'At least one phase in "${t.name}" needs a weight above 0.';
  return null;
}

class _TemplatesEditor extends ConsumerStatefulWidget {
  const _TemplatesEditor({required this.config});

  final AppConfig config;

  @override
  ConsumerState<_TemplatesEditor> createState() => _TemplatesEditorState();
}

class _TemplatesEditorState extends ConsumerState<_TemplatesEditor> {
  late List<PhaseTemplate> _templates = [...widget.config.phaseTemplates];
  late int _rev = widget.config.revisions['phaseTemplates'] ?? 0;
  bool _dirty = false;
  bool _busy = false;

  void _load(AppConfig config) => setState(() {
        _templates = [...config.phaseTemplates];
        _rev = config.revisions['phaseTemplates'] ?? 0;
        _dirty = false;
      });

  Future<void> _edit([int? index]) async {
    final original = index == null ? null : _templates[index];
    final result = await showDialog<PhaseTemplate>(
      context: context,
      builder: (_) => _TemplateDialog(template: original),
    );
    if (result == null) return;
    setState(() {
      if (index == null) {
        _templates.add(PhaseTemplate(
          id: slugId(result.name, _templates.map((t) => t.id)),
          name: result.name,
          phases: result.phases,
        ));
      } else {
        _templates[index] = PhaseTemplate(id: original!.id, name: result.name, phases: result.phases, archived: original.archived);
      }
      _dirty = true;
    });
  }

  Future<void> _save() async {
    final active = _templates.where((t) => !t.archived).toList();
    final error = active.isEmpty ? 'Keep at least one template in use.' : active.map(validatePhaseTemplate).nonNulls.firstOrNull;
    if (error != null) {
      showMessage(context, error, error: true);
      return;
    }
    setState(() => _busy = true);
    final ok = await runConfigSave(
      context,
      () => ref
          .read(configRepositoryProvider)
          .savePhaseTemplates(_templates, expectedRev: _rev, uid: ref.read(currentUserProvider).uid),
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
    return UnsavedGuard(
      dirty: _dirty,
      child: PageScaffold(
        title: 'Phase templates',
        body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(
            'New projects start with these phases. Weights set how much each phase counts toward % complete.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          for (var i = 0; i < _templates.length; i++) ...[
            _TemplateCard(
              template: _templates[i],
              onEdit: () => _edit(i),
              onToggleArchive: () => setState(() {
                final t = _templates[i];
                _templates[i] = PhaseTemplate(id: t.id, name: t.name, phases: t.phases, archived: !t.archived);
                _dirty = true;
              }),
            ),
            const SizedBox(height: 12),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(onPressed: () => _edit(), icon: const Icon(Icons.add), label: const Text('Add template')),
          ),
          SaveBar(dirty: _dirty, busy: _busy, onSave: _save, onDiscard: () => _load(ref.read(appConfigProvider))),
        ]),
      ),
    );
  }
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({required this.template, required this.onEdit, required this.onToggleArchive});

  final PhaseTemplate template;
  final VoidCallback onEdit;
  final VoidCallback onToggleArchive;

  @override
  Widget build(BuildContext context) {
    final total = template.totalWeight;
    return SectionCard(
      title: template.name,
      subtitle: template.archived ? 'Archived · not offered for new projects' : '${template.phases.length} phases',
      trailing: Wrap(children: [
        IconButton(tooltip: 'Edit', icon: const Icon(Icons.edit_outlined), onPressed: onEdit),
        IconButton(
          tooltip: template.archived ? 'Use again' : 'Archive',
          icon: Icon(template.archived ? Icons.unarchive_outlined : Icons.archive_outlined),
          onPressed: onToggleArchive,
        ),
      ]),
      child: Column(children: [
        for (final p in template.phases)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              Expanded(child: Text(p.name)),
              Text(
                total == 0 ? '—' : '${(p.weight * 100 / total).toStringAsFixed(0)}%',
                style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
              ),
            ]),
          ),
      ]),
    );
  }
}

class _TemplateDialog extends StatefulWidget {
  const _TemplateDialog({required this.template});

  final PhaseTemplate? template;

  @override
  State<_TemplateDialog> createState() => _TemplateDialogState();
}

class _PhaseRow {
  _PhaseRow(this.id, String name, int weight)
      : name = TextEditingController(text: name),
        weight = TextEditingController(text: '$weight');

  final String id;
  final TextEditingController name;
  final TextEditingController weight;
}

class _TemplateDialogState extends State<_TemplateDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.template?.name ?? '');
  late final List<_PhaseRow> _rows = [
    for (final p in widget.template?.phases ?? const <PhaseTemplatePhase>[]) _PhaseRow(p.id, p.name, p.weight),
  ];

  @override
  void dispose() {
    _name.dispose();
    for (final r in _rows) {
      r.name.dispose();
      r.weight.dispose();
    }
    super.dispose();
  }

  void _submit() {
    if (!_form.currentState!.validate()) return;
    final taken = <String>[];
    final phases = <PhaseTemplatePhase>[];
    for (final r in _rows) {
      final id = r.id.isNotEmpty ? r.id : slugId(r.name.text, [...taken, ..._rows.map((x) => x.id)]);
      taken.add(id);
      phases.add(PhaseTemplatePhase(id: id, name: r.name.text.trim(), weight: int.parse(r.weight.text.trim())));
    }
    final t = PhaseTemplate(id: widget.template?.id ?? '', name: _name.text.trim(), phases: phases);
    final error = validatePhaseTemplate(t);
    if (error != null) {
      showMessage(context, error, error: true);
      return;
    }
    Navigator.pop(context, t);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
        child: Form(
          key: _form,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Text(widget.template == null ? 'New template' : 'Edit template',
                  style: Theme.of(context).textTheme.titleLarge),
            ),
            Expanded(
              child: ListView(padding: const EdgeInsets.symmetric(horizontal: 20), children: [
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Template name'),
                  validator: (v) => (v ?? '').trim().isEmpty ? 'Enter a name' : null,
                ),
                const SizedBox(height: 16),
                for (var i = 0; i < _rows.length; i++)
                  Padding(
                    key: ObjectKey(_rows[i]),
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(
                        child: TextFormField(
                          controller: _rows[i].name,
                          decoration: InputDecoration(labelText: 'Phase ${i + 1}'),
                          validator: (v) => (v ?? '').trim().isEmpty ? 'Name it' : null,
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 80,
                        child: TextFormField(
                          controller: _rows[i].weight,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Weight'),
                          validator: (v) {
                            final n = int.tryParse((v ?? '').trim());
                            return n == null || n < 0 || n > 1000 ? '0–1000' : null;
                          },
                        ),
                      ),
                      Column(children: [
                        IconButton(
                          tooltip: 'Move up',
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.arrow_upward),
                          onPressed: i == 0 ? null : () => setState(() => _rows.insert(i - 1, _rows.removeAt(i))),
                        ),
                        IconButton(
                          tooltip: 'Remove phase',
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.close),
                          onPressed: () => setState(() => _rows.removeAt(i)),
                        ),
                      ]),
                    ]),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setState(() => _rows.add(_PhaseRow('', '', 10))),
                    icon: const Icon(Icons.add),
                    label: const Text('Add phase'),
                  ),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                const SizedBox(width: 8),
                FilledButton(onPressed: _submit, child: const Text('OK')),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
