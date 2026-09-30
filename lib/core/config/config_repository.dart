import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/data/session.dart';
import '../data/audit.dart';
import '../firebase/firebase_providers.dart';
import 'app_config.dart';
import 'config_models.dart';
import 'default_config.dart';

/// Thrown when another admin saved the same settings since they were loaded.
class ConfigConflictException implements Exception {
  @override
  String toString() =>
      'Someone else changed these settings while you were editing. Your screen has been refreshed; please make your change again.';
}

class ConfigRepository {
  ConfigRepository(this._db);

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _config => _db.collection('config');

  /// One listener for all config docs (about a dozen small documents).
  Stream<AppConfig> watch() => _config.snapshots().map((snap) => AppConfig.fromDocs({
        for (final d in snap.docs)
          if (d.id != 'bootstrap') d.id: d.data(),
      }));

  /// Saves one config document, refusing if it changed since [expectedRev].
  Future<void> save({
    required String docId,
    required Map<String, dynamic> data,
    required int expectedRev,
    required String uid,
    required String summary,
  }) async {
    final ref = _config.doc(docId);
    await _db.runTransaction((tx) async {
      final current = await tx.get(ref);
      final currentRev = (current.data()?['rev'] as num?)?.toInt() ?? 0;
      if (currentRev != expectedRev) throw ConfigConflictException();
      tx.set(ref, {...data, 'rev': currentRev + 1, ...auditUpdate(uid)}, SetOptions(merge: true));
      ActivityEntry(
        actorId: uid,
        action: 'updated',
        entity: 'config',
        entityId: docId,
        summary: summary,
      ).addToTransaction(tx, _db);
    });
  }

  Future<void> saveList(ConfigList list, List<ConfigItem> items, {required int expectedRev, required String uid}) =>
      save(
        docId: list.docId,
        data: {'items': items.map((i) => i.toMap()).toList()},
        expectedRev: expectedRev,
        uid: uid,
        summary: 'Updated ${list.title.toLowerCase()}',
      );

  Future<void> saveFields(FieldEntity entity, List<FieldDef> fields, {required int expectedRev, required String uid}) =>
      save(
        docId: entity.docId,
        data: {'items': fields.map((f) => f.toMap()).toList()},
        expectedRev: expectedRev,
        uid: uid,
        summary: 'Updated custom fields for ${entity.title.toLowerCase()}',
      );

  Future<void> savePhaseTemplates(List<PhaseTemplate> templates, {required int expectedRev, required String uid}) =>
      save(
        docId: 'phaseTemplates',
        data: {'items': templates.map((t) => t.toMap()).toList()},
        expectedRev: expectedRev,
        uid: uid,
        summary: 'Updated phase templates',
      );

  Future<void> saveCompany(CompanySettings company, {required int expectedRev, required String uid}) => save(
        docId: 'company',
        data: company.toMap(),
        expectedRev: expectedRev,
        uid: uid,
        summary: 'Updated company settings',
      );

  /// Default config docs, written in the same batch as the first admin.
  static Map<String, Map<String, dynamic>> defaultDocs(String companyName, String uid) {
    Map<String, dynamic> stamp(Map<String, dynamic> data) => {...data, 'rev': 1, ...auditCreate(uid)};
    return {
      'company': stamp(CompanySettings(name: companyName).toMap()),
      for (final l in ConfigList.values)
        l.docId: stamp({'items': DefaultConfig.list(l).map((i) => i.toMap()).toList()}),
      'phaseTemplates': stamp({'items': DefaultConfig.phaseTemplates.map((t) => t.toMap()).toList()}),
      for (final e in FieldEntity.values) e.docId: stamp({'items': <Map<String, dynamic>>[]}),
    };
  }
}

final configRepositoryProvider = Provider<ConfigRepository>(
  (ref) => ConfigRepository(ref.watch(firestoreProvider)),
);

/// Live config. Screens read `ref.watch(appConfigProvider)`.
/// Config is only readable by active users, so listen only once signed in.
final appConfigStreamProvider = StreamProvider<AppConfig>((ref) {
  final ready = ref.watch(sessionProvider.select((s) => s.isReady));
  if (!ready) return Stream.value(AppConfig.defaults);
  return ref.watch(configRepositoryProvider).watch();
});

/// Config with defaults while loading, so screens never wait on it.
final appConfigProvider = Provider<AppConfig>(
  (ref) => ref.watch(appConfigStreamProvider).value ?? AppConfig.defaults,
);
