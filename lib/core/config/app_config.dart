import '../data/json_read.dart';
import 'config_models.dart';
import 'default_config.dart';

/// Everything under config/, read once and shared by the whole app.
///
/// Built from the raw documents so missing docs fall back to defaults and
/// unknown keys are ignored.
class AppConfig {
  const AppConfig({
    required this.company,
    required this.lists,
    required this.phaseTemplates,
    required this.fields,
    required this.revisions,
  });

  final CompanySettings company;
  final Map<ConfigList, List<ConfigItem>> lists;
  final List<PhaseTemplate> phaseTemplates;
  final Map<FieldEntity, List<FieldDef>> fields;

  /// Document revision per config doc id, used to catch two admins editing
  /// the same list at once.
  final Map<String, int> revisions;

  static const AppConfig defaults = AppConfig(
    company: CompanySettings(name: 'My company'),
    lists: {},
    phaseTemplates: DefaultConfig.phaseTemplates,
    fields: {},
    revisions: {},
  );

  factory AppConfig.fromDocs(Map<String, Map<String, dynamic>> docs) {
    final lists = <ConfigList, List<ConfigItem>>{};
    for (final l in ConfigList.values) {
      final doc = docs[l.docId];
      lists[l] = doc == null
          ? DefaultConfig.list(l)
          : doc.readMapList('items').map(ConfigItem.fromMap).where((i) => i.id.isNotEmpty).toList();
    }

    final fields = <FieldEntity, List<FieldDef>>{};
    for (final e in FieldEntity.values) {
      fields[e] = (docs[e.docId]?.readMapList('items') ?? const [])
          .map(FieldDef.fromMap)
          .where((f) => f.id.isNotEmpty)
          .toList();
    }

    final templatesDoc = docs['phaseTemplates'];
    return AppConfig(
      company: CompanySettings.fromMap(docs['company'] ?? const {}),
      lists: lists,
      phaseTemplates: templatesDoc == null
          ? DefaultConfig.phaseTemplates
          : templatesDoc.readMapList('items').map(PhaseTemplate.fromMap).toList(),
      fields: fields,
      revisions: {for (final e in docs.entries) e.key: e.value.readInt('rev')},
    );
  }

  /// All items, including archived ones (for showing old records).
  List<ConfigItem> allOf(ConfigList l) => lists[l] ?? DefaultConfig.list(l);

  /// Items that can be picked for new records.
  List<ConfigItem> activeOf(ConfigList l) => allOf(l).where((i) => !i.archived).toList();

  /// Label for a stored id. Falls back to the id itself so nothing shows blank.
  String labelOf(ConfigList l, String? id) {
    if (id == null || id.isEmpty) return '—';
    return allOf(l).where((i) => i.id == id).firstOrNull?.label ?? id;
  }

  ProjectStage stageOfStatus(String? statusId) =>
      allOf(ConfigList.projectStatuses).where((i) => i.id == statusId).firstOrNull?.stage ??
      ProjectStage.pipeline;

  List<FieldDef> fieldsFor(FieldEntity e) => fields[e] ?? const [];

  List<FieldDef> activeFieldsFor(FieldEntity e) => fieldsFor(e).where((f) => !f.archived).toList();
}
