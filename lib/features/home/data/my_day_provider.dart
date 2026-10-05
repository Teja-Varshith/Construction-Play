import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/config_models.dart';
import '../../../core/config/config_repository.dart';
import '../../../core/utils/work_day.dart';
import '../../auth/data/session.dart';
import '../../finance/data/finance_repository.dart';
import '../../finance/domain/expense.dart';
import '../../inventory/data/inventory_repository.dart';
import '../../inventory/domain/inventory.dart';
import '../../projects/data/project_detail_repository.dart';
import '../../projects/data/project_insight_provider.dart';
import '../../projects/data/project_repository.dart';
import '../../projects/domain/project_insight.dart';
import '../../projects/presentation/project_record_actions.dart';
import '../domain/my_day.dart';

/// One of my projects on the My day screen.
class MyProject {
  const MyProject({required this.insight, required this.access, required this.reportedToday, required this.taskCount});

  final ProjectInsight insight;
  final DayAccess access;
  final bool reportedToday;
  final int taskCount;
}

class MyDayData {
  const MyDayData({required this.tasks, required this.projects, required this.today});

  final List<DayTask> tasks;

  /// Ongoing projects first, then by how much needs doing.
  final List<MyProject> projects;
  final String today;
}

/// Tasks for the signed-in user across every project they belong to,
/// recomputed from the project records whenever any of them changes.
final myDayProvider = Provider<AsyncValue<MyDayData>>((ref) {
  final user = ref.watch(currentUserProvider);
  final config = ref.watch(appConfigProvider);
  final clock = ref.watch(projectClockProvider).value ?? DateTime.now();
  final today = WorkDay.key(clock, utcOffsetMinutes: config.company.utcOffsetMinutes);
  final projects = ref.watch(visibleProjectsProvider);
  if (projects.hasError) return AsyncError(projects.error!, projects.stackTrace ?? StackTrace.current);
  if (!projects.hasValue) return const AsyncLoading();

  final tasks = <DayTask>[];
  final mine = <MyProject>[];
  for (final p in projects.requireValue.where((p) => p.memberIds.contains(user.uid))) {
    final stage = config.stageOfStatus(p.statusId);
    final access = DayAccess(
      report: canReportProject(user, p),
      manage: canManageProject(user, p),
      seeMoney: canSeeMoney(user, p, stage),
    );
    final insight = ref.watch(projectInsightProvider(p.id));
    final reports = ref.watch(projectDprsProvider(p.id));
    // Without reports we cannot tell whether today's is done; wait for them.
    if (reports.hasError || insight.hasError) continue;
    if (!reports.hasValue || !insight.hasValue) return const AsyncLoading();
    final issues = ref.watch(projectIssuesProvider(p.id)).value ?? const [];
    final inventory = ref.watch(projectInventoryProvider(p.id)).value;
    final grns = access.manage ? ref.watch(projectGrnsProvider(p.id)).value ?? const <Grn>[] : const <Grn>[];
    final expenses = access.manage && access.seeMoney
        ? ref.watch(projectExpensesProvider(p.id)).value ?? const <Expense>[]
        : const <Expense>[];
    final projectTasks = MyDay.forProject(
      uid: user.uid,
      project: p,
      stage: stage,
      access: access,
      today: today,
      backdateDays: config.company.dprBackdateDays,
      reports: reports.requireValue,
      issues: issues,
      insight: insight.requireValue,
      inventory: inventory,
      grns: grns,
      expenses: expenses,
      now: clock,
    );
    tasks.addAll(projectTasks);
    mine.add(MyProject(
      insight: insight.requireValue,
      access: access,
      reportedToday: reports.requireValue.any((r) => r.date == today),
      taskCount: projectTasks.length,
    ));
  }
  mine.sort((a, b) {
    int rank(MyProject p) => p.insight.stage == ProjectStage.ongoing ? -1 : p.insight.stage.index;
    final byStage = rank(a).compareTo(rank(b));
    return byStage != 0 ? byStage : b.taskCount.compareTo(a.taskCount);
  });
  return AsyncData(MyDayData(tasks: MyDay.sorted(tasks), projects: mine, today: today));
});
