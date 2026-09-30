import '../../../core/config/config_models.dart';
import '../../../core/utils/work_day.dart';
import 'project.dart';
import 'project_detail.dart';

/// Derived from source phases at read time. No client-written health totals.
class ProjectAnalysis {
  const ProjectAnalysis(
    this.planned,
    this.actual,
    this.health,
    this.incomplete,
    this.daysBehind, [
    this.pausedDays = 0,
  ]);
  final double planned;
  final double actual;
  final ProjectHealth health;
  final bool incomplete;
  final int daysBehind;

  /// Days spent on hold up to today. The planned clock is paused for these,
  /// so they push the finish date out without counting as "behind".
  final int pausedDays;
  double get gap => (planned - actual).clamp(0, 100);

  static DateTime day(String value) {
    final d = WorkDay.tryParse(value)!;
    return DateTime.utc(d.year, d.month, d.day);
  }

  static double plannedFor(ProjectPhase phase, DateTime date) {
    if (!phase.hasValidDates) return 0;
    final start = day(phase.plannedStart!);
    final end = day(phase.plannedEnd!);
    return (date.difference(start).inDays / end.difference(start).inDays * 100)
        .clamp(0, 100);
  }

  factory ProjectAnalysis.calculate(
    Project project,
    List<ProjectPhase> source,
    ProjectStage stage,
    String today,
  ) {
    final phases = source
        .where((p) => !p.deleted && p.weight > 0 && p.weight.isFinite)
        .toList();
    final incomplete = phases.isEmpty || phases.any((p) => !p.hasValidDates);
    final total = phases.fold(0.0, (sum, p) => sum + p.weight);
    if (total == 0) {
      return const ProjectAnalysis(0, 0, ProjectHealth.noData, true, 0);
    }
    var date = day(today);
    var pausedDays = 0;
    for (final hold in project.holdPeriods) {
      final start = WorkDay.tryParse(hold['start'] as String?);
      final end = WorkDay.tryParse(hold['end'] as String?) ?? date;
      if (start != null) {
        final until = end.isAfter(date) ? date : end;
        pausedDays += until.difference(start).inDays.clamp(0, 100000);
      }
    }
    date = date.subtract(Duration(days: pausedDays));
    double plannedAt(DateTime d) =>
        phases.fold(0.0, (sum, p) => sum + p.weight * plannedFor(p, d)) / total;
    final actual =
        phases.fold(
          0.0,
          (sum, p) => sum + p.weight * p.actualPct.clamp(0, 100),
        ) /
        total;
    final planned = plannedAt(date);
    var daysBehind = 0;
    if (!incomplete && planned > actual) {
      final earliest = phases
          .map((p) => day(p.plannedStart!))
          .reduce((a, b) => a.isBefore(b) ? a : b);
      var low = 0;
      var high = date.difference(earliest).inDays.clamp(0, 100000);
      while (low < high) {
        final mid = (low + high + 1) ~/ 2;
        if (plannedAt(date.subtract(Duration(days: mid))) >= actual) {
          low = mid;
        } else {
          high = mid - 1;
        }
      }
      daysBehind = low;
    }
    final gap = planned - actual;
    final health = incomplete || stage != ProjectStage.ongoing
        ? ProjectHealth.noData
        : gap > 10 || daysBehind > 7
        ? ProjectHealth.red
        : gap > 3 || daysBehind > 2
        ? ProjectHealth.amber
        : ProjectHealth.green;
    return ProjectAnalysis(
      planned,
      actual,
      health,
      incomplete,
      daysBehind,
      pausedDays,
    );
  }
}
