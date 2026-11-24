import '../../../core/data/json_read.dart';

enum TradeCategory {
  mason('Mason / Bricklayer'),
  carpenter('Carpenter / Shuttering'),
  barBender('Bar Bender / Steel'),
  electrician('Electrician'),
  plumber('Plumber'),
  painter('Painter'),
  tileLayer('Tile & Marble Layer'),
  welder('Welder / Fabricator'),
  helper('General Helper / Labor'),
  other('Other Specialist');

  const TradeCategory(this.label);
  final String label;

  static TradeCategory fromName(String? name) =>
      TradeCategory.values.firstWhere((t) => t.name == name, orElse: () => TradeCategory.helper);
}

class LaborEntry {
  const LaborEntry({
    required this.id,
    required this.trade,
    required this.contractorName,
    required this.headCount,
    this.wagePerDayPaise = 0,
    this.totalWagePaise = 0,
    this.workAllocated = '',
    this.hoursWorked = 8.0,
    this.notes = '',
  });

  final String id;
  final TradeCategory trade;
  final String contractorName;
  final int headCount;
  final int wagePerDayPaise;
  final int totalWagePaise;
  final String workAllocated;
  final double hoursWorked;
  final String notes;

  int get computedTotalWagePaise =>
      totalWagePaise > 0 ? totalWagePaise : (headCount * wagePerDayPaise);

  factory LaborEntry.fromMap(Map<String, dynamic> m) => LaborEntry(
        id: m.readString('id'),
        trade: TradeCategory.fromName(m.readStringOrNull('trade')),
        contractorName: m.readString('contractorName'),
        headCount: m.readInt('headCount', 1),
        wagePerDayPaise: m.readInt('wagePerDayPaise'),
        totalWagePaise: m.readInt('totalWagePaise'),
        workAllocated: m.readString('workAllocated'),
        hoursWorked: (m.readNumOrNull('hoursWorked') ?? 8.0).toDouble(),
        notes: m.readString('notes'),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'trade': trade.name,
        'contractorName': contractorName,
        'headCount': headCount,
        'wagePerDayPaise': wagePerDayPaise,
        'totalWagePaise': computedTotalWagePaise,
        'workAllocated': workAllocated,
        'hoursWorked': hoursWorked,
        'notes': notes,
      };
}

class DailyLaborMuster {
  const DailyLaborMuster({
    required this.id,
    required this.projectId,
    required this.date, // YYYY-MM-DD
    required this.entries,
    this.supervisorId = '',
    this.supervisorName = '',
    this.verifiedByManager = false,
    this.revision = 1,
    this.updatedAt,
  });

  final String id;
  final String projectId;
  final String date;
  final List<LaborEntry> entries;
  final String supervisorId;
  final String supervisorName;
  final bool verifiedByManager;
  final int revision;
  final DateTime? updatedAt;

  int get totalWorkers => entries.fold<int>(0, (sum, e) => sum + e.headCount);
  int get totalDailyWagePaise => entries.fold<int>(0, (sum, e) => sum + e.computedTotalWagePaise);

  factory DailyLaborMuster.fromMap(String id, String projectId, Map<String, dynamic> m) {
    final rawEntries = m['entries'];
    final list = <LaborEntry>[];
    if (rawEntries is List) {
      for (final item in rawEntries) {
        if (item is Map<String, dynamic>) {
          list.add(LaborEntry.fromMap(item));
        }
      }
    }

    return DailyLaborMuster(
      id: id,
      projectId: projectId,
      date: m.readString('date'),
      entries: list,
      supervisorId: m.readString('supervisorId'),
      supervisorName: m.readString('supervisorName'),
      verifiedByManager: m.readBool('verifiedByManager'),
      revision: m.readInt('revision', 1),
      updatedAt: m.readDateTime('updatedAt'),
    );
  }

  Map<String, dynamic> toMap() => {
        'date': date,
        'entries': entries.map((e) => e.toMap()).toList(),
        'supervisorId': supervisorId,
        'supervisorName': supervisorName,
        'verifiedByManager': verifiedByManager,
        'revision': revision,
      };
}
