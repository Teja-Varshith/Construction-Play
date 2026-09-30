import 'package:cloud_firestore/cloud_firestore.dart';

/// Tolerant readers for Firestore data.
///
/// The client will keep changing what a record holds, so a missing or
/// wrongly-typed field must never crash a screen. Every reader falls back to a
/// sensible default instead of throwing.
extension JsonRead on Map<String, dynamic> {
  String readString(String key, [String fallback = '']) {
    final v = this[key];
    if (v is String) return v;
    if (v == null) return fallback;
    return v.toString();
  }

  String? readStringOrNull(String key) {
    final v = this[key];
    if (v is String && v.isNotEmpty) return v;
    return null;
  }

  int readInt(String key, [int fallback = 0]) => readIntOrNull(key) ?? fallback;

  int? readIntOrNull(String key) {
    final v = this[key];
    if (v is int) return v;
    if (v is num) return v.round();
    if (v is String) return int.tryParse(v.trim());
    return null;
  }

  num? readNumOrNull(String key) {
    final v = this[key];
    if (v is num) return v;
    if (v is String) return num.tryParse(v.trim());
    return null;
  }

  bool readBool(String key, [bool fallback = false]) {
    final v = this[key];
    if (v is bool) return v;
    return fallback;
  }

  DateTime? readDateTime(String key) {
    final v = this[key];
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    return null;
  }

  List<String> readStringList(String key) {
    final v = this[key];
    if (v is List) return v.whereType<String>().toList();
    return const [];
  }

  List<Map<String, dynamic>> readMapList(String key) {
    final v = this[key];
    if (v is List) {
      return v.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
    }
    return const [];
  }

  Map<String, dynamic> readMap(String key) {
    final v = this[key];
    if (v is Map) return Map<String, dynamic>.from(v);
    return {};
  }
}
