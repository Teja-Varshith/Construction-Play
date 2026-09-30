import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:chennapatanam/core/config/app_config.dart';
import 'package:chennapatanam/core/config/config_repository.dart';
import 'package:chennapatanam/core/theme/app_theme.dart';
import 'package:chennapatanam/features/auth/data/session.dart';
import 'package:chennapatanam/features/auth/domain/app_user.dart';
import 'package:chennapatanam/features/projects/data/project_repository.dart';
import 'package:chennapatanam/features/projects/data/project_detail_repository.dart';
import 'package:chennapatanam/features/projects/domain/project.dart';
import 'package:chennapatanam/features/projects/domain/project_detail.dart';
import 'package:chennapatanam/features/projects/presentation/project_overview_screen.dart';
import 'package:chennapatanam/features/projects/presentation/project_activity.dart';
import 'package:chennapatanam/features/users/data/user_repository.dart';

void main() {
  setUpAll(() => initializeDateFormatting('en_IN'));
  const project = Project(id: 'site', name: 'Lake House', statusId: 'ongoing', clientName: 'Client', city: 'Chennai', memberIds: ['manager']);
  Widget app(UserRole role) => ProviderScope(overrides: [
    currentUserProvider.overrideWithValue(AppUser(uid: role.name, name: 'Person', email: 'person@example.com', role: role, active: true)),
    appConfigProvider.overrideWithValue(AppConfig.defaults),
    projectProvider('site').overrideWith((ref) => Stream.value(project)),
    projectClockProvider.overrideWith((ref) => Stream.value(DateTime.utc(2026,9,6))),
    projectPhasesProvider('site').overrideWith((ref) => Stream.value([
      const ProjectPhase(id:'phase', name:'Structure', weight:10, plannedStart:'2026-09-01', plannedEnd:'2026-09-11', actualPct:20),
    ])),
    projectDprsProvider('site').overrideWith((ref) => Stream.value([])),
    projectIssuesProvider('site').overrideWith((ref) => Stream.value([])),
    projectDocumentsProvider('site').overrideWith((ref) => Stream.value([])),
    projectActivityProvider('site').overrideWith((ref) => Stream.value([])),
    allUsersProvider.overrideWith((ref) => Stream.value([])),
  ], child: MaterialApp(theme: AppTheme.light(), home: const ProjectOverviewScreen(projectId:'site')));

  testWidgets('CEO sees calculated overview without entry actions on mobile', (tester) async {
    tester.view.physicalSize = const Size(390, 844); tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app(UserRole.ceo)); await tester.pumpAndSettle();
    expect(find.text('3 days behind the plan'), findsOneWidget);
    // Overall progress and the single phase row both read 20%.
    expect(find.text('20%'), findsWidgets);
    expect(find.byTooltip('Project actions'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('manager can open the phase form and info tab renders', (tester) async {
    await tester.pumpWidget(app(UserRole.manager)); await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Project actions')); await tester.pumpAndSettle();
    await tester.tap(find.text('Add phase')); await tester.pumpAndSettle();
    expect(find.text('Phase name'), findsOneWidget);
    await tester.tap(find.text('Cancel')); await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Info'));
    await tester.tap(find.text('Info')); await tester.pumpAndSettle();
    expect(find.text('Project information'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
