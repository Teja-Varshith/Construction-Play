import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/config_models.dart';
import '../../../core/config/config_repository.dart';
import '../../../core/utils/work_day.dart';
import '../../finance/data/finance_repository.dart';
import '../../inventory/data/inventory_repository.dart';
import '../domain/project_insight.dart';
import 'project_detail_repository.dart';
import 'project_repository.dart';

/// Everything about one project, recomputed whenever any source changes.
final projectInsightProvider =
    Provider.family<AsyncValue<ProjectInsight>, String>((ref, projectId) {
      final config = ref.watch(appConfigProvider);
      final clock = ref.watch(projectClockProvider).value ?? DateTime.now();
      final project = ref.watch(projectProvider(projectId));
      final phases = ref.watch(projectPhasesProvider(projectId));
      final expenses = ref.watch(projectExpensesProvider(projectId));
      final budget = ref.watch(projectBudgetProvider(projectId));
      final issues = ref.watch(projectIssuesProvider(projectId));
      final reports = ref.watch(projectDprsProvider(projectId));
      final indents = ref.watch(projectIndentsProvider(projectId));
      final inventory = ref.watch(projectInventoryProvider(projectId));
      for (final AsyncValue<Object?> source in [
        project,
        phases,
        expenses,
        budget,
        issues,
        reports,
        indents,
        inventory,
      ]) {
        if (source.hasError) {
          return AsyncError(
            source.error!,
            source.stackTrace ?? StackTrace.current,
          );
        }
        if (!source.hasValue) return const AsyncLoading();
      }
      final p = project.requireValue;
      if (p == null) return const AsyncLoading();
      return AsyncData(
        ProjectInsight.calculate(
          project: p,
          stage: config.stageOfStatus(p.statusId),
          phases: phases.requireValue,
          today: WorkDay.key(
            clock,
            utcOffsetMinutes: config.company.utcOffsetMinutes,
          ),
          expenses: expenses.requireValue,
          budget: budget.requireValue,
          issues: issues.requireValue,
          reports: reports.requireValue,
          indents: indents.requireValue,
          stock: inventory.requireValue.stock,
          priorityLabel: (id) => config.labelOf(ConfigList.issuePriorities, id),
        ),
      );
    });

/// Insight for every visible project. Loads while any project is loading, so
/// the CEO never sees half a portfolio's totals.
final portfolioInsightProvider = Provider<AsyncValue<PortfolioInsight>>((ref) {
  final projects = ref.watch(rawVisibleProjectsProvider);
  if (projects.hasError) {
    return AsyncError(
      projects.error!,
      projects.stackTrace ?? StackTrace.current,
    );
  }
  if (!projects.hasValue) return const AsyncLoading();
  // Watch every project first so they all load in parallel.
  final feeds = [
    for (final p in projects.requireValue) ref.watch(projectInsightProvider(p.id)),
  ];
  final result = <ProjectInsight>[];
  for (final insight in feeds) {
    if (insight.hasError) {
      return AsyncError(
        insight.error!,
        insight.stackTrace ?? StackTrace.current,
      );
    }
    if (!insight.hasValue) return const AsyncLoading();
    result.add(insight.requireValue);
  }
  return AsyncData(PortfolioInsight(result));
});
