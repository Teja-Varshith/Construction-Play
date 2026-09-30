import '../../../core/data/json_read.dart';
import '../../../core/utils/work_day.dart';

/// A schedule phase within a project. The same records will later be edited by
/// office and site teams; the CEO uses them here as a read-only timeline.
class ProjectPhase {
  const ProjectPhase({
    required this.id,
    required this.name,
    this.order = 0,
    this.weight = 0,
    this.plannedStart,
    this.plannedEnd,
    this.actualPct = 0,
    this.ownerId,
    this.budgetPaise = 0,
    this.delayReason = '',
    this.deleted = false,
    this.revision = 0,
  });

  final String id;
  final String name;
  final int order;
  final double weight;
  final String? plannedStart;
  final String? plannedEnd;
  final double actualPct;
  final String? ownerId;

  /// Money set aside for this phase. 0 means no phase budget.
  final int budgetPaise;

  /// Why the phase is late, in the manager's words. Shown to the CEO.
  final String delayReason;
  final bool deleted;
  final int revision;

  bool get hasValidDates {
    final start = WorkDay.tryParse(plannedStart);
    final end = WorkDay.tryParse(plannedEnd);
    return start != null && end != null && end.isAfter(start);
  }

  factory ProjectPhase.fromMap(
    String id,
    Map<String, dynamic> map,
  ) => ProjectPhase(
    id: id,
    name: map.readString('name', 'Untitled phase'),
    order: map.readInt('order'),
    weight: (map.readNumOrNull('weight') ?? 0).toDouble(),
    plannedStart:
        map.readStringOrNull('plannedStart') ??
        map.readStringOrNull('startDate'),
    plannedEnd:
        map.readStringOrNull('plannedEnd') ?? map.readStringOrNull('endDate'),
    actualPct: (map.readNumOrNull('actualPct') ?? map.readNumOrNull('pct') ?? 0)
        .toDouble()
        .clamp(0, 100),
    ownerId: map.readStringOrNull('ownerId'),
    budgetPaise: map.readInt('budgetPaise'),
    delayReason: map.readString('delayReason'),
    deleted: map.readBool('deleted'),
    revision: map.readInt('revision'),
  );
}

/// One daily progress report. Quantities are deliberately [num] because each
/// site chooses its own units (m³, bags, floors, tasks, ...).
class DailyProgressReport {
  const DailyProgressReport({
    required this.id,
    required this.date,
    this.targetQuantity,
    this.achievedQuantity,
    this.unit = '',
    this.notes = '',
    this.photoUrls = const [],
    this.submittedAt,
    this.submittedBy,
    this.deleted = false,
    this.revision = 0,
    this.flaggedAboveTarget = false,
    this.submittedLate = false,
  });

  final String id;
  final String date;
  final num? targetQuantity;
  final num? achievedQuantity;
  final String unit;
  final String notes;
  final List<String> photoUrls;
  final DateTime? submittedAt;
  final String? submittedBy;
  final bool deleted;
  final int revision;

  /// Achieved quantity was over 150% of target; entered and confirmed, but
  /// flagged for review.
  final bool flaggedAboveTarget;

  /// Recorded for an earlier working day than it was submitted on.
  final bool submittedLate;

  double? get achievedPercent {
    if (targetQuantity == null ||
        targetQuantity == 0 ||
        achievedQuantity == null) {
      return null;
    }
    return achievedQuantity! / targetQuantity! * 100;
  }

  factory DailyProgressReport.fromMap(String id, Map<String, dynamic> map) =>
      DailyProgressReport(
        id: id,
        date: map.readString('date'),
        targetQuantity:
            map.readNumOrNull('targetQuantity') ??
            map.readNumOrNull('targetQty'),
        achievedQuantity:
            map.readNumOrNull('achievedQuantity') ??
            map.readNumOrNull('achievedQty'),
        unit: map.readString('unit'),
        notes: map.readString('notes') == ''
            ? map.readString('note')
            : map.readString('notes'),
        photoUrls: <String>{
          ...map.readStringList('photoUrls'),
          ...map.readStringList('photos'),
        }.toList(),
        submittedAt: map.readDateTime('submittedAt'),
        submittedBy: map.readStringOrNull('submittedBy'),
        deleted: map.readBool('deleted'),
        revision: map.readInt('revision'),
        flaggedAboveTarget: map.readBool('flaggedAboveTarget'),
        submittedLate: map.readBool('submittedLate'),
      );
}

class ProjectIssue {
  const ProjectIssue({
    required this.id,
    required this.title,
    this.description = '',
    this.priorityId = 'medium',
    this.status = 'open',
    this.reportedAt,
    this.assigneeId,
    this.phaseId,
    this.photoUrls = const [],
    this.deleted = false,
    this.revision = 0,
  });

  final String id;
  final String title;

  /// The schedule phase the issue affects, if any.
  final String? phaseId;
  final String description;
  final String priorityId;
  final String status;
  final DateTime? reportedAt;
  final String? assigneeId;
  final List<String> photoUrls;
  final bool deleted;
  final int revision;

  bool get isOpen => status != 'closed' && status != 'resolved';

  factory ProjectIssue.fromMap(String id, Map<String, dynamic> map) =>
      ProjectIssue(
        id: id,
        title: map.readString('title', 'Untitled issue'),
        description: map.readString('description'),
        priorityId: map.readString('priorityId', 'medium'),
        status: map.readString('status', 'open'),
        reportedAt:
            map.readDateTime('reportedAt') ?? map.readDateTime('createdAt'),
        assigneeId: map.readStringOrNull('assigneeId'),
        phaseId: map.readStringOrNull('phaseId'),
        photoUrls: <String>{
          ...map.readStringList('photoUrls'),
          ...map.readStringList('photos'),
        }.toList(),
        deleted: map.readBool('deleted'),
        revision: map.readInt('revision'),
      );
}

class ProjectDocument {
  const ProjectDocument({
    required this.id,
    required this.name,
    this.typeId = 'other',
    this.url,
    this.createdAt,
    this.deleted = false,
    this.revision = 0,
    this.storagePath,
  });

  final String id;
  final String name;
  final String typeId;
  final String? url;
  final DateTime? createdAt;
  final bool deleted;
  final int revision;
  final String? storagePath;

  factory ProjectDocument.fromMap(String id, Map<String, dynamic> map) =>
      ProjectDocument(
        id: id,
        name: map.readString(
          'name',
          map.readString('fileName', 'Untitled document'),
        ),
        typeId: map.readString('typeId', 'other'),
        url: map.readStringOrNull('url') ?? map.readStringOrNull('fileUrl'),
        createdAt:
            map.readDateTime('createdAt') ?? map.readDateTime('uploadedAt'),
        deleted: map.readBool('deleted'),
        revision: map.readInt('revision'),
        storagePath: map.readStringOrNull('storagePath'),
      );
}
