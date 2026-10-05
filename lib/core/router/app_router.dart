import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/data/session.dart';
import '../../features/auth/presentation/account_issue_screen.dart';
import '../../features/auth/presentation/forgot_password_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/setup_screen.dart';
import '../../features/auth/presentation/splash_screen.dart';
import '../../features/finance/presentation/approvals_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/projects/presentation/ceo_portfolio_screen.dart';
import '../../features/projects/presentation/project_create_screen.dart';
import '../../features/projects/presentation/project_overview_screen.dart';
import '../../features/settings/presentation/company_settings_screen.dart';
import '../../features/settings/presentation/custom_fields_screen.dart';
import '../../features/settings/presentation/list_editor_screen.dart';
import '../../features/settings/presentation/phase_templates_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/users/presentation/user_form_screen.dart';
import '../../features/users/presentation/users_screen.dart';
import '../config/config_models.dart';
import 'app_shell.dart';
import 'nav.dart';

const _publicRoutes = {'/login', '/forgot-password'};

/// Decides where a person may be, given their session. Kept as a pure function
/// so it can be unit tested.
String? resolveRedirect({
  required Session session,
  required AsyncValue<bool> setupDone,
  required bool setupInProgress,
  required Uri uri,
}) {
  final loc = uri.path;
  final from = uri.queryParameters['from'];

  if (loc == '/setup' && setupInProgress) return null;

  if (session.status == SessionStatus.loading ||
      (!setupDone.hasValue && !setupDone.hasError)) {
    return loc == '/splash'
        ? null
        : '/splash?from=${Uri.encodeComponent(uri.toString())}';
  }

  // If the check fails (e.g. offline), assume setup is done and show login.
  final needsSetup = setupDone.hasValue && setupDone.value == false;
  if (needsSetup && session.status == SessionStatus.signedOut) {
    return loc == '/setup' ? null : '/setup';
  }

  switch (session.status) {
    case SessionStatus.loading:
      return null;
    case SessionStatus.signedOut:
      if (_publicRoutes.contains(loc)) return null;
      final target = loc == '/splash' ? from : uri.toString();
      final keep =
          target != null &&
          target != '/' &&
          !target.startsWith('/splash') &&
          target != '/setup';
      return keep ? '/login?from=${Uri.encodeComponent(target)}' : '/login';
    case SessionStatus.noProfile:
    case SessionStatus.inactive:
      return loc == '/account-issue' ? null : '/account-issue';
    case SessionStatus.ready:
      if (loc == '/splash' ||
          loc == '/setup' ||
          loc == '/account-issue' ||
          _publicRoutes.contains(loc) ||
          loc == '/') {
        final target =
            from != null && from.startsWith('/') && !from.startsWith('/splash')
            ? from
            : '/home';
        return canAccess(session.user!.role, Uri.parse(target).path)
            ? target
            : '/home';
      }
      if (!canAccess(session.user!.role, loc)) return '/home';
      return null;
  }
}

class _RouterRefresh extends ChangeNotifier {
  void ping() => notifyListeners();
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefresh();
  ref.listen(sessionProvider, (_, _) => refresh.ping());
  ref.listen(setupDoneProvider, (_, _) => refresh.ping());
  ref.listen(setupInProgressProvider, (_, _) => refresh.ping());
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/home',
    refreshListenable: refresh,
    debugLogDiagnostics: kDebugMode,
    redirect: (context, state) => resolveRedirect(
      session: ref.read(sessionProvider),
      setupDone: ref.read(setupDoneProvider),
      setupInProgress: ref.read(setupInProgressProvider),
      uri: state.uri,
    ),
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Page not found'),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => context.go('/home'),
              child: const Text('Go home'),
            ),
          ],
        ),
      ),
    ),
    routes: [
      GoRoute(path: '/', redirect: (_, _) => '/home'),
      GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/setup', builder: (_, _) => const SetupScreen()),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(
        path: '/forgot-password',
        builder: (_, state) => ForgotPasswordScreen(
          initialEmail: state.uri.queryParameters['email'],
        ),
      ),
      GoRoute(
        path: '/account-issue',
        builder: (_, _) => const AccountIssueScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) =>
            AppShell(location: state.uri.path, child: child),
        routes: [
          GoRoute(
            path: '/home',
            builder: (_, state) => HomeScreen(sort: state.uri.queryParameters['sort']),
          ),
          GoRoute(
            path: '/approvals',
            builder: (_, _) => const ApprovalsScreen(),
          ),
          GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen()),
          GoRoute(path: '/insights', builder: (_, _) => const PortfolioInsightsScreen()),
          // The portfolio tracker for managers, whose home is My day.
          GoRoute(
            path: '/portfolio',
            builder: (_, state) => CeoPortfolioScreen(sort: state.uri.queryParameters['sort']),
          ),
          GoRoute(path: '/watchlist', builder: (_, _) => const DelayWatchlistScreen()),
          GoRoute(path: '/organisation', builder: (_, _) => const OrganisationScreen()),
          GoRoute(
            path: '/users',
            builder: (_, _) => const UsersScreen(),
            routes: [
              GoRoute(path: 'new', builder: (_, _) => const UserFormScreen()),
              GoRoute(
                path: ':uid',
                builder: (_, state) =>
                    UserFormScreen(uid: state.pathParameters['uid']),
              ),
            ],
          ),
          GoRoute(
            path: '/projects',
            builder: (_, state) => ProjectListScreen(
              initialAtRisk:
                  state.uri.queryParameters['health'] == 'at-risk',
            ),
            routes: [
              GoRoute(
                path: 'new',
                builder: (_, _) => const ProjectCreateScreen(),
              ),
              GoRoute(
                path: 'stage/:stage',
                builder: (_, state) => ProjectListScreen(
                  stage: ProjectStage.values.firstWhere(
                    (stage) => stage.name == state.pathParameters['stage'],
                    orElse: () => ProjectStage.pipeline,
                  ),
                  initialAtRisk:
                      state.uri.queryParameters['health'] == 'at-risk',
                ),
              ),
              GoRoute(
                path: ':projectId',
                // ?tab=<slug>&focus=<what to investigate>; see ProjectLink.
                builder: (_, state) => ProjectOverviewScreen(
                  projectId: state.pathParameters['projectId']!,
                  tab: state.uri.queryParameters['tab'],
                  focus: state.uri.queryParameters['focus'],
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/settings',
            builder: (_, _) => const SettingsScreen(),
            routes: [
              GoRoute(
                path: 'company',
                builder: (_, _) => const CompanySettingsScreen(),
              ),
              GoRoute(
                path: 'phase-templates',
                builder: (_, _) => const PhaseTemplatesScreen(),
              ),
              GoRoute(
                path: 'lists/:list',
                builder: (_, state) {
                  final list = ConfigList.fromName(
                    state.pathParameters['list'],
                  );
                  return list == null
                      ? const SettingsScreen()
                      : ListEditorScreen(list: list);
                },
              ),
              GoRoute(
                path: 'fields/:entity',
                builder: (_, state) {
                  final entity = FieldEntity.fromName(
                    state.pathParameters['entity'],
                  );
                  return entity == null
                      ? const SettingsScreen()
                      : CustomFieldsScreen(entity: entity);
                },
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
