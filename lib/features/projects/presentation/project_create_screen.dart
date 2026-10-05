import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/config_models.dart';
import '../../../core/config/config_repository.dart';
import '../../../core/dynamic_form/dynamic_fields.dart';
import '../../../core/widgets/common.dart';
import '../../auth/data/auth_errors.dart';
import '../../auth/data/session.dart';
import '../../auth/domain/app_user.dart';
import '../../users/data/user_repository.dart';
import '../data/project_repository.dart';
import '../domain/project.dart';
import 'ceo_ui.dart';

class ProjectCreateScreen extends ConsumerStatefulWidget {
  const ProjectCreateScreen({super.key});

  @override
  ConsumerState<ProjectCreateScreen> createState() =>
      _ProjectCreateScreenState();
}

class _ProjectCreateScreenState extends ConsumerState<ProjectCreateScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _code = TextEditingController();
  final _client = TextEditingController();
  final _city = TextEditingController();
  final _address = TextEditingController();
  String? _typeId;
  String? _statusId;
  String? _managerId;
  String? _templateId;
  String? _startDate;
  String? _endDate;
  int? _contractValuePaise;
  final _supervisorIds = <String>{};
  final _customValues = <String, dynamic>{};
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _client.dispose();
    _city.dispose();
    _address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(appConfigProvider);
    final people = ref.watch(allUsersProvider).value ?? const <AppUser>[];
    final managers = people
        .where((person) => person.active && person.role == UserRole.manager)
        .toList();
    final supervisors = people
        .where((person) => person.active && person.role == UserRole.supervisor)
        .toList();
    final types = config.activeOf(ConfigList.projectTypes);
    final statuses = config.activeOf(ConfigList.projectStatuses);
    final templates = config.phaseTemplates
        .where((template) => !template.archived)
        .toList();
    final typeId = types.any((item) => item.id == _typeId)
        ? _typeId
        : types.firstOrNull?.id;
    final statusId = statuses.any((item) => item.id == _statusId)
        ? _statusId!
        : statuses.where((item) => item.id == 'enquiry').firstOrNull?.id ??
              statuses.firstOrNull?.id ??
              'enquiry';
    final managerId = managers.any((person) => person.uid == _managerId)
        ? _managerId
        : null;
    final template = templates
        .where((item) => item.id == _templateId)
        .firstOrNull;
    final ongoing = config.stageOfStatus(statusId) == ProjectStage.ongoing;

    return PageScaffold(
      title: 'New project',
      maxWidth: 920,
      actions: [
        IconButton(
          tooltip: 'Cancel',
          onPressed: () => context.go('/projects'),
          icon: const Icon(Icons.close),
        ),
      ],
      body: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Create a project',
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 5),
            Text(
              'Enter the core details, then assign its delivery team and starting phases.',
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: AppColors.muted),
            ),
            const SizedBox(height: 20),
            SectionCard(
              title: 'Project details',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Project name *',
                    ),
                    validator: (value) => (value ?? '').trim().isEmpty
                        ? 'Enter a project name'
                        : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _code,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Project code',
                      helperText: 'Optional internal reference',
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _client,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Client / owner *',
                    ),
                    validator: (value) => (value ?? '').trim().isEmpty
                        ? 'Enter the client or owner name'
                        : null,
                  ),
                  if (types.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      initialValue: typeId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Project type *',
                      ),
                      items: [
                        for (final item in types)
                          DropdownMenuItem(
                            value: item.id,
                            child: Text(item.label),
                          ),
                      ],
                      onChanged: (value) => setState(() => _typeId = value),
                      validator: (value) =>
                          value == null ? 'Select a project type' : null,
                    ),
                  ],
                  const SizedBox(height: 14),
                  if (statuses.isEmpty)
                    const Text(
                      'Add an active project status in Settings before creating projects.',
                    )
                  else
                    DropdownButtonFormField<String>(
                      initialValue: statusId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Project status',
                      ),
                      items: [
                        for (final item in statuses)
                          DropdownMenuItem(
                            value: item.id,
                            child: Text(item.label),
                          ),
                      ],
                      onChanged: (value) => setState(() => _statusId = value),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SectionCard(
              title: 'Site & commercial',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _city,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'City'),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _address,
                    textCapitalization: TextCapitalization.sentences,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Site address',
                    ),
                  ),
                  const SizedBox(height: 14),
                  MoneyFormField(
                    label: 'Contract value',
                    helperText: 'Leave blank if not confirmed yet',
                    initialPaise: _contractValuePaise,
                    onChanged: (value) => _contractValuePaise = value,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SectionCard(
              title: 'Schedule & team',
              subtitle: ongoing
                  ? 'Required when a project is marked ongoing.'
                  : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DateFormField(
                    label: ongoing ? 'Planned start *' : 'Planned start',
                    initialKey: _startDate,
                    onChanged: (value) => _startDate = value,
                    validator: (value) => ongoing && value == null
                        ? 'Choose a planned start date'
                        : null,
                  ),
                  const SizedBox(height: 14),
                  DateFormField(
                    label: ongoing
                        ? 'Target completion *'
                        : 'Target completion',
                    initialKey: _endDate,
                    onChanged: (value) => _endDate = value,
                    validator: (value) => ongoing && value == null
                        ? 'Choose a target completion date'
                        : null,
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String?>(
                    initialValue: managerId,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: ongoing
                          ? 'Project manager *'
                          : 'Project manager',
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Unassigned'),
                      ),
                      for (final person in managers)
                        DropdownMenuItem<String?>(
                          value: person.uid,
                          child: Text(
                            person.name.isEmpty ? person.email : person.name,
                          ),
                        ),
                    ],
                    onChanged: (value) => setState(() => _managerId = value),
                    validator: (value) => ongoing && value == null
                        ? 'Assign a project manager'
                        : null,
                  ),
                  if (supervisors.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text(
                      'Site supervisors',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final person in supervisors)
                          FilterChip(
                            label: Text(
                              person.name.isEmpty ? person.email : person.name,
                            ),
                            selected: _supervisorIds.contains(person.uid),
                            onSelected: (selected) => setState(() {
                              selected
                                  ? _supervisorIds.add(person.uid)
                                  : _supervisorIds.remove(person.uid);
                            }),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            SectionCard(
              title: 'Starting phases',
              subtitle: 'Choose a template to seed this project with its standard phases.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<String?>(
                    initialValue: template?.id,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Phase template',
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('No template'),
                      ),
                      for (final item in templates)
                        DropdownMenuItem<String?>(
                          value: item.id,
                          child: Text(item.name),
                        ),
                    ],
                    onChanged: (value) => setState(() => _templateId = value),
                  ),
                  if (template != null) ...[
                    const SizedBox(height: 10),
                    for (var index = 0; index < template.phases.length; index++)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          radius: 14,
                          child: Text('${index + 1}'),
                        ),
                        title: Text(template.phases[index].name),
                        trailing: Text('${template.phases[index].weight}%'),
                      ),
                  ],
                ],
              ),
            ),
            if (config.activeFieldsFor(FieldEntity.project).isNotEmpty) ...[
              const SizedBox(height: 14),
              SectionCard(
                title: 'Additional details',
                child: DynamicFields(
                  fields: config.activeFieldsFor(FieldEntity.project),
                  values: _customValues,
                  onChanged: (id, value) =>
                      setState(() => _customValues[id] = value),
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 14),
              MessageView(
                icon: Icons.error_outline,
                title: 'Couldn’t create project',
                message: _error,
              ),
            ],
            const SizedBox(height: 18),
            Align(
              alignment: Alignment.centerLeft,
              child: NeoActionButton(
                label: _saving ? 'Saving...' : 'Create project',
                icon: Icons.add,
                onPressed: _saving ? null : _save,
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    final config = ref.read(appConfigProvider);
    final statuses = config.activeOf(ConfigList.projectStatuses);
    final statusId = statuses.any((item) => item.id == _statusId)
        ? _statusId!
        : statuses.where((item) => item.id == 'enquiry').firstOrNull?.id ??
              statuses.firstOrNull?.id ??
              'enquiry';
    if (_startDate != null &&
        _endDate != null &&
        _endDate!.compareTo(_startDate!) < 0) {
      setState(
        () => _error =
            'Target completion must be on or after the planned start date.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final user = ref.read(currentUserProvider);
    final types = config.activeOf(ConfigList.projectTypes);
    final typeId = types.any((item) => item.id == _typeId)
        ? _typeId
        : types.firstOrNull?.id;
    final template = config.phaseTemplates
        .where((item) => !item.archived && item.id == _templateId)
        .firstOrNull;
    try {
      final projectId = await ref
          .read(projectRepositoryProvider)
          .create(
            Project(
              id: '',
              name: _name.text.trim(),
              code: _code.text.trim(),
              clientName: _client.text.trim(),
              city: _city.text.trim(),
              address: _address.text.trim(),
              typeId: typeId,
              statusId: statusId,
              contractValuePaise: _contractValuePaise ?? 0,
              startDate: _startDate,
              endDate: _endDate,
              managerId: _managerId,
              supervisorIds: _supervisorIds.toList(),
              custom: Map.of(_customValues),
            ),
            uid: user.uid,
            phaseTemplate: template,
            stage: config.stageOfStatus(statusId),
            statusIndex: config
                .allOf(ConfigList.projectStatuses)
                .indexWhere((s) => s.id == statusId),
          );
      if (mounted) context.go('/projects/$projectId');
    } catch (error) {
      if (mounted) setState(() => _error = friendlyError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
