import '../data/json_read.dart';

/// The fixed stages the CEO dashboard groups projects by. Client-defined
/// statuses (e.g. "Tender submitted") each map onto one of these.
enum ProjectStage {
  pipeline('Pipeline'),
  ongoing('Ongoing'),
  onHold('On hold'),
  completed('Completed'),
  cancelled('Cancelled');

  const ProjectStage(this.label);
  final String label;

  static ProjectStage fromName(String? name) =>
      ProjectStage.values.firstWhere((s) => s.name == name, orElse: () => ProjectStage.pipeline);
}

/// One entry in an editable list (project types, expense categories, ...).
///
/// [id] never changes. [label] can be renamed. Items are archived, never
/// deleted, so old records that point at them still show a proper name.
class ConfigItem {
  const ConfigItem({
    required this.id,
    required this.label,
    this.archived = false,
    this.stage,
    this.extra = const {},
  });

  final String id;
  final String label;
  final bool archived;

  /// Only used by project statuses.
  final ProjectStage? stage;

  /// Unknown keys are kept so newer app versions don't lose data.
  final Map<String, dynamic> extra;

  factory ConfigItem.fromMap(Map<String, dynamic> m) {
    final stageName = m.readStringOrNull('stage');
    return ConfigItem(
      id: m.readString('id'),
      label: m.readString('label', m.readString('id')),
      archived: m.readBool('archived'),
      stage: stageName == null ? null : ProjectStage.fromName(stageName),
      extra: Map.of(m)..removeWhere((k, _) => const {'id', 'label', 'archived', 'stage'}.contains(k)),
    );
  }

  Map<String, dynamic> toMap() => {
        ...extra,
        'id': id,
        'label': label,
        'archived': archived,
        'stage': ?stage?.name,
      };

  ConfigItem copyWith({String? label, bool? archived, ProjectStage? stage}) => ConfigItem(
        id: id,
        label: label ?? this.label,
        archived: archived ?? this.archived,
        stage: stage ?? this.stage,
        extra: extra,
      );
}

/// The kinds of custom field an admin can add without a code change.
enum FieldType {
  text('Short text'),
  longText('Long text'),
  number('Number'),
  money('Amount (₹)'),
  date('Date'),
  select('Pick one'),
  multiSelect('Pick many'),
  toggle('Yes / No'),
  phone('Phone number');

  const FieldType(this.label);
  final String label;

  bool get hasOptions => this == select || this == multiSelect;

  static FieldType fromName(String? name) =>
      FieldType.values.firstWhere((t) => t.name == name, orElse: () => FieldType.text);
}

/// Definition of one custom field. Values are stored under
/// `custom.{id}` on the record.
///
/// [id] and [type] are fixed once saved, because stored values depend on them.
class FieldDef {
  const FieldDef({
    required this.id,
    required this.label,
    required this.type,
    this.required = false,
    this.archived = false,
    this.help = '',
    this.showOnCard = false,
    this.options = const [],
  });

  final String id;
  final String label;
  final FieldType type;
  final bool required;
  final bool archived;
  final String help;
  final bool showOnCard;
  final List<ConfigItem> options;

  List<ConfigItem> get activeOptions => options.where((o) => !o.archived).toList();

  factory FieldDef.fromMap(Map<String, dynamic> m) => FieldDef(
        id: m.readString('id'),
        label: m.readString('label', m.readString('id')),
        type: FieldType.fromName(m.readStringOrNull('type')),
        required: m.readBool('required'),
        archived: m.readBool('archived'),
        help: m.readString('help'),
        showOnCard: m.readBool('showOnCard'),
        options: m.readMapList('options').map(ConfigItem.fromMap).toList(),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'label': label,
        'type': type.name,
        'required': required,
        'archived': archived,
        'help': help,
        'showOnCard': showOnCard,
        if (type.hasOptions) 'options': options.map((o) => o.toMap()).toList(),
      };

  FieldDef copyWith({
    String? label,
    bool? required,
    bool? archived,
    String? help,
    bool? showOnCard,
    List<ConfigItem>? options,
  }) =>
      FieldDef(
        id: id,
        label: label ?? this.label,
        type: type,
        required: required ?? this.required,
        archived: archived ?? this.archived,
        help: help ?? this.help,
        showOnCard: showOnCard ?? this.showOnCard,
        options: options ?? this.options,
      );
}

class PhaseTemplatePhase {
  const PhaseTemplatePhase({required this.id, required this.name, required this.weight});

  final String id;
  final String name;

  /// Share of the whole project, used for % complete. Weights are normalised
  /// when used, so they don't have to add up to exactly 100.
  final int weight;

  factory PhaseTemplatePhase.fromMap(Map<String, dynamic> m) => PhaseTemplatePhase(
        id: m.readString('id'),
        name: m.readString('name'),
        weight: m.readInt('weight', 1).clamp(0, 1000),
      );

  Map<String, dynamic> toMap() => {'id': id, 'name': name, 'weight': weight};
}

class PhaseTemplate {
  const PhaseTemplate({
    required this.id,
    required this.name,
    required this.phases,
    this.archived = false,
  });

  final String id;
  final String name;
  final List<PhaseTemplatePhase> phases;
  final bool archived;

  int get totalWeight => phases.fold(0, (sum, p) => sum + p.weight);

  factory PhaseTemplate.fromMap(Map<String, dynamic> m) => PhaseTemplate(
        id: m.readString('id'),
        name: m.readString('name'),
        archived: m.readBool('archived'),
        phases: m.readMapList('phases').map(PhaseTemplatePhase.fromMap).toList(),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'archived': archived,
        'phases': phases.map((p) => p.toMap()).toList(),
      };
}

class CompanySettings {
  const CompanySettings({
    required this.name,
    this.utcOffsetMinutes = 330,
    this.currency = 'INR',
    this.approvalThresholdPaise = 5000000, // ₹50,000
    this.dprBackdateDays = 7,
    this.financeLockedUntil,
  });

  final String name;
  final int utcOffsetMinutes;
  final String currency;

  /// Expenses above this need the CEO's approval (Phase 3).
  final int approvalThresholdPaise;

  /// How many days late a daily report may still be entered.
  final int dprBackdateDays;

  /// Expenses dated on or before this working day need an admin override
  /// (the month has been closed for accounting).
  final String? financeLockedUntil;

  factory CompanySettings.fromMap(Map<String, dynamic> m) => CompanySettings(
        name: m.readString('name', 'My company'),
        utcOffsetMinutes: m.readInt('utcOffsetMinutes', 330),
        currency: m.readString('currency', 'INR'),
        approvalThresholdPaise: m.readInt('approvalThresholdPaise', 5000000),
        dprBackdateDays: m.readInt('dprBackdateDays', 7),
        financeLockedUntil: m.readStringOrNull('financeLockedUntil'),
      );

  Map<String, dynamic> toMap() => {
        'name': name,
        'utcOffsetMinutes': utcOffsetMinutes,
        'currency': currency,
        'approvalThresholdPaise': approvalThresholdPaise,
        'dprBackdateDays': dprBackdateDays,
        'financeLockedUntil': financeLockedUntil,
      };
}

/// Editable lists, one Firestore document each under config/.
enum ConfigList {
  projectStatuses('Project stages', 'The steps a project goes through, from enquiry to handover.'),
  projectTypes('Project types', 'Residential, commercial, and so on.'),
  expenseCategories('Expense categories', 'Budget and expense heads for every project.'),
  issuePriorities('Issue priorities', 'How urgent a site problem is.'),
  documentTypes('Document types', 'Drawings, approvals, contracts and other files.');

  const ConfigList(this.title, this.description);
  final String title;
  final String description;

  String get docId => name;

  static ConfigList? fromName(String? name) =>
      ConfigList.values.where((l) => l.name == name).firstOrNull;
}

/// Records that can carry custom fields.
enum FieldEntity {
  project('Projects'),
  expense('Expenses'),
  issue('Issues'),
  worker('Workers');

  const FieldEntity(this.title);
  final String title;

  String get docId => 'fields_$name';

  static FieldEntity? fromName(String? name) =>
      FieldEntity.values.where((e) => e.name == name).firstOrNull;
}
