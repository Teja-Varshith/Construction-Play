import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/config_models.dart';
import '../utils/money.dart';
import '../utils/work_day.dart';
import 'field_values.dart';

/// Renders custom fields defined in config. Put it inside a [Form]; each field
/// validates itself when the form is validated.
///
/// Only changed keys are reported through [onChanged], so values of archived
/// or unknown fields already on the record are left untouched.
class DynamicFields extends StatelessWidget {
  const DynamicFields({
    super.key,
    required this.fields,
    required this.values,
    required this.onChanged,
    this.enabled = true,
  });

  final List<FieldDef> fields;
  final Map<String, dynamic> values;
  final void Function(String fieldId, Object? value) onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final active = fields.where((f) => !f.archived).toList();
    if (active.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final f in active)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _DynamicField(
              key: ValueKey('custom-${f.id}'),
              def: f,
              value: values[f.id],
              enabled: enabled,
              onChanged: (v) => onChanged(f.id, v),
            ),
          ),
      ],
    );
  }
}

class _DynamicField extends StatelessWidget {
  const _DynamicField({
    super.key,
    required this.def,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final FieldDef def;
  final Object? value;
  final bool enabled;
  final ValueChanged<Object?> onChanged;

  String get _label => def.required ? '${def.label} *' : def.label;
  String? get _help => def.help.isEmpty ? null : def.help;

  @override
  Widget build(BuildContext context) {
    switch (def.type) {
      case FieldType.text:
      case FieldType.longText:
      case FieldType.phone:
        return TextFormField(
          initialValue: value is String ? value as String : null,
          enabled: enabled,
          maxLines: def.type == FieldType.longText ? 4 : 1,
          keyboardType: def.type == FieldType.phone ? TextInputType.phone : null,
          decoration: InputDecoration(labelText: _label, helperText: _help),
          onChanged: (t) => onChanged(t.trim().isEmpty ? null : t.trim()),
          validator: (t) => FieldValues.validate(def, (t ?? '').trim().isEmpty ? null : t!.trim()),
        );
      case FieldType.number:
        return TextFormField(
          initialValue: value is num ? FieldValues.display(def, value) : null,
          enabled: enabled,
          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
          decoration: InputDecoration(labelText: _label, helperText: _help),
          onChanged: (t) => onChanged(FieldValues.parseNumber(t)),
          validator: (t) {
            if ((t ?? '').trim().isNotEmpty && FieldValues.parseNumber(t!) == null) return 'Enter a number';
            return FieldValues.validate(def, FieldValues.parseNumber(t ?? ''));
          },
        );
      case FieldType.money:
        return MoneyFormField(
          label: _label,
          helperText: _help,
          initialPaise: value is int ? value as int : null,
          enabled: enabled,
          onChanged: onChanged,
          validator: (paise) => FieldValues.validate(def, paise),
        );
      case FieldType.date:
        return DateFormField(
          label: _label,
          helperText: _help,
          initialKey: value is String ? value as String : null,
          enabled: enabled,
          onChanged: onChanged,
          validator: (key) => FieldValues.validate(def, key),
        );
      case FieldType.select:
        final current = value is String ? value as String : null;
        // Keep a stored value visible even if its option was archived since.
        final options = def.options.where((o) => !o.archived || o.id == current).toList();
        return DropdownButtonFormField<String>(
          initialValue: options.any((o) => o.id == current) ? current : null,
          isExpanded: true,
          decoration: InputDecoration(labelText: _label, helperText: _help),
          items: [
            if (!def.required) const DropdownMenuItem<String>(value: null, child: Text('—')),
            for (final o in options) DropdownMenuItem(value: o.id, child: Text(o.label)),
          ],
          onChanged: enabled ? onChanged : null,
          validator: (v) => FieldValues.validate(def, v),
        );
      case FieldType.multiSelect:
        final selected = value is List ? (value as List).whereType<String>().toList() : <String>[];
        return FormField<List<String>>(
          initialValue: selected,
          validator: (v) => FieldValues.validate(def, v),
          builder: (state) {
            final picked = state.value ?? const [];
            final options = def.options.where((o) => !o.archived || picked.contains(o.id)).toList();
            return InputDecorator(
              decoration: InputDecoration(
                labelText: _label,
                helperText: _help,
                errorText: state.errorText,
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final o in options)
                    FilterChip(
                      label: Text(o.label),
                      selected: picked.contains(o.id),
                      onSelected: !enabled
                          ? null
                          : (on) {
                              final next = [...picked];
                              on ? next.add(o.id) : next.remove(o.id);
                              state.didChange(next);
                              onChanged(next.isEmpty ? null : next);
                            },
                    ),
                ],
              ),
            );
          },
        );
      case FieldType.toggle:
        return FormField<bool>(
          initialValue: value == true,
          builder: (state) => SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(def.label),
            subtitle: _help == null ? null : Text(_help!),
            value: state.value ?? false,
            onChanged: !enabled
                ? null
                : (v) {
                    state.didChange(v);
                    onChanged(v);
                  },
          ),
        );
    }
  }
}

/// Rupee input that stores whole paise. Reusable outside custom fields.
class MoneyFormField extends StatelessWidget {
  const MoneyFormField({
    super.key,
    required this.label,
    required this.onChanged,
    this.initialPaise,
    this.helperText,
    this.enabled = true,
    this.validator,
  });

  final String label;
  final String? helperText;
  final int? initialPaise;
  final bool enabled;
  final ValueChanged<int?> onChanged;
  final String? Function(int? paise)? validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: initialPaise == null ? null : Money.toInput(initialPaise!),
      enabled: enabled,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
      decoration: InputDecoration(labelText: label, helperText: helperText, prefixText: '₹ '),
      onChanged: (t) => onChanged(Money.parse(t)),
      validator: (t) {
        final text = (t ?? '').trim();
        final paise = Money.parse(text);
        if (text.isNotEmpty && paise == null) return 'Enter a valid amount, like 125000 or 999.50';
        return validator?.call(paise);
      },
    );
  }
}

/// Date picker field that stores a 'YYYY-MM-DD' key.
class DateFormField extends StatelessWidget {
  const DateFormField({
    super.key,
    required this.label,
    required this.onChanged,
    this.initialKey,
    this.helperText,
    this.enabled = true,
    this.validator,
    this.firstDate,
    this.lastDate,
  });

  final String label;
  final String? helperText;
  final String? initialKey;
  final bool enabled;
  final ValueChanged<String?> onChanged;
  final String? Function(String? key)? validator;
  final DateTime? firstDate;
  final DateTime? lastDate;

  @override
  Widget build(BuildContext context) {
    return FormField<String>(
      initialValue: initialKey,
      validator: validator,
      builder: (state) {
        Future<void> pick() async {
          final now = DateTime.now();
          final picked = await showDatePicker(
            context: context,
            initialDate: WorkDay.tryParse(state.value) ?? now,
            firstDate: firstDate ?? DateTime(now.year - 20),
            lastDate: lastDate ?? DateTime(now.year + 20),
          );
          if (picked == null) return;
          final key = WorkDay.fromDate(picked);
          state.didChange(key);
          onChanged(key);
        }

        return InkWell(
          onTap: enabled ? pick : null,
          borderRadius: BorderRadius.circular(8),
          child: InputDecorator(
            isEmpty: state.value == null,
            decoration: InputDecoration(
              labelText: label,
              helperText: helperText,
              errorText: state.errorText,
              enabled: enabled,
              suffixIcon: state.value != null && enabled
                  ? IconButton(
                      tooltip: 'Clear date',
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        state.didChange(null);
                        onChanged(null);
                      },
                    )
                  : const Icon(Icons.calendar_today_outlined),
            ),
            child: Text(state.value == null ? '' : WorkDay.display(state.value)),
          ),
        );
      },
    );
  }
}
