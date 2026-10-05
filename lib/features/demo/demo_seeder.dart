import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/config/config_models.dart';
import '../../core/config/default_config.dart';
import '../../core/data/audit.dart';
import '../../core/firebase/firebase_providers.dart';
import '../../core/utils/work_day.dart';
import '../auth/domain/app_user.dart';
import '../finance/domain/expense.dart';
import '../users/data/user_repository.dart';
import 'demo_accounts.dart';

/// Loads a realistic demo portfolio so the CEO dashboard can be tried end to
/// end: projects on track, slipping, badly delayed (with a past hold), over
/// budget, on hold and in the pipeline, each with phases, phase and category
/// budgets, expenses (some awaiting approval), issues and daily reports.
///
/// Everything is written through the same security rules as real data, as the
/// signed-in admin. Demo projects carry `demo: true` so they can be removed.
class DemoSeeder {
  DemoSeeder(this._db, this._users);

  final FirebaseFirestore _db;
  final UserRepository _users;
  final _rand = math.Random(7);

  CollectionReference<Map<String, dynamic>> get _projects => _db.collection('projects');

  Future<bool> hasDemoData() async {
    final snap = await _projects
        .where('demo', isEqualTo: true)
        .where('deleted', isEqualTo: false)
        .limit(1)
        .get();
    return snap.docs.isNotEmpty;
  }

  /// Archives every demo project (soft delete, like everything else).
  Future<int> removeDemoData(String uid) async {
    final snap = await _projects
        .where('demo', isEqualTo: true)
        .where('deleted', isEqualTo: false)
        .get();
    final batch = _db.batch();
    for (final doc in snap.docs) {
      batch.update(doc.reference, {'deleted': true, ...auditUpdate(uid)});
    }
    // Switch the demo logins off too (never the admin doing this).
    final people = await _db.collection('users').where('active', isEqualTo: true).get();
    for (final doc in people.docs) {
      if (doc.id != uid && isDemoEmail(doc.data()['email'] as String? ?? '')) {
        batch.update(doc.reference, {'active': false, ...auditUpdate(uid)});
      }
    }
    batch.set(demoStateDoc(_db), {'enabled': false, 'updatedBy': uid, 'updatedAt': FieldValue.serverTimestamp()});
    if (snap.docs.isNotEmpty) {
      ActivityEntry(
        actorId: uid,
        action: 'archived',
        entity: 'demo',
        entityId: 'demo',
        summary: 'Removed ${snap.docs.length} demo projects',
      ).addTo(batch, _db);
    }
    await batch.commit();
    return snap.docs.length;
  }

  /// Creates (or reactivates) one login per role; see [demoAccounts].
  Future<void> ensureDemoLogins(String adminUid, {void Function(String step)? onProgress}) async {
    for (final a in demoAccounts) {
      onProgress?.call('Creating demo login: ${a.role.label}');
      final uid = await _users.ensureLogin(a.email, demoPassword);
      if (uid == adminUid) continue; // the admin running this is already set up
      await _users.upsertProfile(
        adminUid: adminUid,
        uid: uid,
        name: a.name,
        email: a.email,
        role: a.role,
        designation: a.designation,
      );
    }
    await demoStateDoc(_db).set({
      'enabled': true,
      'updatedBy': adminUid,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> seed({
    required AppConfig config,
    required AppUser admin,
    void Function(String step)? onProgress,
  }) async {
    if (await hasDemoData()) {
      throw StateError('Demo data is already loaded. Remove it first to load it again.');
    }
    await ensureDemoLogins(admin.uid, onProgress: onProgress);
    final users = (await _db.collection('users').get())
        .docs
        .map((d) => AppUser.fromMap(d.id, d.data()))
        .where((u) => u.active)
        .toList();
    // Put demo people on demo projects, so each demo login sees real work.
    List<AppUser> pick(UserRole role) {
      final all = users.where((u) => u.role == role).toList();
      final demo = all.where((u) => isDemoEmail(u.email)).toList();
      return demo.isNotEmpty ? demo : all;
    }

    final company = config.company;
    final today = WorkDay.tryParse(WorkDay.today(utcOffsetMinutes: company.utcOffsetMinutes))!;
    final todayUtc = DateTime.utc(today.year, today.month, today.day);
    final managers = pick(UserRole.manager);
    final supervisors = pick(UserRole.supervisor);
    final staff = pick(UserRole.staff);
    final statuses = config.allOf(ConfigList.projectStatuses);

    for (var n = 0; n < _scenarios.length; n++) {
      final s = _scenarios[n];
      onProgress?.call('Creating ${s.name} (${n + 1} of ${_scenarios.length})');
      final statusIndex = statuses.indexWhere((st) => st.stage == s.stage && !st.archived);
      if (statusIndex < 0) {
        throw StateError('No active "${s.stage.label}" status in Settings → Lists.');
      }
      final status = statuses[statusIndex];
      final manager = managers.isEmpty ? null : managers[n % managers.length];
      final supervisor = supervisors.isEmpty ? null : supervisors[n % supervisors.length];
      await _seedProject(
        s: s,
        statusId: status.id,
        statusIndex: statusIndex,
        today: todayUtc,
        admin: admin,
        managerId: manager?.uid,
        supervisorIds: [?supervisor?.uid],
        staffIds: [for (final u in staff) u.uid],
        threshold: company.approvalThresholdPaise,
        lockedUntil: company.financeLockedUntil,
        backdateDays: company.dprBackdateDays,
      );
    }
    onProgress?.call('Done');
  }

  Future<void> _seedProject({
    required _Scenario s,
    required String statusId,
    required int statusIndex,
    required DateTime today,
    required AppUser admin,
    required String? managerId,
    required List<String> supervisorIds,
    required List<String> staffIds,
    required int threshold,
    required String? lockedUntil,
    required int backdateDays,
  }) async {
    final uid = admin.uid;
    final start = today.subtract(Duration(days: s.startedDaysAgo));
    final end = start.add(Duration(days: s.durationDays));
    final holds = [
      for (final h in s.holds)
        {
          'start': _key(today.subtract(Duration(days: h.$1))),
          if (h.$2 != null) 'end': _key(today.subtract(Duration(days: h.$2!))),
        },
    ];
    final pausedDays = s.holds.fold(0, (total, h) => total + (h.$1 - (h.$2 ?? 0)));
    // The plan runs on the paused clock, exactly as ProjectAnalysis does.
    final clock = today.subtract(Duration(days: pausedDays));
    final contract = (s.valueCr * 1e7 * 100).round();
    final totalBudget = (contract * 0.82).round();
    final memberIds = {?managerId, ...supervisorIds, ...staffIds}.toList();

    // ---- batch 1: project + phases ----
    final project = _projects.doc();
    final b1 = _db.batch();
    b1.set(project, {
      'name': s.name,
      'nameLower': s.name.toLowerCase(),
      'code': s.code,
      'clientName': s.client,
      'city': s.city,
      'address': '${s.city}, ${s.state}',
      'typeId': s.typeId,
      'contractValuePaise': contract,
      'startDate': _key(start),
      'endDate': _key(end),
      'managerId': managerId,
      'supervisorIds': supervisorIds,
      'memberIds': memberIds,
      'custom': <String, dynamic>{},
      'statusId': statusId,
      'stage': s.stage.name,
      'statusIndex': statusIndex,
      'revision': 0,
      'statusHistory': [
        {'statusId': statusId, 'at': Timestamp.now(), 'by': uid, 'note': 'Demo data'},
      ],
      'holdPeriods': holds,
      'plannedPct': 0,
      'actualPct': 0,
      'health': 'noData',
      'budgetTotalPaise': 0,
      'spentTotalPaise': 0,
      'demo': true,
      ...auditCreate(uid),
    });

    final template = DefaultConfig.phaseTemplates.first.phases;
    const shares = [0.06, 0.14, 0.30, 0.18, 0.16, 0.12, 0.04];
    final phases = <_SeedPhase>[];
    var cursor = 0.0;
    for (var i = 0; i < template.length; i++) {
      final pStart = start.add(Duration(days: (cursor * s.durationDays).round()));
      cursor += shares[i];
      // Phases overlap a little, like real sites.
      final overlap = i == 0 || i == template.length - 1 ? 0.0 : 0.03;
      final pEnd = start.add(Duration(days: ((cursor + overlap).clamp(0, 1) * s.durationDays).round()));
      final planned = pEnd.isAfter(pStart)
          ? (clock.difference(pStart).inDays / pEnd.difference(pStart).inDays * 100).clamp(0, 100).toDouble()
          : 0.0;
      final factor = s.phaseProgress[i] ?? s.progress;
      var actual = s.stage == ProjectStage.pipeline ? 0.0 : (planned * factor).clamp(0, 100).toDouble();
      if (planned >= 100 && clock.difference(pEnd).inDays > 25) actual = 100;
      actual = actual.roundToDouble();
      final budget = (totalBudget * template[i].weight / 100).round();
      final ref = project.collection('phases').doc(template[i].id);
      phases.add(_SeedPhase(ref.id, template[i].name, pStart, pEnd, actual, budget, s.phaseCost[i] ?? s.cost));
      b1.set(ref, {
        'name': template[i].name,
        'order': i,
        'weight': template[i].weight,
        'plannedStart': _key(pStart),
        'plannedEnd': _key(pEnd),
        'actualPct': actual,
        'budgetPaise': budget,
        'delayReason': s.delayReasons[i] ?? '',
        'ownerId': managerId,
        ...auditCreate(uid),
      });
    }
    await b1.commit();

    if (s.stage == ProjectStage.pipeline) return;

    // ---- batch 2: budget, expenses, issues, daily reports ----
    final b2 = _db.batch();
    const categoryShare = {
      'labour': 0.24,
      'material': 0.44,
      'equipment': 0.10,
      'subcontract': 0.16,
      'overheads': 0.06,
    };
    for (final c in categoryShare.entries) {
      final planned = (totalBudget * c.value).round();
      b2.set(project.collection('budget').doc(c.key), {
        'plannedPaise': planned,
        'originalPaise': planned,
        'revisions': <Map<String, dynamic>>[],
        'revision': 1,
        ...auditCreate(uid),
      });
    }

    final toApprove = <DocumentReference<Map<String, dynamic>>>[];
    final activePhase = phases.lastWhere((p) => p.actual > 0, orElse: () => phases.first);
    var pendingLeft = s.pendingCount;
    var unpaidLeft = s.overdueUnpaid;
    for (final p in phases.where((p) => p.actual > 0)) {
      final target = (p.budget * p.actual / 100 * p.cost).round();
      final count = p.actual >= 100 ? 4 : 3;
      final last = today.isBefore(p.end) ? today : p.end;
      final spanDays = math.max(1, last.difference(p.start).inDays);
      var remaining = target;
      for (var k = 0; k < count; k++) {
        final share = k == count - 1 ? remaining : (target * (0.18 + _rand.nextDouble() * 0.14)).round();
        remaining -= share;
        final amount = (share ~/ 10000) * 10000; // whole ₹100s
        if (amount <= 0) continue;
        final vendor = _vendors[(p.id.hashCode + k) % _vendors.length];
        final date = p.start.add(Duration(days: ((k + 1) / (count + 0.5) * spanDays).round()));
        final dateKey = _key(date.isAfter(today) ? today : date);
        final pending = p.id == activePhase.id && k >= count - 2 && pendingLeft > 0;
        if (pending) pendingLeft--;
        // Bills over 30 days old are normally paid; a few stay unpaid on the
        // troubled projects so overdue payables show up. Recent ones are unpaid.
        final billDay = date.isAfter(today) ? today : date;
        final age = today.difference(billDay).inDays;
        var paid = !pending && age > 30;
        if (paid && age <= 80 && unpaidLeft > 0) {
          paid = false;
          unpaidLeft--;
        }
        final auto = !pending && amount <= threshold;
        final ref = _db.collection('expenses').doc();
        b2.set(ref, {
          'projectId': project.id,
          'amountPaise': amount,
          'categoryId': vendor.$2,
          'phaseId': p.id,
          'payee': vendor.$1,
          'date': dateKey,
          'description': '${p.name}: ${vendor.$3}',
          'billPath': null,
          'billHash': null,
          'status': auto ? ExpenseStatus.approved.value : ExpenseStatus.pending.value,
          'thresholdAtSubmit': threshold,
          'flags': <String>[],
          'approvedBy': auto ? 'system' : null,
          'custom': <String, dynamic>{},
          'submittedBy': uid,
          'submittedAt': FieldValue.serverTimestamp(),
          if (paid) ...{
            'paidAt': Timestamp.fromDate(billDay.add(Duration(days: 12 + _rand.nextInt(14)))),
            'paidBy': uid,
            'paymentRef': 'UTR${900000 + _rand.nextInt(99999)}',
          },
          if (lockedUntil != null && dateKey.compareTo(lockedUntil) <= 0)
            'lockOverrideReason': 'Demo data',
          'revision': 1,
          'demo': true,
          ...auditCreate(uid),
        });
        if (!auto && !pending) toApprove.add(ref);
      }
    }

    for (final issue in s.issues) {
      b2.set(project.collection('issues').doc(), {
        'title': issue.$1,
        'description': issue.$2,
        'priorityId': issue.$3,
        'status': issue.$4,
        'assigneeId': managerId,
        'reportedAt': Timestamp.fromDate(today.subtract(Duration(days: issue.$5))),
        ...auditCreate(uid),
      });
    }

    if (s.stage == ProjectStage.ongoing) {
      final unit = _units[phases.indexOf(activePhase) % _units.length];
      final days = math.max(0, backdateDays - 1);
      for (var d = days; d >= 0; d--) {
        final date = today.subtract(Duration(days: d));
        if (date.weekday == DateTime.sunday || s.missingReportDays.contains(d)) continue;
        final target = unit.$2;
        final achieved = (target * (s.output + (_rand.nextDouble() - 0.5) * 0.2)).clamp(0, target * 1.4).round();
        final key = _key(date);
        b2.set(project.collection('dprs').doc(key), {
          'date': key,
          'reportDay': Timestamp.fromDate(date),
          'targetQuantity': target,
          'achievedQuantity': achieved,
          'unit': unit.$1,
          'notes': '${activePhase.name}: ${_notes[(d + s.code.length) % _notes.length]}',
          'photoUrls': ['https://picsum.photos/seed/${s.code}-$key/640/480'],
          'flaggedAboveTarget': achieved > target * 1.5,
          'submittedLate': d > 0,
          'submittedAt': FieldValue.serverTimestamp(),
          'submittedBy': uid,
          ...auditCreate(uid),
        });
      }
    }
    ActivityEntry(
      actorId: uid,
      action: 'created',
      entity: 'demo',
      entityId: project.id,
      projectId: project.id,
      summary: 'Loaded demo data for ${s.name}',
    ).addTo(b2, _db);
    await b2.commit();

    // ---- batch 3: the CEO/admin approves the larger bills ----
    if (toApprove.isNotEmpty) {
      final b3 = _db.batch();
      for (final ref in toApprove) {
        b3.update(ref, {
          'status': ExpenseStatus.approved.value,
          'approvedBy': uid,
          'decidedBy': uid,
          'decidedAt': FieldValue.serverTimestamp(),
          'rejectReason': '',
          'revision': 2,
          ...auditUpdate(uid),
        });
      }
      await b3.commit();
    }

    await _seedStores(project, s, activePhase.id, today, uid);
  }

  /// Site stores through the real flow: indents raised (pending), most
  /// approved and received on a GRN, part issued to the work; one left
  /// waiting for approval, and on troubled projects one approved delivery
  /// that is now overdue and only part delivered.
  Future<void> _seedStores(
    DocumentReference<Map<String, dynamic>> project,
    _Scenario s,
    String phaseId,
    DateTime today,
    String uid,
  ) async {
    final indents = project.collection('indents');
    // (items, needed-by days from today, fate)
    final plan = <(List<(String, String, double, int)>, int, String)>[
      ([('Cement (OPC 53)', 'bags', 800, 42000), ('TMT steel', 'kg', 12000, 6800)], -45, 'received'),
      ([('River sand', 'cft', 2400, 5500), ('20mm aggregate', 'cft', 1800, 4800)], -25, 'received'),
      ([('Binding wire', 'kg', 300, 8500), ('Plywood shuttering', 'sheets', 120, 145000)], -12, 'received'),
      if (s.lateMaterial) ([('TMT steel', 'kg', 8000, 6900), ('Cement (OPC 53)', 'bags', 500, 42000)], -6, 'late'),
      ([('Red bricks', 'nos', 25000, 900), ('M-sand', 'cft', 1500, 5200)], 7, 'pending'),
    ];
    final refs = <DocumentReference<Map<String, dynamic>>>[];
    final b1 = _db.batch();
    for (var n = 0; n < plan.length; n++) {
      final (items, neededIn, _) = plan[n];
      final ref = indents.doc();
      refs.add(ref);
      b1.set(ref, {
        'number': 'IND-${s.code}-${(n + 1).toString().padLeft(3, '0')}',
        'items': [for (final it in items) {'material': it.$1, 'unit': it.$2, 'qty': it.$3}],
        'neededBy': _key(today.add(Duration(days: neededIn))),
        'phaseId': phaseId,
        'note': n == 0 ? 'For slab casting this month.' : '',
        'status': 'pending',
        'requestedBy': uid,
        'requestedAt': FieldValue.serverTimestamp(),
        'revision': 1,
        'demo': true,
        ...auditCreate(uid),
      });
    }
    await b1.commit();

    // Approve everything except the one left waiting.
    final b2 = _db.batch();
    for (var n = 0; n < plan.length; n++) {
      if (plan[n].$3 == 'pending') continue;
      b2.update(refs[n], {
        'status': 'approved',
        'decidedBy': uid,
        'decidedAt': FieldValue.serverTimestamp(),
        'decisionNote': 'Approved. Order from the rate-contract vendor.',
        'revision': 2,
        ...auditUpdate(uid),
      });
    }
    await b2.commit();

    // Receive the delivered ones and issue part of the stock to the work.
    const vendors = ['Sri Balaji Steel & Cement', 'Kaveri Aggregates', 'Hosur Hardware Mart'];
    final b3 = _db.batch();
    final issued = <String, (String, String, double)>{};
    for (var n = 0; n < plan.length; n++) {
      final (items, neededIn, fate) = plan[n];
      if (fate != 'received') continue;
      final grn = project.collection('grns').doc();
      final date = _key(today.add(Duration(days: neededIn + 1)));
      b3.set(grn, {
        'number': 'GRN-${s.code}-${(n + 1).toString().padLeft(3, '0')}',
        'items': [
          for (final it in items) {'material': it.$1, 'unit': it.$2, 'qty': it.$3, 'ratePaise': it.$4},
        ],
        'vendor': vendors[n % vendors.length],
        'invoiceNo': 'INV/${2600 + n * 37}',
        'date': date,
        'note': '',
        'indentId': refs[n].id,
        'receivedBy': uid,
        'revision': 1,
        'demo': true,
        ...auditCreate(uid),
      });
      b3.update(refs[n], {
        'status': 'received',
        'grnId': grn.id,
        'receivedAt': FieldValue.serverTimestamp(),
        'revision': 3,
        ...auditUpdate(uid),
      });
      for (final it in items) {
        final key = '${it.$1}|${it.$2}';
        final prev = issued[key]?.$3 ?? 0;
        issued[key] = (it.$1, it.$2, prev + it.$3);
      }
    }
    // A troubled project's late indent is part delivered: some steel came,
    // the rest is still awaited, so the indent stays open (and late).
    for (var n = 0; n < plan.length; n++) {
      final (items, neededIn, fate) = plan[n];
      if (fate != 'late') continue;
      final first = items.first;
      b3.set(project.collection('grns').doc(), {
        'number': 'GRN-${s.code}-${(n + 1).toString().padLeft(3, '0')}A',
        'items': [
          {'material': first.$1, 'unit': first.$2, 'qty': (first.$3 * 0.6).roundToDouble(), 'ratePaise': first.$4},
        ],
        'vendor': vendors[0],
        'invoiceNo': 'INV/${2600 + n * 37}',
        'date': _key(today.add(Duration(days: neededIn - 1))),
        'note': 'Part load. Balance promised next week.',
        'indentId': refs[n].id,
        'receivedBy': uid,
        'revision': 1,
        'demo': true,
        ...auditCreate(uid),
      });
    }
    // Issue most of what came in, some of it a while ago and some in the last
    // two weeks (which sets the rate of use and so the days of stock left). A
    // healthy project issues less; a busy one runs low on cement and steel.
    var slip = 0;
    void issue(String material, String unit, double qty, int daysAgo) {
      if (qty <= 0) return;
      slip++;
      b3.set(project.collection('materialIssues').doc(), {
        'number': 'MI-${s.code}-${slip.toString().padLeft(3, '0')}',
        'items': [
          {'material': material, 'unit': unit, 'qty': qty.roundToDouble()},
        ],
        'date': _key(today.subtract(Duration(days: daysAgo))),
        'phaseId': phaseId,
        'issuedTo': slip.isEven ? 'Murugan shuttering crew' : 'Ramesh labour gang',
        'note': '',
        'issuedBy': uid,
        'revision': 1,
        'demo': true,
        ...auditCreate(uid),
      });
    }

    var m = 0;
    for (final e in issued.values) {
      m++;
      final critical = s.output < 0.95 && (e.$1.startsWith('Cement') || e.$1.startsWith('TMT'));
      final share = critical ? 0.95 : (s.output >= 0.95 ? 0.7 : 0.8);
      final recent = critical ? 0.4 : 0.25;
      issue(e.$1, e.$2, e.$3 * (share - recent), 18 + m % 5);
      issue(e.$1, e.$2, e.$3 * recent / 2, 9 + m % 3);
      issue(e.$1, e.$2, e.$3 * recent / 2, 1 + m % 3);
    }
    await b3.commit();
  }

  static String _key(DateTime d) => WorkDay.fromDate(d);
}

final demoSeederProvider = Provider<DemoSeeder>(
  (ref) => DemoSeeder(ref.watch(firestoreProvider), ref.watch(userRepositoryProvider)),
);

class _SeedPhase {
  _SeedPhase(this.id, this.name, this.start, this.end, this.actual, this.budget, this.cost);
  final String id;
  final String name;
  final DateTime start;
  final DateTime end;
  final double actual;
  final int budget;
  final double cost;
}

class _Scenario {
  const _Scenario({
    required this.name,
    required this.code,
    required this.client,
    required this.city,
    required this.state,
    required this.typeId,
    required this.valueCr,
    required this.startedDaysAgo,
    required this.durationDays,
    required this.stage,
    this.progress = 1.0,
    this.phaseProgress = const {},
    this.cost = 0.97,
    this.phaseCost = const {},
    this.holds = const [],
    this.delayReasons = const {},
    this.issues = const [],
    this.output = 0.95,
    this.missingReportDays = const {},
    this.pendingCount = 1,
    this.overdueUnpaid = 0,
    this.lateMaterial = false,
  });

  final String name, code, client, city, state, typeId;
  final double valueCr;
  final int startedDaysAgo, durationDays;
  final ProjectStage stage;

  /// Actual progress as a share of planned progress (1.0 = on plan).
  final double progress;
  final Map<int, double> phaseProgress;

  /// Spend as a share of (phase budget × progress). Above 1 overspends.
  final double cost;
  final Map<int, double> phaseCost;

  /// (started days ago, ended days ago or null if still on hold).
  final List<(int, int?)> holds;
  final Map<int, String> delayReasons;

  /// (title, description, priority, status, days ago).
  final List<(String, String, String, String, int)> issues;

  /// Daily output as a share of target.
  final double output;

  /// Days ago (0 = today) with no daily report.
  final Set<int> missingReportDays;
  final int pendingCount;

  /// Bills older than 30 days left unpaid (overdue payables).
  final int overdueUnpaid;

  /// Leave one approved material delivery overdue.
  final bool lateMaterial;
}

const _scenarios = [
  _Scenario(
    name: 'Green Meadows Villas',
    code: 'GMV-02',
    client: 'Green Meadows Developers',
    city: 'Mysuru',
    state: 'Karnataka',
    typeId: 'residential',
    valueCr: 18,
    startedDaysAgo: 210,
    durationDays: 420,
    stage: ProjectStage.ongoing,
    progress: 1.02,
    cost: 0.95,
    issues: [
      ('Curing water tanker delayed one day', 'Arranged an alternate tanker; no impact on schedule.', 'low', 'resolved', 12),
    ],
    output: 1.02,
  ),
  _Scenario(
    name: 'Lakeview Residency – Tower A',
    code: 'LVR-A',
    client: 'Lakeview Homes Pvt Ltd',
    city: 'Bengaluru',
    state: 'Karnataka',
    typeId: 'residential',
    valueCr: 42,
    startedDaysAgo: 300,
    durationDays: 540,
    stage: ProjectStage.ongoing,
    progress: 0.93,
    phaseProgress: {2: 0.86},
    delayReasons: {2: 'Shuttering material arrived late for floors 9–11; extra crew added from next week.'},
    issues: [
      ('Shuttering plywood shortage on 10th floor', 'Supplier short by 120 sheets. Alternate vendor quote requested.', 'high', 'in-progress', 6),
      ('Tower crane inspection due', 'Annual inspection certificate expires in 10 days.', 'medium', 'open', 3),
    ],
    output: 0.84,
    missingReportDays: {2},
    pendingCount: 2,
    overdueUnpaid: 1,
    lateMaterial: true,
  ),
  _Scenario(
    name: 'Chennapatna Tech Park – Phase 2',
    code: 'CTP-2',
    client: 'Chennapatna Infra LLP',
    city: 'Chennai',
    state: 'Tamil Nadu',
    typeId: 'commercial',
    valueCr: 68,
    startedDaysAgo: 360,
    durationDays: 600,
    stage: ProjectStage.ongoing,
    progress: 0.78,
    phaseProgress: {1: 1.0, 2: 0.7, 3: 0.55},
    cost: 1.0,
    phaseCost: {1: 1.18, 2: 1.12},
    holds: [(170, 145)],
    delayReasons: {
      2: 'Monsoon flooding stopped slab work for 3 weeks; rebar price hike delayed purchase approvals.',
      3: 'Masonry sub-contractor demobilised during the hold; replacement mobilising now.',
    },
    issues: [
      ('Rebar supply stalled – price escalation', 'Supplier asking 11% escalation. Needs CEO decision on revised PO.', 'critical', 'open', 9),
      ('Basement dewatering pump failure', 'Standby pump running; main pump sent for repair.', 'high', 'in-progress', 4),
      ('Labour shortfall after festival', 'Only 62 of 90 workers back on site.', 'high', 'open', 5),
    ],
    output: 0.66,
    missingReportDays: {1, 3, 4},
    pendingCount: 3,
    overdueUnpaid: 3,
    lateMaterial: true,
  ),
  _Scenario(
    name: 'Sri Lakshmi Logistics Warehouse',
    code: 'SLW-01',
    client: 'Sri Lakshmi Logistics',
    city: 'Hosur',
    state: 'Tamil Nadu',
    typeId: 'industrial',
    valueCr: 9.5,
    startedDaysAgo: 260,
    durationDays: 320,
    stage: ProjectStage.ongoing,
    progress: 0.97,
    cost: 1.0,
    phaseCost: {2: 1.22, 4: 1.15},
    delayReasons: {},
    issues: [
      ('PEB structure cost overrun', 'Steel rate increase added ₹38 L to the pre-engineered building package.', 'high', 'open', 15),
    ],
    output: 0.93,
  ),
  _Scenario(
    name: 'Marina Commercial Complex',
    code: 'MCC-01',
    client: 'Marina Estates',
    city: 'Chennai',
    state: 'Tamil Nadu',
    typeId: 'commercial',
    valueCr: 26,
    startedDaysAgo: 190,
    durationDays: 480,
    stage: ProjectStage.onHold,
    progress: 0.95,
    holds: [(38, null)],
    issues: [
      ('CMDA revised approval pending', 'Work paused until revised building plan approval is received.', 'critical', 'open', 38),
    ],
    pendingCount: 0,
  ),
  _Scenario(
    name: 'Riverside Hospital Block',
    code: 'RHB-T',
    client: 'Kaveri Health Trust',
    city: 'Srirangapatna',
    state: 'Karnataka',
    typeId: 'infrastructure',
    valueCr: 34,
    startedDaysAgo: -45,
    durationDays: 560,
    stage: ProjectStage.pipeline,
  ),
];

/// (payee, category, what was bought)
const _vendors = [
  ('UltraTech Cement Dealers', 'material', 'cement'),
  ('Sri Balaji Steel Traders', 'material', 'TMT rebar'),
  ('Ramesh Labour Contractors', 'labour', 'weekly labour payment'),
  ('Hosur JCB & Crane Rentals', 'equipment', 'equipment hire'),
  ('Kaveri Electricals', 'subcontract', 'electrical works bill'),
  ('Om Sai Plumbing Works', 'subcontract', 'plumbing works bill'),
  ('Lakshmi Tiles & Granite', 'material', 'tiles and granite'),
  ('Site office running costs', 'overheads', 'site office, power and security'),
  ('Murugan Shuttering Works', 'labour', 'shuttering labour'),
];

/// (unit, daily target) by phase order.
const _units = [
  ('m² cleared', 400),
  ('m³ excavated', 120),
  ('m³ concrete', 45),
  ('m² blockwork', 160),
  ('points wired', 90),
  ('m² finished', 220),
  ('items closed', 25),
];

const _notes = [
  'Work progressed as planned. Material stock adequate for 3 days.',
  'Rain in the afternoon slowed work for two hours.',
  'Concrete pour completed; curing started.',
  'Labour strength lower than required; contractor informed.',
  'Quality check done by site engineer, minor rework noted.',
  'Material delivery arrived late in the day.',
];
