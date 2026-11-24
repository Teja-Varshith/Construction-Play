import '../../../core/data/json_read.dart';

enum BusinessVertical {
  architectureInterior('Architecture & Interior Design', 'Bespoke designs, 2D/3D layouts and fit-outs'),
  constructionTurnkey('Construction & Turnkey', 'End-to-end civil construction, residential & commercial'),
  realEstateVenture('Real Estate & Venture Development', 'Plotted layouts, gated communities & ventures');

  const BusinessVertical(this.label, this.description);
  final String label;
  final String description;

  static BusinessVertical fromName(String? name) =>
      BusinessVertical.values.firstWhere((v) => v.name == name, orElse: () => BusinessVertical.constructionTurnkey);
}

enum LeadStage {
  enquiry('Enquiry', 'Fresh customer enquiry received'),
  leadQualification('Lead Management', 'Initial screening and requirements gathered'),
  followUp('Follow-up / Meeting', 'Customer discussion in progress'),
  siteVisit('Site Visit', 'Site inspection and field assessment done'),
  estimation('Design & Estimation', 'Design concept and BOQ costing prepared'),
  quotation('Quotation Submitted', 'Formal quotation sent for client approval'),
  agreement('Agreement & Advance', 'Contract drafted, advance payment pending'),
  confirmed('Project Confirmed', 'Converted to project and handed to planning'),
  lost('Lost Enquiry', 'Client opted out or went elsewhere');

  const LeadStage(this.label, this.description);
  final String label;
  final String description;

  static LeadStage fromName(String? name) =>
      LeadStage.values.firstWhere((s) => s.name == name, orElse: () => LeadStage.enquiry);

  bool get isWon => this == LeadStage.confirmed;
  bool get isLost => this == LeadStage.lost;
  bool get isActive => !isWon && !isLost;
}

class LeadFollowUp {
  const LeadFollowUp({
    required this.id,
    required this.scheduledDate,
    required this.notes,
    required this.done,
    this.completedDate,
    this.recordedByName = '',
  });

  final String id;
  final String scheduledDate; // YYYY-MM-DD
  final String notes;
  final bool done;
  final String? completedDate;
  final String recordedByName;

  factory LeadFollowUp.fromMap(Map<String, dynamic> m) => LeadFollowUp(
        id: m.readString('id'),
        scheduledDate: m.readString('scheduledDate'),
        notes: m.readString('notes'),
        done: m.readBool('done'),
        completedDate: m.readStringOrNull('completedDate'),
        recordedByName: m.readString('recordedByName'),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'scheduledDate': scheduledDate,
        'notes': notes,
        'done': done,
        if (completedDate != null) 'completedDate': completedDate,
        'recordedByName': recordedByName,
      };
}

class Lead {
  const Lead({
    required this.id,
    required this.clientName,
    required this.phone,
    this.email = '',
    required this.vertical,
    required this.stage,
    this.estimatedValuePaise = 0,
    this.quotationValuePaise = 0,
    this.assignedToUid = '',
    this.assignedToName = '',
    this.requirementDetails = '',
    this.siteLocation = '',
    this.lostReason = '',
    this.followUps = const [],
    this.convertedProjectId,
    this.deleted = false,
    this.createdAt,
    this.updatedAt,
    this.createdBy = '',
    this.updatedBy = '',
    this.revision = 1,
  });

  final String id;
  final String clientName;
  final String phone;
  final String email;
  final BusinessVertical vertical;
  final LeadStage stage;
  final int estimatedValuePaise;
  final int quotationValuePaise;
  final String assignedToUid;
  final String assignedToName;
  final String requirementDetails;
  final String siteLocation;
  final String lostReason;
  final List<LeadFollowUp> followUps;
  final String? convertedProjectId;
  final bool deleted;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String createdBy;
  final String updatedBy;
  final int revision;

  int get pendingFollowUpsCount => followUps.where((f) => !f.done).length;

  factory Lead.fromMap(String id, Map<String, dynamic> m) {
    final rawFollowUps = m['followUps'];
    final followUpsList = <LeadFollowUp>[];
    if (rawFollowUps is List) {
      for (final item in rawFollowUps) {
        if (item is Map<String, dynamic>) {
          followUpsList.add(LeadFollowUp.fromMap(item));
        }
      }
    }

    return Lead(
      id: id,
      clientName: m.readString('clientName'),
      phone: m.readString('phone'),
      email: m.readString('email'),
      vertical: BusinessVertical.fromName(m.readStringOrNull('vertical')),
      stage: LeadStage.fromName(m.readStringOrNull('stage')),
      estimatedValuePaise: m.readInt('estimatedValuePaise'),
      quotationValuePaise: m.readInt('quotationValuePaise'),
      assignedToUid: m.readString('assignedToUid'),
      assignedToName: m.readString('assignedToName'),
      requirementDetails: m.readString('requirementDetails'),
      siteLocation: m.readString('siteLocation'),
      lostReason: m.readString('lostReason'),
      followUps: followUpsList,
      convertedProjectId: m.readStringOrNull('convertedProjectId'),
      deleted: m.readBool('deleted'),
      createdAt: m.readDateTime('createdAt'),
      updatedAt: m.readDateTime('updatedAt'),
      createdBy: m.readString('createdBy'),
      updatedBy: m.readString('updatedBy'),
      revision: m.readInt('revision', 1),
    );
  }

  Map<String, dynamic> toMap() => {
        'clientName': clientName,
        'phone': phone,
        'email': email,
        'vertical': vertical.name,
        'stage': stage.name,
        'estimatedValuePaise': estimatedValuePaise,
        'quotationValuePaise': quotationValuePaise,
        'assignedToUid': assignedToUid,
        'assignedToName': assignedToName,
        'requirementDetails': requirementDetails,
        'siteLocation': siteLocation,
        'lostReason': lostReason,
        'followUps': followUps.map((f) => f.toMap()).toList(),
        'convertedProjectId': convertedProjectId,
        'deleted': deleted,
        'revision': revision,
      };
}
