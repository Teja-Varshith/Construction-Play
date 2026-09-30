import 'config_models.dart';

/// Starting configuration for a construction company. Written to Firestore
/// during first-run setup and used as a fallback while config is loading.
class DefaultConfig {
  DefaultConfig._();

  static const projectStatuses = [
    ConfigItem(id: 'enquiry', label: 'Enquiry', stage: ProjectStage.pipeline),
    ConfigItem(id: 'tender', label: 'Tender / Quotation', stage: ProjectStage.pipeline),
    ConfigItem(id: 'negotiation', label: 'Negotiation', stage: ProjectStage.pipeline),
    ConfigItem(id: 'ongoing', label: 'Ongoing', stage: ProjectStage.ongoing),
    ConfigItem(id: 'on-hold', label: 'On hold', stage: ProjectStage.onHold),
    ConfigItem(id: 'completed', label: 'Completed', stage: ProjectStage.completed),
    ConfigItem(id: 'cancelled', label: 'Cancelled', stage: ProjectStage.cancelled),
  ];

  static const projectTypes = [
    ConfigItem(id: 'residential', label: 'Residential'),
    ConfigItem(id: 'commercial', label: 'Commercial'),
    ConfigItem(id: 'industrial', label: 'Industrial'),
    ConfigItem(id: 'infrastructure', label: 'Infrastructure'),
    ConfigItem(id: 'interior', label: 'Interior / Renovation'),
  ];

  static const expenseCategories = [
    ConfigItem(id: 'labour', label: 'Labour'),
    ConfigItem(id: 'material', label: 'Material'),
    ConfigItem(id: 'equipment', label: 'Equipment'),
    ConfigItem(id: 'subcontract', label: 'Subcontract'),
    ConfigItem(id: 'overheads', label: 'Overheads'),
    ConfigItem(id: 'other', label: 'Other'),
  ];

  static const issuePriorities = [
    ConfigItem(id: 'low', label: 'Low'),
    ConfigItem(id: 'medium', label: 'Medium'),
    ConfigItem(id: 'high', label: 'High'),
    ConfigItem(id: 'critical', label: 'Critical'),
  ];

  static const documentTypes = [
    ConfigItem(id: 'drawing', label: 'Drawing'),
    ConfigItem(id: 'approval', label: 'Approval / Permit'),
    ConfigItem(id: 'contract', label: 'Contract'),
    ConfigItem(id: 'invoice', label: 'Invoice / Bill'),
    ConfigItem(id: 'other', label: 'Other'),
  ];

  static const phaseTemplates = [
    PhaseTemplate(id: 'standard-building', name: 'Standard building', phases: [
      PhaseTemplatePhase(id: 'site-prep', name: 'Site preparation', weight: 5),
      PhaseTemplatePhase(id: 'foundation', name: 'Foundation', weight: 15),
      PhaseTemplatePhase(id: 'structure', name: 'Structure', weight: 30),
      PhaseTemplatePhase(id: 'masonry', name: 'Masonry', weight: 15),
      PhaseTemplatePhase(id: 'mep', name: 'MEP (electrical, plumbing)', weight: 15),
      PhaseTemplatePhase(id: 'finishing', name: 'Finishing', weight: 15),
      PhaseTemplatePhase(id: 'handover', name: 'Handover', weight: 5),
    ]),
  ];

  static List<ConfigItem> list(ConfigList l) => switch (l) {
        ConfigList.projectStatuses => projectStatuses,
        ConfigList.projectTypes => projectTypes,
        ConfigList.expenseCategories => expenseCategories,
        ConfigList.issuePriorities => issuePriorities,
        ConfigList.documentTypes => documentTypes,
      };
}
