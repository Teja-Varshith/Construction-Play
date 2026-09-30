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
  received('received', 'Received'),

  /// Approved, then closed by the manager before everything arrived (the rest
  /// is no longer needed, or was bought another way).
  closed('closed', 'Closed short');

  const IndentStatus(this.value, this.label);
  final String value;
  final String label;

  static IndentStatus fromValue(String? v) =>
      IndentStatus.values.firstWhere((s) => s.value == v, orElse: () => IndentStatus.pending);
}

/// A material request from site. Approved by the project manager or the
/// CEO/admin, then fulfilled by one or more GRNs.
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
    this.closeNote = '',
    this.closedBy,
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

  /// The GRN that completed the indent.
  final String? grnId;
  final String closeNote;
  final String? closedBy;
  final int revision;

  bool get isPending => status == IndentStatus.pending;
  bool get isOpen => status == IndentStatus.approved;
  bool get isDone => status == IndentStatus.received || status == IndentStatus.closed;

  /// Approved but not fully delivered by the date the site needed it.
  bool isLate(String today) => isOpen && neededBy != null && neededBy!.compareTo(today) < 0;

  int daysLate(String today) {
    final t = WorkDay.tryParse(today);
    final n = WorkDay.tryParse(neededBy);
    return t == null || n == null ? 0 : t.difference(n).inDays;
  }

  /// Days until [neededBy]; negative once it has passed.
  int? daysToNeed(String today) {
    final t = WorkDay.tryParse(today);
    final n = WorkDay.tryParse(neededBy);
    return t == null || n == null ? null : n.difference(t).inDays;
  }

  int waitingDays(DateTime now) => requestedAt == null ? 0 : now.difference(requestedAt!).inDays;

  String get summary => items.map((l) => '${formatQty(l.qty)} ${l.unit} ${l.material}').join(', ');

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
    closeNote: m.readString('closeNote'),
    closedBy: m.readStringOrNull('closedBy'),
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


/// One movement in or out of the site store, for a material's ledger.
class StockMove {
  const StockMove({
    required this.date,
    required this.inward,
    required this.qty,
    required this.number,
    this.party = '',
    this.phaseId,
    this.ratePaise,
  });

  final String date;

  /// Received (GRN) when true, issued to the work when false.
  final bool inward;
  final double qty;

  /// GRN or issue slip number.
  final String number;

  /// Vendor for a receipt, contractor / crew for an issue.
  final String party;
  final String? phaseId;
  final int? ratePaise;
}

/// Stock of one material, summed from GRNs, issues and open indents.
class StockLine {
  StockLine(this.material, this.unit);

  /// Days of recent issues used to estimate how fast a material is used.
  static const usageWindowDays = 14;

  /// Running out when this many days of use or fewer are left.
  static const lowDays = 3;

  final String material;
  final String unit;
  double received = 0;
  double issued = 0;

  /// Approved and not yet delivered (partial deliveries already subtracted).
  double onOrder = 0;

  /// Requested, not yet approved.
  double requested = 0;

  /// Issued in the last [usageWindowDays].
  double usedRecently = 0;

  double _ratedQty = 0;
  int _ratedValuePaise = 0;
  int? lastRatePaise;
  String? _lastRateDate;
  String? lastReceived;
  String? lastIssued;
  final moves = <StockMove>[];

  String get key => '${material.toLowerCase()}|${unit.toLowerCase()}';

  double get inStock => received - issued;

  /// Average use per calendar day over the recent window; 0 when not used.
  double get dailyUse => usedRecently / usageWindowDays;

  /// How long the stock lasts at the recent rate of use; null when nothing
  /// was issued recently (no basis to estimate).
  double? get daysLeft => dailyUse <= 0 ? null : (inStock <= 0 ? 0 : inStock / dailyUse);

  /// Weighted average purchase rate from priced GRNs.
  int? get avgRatePaise => _ratedQty <= 0 ? null : (_ratedValuePaise / _ratedQty).round();

  int get valuePaise => avgRatePaise == null || inStock <= 0 ? 0 : (avgRatePaise! * inStock).round();

  bool get out => received > 0 && inStock <= 1e-9;

  /// Out of stock, a few days of use left, or (with no recent use to go by)
  /// under 15% of everything received so far.
  bool get low {
    if (received <= 0) return false;
    if (out) return true;
    final d = daysLeft;
    return d != null ? d <= lowDays : inStock <= received * 0.15;
  }

  /// Low and nothing already requested or on its way.
  bool get needsReorder => low && onOrder <= 1e-9 && requested <= 1e-9;

  /// A suggested reorder quantity: two weeks of recent use, or what was
  /// last received when there is no usage yet.
  double get suggestedReorder {
    final twoWeeks = dailyUse * 14 - inStock - onOrder;
    if (twoWeeks > 0) return (twoWeeks).ceilToDouble();
    final lastIn = moves.where((m) => m.inward).map((m) => m.qty).firstOrNull;
    return lastIn ?? 0;
  }

  void _rate(MaterialLine l, String date) {
    if (l.ratePaise == null) return;
    _ratedQty += l.qty;
    _ratedValuePaise += l.valuePaise;
    if (_lastRateDate == null || date.compareTo(_lastRateDate!) >= 0) {
      _lastRateDate = date;
      lastRatePaise = l.ratePaise;
    }
  }
}

/// Material used on one phase, valued at average purchase rates.
class PhaseUsage {
  PhaseUsage(this.phaseId);

  final String? phaseId;
  int valuePaise = 0;
  int slips = 0;
  final qtyByMaterial = <String, double>{};
}

/// Everything the Materials section and the delay factors need, recomputed
/// from source records at read time (never stored as running totals).
class InventorySummary {
  InventorySummary._({
    required this.stock,
    required this.pending,
    required this.late,
    required this.open,
    required this.receivedValuePaise,
    required this.receivedByIndent,
    required this.usageByPhase,
    required this.vendors,
  });

  /// Every material ever received, issued or requested, A–Z.
  final List<StockLine> stock;

  /// Waiting for approval, oldest first.
  final List<Indent> pending;

  /// Approved, not fully delivered and past the needed-by date, latest first.
  final List<Indent> late;

  /// Approved and awaiting (the rest of) delivery.
  final List<Indent> open;
  final int receivedValuePaise;

  /// Quantity received against each indent, by indent id then material key.
  final Map<String, Map<String, double>> receivedByIndent;

  /// Issued material by phase (null = no specific phase), costliest first.
  final List<PhaseUsage> usageByPhase;

  /// Vendors from past GRNs, most recent first.
  final List<String> vendors;

  int get lowCount => stock.where((s) => s.low).length;
  int get reorderCount => stock.where((s) => s.needsReorder).length;
  int get stockValuePaise => stock.fold(0, (s, l) => s + l.valuePaise);
  int get usedValuePaise => usageByPhase.fold(0, (s, u) => s + u.valuePaise);

  StockLine? line(String key) => stock.where((s) => s.key == key).firstOrNull;

  double receivedFor(Indent indent, MaterialLine l) => receivedByIndent[indent.id]?[l.key] ?? 0;

  /// What is still to arrive on an indent, line by line (only lines with
  /// something outstanding).
  List<MaterialLine> remaining(Indent indent) => [
    for (final l in indent.items)
      if (l.qty - receivedFor(indent, l) > 1e-9)
        MaterialLine(material: l.material, unit: l.unit, qty: l.qty - receivedFor(indent, l)),
  ];

  /// Share of the indent's quantity delivered so far, 0..1.
  double deliveredShare(Indent indent) {
    var ordered = 0.0, got = 0.0;
    for (final l in indent.items) {
      ordered += l.qty;
      got += receivedFor(indent, l).clamp(0, l.qty);
    }
    return ordered <= 0 ? 0 : got / ordered;
  }

  /// Last rate paid for a material, for pre-filling a GRN.
  int? lastRate(String key) => line(key)?.lastRatePaise;

  static InventorySummary calculate({
    required List<Indent> indents,
    required List<Grn> grns,
    required List<MaterialIssue> issues,
    required String today,
  }) {
    final byKey = <String, StockLine>{};
    StockLine line(MaterialLine l) => byKey.putIfAbsent(l.key, () => StockLine(l.material.trim(), l.unit.trim()));
    final t = WorkDay.tryParse(today);
    final windowStart = t == null ? today : WorkDay.fromDate(t.subtract(const Duration(days: StockLine.usageWindowDays)));

    final receivedByIndent = <String, Map<String, double>>{};
    final vendors = <String>[];
    final byDate = [...grns]..sort((a, b) => b.date.compareTo(a.date));
    for (final g in byDate) {
      final v = g.vendor.trim();
      if (v.isNotEmpty && !vendors.any((x) => x.toLowerCase() == v.toLowerCase())) vendors.add(v);
    }
    for (final g in grns) {
      for (final l in g.items) {
        final s = line(l)..received += l.qty;
        s._rate(l, g.date);
        if (s.lastReceived == null || g.date.compareTo(s.lastReceived!) > 0) s.lastReceived = g.date;
        s.moves.add(
          StockMove(date: g.date, inward: true, qty: l.qty, number: g.number, party: g.vendor, ratePaise: l.ratePaise),
        );
        if (g.indentId != null) {
          final m = receivedByIndent.putIfAbsent(g.indentId!, () => {});
          m[l.key] = (m[l.key] ?? 0) + l.qty;
        }
      }
    }
    for (final i in issues) {
      for (final l in i.items) {
        final s = line(l)..issued += l.qty;
        if (i.date.compareTo(windowStart) > 0 && i.date.compareTo(today) <= 0) s.usedRecently += l.qty;
        if (s.lastIssued == null || i.date.compareTo(s.lastIssued!) > 0) s.lastIssued = i.date;
        s.moves.add(
          StockMove(date: i.date, inward: false, qty: l.qty, number: i.number, party: i.issuedTo, phaseId: i.phaseId),
        );
      }
    }
    for (final ind in indents) {
      for (final l in ind.items) {
        if (ind.status == IndentStatus.approved) {
          final left = l.qty - (receivedByIndent[ind.id]?[l.key] ?? 0);
          if (left > 0) line(l).onOrder += left;
        }
        if (ind.status == IndentStatus.pending) line(l).requested += l.qty;
      }
    }
    for (final s in byKey.values) {
      // Newest first; on the same day, receipts count as coming in before issues.
      s.moves.sort((a, b) {
        final byDate = b.date.compareTo(a.date);
        return byDate != 0 ? byDate : (a.inward == b.inward ? 0 : (a.inward ? 1 : -1));
      });
    }

    final usage = <String?, PhaseUsage>{};
    for (final i in issues) {
      final u = usage.putIfAbsent(i.phaseId, () => PhaseUsage(i.phaseId));
      u.slips++;
      for (final l in i.items) {
        final rate = byKey[l.key]?.avgRatePaise;
        if (rate != null) u.valuePaise += (rate * l.qty).round();
        final name = '${l.material.trim()} (${l.unit.trim()})';
        u.qtyByMaterial[name] = (u.qtyByMaterial[name] ?? 0) + l.qty;
      }
    }

    final stock = byKey.values.toList()..sort((a, b) => a.material.toLowerCase().compareTo(b.material.toLowerCase()));
    return InventorySummary._(
      stock: stock,
      pending: indents.where((i) => i.isPending).toList()
        ..sort((a, b) => (a.requestedAt ?? DateTime(0)).compareTo(b.requestedAt ?? DateTime(0))),
      late: indents.where((i) => i.isLate(today)).toList()..sort((a, b) => b.daysLate(today).compareTo(a.daysLate(today))),
      open: indents.where((i) => i.isOpen).toList(),
      receivedValuePaise: grns.fold(0, (s, g) => s + g.valuePaise),
      receivedByIndent: receivedByIndent,
      usageByPhase: usage.values.toList()..sort((a, b) => b.valuePaise.compareTo(a.valuePaise)),
      vendors: vendors,
    );
  }
}
