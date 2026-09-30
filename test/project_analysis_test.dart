import 'package:flutter_test/flutter_test.dart';
import 'package:chennapatanam/core/config/config_models.dart';
import 'package:chennapatanam/features/projects/domain/project.dart';
import 'package:chennapatanam/features/projects/domain/project_detail.dart';
import 'package:chennapatanam/features/projects/domain/project_analysis.dart';

void main() {
  const project = Project(id: 'p', name: 'Site', statusId: 'ongoing');
  const phase = ProjectPhase(id: 'one', name: 'Structure', weight: 5,
    plannedStart: '2026-09-01', plannedEnd: '2026-09-11', actualPct: 50);
  test('weighted progress uses relative weights and calendar dates', () {
    final a = ProjectAnalysis.calculate(project, [phase,
      const ProjectPhase(id: 'two', name: 'Finish', weight: 15,
        plannedStart: '2026-09-01', plannedEnd: '2026-09-11', actualPct: 10)],
      ProjectStage.ongoing, '2026-09-06');
    expect(a.planned, 50);
    expect(a.actual, 20);
    expect(a.health, ProjectHealth.red);
    expect(a.daysBehind, 3);
  });
  test('missing and invalid phase dates never imply healthy work', () {
    final a = ProjectAnalysis.calculate(project, [phase,
      const ProjectPhase(id: 'two', name: 'Unscheduled', weight: 5)],
      ProjectStage.ongoing, '2026-09-06');
    expect(a.incomplete, isTrue);
    expect(a.health, ProjectHealth.noData);
    expect(const ProjectPhase(id: 'x', name: 'x', plannedStart: '2026-09-11', plannedEnd: '2026-09-01').hasValidDates, isFalse);
  });
  test('on hold freezes planned progress and resume retains paused days', () {
    const held = Project(id: 'p', name: 'Site', statusId: 'on-hold', holdPeriods: [{'start': '2026-09-04'}]);
    final a = ProjectAnalysis.calculate(held, [phase], ProjectStage.onHold, '2026-09-09');
    expect(a.planned, 30);
    expect(a.health, ProjectHealth.noData);
    const resumed = Project(id: 'p', name: 'Site', statusId: 'ongoing', holdPeriods: [{'start': '2026-09-04', 'end': '2026-09-09'}]);
    expect(ProjectAnalysis.calculate(resumed, [phase], ProjectStage.ongoing, '2026-09-11').planned, 50);
  });
  test('closed projects and pipeline do not appear at risk', () {
    for (final stage in [ProjectStage.completed, ProjectStage.cancelled, ProjectStage.pipeline]) {
      expect(ProjectAnalysis.calculate(project, [phase], stage, '2026-09-20').health, ProjectHealth.noData);
    }
  });
  test('empty and archived phases cannot create a percentage', () {
    expect(ProjectAnalysis.calculate(project, [], ProjectStage.ongoing, '2026-09-06').incomplete, isTrue);
    expect(ProjectAnalysis.calculate(project, [const ProjectPhase(id: 'x', name: 'old', weight: 100, deleted: true)], ProjectStage.ongoing, '2026-09-06').actual, 0);
  });
}
