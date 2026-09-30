import 'package:intl/intl.dart';

/// Money is always stored as whole paise (int). Never use doubles for amounts.
class Money {
  Money._();

  static final _rupees = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
  static final _withPaise = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);

  /// ₹12,50,000 (Indian digit grouping).
  static String format(int paise, {bool showPaise = false}) {
    if (showPaise) return _withPaise.format(paise / 100);
    return _rupees.format(paise ~/ 100 + ((paise % 100) >= 50 ? 1 : 0));
  }

  /// Short form for dashboards: ₹4.5 Cr, ₹12.5 L, ₹85,000.
  static String compact(int paise) {
    final sign = paise < 0 ? '-' : '';
    final rupees = paise.abs() / 100;
    if (rupees >= 1e7) return '$sign₹${_trim(rupees / 1e7)} Cr';
    if (rupees >= 1e5) return '$sign₹${_trim(rupees / 1e5)} L';
    return '$sign${format(paise.abs())}';
  }

  static String _trim(double v) {
    final fixed = v >= 100 ? v.toStringAsFixed(0) : v.toStringAsFixed(v >= 10 ? 1 : 2);
    return fixed.contains('.') ? fixed.replaceFirst(RegExp(r'\.?0+$'), '') : fixed;
  }

  /// Parses what a person types ("12,50,000", "₹ 999.5") into paise.
  /// Returns null for anything that is not a valid amount.
  static int? parse(String input) {
    final s = input.replaceAll(RegExp(r'[₹,\s]'), '');
    if (s.isEmpty) return null;
    final m = RegExp(r'^(-?)(\d{1,13})(?:\.(\d{0,2}))?$').firstMatch(s);
    if (m == null) return null;
    final whole = int.parse(m[2]!);
    final frac = int.parse((m[3] ?? '').padRight(2, '0'));
    final value = whole * 100 + frac;
    return m[1] == '-' ? -value : value;
  }

  /// Text to pre-fill an input with: "1250000" or "999.50".
  static String toInput(int paise) {
    final sign = paise < 0 ? '-' : '';
    final abs = paise.abs();
    final rest = abs % 100;
    return rest == 0 ? '$sign${abs ~/ 100}' : '$sign${abs ~/ 100}.${rest.toString().padLeft(2, '0')}';
  }
}
