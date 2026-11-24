import '../../../core/data/json_read.dart';

class SalesTarget {
  const SalesTarget({
    required this.id,
    required this.yearMonth, // e.g. "2026-11"
    required this.targetPaise,
    this.achievedPaise = 0,
    required this.employeeUid,
    this.employeeName = '',
    this.targetLeadsCount = 10,
    this.achievedLeadsCount = 0,
    this.targetWonCount = 2,
    this.achievedWonCount = 0,
    this.deleted = false,
    this.createdAt,
    this.updatedAt,
    this.createdBy = '',
    this.updatedBy = '',
    this.revision = 1,
  });

  final String id;
  final String yearMonth;
  final int targetPaise;
  final int achievedPaise;
  final String employeeUid;
  final String employeeName;
  final int targetLeadsCount;
  final int achievedLeadsCount;
  final int targetWonCount;
  final int achievedWonCount;
  final bool deleted;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String createdBy;
  final String updatedBy;
  final int revision;

  double get revenueAchievementPct =>
      targetPaise > 0 ? ((achievedPaise / targetPaise) * 100).clamp(0, 500) : 0.0;

  double get wonAchievementPct =>
      targetWonCount > 0 ? ((achievedWonCount / targetWonCount) * 100).clamp(0, 500) : 0.0;

  factory SalesTarget.fromMap(String id, Map<String, dynamic> m) => SalesTarget(
        id: id,
        yearMonth: m.readString('yearMonth'),
        targetPaise: m.readInt('targetPaise'),
        achievedPaise: m.readInt('achievedPaise'),
        employeeUid: m.readString('employeeUid'),
        employeeName: m.readString('employeeName'),
        targetLeadsCount: m.readInt('targetLeadsCount', 10),
        achievedLeadsCount: m.readInt('achievedLeadsCount'),
        targetWonCount: m.readInt('targetWonCount', 2),
        achievedWonCount: m.readInt('achievedWonCount'),
        deleted: m.readBool('deleted'),
        createdAt: m.readDateTime('createdAt'),
        updatedAt: m.readDateTime('updatedAt'),
        createdBy: m.readString('createdBy'),
        updatedBy: m.readString('updatedBy'),
        revision: m.readInt('revision', 1),
      );

  Map<String, dynamic> toMap() => {
        'yearMonth': yearMonth,
        'targetPaise': targetPaise,
        'achievedPaise': achievedPaise,
        'employeeUid': employeeUid,
        'employeeName': employeeName,
        'targetLeadsCount': targetLeadsCount,
        'achievedLeadsCount': achievedLeadsCount,
        'targetWonCount': targetWonCount,
        'achievedWonCount': achievedWonCount,
        'deleted': deleted,
        'revision': revision,
      };
}
