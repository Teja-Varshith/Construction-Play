import '../../../core/data/json_read.dart';

/// Health colour of a project, calculated from progress and money.
enum ProjectHealth {
  green,
  amber,
  red,
  noData;

  static ProjectHealth fromName(String? name) => ProjectHealth.values
      .firstWhere((h) => h.name == name, orElse: () => ProjectHealth.noData);
}

class StatusChange {
  const StatusChange({
    required this.statusId,
    required this.at,
    required this.by,
    this.note = '',
  });

  final String statusId;
  final DateTime? at;
  final String by;
  final String note;

  factory StatusChange.fromMap(Map<String, dynamic> m) => StatusChange(
    statusId: m.readString('statusId'),
    at: m.readDateTime('at'),
    by: m.readString('by'),
    note: m.readString('note'),
  );
}

/// A construction project: the centre of everything else in the app.
///
/// Fixed fields are the ones the dashboard needs. Anything client-specific
/// (RERA number, plot area, ...) goes in [custom], defined in Settings.
class Project {
  const Project({
    required this.id,
    required this.name,
    required this.statusId,
    this.code = '',
    this.clientName = '',
    this.city = '',
    this.address = '',
    this.typeId,
    this.contractValuePaise = 0,
    this.startDate,
    this.endDate,
    this.managerId,
    this.supervisorIds = const [],
    this.memberIds = const [],
    this.statusHistory = const [],
    this.custom = const {},
    this.plannedPct = 0,
    this.actualPct = 0,
    this.health = ProjectHealth.noData,
    this.budgetTotalPaise = 0,
    this.spentTotalPaise = 0,
    this.deleted = false,
    this.createdAt,
    this.updatedAt,
    this.revision = 0,
    this.holdPeriods = const [],
  });

  final String id;
  final String name;
  final String code;
  final String clientName;
  final String city;
  final String address;
  final String? typeId;
  final String statusId;
  final int contractValuePaise;

  /// Working-day keys (YYYY-MM-DD).
  final String? startDate;
  final String? endDate;

  final String? managerId;
  final List<String> supervisorIds;

  /// Everyone who may open this project (manager + supervisors + staff).
  /// The security rules check this list.
  final List<String> memberIds;

  final List<StatusChange> statusHistory;
  final Map<String, dynamic> custom;

  // Kept up to date when phases, daily reports and expenses change.
  final double plannedPct;
  final double actualPct;
  final ProjectHealth health;
  final int budgetTotalPaise;
  final int spentTotalPaise;

  final bool deleted;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final int revision;
  final List<Map<String, dynamic>> holdPeriods;

  factory Project.fromMap(String id, Map<String, dynamic> m) => Project(
    id: id,
    name: m.readString('name', 'Untitled project'),
    code: m.readString('code'),
    clientName: m.readString('clientName'),
    city: m.readString('city'),
    address: m.readString('address'),
    typeId: m.readStringOrNull('typeId'),
    statusId: m.readString('statusId', 'enquiry'),
    contractValuePaise: m.readInt('contractValuePaise'),
    startDate: m.readStringOrNull('startDate'),
    endDate: m.readStringOrNull('endDate'),
    managerId: m.readStringOrNull('managerId'),
    supervisorIds: m.readStringList('supervisorIds'),
    memberIds: m.readStringList('memberIds'),
    statusHistory: m
        .readMapList('statusHistory')
        .map(StatusChange.fromMap)
        .toList(),
    custom: m.readMap('custom'),
    plannedPct: (m.readNumOrNull('plannedPct') ?? 0).toDouble(),
    actualPct: (m.readNumOrNull('actualPct') ?? 0).toDouble(),
    health: ProjectHealth.fromName(m.readStringOrNull('health')),
    budgetTotalPaise: m.readInt('budgetTotalPaise'),
    spentTotalPaise: m.readInt('spentTotalPaise'),
    deleted: m.readBool('deleted'),
    createdAt: m.readDateTime('createdAt'),
    updatedAt: m.readDateTime('updatedAt'),
    revision: m.readInt('revision'),
    holdPeriods: m.readMapList('holdPeriods'),
  );

  /// Editable fields only. Calculated fields and audit stamps are written by
  /// the repository.
  Map<String, dynamic> toEditableMap() => {
    'name': name.trim(),
    'nameLower': name.trim().toLowerCase(),
    'code': code.trim(),
    'clientName': clientName.trim(),
    'city': city.trim(),
    'address': address.trim(),
    'typeId': typeId,
    'contractValuePaise': contractValuePaise,
    'startDate': startDate,
    'endDate': endDate,
    'managerId': managerId,
    'supervisorIds': supervisorIds,
    'memberIds': computeMemberIds(managerId, supervisorIds),
    'custom': custom,
  };

  static List<String> computeMemberIds(
    String? managerId,
    List<String> supervisorIds,
  ) => {?managerId, ...supervisorIds}.toList();

  Project withProgress(double planned, double actual, ProjectHealth state) =>
      Project(
        id: id,
        name: name,
        statusId: statusId,
        code: code,
        clientName: clientName,
        city: city,
        address: address,
        typeId: typeId,
        contractValuePaise: contractValuePaise,
        startDate: startDate,
        endDate: endDate,
        managerId: managerId,
        supervisorIds: supervisorIds,
        memberIds: memberIds,
        statusHistory: statusHistory,
        custom: custom,
        plannedPct: planned,
        actualPct: actual,
        health: state,
        budgetTotalPaise: budgetTotalPaise,
        spentTotalPaise: spentTotalPaise,
        deleted: deleted,
        createdAt: createdAt,
        updatedAt: updatedAt,
        revision: revision,
        holdPeriods: holdPeriods,
      );
}
