import '../../../core/data/json_read.dart';
import '../../../core/utils/work_day.dart';

/// Common construction materials offered when raising an indent. Anything
/// else can be typed in.
const commonMaterials = <(String, String)>[
  ('Cement (OPC 53)', 'bags'),
  ('TMT steel', 'kg'),
  ('River sand', 'cft'),
  ('M-sand', 'cft'),
  ('20mm aggregate', 'cft'),
  ('Red bricks', 'nos'),
  ('AAC blocks', 'nos'),
  ('Ready-mix concrete M25', 'm³'),
  ('Binding wire', 'kg'),
  ('Plywood shuttering', 'sheets'),
  ('Electrical wire 2.5 sq mm', 'coils'),
  ('CPVC pipe 1 inch', 'm'),
  ('Vitrified tiles', 'sqft'),
  ('Wall putty', 'bags'),
  ('Emulsion paint', 'litres'),
];

/// One material and quantity on an indent, GRN or issue slip.
class MaterialLine {
  const MaterialLine({required this.material, required this.unit, required this.qty, this.ratePaise});

  final String material;
  final String unit;
  final double qty;

  /// Price per unit; only on GRNs.
  final int? ratePaise;

  /// Same material in the same unit, however it was typed.
  String get key => '${material.trim().toLowerCase()}|${unit.trim().toLowerCase()}';

  int get valuePaise => ratePaise == null ? 0 : (ratePaise! * qty).round();

  factory MaterialLine.fromMap(Map<String, dynamic> m) => MaterialLine(
    material: m.readString('material'),
    unit: m.readString('unit'),
    qty: (m.readNumOrNull('qty') ?? 0).toDouble(),
    ratePaise: m.readIntOrNull('ratePaise'),
  );

  Map<String, dynamic> toMap() => {
    'material': material.trim(),
    'unit': unit.trim(),
    'qty': qty,
    'ratePaise': ?ratePaise,
  };
}

String formatQty(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');

enum IndentStatus {
  pending('pending', 'Waiting for approval'),
  approved('approved', 'Approved · awaiting delivery'),
  rejected('rejected', 'Rejected'),
  received('received', 'Received');

  const IndentStatus(this.value, this.label);
  final String value;
  final String label;

  static IndentStatus fromValue(String? v) =>
      IndentStatus.values.firstWhere((s) => s.value == v, orElse: () => IndentStatus.pending);
}

/// A material request from site. Approved by the project manager or the
/// CEO/admin, then fulfilled by a GRN.
class Indent {
  const Indent({
    required this.id,
    required this.number,
    required this.items,
    this.neededBy,
    this.phaseId,
    this.note = '',
    this.status = IndentStatus.pending,
    this.requestedBy,
    this.requestedAt,
    this.decidedBy,
    this.decidedAt,
    this.decisionNote = '',
    this.grnId,
    this.revision = 0,
  });

  final String id;
  final String number;
  final List<MaterialLine> items;

  /// Work-day key the site needs the material by.
  final String? neededBy;
  final String? phaseId;
  final String note;
  final IndentStatus status;
  final String? requestedBy;
  final DateTime? requestedAt;
  final String? decidedBy;
  final DateTime? decidedAt;
  final String decisionNote;
  final String? grnId;
  final int revision;

  bool get isPending => status == IndentStatus.pending;

  /// Approved but not delivered by the date the site needed it.
  bool isLate(String today) =>
      status == IndentStatus.approved && neededBy != null && neededBy!.compareTo(today) < 0;

  int daysLate(String today) {
    final t = WorkDay.tryParse(today);
    final n = WorkDay.tryParse(neededBy);
    return t == null || n == null ? 0 : t.difference(n).inDays;
  }

  int waitingDays(DateTime now) => requestedAt == null ? 0 : now.difference(requestedAt!).inDays;

  factory Indent.fromMap(String id, Map<String, dynamic> m) => Indent(
    id: id,
    number: m.readString('number', id.substring(0, id.length < 6 ? id.length : 6).toUpperCase()),
    items: m.readMapList('items').map(MaterialLine.fromMap).toList(),
    neededBy: m.readStringOrNull('neededBy'),
    phaseId: m.readStringOrNull('phaseId'),
    note: m.readString('note'),
    status: IndentStatus.fromValue(m.readStringOrNull('status')),
    requestedBy: m.readStringOrNull('requestedBy'),
    requestedAt: m.readDateTime('requestedAt') ?? m.readDateTime('createdAt'),
    decidedBy: m.readStringOrNull('decidedBy'),
    decidedAt: m.readDateTime('decidedAt'),
    decisionNote: m.readString('decisionNote'),
    grnId: m.readStringOrNull('grnId'),
    revision: m.readInt('revision'),
  );
}

/// Goods received note: what actually arrived on site, from whom, at what rate.
class Grn {
  const Grn({
    required this.id,
    required this.number,
    required this.items,
    required this.vendor,
    required this.date,
    this.invoiceNo = '',
    this.indentId,
    this.note = '',
    this.receivedBy,
  });

  final String id;
  final String number;
  final List<MaterialLine> items;
  final String vendor;
  final String date;
  final String invoiceNo;
  final String? indentId;
  final String note;
  final String? receivedBy;

  int get valuePaise => items.fold(0, (s, l) => s + l.valuePaise);

  factory Grn.fromMap(String id, Map<String, dynamic> m) => Grn(
    id: id,
    number: m.readString('number', id.substring(0, id.length < 6 ? id.length : 6).toUpperCase()),
    items: m.readMapList('items').map(MaterialLine.fromMap).toList(),
    vendor: m.readString('vendor'),
    date: m.readString('date'),
    invoiceNo: m.readString('invoiceNo'),
    indentId: m.readStringOrNull('indentId'),
    note: m.readString('note'),
    receivedBy: m.readStringOrNull('receivedBy'),
  );
}

/// Material issued from the site store to the work.
class MaterialIssue {
  const MaterialIssue({
    required this.id,
    required this.number,
    required this.items,
    required this.date,
    this.phaseId,
    this.issuedTo = '',
    this.note = '',
    this.issuedBy,
  });

  final String id;
  final String number;
  final List<MaterialLine> items;
  final String date;
  final String? phaseId;
  final String issuedTo;
  final String note;
  final String? issuedBy;

  factory MaterialIssue.fromMap(String id, Map<String, dynamic> m) => MaterialIssue(
    id: id,
    number: m.readString('number', id.substring(0, id.length < 6 ? id.length : 6).toUpperCase()),
    items: m.readMapList('items').map(MaterialLine.fromMap).toList(),
    date: m.readString('date'),
    phaseId: m.readStringOrNull('phaseId'),
    issuedTo: m.readString('issuedTo'),
    note: m.readString('note'),
    issuedBy: m.readStringOrNull('issuedBy'),
  );
}

/// Stock of one material, summed from GRNs, issues and open indents.
class StockLine {
  StockLine(this.material, this.unit);

  final String material;
  final String unit;
  double received = 0;
  double issued = 0;

  /// Approved, not yet delivered.
  double onOrder = 0;

  /// Requested, not yet approved.
  double requested = 0;

  double get inStock => received - issued;

  /// Nothing left, or under 15% of everything received so far.
  bool get low => received > 0 && inStock <= received * 0.15;
}

/// Everything the Materials section and the delay factors need, recomputed
/// from source records at read time (never stored as running totals).
class InventorySummary {
  InventorySummary._(this.stock, this.pending, this.late, this.receivedValuePaise);

  final List<StockLine> stock;
  final List<Indent> pending;
  final List<Indent> late;
  final int receivedValuePaise;

  int get lowCount => stock.where((s) => s.low).length;

  static InventorySummary calculate({
    required List<Indent> indents,
    required List<Grn> grns,
    required List<MaterialIssue> issues,
    required String today,
  }) {
    final byKey = <String, StockLine>{};
    StockLine line(MaterialLine l) => byKey.putIfAbsent(l.key, () => StockLine(l.material.trim(), l.unit.trim()));
    for (final g in grns) {
      for (final l in g.items) {
        line(l).received += l.qty;
      }
    }
    for (final i in issues) {
      for (final l in i.items) {
        line(l).issued += l.qty;
      }
    }
    for (final ind in indents) {
      for (final l in ind.items) {
        if (ind.status == IndentStatus.approved) line(l).onOrder += l.qty;
        if (ind.status == IndentStatus.pending) line(l).requested += l.qty;
      }
    }
    final stock = byKey.values.toList()..sort((a, b) => a.material.toLowerCase().compareTo(b.material.toLowerCase()));
    return InventorySummary._(
      stock,
      indents.where((i) => i.isPending).toList(),
      indents.where((i) => i.isLate(today)).toList(),
      grns.fold(0, (s, g) => s + g.valuePaise),
    );
  }
}
