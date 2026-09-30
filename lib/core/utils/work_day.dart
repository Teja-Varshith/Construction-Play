import 'package:intl/intl.dart';

/// A "working day" is a date string (YYYY-MM-DD) in the company's timezone.
///
/// Daily reports and attendance are keyed by it, so a report recorded late at
/// night or synced the next morning still lands on the right day, whatever the
/// phone's own timezone is.
class WorkDay {
  WorkDay._();

  /// India does not use daylight saving, so a fixed offset is exact.
  static const defaultUtcOffsetMinutes = 330;

  static String key(DateTime instant, {int utcOffsetMinutes = defaultUtcOffsetMinutes}) {
    final local = instant.toUtc().add(Duration(minutes: utcOffsetMinutes));
    return _fmt(local.year, local.month, local.day);
  }

  static String today({int utcOffsetMinutes = defaultUtcOffsetMinutes}) =>
      key(DateTime.now(), utcOffsetMinutes: utcOffsetMinutes);

  /// For values from a date picker, which have no meaningful time part.
  static String fromDate(DateTime date) => _fmt(date.year, date.month, date.day);

  static DateTime? tryParse(String? key) {
    if (key == null) return null;
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(key);
    if (m == null) return null;
    final d = DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
    // Reject impossible dates such as 2026-02-31, which DateTime would roll over.
    return fromDate(d) == key ? d : null;
  }

  static String display(String? key) {
    final d = tryParse(key);
    return d == null ? '—' : DateFormat('d MMM yyyy', 'en_IN').format(d);
  }

  static String _fmt(int y, int m, int d) =>
      '${y.toString().padLeft(4, '0')}-${m.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';
}
