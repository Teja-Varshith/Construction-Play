import 'package:cloud_firestore/cloud_firestore.dart';

/// Bump when a document shape changes in a way readers must know about.
const int kSchemaVersion = 1;

/// Stamps every new document. The security rules check these values.
Map<String, dynamic> auditCreate(String uid) => {
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': uid,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': uid,
      'schemaVersion': kSchemaVersion,
      'deleted': false,
    };

Map<String, dynamic> auditUpdate(String uid) => {
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': uid,
    };

/// One entry in the activity log (who did what, and what changed).
///
/// Write it in the same batch or transaction as the change itself, so the log
/// can never disagree with the data.
class ActivityEntry {
  ActivityEntry({
    required this.actorId,
    required this.action,
    required this.entity,
    required this.entityId,
    this.projectId,
    this.summary = '',
    this.changes,
  });

  final String actorId;
  final String action; // e.g. created, updated, archived, approved
  final String entity; // e.g. user, project, config
  final String entityId;
  final String? projectId;
  final String summary;
  final Map<String, dynamic>? changes;

  DocumentReference<Map<String, dynamic>> newRef(FirebaseFirestore db) =>
      db.collection('activity').doc();

  Map<String, dynamic> toMap() => {
        'actorId': actorId,
        'action': action,
        'entity': entity,
        'entityId': entityId,
        'projectId': ?projectId,
        'summary': summary,
        'changes': ?changes,
        'at': FieldValue.serverTimestamp(),
      };

  void addTo(WriteBatch batch, FirebaseFirestore db) => batch.set(newRef(db), toMap());

  void addToTransaction(Transaction tx, FirebaseFirestore db) => tx.set(newRef(db), toMap());
}
