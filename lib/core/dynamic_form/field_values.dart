import '../config/config_models.dart';
import '../utils/money.dart';
import '../utils/work_day.dart';

/// Pure helpers for custom field values, kept free of widgets so they can be
/// unit tested.
///
/// Storage format per type:
///   text, longText, phone -> String
///   number                -> num
///   money                 -> int paise
///   date                  -> 'YYYY-MM-DD'
///   select                -> option id (String)
///   multiSelect           -> list of option ids
///   toggle                -> bool
class FieldValues {
  FieldValues._();

  static bool isEmpty(Object? value) =>
      value == null ||
      (value is String && value.trim().isEmpty) ||
      (value is List && value.isEmpty);

  /// Returns an error message, or null when [value] is acceptable for [def].
  static String? validate(FieldDef def, Object? value) {
    if (isEmpty(value)) {
      // Toggles always have a value (false is an answer).
      if (def.required && def.type != FieldType.toggle) {
        return '${def.label} is required';
      }
      return null;
    }
    switch (def.type) {
      case FieldType.text:
      case FieldType.longText:
        if (value is! String) return 'Enter text';
        if (value.length > (def.type == FieldType.text ? 200 : 5000)) {
          return 'Too long';
        }
        return null;
      case FieldType.phone:
        if (value is! String) return 'Enter a phone number';
        final digits = value.replaceAll(RegExp(r'[\s\-()]'), '');
        if (!RegExp(r'^\+?\d{10,13}$').hasMatch(digits)) {
          return 'Enter a valid phone number';
        }
        return null;
      case FieldType.number:
        return value is num ? null : 'Enter a number';
      case FieldType.money:
        if (value is! int) return 'Enter an amount';
        return value < 0 ? 'Amount cannot be negative' : null;
      case FieldType.date:
        return value is String && WorkDay.tryParse(value) != null
            ? null
            : 'Pick a date';
      case FieldType.select:
        if (value is! String) return 'Pick an option';
        return def.options.any((o) => o.id == value)
            ? null
            : 'Pick an option from the list';
      case FieldType.multiSelect:
        if (value is! List) return 'Pick options';
        final ids = def.options.map((o) => o.id).toSet();
        return value.every((v) => v is String && ids.contains(v))
            ? null
            : 'Pick options from the list';
      case FieldType.toggle:
        return value is bool ? null : 'Choose yes or no';
    }
  }

  /// Validates every active field. Returns field id -> message.
  static Map<String, String> validateAll(
    List<FieldDef> defs,
    Map<String, dynamic> values,
  ) {
    final errors = <String, String>{};
    for (final def in defs.where((d) => !d.archived)) {
      final error = validate(def, values[def.id]);
      if (error != null) errors[def.id] = error;
    }
    return errors;
  }

  /// Human-readable value for detail screens and cards.
  static String display(FieldDef def, Object? value) {
    if (isEmpty(value)) return '—';
    String optionLabel(Object? id) =>
        def.options.where((o) => o.id == id).firstOrNull?.label ??
        id.toString();
    return switch (def.type) {
      FieldType.money => value is int ? Money.format(value) : value.toString(),
      FieldType.date =>
        value is String ? WorkDay.display(value) : 'Invalid date',
      FieldType.select => optionLabel(value),
      FieldType.multiSelect =>
        value is List ? value.map(optionLabel).join(', ') : value.toString(),
      FieldType.toggle => value == true ? 'Yes' : 'No',
      FieldType.number =>
        value is num && value == value.roundToDouble()
            ? value.toInt().toString()
            : value.toString(),
      _ => value.toString(),
    };
  }

  /// Converts text typed into a number box. Keeps whole numbers as int.
  static num? parseNumber(String text) {
    final s = text.replaceAll(',', '').trim();
    if (s.isEmpty) return null;
    final n = num.tryParse(s);
    if (n == null || n.isNaN || n.isInfinite) return null;
    return n == n.roundToDouble() && !s.contains('.') ? n.toInt() : n;
  }
}
