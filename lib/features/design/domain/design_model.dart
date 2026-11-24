import '../../../core/data/json_read.dart';

enum DrawingCategory {
  architecture2D('2D Architectural Layout'),
  interior3D('3D Interior Render & View'),
  structural('Structural & Reinforcement Drawing'),
  electrical('Electrical & Lighting Scheme'),
  plumbing('Plumbing & Drainage Layout'),
  landscape('Landscape & Exterior Design');

  const DrawingCategory(this.label);
  final String label;

  static DrawingCategory fromName(String? name) =>
      DrawingCategory.values.firstWhere((c) => c.name == name, orElse: () => DrawingCategory.architecture2D);
}

enum DrawingStatus {
  draft('Draft', 'Work in progress by design team'),
  inReview('Internal Review', 'Design lead reviewing model/drawings'),
  clientReview('Client Review', 'Presented to client for feedback and sign-off'),
  revisionRequested('Revision Requested', 'Client asked for adjustments/changes'),
  clientApproved('Client Approved', 'Design finalized and approved by client'),
  gfc('Good For Construction (GFC)', 'Released to site team and supervisors for execution');

  const DrawingStatus(this.label, this.description);
  final String label;
  final String description;

  static DrawingStatus fromName(String? name) =>
      DrawingStatus.values.firstWhere((s) => s.name == name, orElse: () => DrawingStatus.draft);
}

class DrawingRevision {
  const DrawingRevision({
    required this.version,
    required this.fileUrl,
    required this.notes,
    required this.changedBy,
    this.changedAt,
  });

  final String version;
  final String fileUrl;
  final String notes;
  final String changedBy;
  final DateTime? changedAt;

  factory DrawingRevision.fromMap(Map<String, dynamic> m) => DrawingRevision(
        version: m.readString('version'),
        fileUrl: m.readString('fileUrl'),
        notes: m.readString('notes'),
        changedBy: m.readString('changedBy'),
        changedAt: m.readDateTime('changedAt'),
      );

  Map<String, dynamic> toMap() => {
        'version': version,
        'fileUrl': fileUrl,
        'notes': notes,
        'changedBy': changedBy,
        if (changedAt != null) 'changedAt': changedAt!.toIso8601String(),
      };
}

class DesignDrawing {
  const DesignDrawing({
    required this.id,
    required this.projectId,
    required this.title,
    required this.category,
    this.currentVersion = 'v1.0',
    this.status = DrawingStatus.draft,
    this.fileUrl = '',
    this.designerUid = '',
    this.designerName = '',
    this.notes = '',
    this.clientFeedback = '',
    this.revisions = const [],
    this.createdAt,
    this.updatedAt,
    this.revision = 1,
  });

  final String id;
  final String projectId;
  final String title;
  final DrawingCategory category;
  final String currentVersion;
  final DrawingStatus status;
  final String fileUrl;
  final String designerUid;
  final String designerName;
  final String notes;
  final String clientFeedback;
  final List<DrawingRevision> revisions;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final int revision;

  factory DesignDrawing.fromMap(String id, String projectId, Map<String, dynamic> m) {
    final rawRevs = m['revisions'];
    final revList = <DrawingRevision>[];
    if (rawRevs is List) {
      for (final item in rawRevs) {
        if (item is Map<String, dynamic>) {
          revList.add(DrawingRevision.fromMap(item));
        }
      }
    }

    return DesignDrawing(
      id: id,
      projectId: projectId,
      title: m.readString('title'),
      category: DrawingCategory.fromName(m.readStringOrNull('category')),
      currentVersion: m.readString('currentVersion', 'v1.0'),
      status: DrawingStatus.fromName(m.readStringOrNull('status')),
      fileUrl: m.readString('fileUrl'),
      designerUid: m.readString('designerUid'),
      designerName: m.readString('designerName'),
      notes: m.readString('notes'),
      clientFeedback: m.readString('clientFeedback'),
      revisions: revList,
      createdAt: m.readDateTime('createdAt'),
      updatedAt: m.readDateTime('updatedAt'),
      revision: m.readInt('revision', 1),
    );
  }

  Map<String, dynamic> toMap() => {
        'title': title,
        'category': category.name,
        'currentVersion': currentVersion,
        'status': status.name,
        'fileUrl': fileUrl,
        'designerUid': designerUid,
        'designerName': designerName,
        'notes': notes,
        'clientFeedback': clientFeedback,
        'revisions': revisions.map((r) => r.toMap()).toList(),
        'revision': revision,
      };
}
