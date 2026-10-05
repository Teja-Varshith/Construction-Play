import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/work_day.dart';

const _line = AppColors.line;
const _muted = AppColors.muted;

/// Month view of daily reports: green = submitted, red = missing on a working
/// day the site should have reported. Sundays are treated as the weekly off
/// until per-project calendars exist.
class DprCalendar extends StatefulWidget {
  const DprCalendar({
    super.key,
    required this.reportDays,
    required this.today,
    required this.selected,
    required this.onSelect,
    this.expectFrom,
    this.expectReports = true,
  });

  final Set<String> reportDays;
  final String today;
  final String? selected;
  final ValueChanged<String?> onSelect;

  /// First working day a report is expected (the project's start date).
  final String? expectFrom;

  /// False for projects that are not ongoing, so no day shows as missing.
  final bool expectReports;

  @override
  State<DprCalendar> createState() => _DprCalendarState();
}

class _DprCalendarState extends State<DprCalendar> {
  late DateTime _month = _firstOf(
    WorkDay.tryParse(widget.selected ?? widget.today)!,
  );

  static DateTime _firstOf(DateTime d) => DateTime(d.year, d.month, 1);

  bool _missing(String key, DateTime day) {
    if (!widget.expectReports || widget.reportDays.contains(key)) return false;
    if (day.weekday == DateTime.sunday) return false;
    // Today's report may still come in.
    if (key.compareTo(widget.today) >= 0) return false;
    final from = widget.expectFrom;
    return from != null && key.compareTo(from) >= 0;
  }

  @override
  Widget build(BuildContext context) {
    final today = WorkDay.tryParse(widget.today)!;
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final leading = _month.weekday - 1; // Monday first
    final cells = <DateTime?>[
      for (var i = 0; i < leading; i++) null,
      for (var d = 1; d <= daysInMonth; d++)
        DateTime(_month.year, _month.month, d),
    ];
    var submitted = 0;
    var missing = 0;
    for (final d in cells.whereType<DateTime>()) {
      final key = WorkDay.fromDate(d);
      if (widget.reportDays.contains(key)) submitted++;
      if (_missing(key, d)) missing++;
    }
    final atCurrentMonth =
        _month.year == today.year && _month.month == today.month;

    return Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    iconSize: 20,
                    tooltip: 'Previous month',
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () => setState(
                      () => _month = DateTime(_month.year, _month.month - 1, 1),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          DateFormat('MMMM yyyy', 'en_IN').format(_month),
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        Text(
                          '$submitted submitted${widget.expectReports ? ' · $missing missing' : ''}',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: missing > 0
                                    ? context.statusColors.bad
                                    : _muted,
                              ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    iconSize: 20,
                    tooltip: 'Next month',
                    icon: const Icon(Icons.chevron_right),
                    onPressed: atCurrentMonth
                        ? null
                        : () => setState(
                            () => _month = DateTime(
                              _month.year,
                              _month.month + 1,
                              1,
                            ),
                          ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (final d in const ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
                    Expanded(
                      child: Center(
                        child: Text(
                          d,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: _muted),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              GridView.count(
                crossAxisCount: 7,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 1.0,
                children: [
                  for (final d in cells)
                    if (d == null)
                      const SizedBox.shrink()
                    else
                      _dayCell(context, d, today),
                ],
              ),
              if (widget.selected != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => widget.onSelect(null),
                    child: const Text('Show all reports'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dayCell(BuildContext context, DateTime d, DateTime today) {
    final key = WorkDay.fromDate(d);
    final has = widget.reportDays.contains(key);
    final missing = _missing(key, d);
    final isToday = key == widget.today;
    final selected = key == widget.selected;
    final future = d.isAfter(today);
    final dot = has
        ? context.statusColors.ok
        : (missing ? context.statusColors.bad : null);
    final primary = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.all(2),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: future ? null : () => widget.onSelect(selected ? null : key),
        child: Container(
          decoration: BoxDecoration(
            color: selected ? primary.withValues(alpha: 0.12) : null,
            borderRadius: BorderRadius.circular(6),
            border: isToday ? Border.all(color: primary, width: 1.5) : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${d.day}',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: isToday || selected
                      ? FontWeight.w800
                      : FontWeight.w500,
                  color: future ? AppColors.subtle : null,
                ),
              ),
              const SizedBox(height: 2),
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  color: dot ?? Colors.transparent,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
