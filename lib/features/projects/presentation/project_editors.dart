import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/config_models.dart';
import '../../../core/config/config_repository.dart';
import '../../../core/dynamic_form/dynamic_fields.dart';
import '../../../core/utils/work_day.dart';
import '../../../core/widgets/common.dart';
import '../../auth/data/session.dart';
import '../../users/data/user_repository.dart';
import '../data/project_detail_repository.dart';
import '../data/project_media.dart';
import '../data/project_repository.dart';
import '../domain/project.dart';
import '../domain/project_detail.dart';

Future<void> showProjectEditor(
  BuildContext context, {
  required Project project,
  required String kind,
  Object? record,
  int nextOrder = 0,
}) {
  final container = ProviderScope.containerOf(context);
  if (kind == 'dprs' && record == null) {
    final config = container.read(appConfigProvider);
    final today = WorkDay.today(
      utcOffsetMinutes: config.company.utcOffsetMinutes,
    );
    record = container
        .read(projectDprsProvider(project.id))
        .value
        ?.where((r) => r.date == today)
        .firstOrNull;
  }
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => ProjectEditor(
      project: project,
      kind: kind,
      record: record,
      nextOrder: nextOrder,
    ),
  );
}

/// A small form per job; the CEO never has to work through these entry forms.
class ProjectEditor extends ConsumerStatefulWidget {
  const ProjectEditor({
    super.key,
    required this.project,
    required this.kind,
    this.record,
    this.nextOrder = 0,
  });
  final Project project;
  final String kind;
  final Object? record;
  final int nextOrder;
  @override
  ConsumerState<ProjectEditor> createState() => _ProjectEditorState();
}

class _ProjectEditorState extends ConsumerState<ProjectEditor> {
  final _form = GlobalKey<FormState>();
  final _values = <String, dynamic>{};
  final _custom = <String, dynamic>{};
  final _files = <PlatformFile>[];
  final _uploaded = <String>[];
  bool _busy = false;
  String? _error;
  String _saving = 'Saving...';
  String? _id;
  int? _revision;

  @override
  void initState() {
    super.initState();
    final r = widget.record;
    if (r is ProjectPhase) {
      _id = r.id;
      _revision = r.revision;
      _values.addAll({
        'name': r.name,
        'weight': r.weight,
        'actualPct': r.actualPct,
        'plannedStart': r.plannedStart,
        'plannedEnd': r.plannedEnd,
        'ownerId': r.ownerId,
        'order': r.order,
        'budgetPaise': r.budgetPaise,
        'delayReason': r.delayReason,
      });
    } else if (r is DailyProgressReport) {
      _id = r.id;
      _revision = r.revision;
      _values.addAll({
        'date': r.date,
        'targetQuantity': r.targetQuantity,
        'achievedQuantity': r.achievedQuantity,
        'unit': r.unit,
        'notes': r.notes,
        'photoUrls': r.photoUrls,
      });
    } else if (r is ProjectIssue) {
      _id = r.id;
      _revision = r.revision;
      _values.addAll({
        'title': r.title,
        'description': r.description,
        'priorityId': r.priorityId,
        'status': r.status,
        'assigneeId': r.assigneeId,
        'phaseId': r.phaseId,
      });
    }
    if (widget.kind == 'details') {
      _values.addAll(widget.project.toEditableMap());
      _custom.addAll(widget.project.custom);
    }
    if (widget.kind == 'status') _values['statusId'] = widget.project.statusId;
    if (widget.kind == 'phases') {
      _values.putIfAbsent('weight', () => 1.0);
      _values.putIfAbsent('actualPct', () => 0.0);
      _values.putIfAbsent('order', () => widget.nextOrder);
      _values.putIfAbsent('budgetPaise', () => 0);
      _values.putIfAbsent('delayReason', () => '');
    }
    if (widget.kind == 'dprs') {
      final config = ref.read(appConfigProvider);
      final today = WorkDay.today(utcOffsetMinutes: config.company.utcOffsetMinutes);
      _values.putIfAbsent('date', () => today);
      // Sites keep the same unit and usually the same target day to day, so a
      // new report starts from the last one instead of a blank form.
      if (widget.record == null) {
        final last = _lastReport(today);
        if (last != null) {
          _values.putIfAbsent('unit', () => last.unit);
          if (last.targetQuantity != null) _values.putIfAbsent('targetQuantity', () => last.targetQuantity);
        }
      }
    }
    // A new issue starts at "medium", not the first (lowest) priority.
    if (widget.kind == 'issues' && widget.record == null) {
      final config = ref.read(appConfigProvider);
      if (config.activeOf(ConfigList.issuePriorities).any((p) => p.id == 'medium')) {
        _values['priorityId'] = 'medium';
      }
    }
  }

  /// The most recent report before [today], if any.
  DailyProgressReport? _lastReport(String today) {
    final reports = ref.read(projectDprsProvider(widget.project.id)).value ?? const <DailyProgressReport>[];
    DailyProgressReport? best;
    for (final r in reports) {
      if (r.date.compareTo(today) < 0 && (best == null || r.date.compareTo(best.date) > 0)) best = r;
    }
    return best;
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Required' : null;
  Widget _text(
    String key,
    String label, {
    bool required = true,
    int lines = 1,
  }) => TextFormField(
    initialValue: _values[key]?.toString() ?? '',
    maxLines: lines,
    decoration: InputDecoration(labelText: label),
    validator: required ? _required : null,
    onChanged: (value) => _values[key] = value.trim(),
  );
  Widget _number(String key, String label, {double? max}) => TextFormField(
    initialValue: _values[key]?.toString() ?? '',
    decoration: InputDecoration(labelText: label),
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    validator: (value) {
      final n = double.tryParse(value ?? '');
      return n == null || !n.isFinite || n < 0 || (max != null && n > max)
          ? 'Enter a number from 0${max == null ? '' : ' to $max'}'
          : null;
    },
    onChanged: (value) => _values[key] = num.tryParse(value),
  );
  Widget _date(String key, String label, {bool enabled = true}) =>
      DateFormField(
        label: label,
        enabled: enabled,
        initialKey: _values[key] as String?,
        validator: (v) => v == null ? 'Choose a date' : null,
        onChanged: (value) => _values[key] = value,
      );
  Widget _select(
    String key,
    String label,
    Map<String, String> options, {
    bool optional = false,
    String noneLabel = 'Unassigned',
  }) {
    final current = _values[key] as String?;
    final choices = {
      ...options,
      if (current != null && !options.containsKey(current))
        current: 'Previous: $current',
    };
    _values.putIfAbsent(key, () => optional ? null : choices.keys.firstOrNull);
    return DropdownButtonFormField<String>(
      initialValue: _values[key] as String?,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        if (optional)
          DropdownMenuItem(value: null, child: Text(noneLabel)),
        for (final entry in choices.entries)
          DropdownMenuItem(
            value: entry.key,
            child: Text(entry.value, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (value) => _values[key] = value,
      validator: optional
          ? null
          : (value) => value == null ? 'Choose an option' : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(appConfigProvider);
    final people = ref.watch(allUsersProvider).value ?? [];
    final user = ref.watch(currentUserProvider);
    final team = {
      for (final person in people.where(
        (p) => widget.project.memberIds.contains(p.uid),
      ))
        person.uid: person.name,
    };
    Map<String, String> options(ConfigList list) => {
      for (final option in config.activeOf(list)) option.id: option.label,
    };
    final fields = <Widget>[
      if (widget.kind == 'phases') ...[
        _text('name', 'Phase name'),
        _date('plannedStart', 'Planned start'),
        _date('plannedEnd', 'Planned finish'),
        _number('weight', 'Relative weight (e.g. 5, 15, 30)'),
        const Text(
          'Weights determine each phase’s share of project progress. They are normalized automatically.',
        ),
        _number('actualPct', 'Work completed (%)', max: 100),
        _select('ownerId', 'Phase owner', team, optional: true),
        MoneyFormField(
          label: 'Phase budget',
          initialPaise: (_values['budgetPaise'] as int?) == 0
              ? null
              : _values['budgetPaise'] as int?,
          onChanged: (value) => _values['budgetPaise'] = value ?? 0,
          validator: (value) =>
              value != null && value < 0 ? 'Budget cannot be negative' : null,
        ),
        _text(
          'delayReason',
          'Reason for delay (if the phase is late)',
          required: false,
          lines: 2,
        ),
      ],
      if (widget.kind == 'dprs') ...[
        _date('date', 'Report date', enabled: _id == null),
        Text(
          'One report per site and day. Reports can be entered up to ${config.company.dprBackdateDays} days late.',
        ),
        if (_id == null)
          if (_lastReport(_values['date'] as String? ?? '') case final last?)
            Text(
              'Last report (${WorkDay.display(last.date)}): '
              '${last.achievedQuantity ?? '–'} of ${last.targetQuantity ?? '–'} ${last.unit}. '
              'Target and unit are copied from it; change them if today differs.',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12.5),
            ),
        _number('targetQuantity', 'Today’s target quantity'),
        _number('achievedQuantity', 'Quantity completed'),
        _text('unit', 'Unit (m², m³, rooms, floors...)'),
        _text('notes', 'Work done, delays and next steps', lines: 4),
        const Text(
          'Update phase completion in Timeline when this work changes overall progress.',
        ),
        ..._fileControls(photos: true),
      ],
      if (widget.kind == 'issues') ...[
        _text('title', 'What needs attention?'),
        _text('description', 'Details / resolution note', lines: 4),
        _select('priorityId', 'Priority', options(ConfigList.issuePriorities)),
        _select('assigneeId', 'Responsible person', team, optional: true),
        _select('phaseId', 'Affects phase', {
          for (final p in ref.watch(projectPhasesProvider(widget.project.id)).value ?? const <ProjectPhase>[]) p.id: p.name,
        }, optional: true, noneLabel: 'No specific phase'),
        _select('status', 'Status', {
          'open': 'Open',
          'in-progress': 'In progress',
          'resolved': 'Resolved',
        }),
      ],
      if (widget.kind == 'documents') ...[
        _text('name', 'Document name'),
        _select('typeId', 'Document type', options(ConfigList.documentTypes)),
        ..._fileControls(photos: false),
      ],
      if (widget.kind == 'details') ...[
        _text('name', 'Project name'),
        _text('clientName', 'Client / owner'),
        _text('code', 'Project code', required: false),
        _text('city', 'City', required: false),
        _text('address', 'Site address', required: false, lines: 2),
        _select('typeId', 'Project type', options(ConfigList.projectTypes)),
        _date('startDate', 'Planned start'),
        _date('endDate', 'Target completion'),
        if (user.isAdmin) ...[
          MoneyFormField(
            label: 'Contract value',
            initialPaise: widget.project.contractValuePaise,
            onChanged: (value) => _values['contractValuePaise'] = value ?? 0,
          ),
          _select('managerId', 'Project manager', {
            for (final p in people.where(
              (p) => p.active && p.role.name == 'manager',
            ))
              p.uid: p.name,
          }, optional: true),
          const Text('Site supervisors'),
          for (final p in people.where(
            (p) => p.active && p.role.name == 'supervisor',
          ))
            CheckboxListTile(
              title: Text(p.name),
              contentPadding: EdgeInsets.zero,
              value: (_values['supervisorIds'] as List).contains(p.uid),
              onChanged: (checked) => setState(() {
                final ids = List<String>.from(_values['supervisorIds'] as List);
                checked == true ? ids.add(p.uid) : ids.remove(p.uid);
                _values['supervisorIds'] = ids;
              }),
            ),
        ],
        DynamicFields(
          fields: config.activeFieldsFor(FieldEntity.project),
          values: _custom,
          onChanged: (key, value) => setState(() => _custom[key] = value),
        ),
      ],
      if (widget.kind == 'status') ...[
        _select(
          'statusId',
          'Project status',
          options(ConfigList.projectStatuses),
        ),
        _text('reason', 'Reason / handover note', lines: 3),
        const Text(
          'Completed and cancelled projects are locked. Only the office can reopen them. On-hold periods pause the planned-progress clock.',
        ),
      ],
    ];
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text(switch (widget.kind) {
          'phases' => _id == null ? 'Add phase' : 'Update phase',
          'dprs' => _id == null ? 'Daily site report' : 'Edit daily report',
          'issues' => _id == null ? 'Raise an issue' : 'Update issue',
          'documents' => 'Upload document',
          'details' => 'Edit project',
          _ => 'Change project status',
        }),
        content: SizedBox(
          width: 540,
          child: SingleChildScrollView(
            child: Form(
              key: _form,
              child: AbsorbPointer(
                absorbing: _busy,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final field in fields)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: field,
                      ),
                    if (_error != null)
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    if (_busy) ...[
                      const LinearProgressIndicator(),
                      const SizedBox(height: 8),
                      Text(_saving),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  List<Widget> _fileControls({required bool photos}) => [
    Text(
      photos
          ? 'Site photos (up to 6, JPG / PNG / WebP, 10 MB each)'
          : 'PDF or image, up to 10 MB',
    ),
    for (final file in _files) Text(file.name),
    if ((_values['photoUrls'] as List?)?.isNotEmpty == true)
      Text('${(_values['photoUrls'] as List).length} existing photos retained'),
    OutlinedButton.icon(
      icon: const Icon(Icons.attach_file),
      label: Text(photos ? 'Choose photos' : 'Choose file'),
      onPressed: _uploaded.isNotEmpty
          ? null
          : () async {
              try {
                final picked = photos
                    ? await ProjectMedia.pickPhotos()
                    : [await ProjectMedia.pickDocument()]
                          .whereType<PlatformFile>()
                          .toList();
                if (!mounted) return;
                if (picked.length +
                        ((_values['photoUrls'] as List?)?.length ?? 0) >
                    6) {
                  throw StateError('Choose at most 6 photos.');
                }
                setState(() {
                  _files.clear();
                  _files.addAll(picked);
                });
              } catch (e) {
                if (mounted) setState(() => _error = '$e');
              }
            },
    ),
  ];

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final uid = ref.read(currentUserProvider).uid;
    final config = ref.read(appConfigProvider);
    try {
      if (widget.kind == 'phases') {
        if ((_values['weight'] as num) <= 0) {
          throw StateError('Phase weight must be greater than zero.');
        }
        if ((_values['plannedEnd'] as String).compareTo(
              _values['plannedStart'] as String,
            ) <=
            0) {
          throw StateError('Phase finish must be after its start.');
        }
      }
      if (widget.kind == 'details' &&
          (_values['endDate'] as String).compareTo(
                _values['startDate'] as String,
              ) <
              0) {
        throw StateError('Completion must be on or after the start.');
      }
      if (widget.kind == 'dprs') {
        final date = WorkDay.tryParse(_values['date'] as String)!;
        final today = WorkDay.tryParse(
          WorkDay.today(utcOffsetMinutes: config.company.utcOffsetMinutes),
        )!;
        if (date.isAfter(today) ||
            today.difference(date).inDays > config.company.dprBackdateDays) {
          throw StateError('Report date is outside the allowed window.');
        }
        if (_files.isEmpty &&
            ((_values['photoUrls'] as List?)?.isEmpty ?? true)) {
          throw StateError('Add at least one site photo.');
        }
        final target = _values['targetQuantity'] as num;
        final achieved = _values['achievedQuantity'] as num;
        if (achieved > target * 1.5 &&
            !await confirmAction(
              context,
              title: 'Above target',
              message: 'The reported quantity exceeds 150% of the target. Is this correct?',
              confirmLabel: 'Yes, save',
            )) {
          return;
        }
        _values['flaggedAboveTarget'] = achieved > target * 1.5;
        _values['submittedLate'] = date.isBefore(today);
        _values['submittedAt'] = FieldValue.serverTimestamp();
        _values['submittedBy'] = uid;
        _values['reportDay'] = Timestamp.fromDate(
          DateTime.utc(date.year, date.month, date.day),
        );
      }
      if (widget.kind == 'documents' && _files.isEmpty) {
        throw StateError('Choose a file.');
      }
      if (!mounted) return;
      setState(() {
        _busy = true;
        _error = null;
      });
      for (var i = _uploaded.length; i < _files.length; i++) {
        setState(() => _saving = 'Uploading ${i + 1} of ${_files.length}...');
        _uploaded.add(await ProjectMedia.upload(widget.project.id, _files[i]));
      }
      if (widget.kind == 'dprs') {
        _values['photoUrls'] = <dynamic>{
          ...?_values['photoUrls'] as List?,
          ..._uploaded,
        }.toList();
      }
      if (widget.kind == 'documents') _values['storagePath'] = _uploaded.single;
      if (widget.kind == 'details') {
        _values['custom'] = _custom;
        _values['nameLower'] = (_values['name'] as String).toLowerCase();
        if (ref.read(currentUserProvider).isAdmin) {
          _values['memberIds'] = Project.computeMemberIds(
            _values['managerId'] as String?,
            List<String>.from(_values['supervisorIds'] as List),
          );
        } else {
          for (final key in [
            'managerId',
            'memberIds',
            'supervisorIds',
            'contractValuePaise',
          ]) {
            _values.remove(key);
          }
        }
        await ref
            .read(projectRepositoryProvider)
            .saveDetails(widget.project, _values, uid);
      } else if (widget.kind == 'status') {
        await ref
            .read(projectRepositoryProvider)
            .setStatus(
              widget.project,
              _values['statusId'] as String,
              _values['reason'] as String,
              uid,
              config.company.utcOffsetMinutes,
            );
      } else {
        await ref
            .read(projectDetailRepositoryProvider)
            .save(
              widget.project.id,
              widget.kind,
              _values,
              uid: uid,
              id: widget.kind == 'dprs' ? _values['date'] as String : _id,
              expectedRevision: _revision,
            );
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
