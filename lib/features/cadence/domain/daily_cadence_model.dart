import '../../../core/data/json_read.dart';

enum CadenceTimeSlot {
  morningPlan('8:30 AM – Daily Plan', 'Morning muster, day targets, labor allocation & material checks'),
  middayReview('1:00 PM – Progress Review', 'Mid-day pulse check, progress status & bottleneck resolution'),
  dailyClosing('9:30 PM – Daily Closing', 'Final work execution tally, delays & manager signoff');

  const CadenceTimeSlot(this.label, this.description);
  final String label;
  final String description;
}

enum MiddayStatus {
  onTrack('On Track', 'Activities progressing according to daily schedule'),
  minorDelay('Minor Delay', 'Slight bottleneck; catch-up planned for second half'),
  blocked('Critical Delay / Blocked', 'Work halted due to material/labor or drawing issues');

  const MiddayStatus(this.label, this.description);
  final String label;
  final String description;

  static MiddayStatus fromName(String? name) =>
      MiddayStatus.values.firstWhere((s) => s.name == name, orElse: () => MiddayStatus.onTrack);
}

class MorningPlan {
  const MorningPlan({
    this.plannedTasks = '',
    this.targetOutput = '',
    this.plannedLaborCount = 0,
    this.materialsReady = true,
    this.supervisorNotes = '',
    this.submittedBy = '',
    this.submittedAt,
  });

  final String plannedTasks;
  final String targetOutput;
  final int plannedLaborCount;
  final bool materialsReady;
  final String supervisorNotes;
  final String submittedBy;
  final DateTime? submittedAt;

  factory MorningPlan.fromMap(Map<String, dynamic> m) => MorningPlan(
        plannedTasks: m.readString('plannedTasks'),
        targetOutput: m.readString('targetOutput'),
        plannedLaborCount: m.readInt('plannedLaborCount'),
        materialsReady: m.readBool('materialsReady', true),
        supervisorNotes: m.readString('supervisorNotes'),
        submittedBy: m.readString('submittedBy'),
        submittedAt: m.readDateTime('submittedAt'),
      );

  Map<String, dynamic> toMap() => {
        'plannedTasks': plannedTasks,
        'targetOutput': targetOutput,
        'plannedLaborCount': plannedLaborCount,
        'materialsReady': materialsReady,
        'supervisorNotes': supervisorNotes,
        'submittedBy': submittedBy,
        if (submittedAt != null) 'submittedAt': submittedAt!.toIso8601String(),
      };
}

class MiddayReview {
  const MiddayReview({
    this.status = MiddayStatus.onTrack,
    this.progressNotes = '',
    this.laborPresentCount = 0,
    this.bottlenecks = '',
    this.submittedBy = '',
    this.submittedAt,
  });

  final MiddayStatus status;
  final String progressNotes;
  final int laborPresentCount;
  final String bottlenecks;
  final String submittedBy;
  final DateTime? submittedAt;

  factory MiddayReview.fromMap(Map<String, dynamic> m) => MiddayReview(
        status: MiddayStatus.fromName(m.readStringOrNull('status')),
        progressNotes: m.readString('progressNotes'),
        laborPresentCount: m.readInt('laborPresentCount'),
        bottlenecks: m.readString('bottlenecks'),
        submittedBy: m.readString('submittedBy'),
        submittedAt: m.readDateTime('submittedAt'),
      );

  Map<String, dynamic> toMap() => {
        'status': status.name,
        'progressNotes': progressNotes,
        'laborPresentCount': laborPresentCount,
        'bottlenecks': bottlenecks,
        'submittedBy': submittedBy,
        if (submittedAt != null) 'submittedAt': submittedAt!.toIso8601String(),
      };
}

class DailyClosing {
  const DailyClosing({
    this.actualOutput = '',
    this.workCompletedSummary = '',
    this.delaysEncountered = '',
    this.photoUrls = const [],
    this.managerSignoff = 'pending', // pending | approved | queried
    this.managerFeedback = '',
    this.signedOffBy = '',
    this.signedOffAt,
    this.submittedBy = '',
    this.submittedAt,
  });

  final String actualOutput;
  final String workCompletedSummary;
  final String delaysEncountered;
  final List<String> photoUrls;
  final String managerSignoff;
  final String managerFeedback;
  final String signedOffBy;
  final DateTime? signedOffAt;
  final String submittedBy;
  final DateTime? submittedAt;

  factory DailyClosing.fromMap(Map<String, dynamic> m) {
    final rawPhotos = m['photoUrls'];
    final photos = rawPhotos is List ? rawPhotos.map((e) => e.toString()).toList() : <String>[];
    return DailyClosing(
      actualOutput: m.readString('actualOutput'),
      workCompletedSummary: m.readString('workCompletedSummary'),
      delaysEncountered: m.readString('delaysEncountered'),
      photoUrls: photos,
      managerSignoff: m.readString('managerSignoff', 'pending'),
      managerFeedback: m.readString('managerFeedback'),
      signedOffBy: m.readString('signedOffBy'),
      signedOffAt: m.readDateTime('signedOffAt'),
      submittedBy: m.readString('submittedBy'),
      submittedAt: m.readDateTime('submittedAt'),
    );
  }

  Map<String, dynamic> toMap() => {
        'actualOutput': actualOutput,
        'workCompletedSummary': workCompletedSummary,
        'delaysEncountered': delaysEncountered,
        'photoUrls': photoUrls,
        'managerSignoff': managerSignoff,
        'managerFeedback': managerFeedback,
        'signedOffBy': signedOffBy,
        if (signedOffAt != null) 'signedOffAt': signedOffAt!.toIso8601String(),
        'submittedBy': submittedBy,
        if (submittedAt != null) 'submittedAt': submittedAt!.toIso8601String(),
      };
}

class DailyCadence {
  const DailyCadence({
    required this.id,
    required this.projectId,
    required this.date, // YYYY-MM-DD
    this.morningPlan = const MorningPlan(),
    this.middayReview = const MiddayReview(),
    this.dailyClosing = const DailyClosing(),
    this.revision = 1,
    this.updatedAt,
  });

  final String id;
  final String projectId;
  final String date;
  final MorningPlan morningPlan;
  final MiddayReview middayReview;
  final DailyClosing dailyClosing;
  final int revision;
  final DateTime? updatedAt;

  bool get isMorningDone => morningPlan.submittedAt != null;
  bool get isMiddayDone => middayReview.submittedAt != null;
  bool get isClosingDone => dailyClosing.submittedAt != null;
  bool get isManagerApproved => dailyClosing.managerSignoff == 'approved';

  factory DailyCadence.fromMap(String id, String projectId, Map<String, dynamic> m) => DailyCadence(
        id: id,
        projectId: projectId,
        date: m.readString('date'),
        morningPlan: m['morningPlan'] is Map<String, dynamic>
            ? MorningPlan.fromMap(m['morningPlan'] as Map<String, dynamic>)
            : const MorningPlan(),
        middayReview: m['middayReview'] is Map<String, dynamic>
            ? MiddayReview.fromMap(m['middayReview'] as Map<String, dynamic>)
            : const MiddayReview(),
        dailyClosing: m['dailyClosing'] is Map<String, dynamic>
            ? DailyClosing.fromMap(m['dailyClosing'] as Map<String, dynamic>)
            : const DailyClosing(),
        revision: m.readInt('revision', 1),
        updatedAt: m.readDateTime('updatedAt'),
      );

  Map<String, dynamic> toMap() => {
        'date': date,
        'morningPlan': morningPlan.toMap(),
        'middayReview': middayReview.toMap(),
        'dailyClosing': dailyClosing.toMap(),
        'revision': revision,
      };
}
