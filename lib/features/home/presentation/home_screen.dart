import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/config_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../auth/data/session.dart';
import '../../auth/domain/app_user.dart';
import '../../projects/data/project_repository.dart';
import '../../projects/presentation/ceo_portfolio_screen.dart';
import '../../users/data/user_repository.dart';
import 'my_day_screen.dart';

/// Home differs by role: the CEO gets the portfolio, the office admin the setup
/// checklist, and everyone on site (managers, supervisors, staff) My day —
/// what needs doing today, one tap from each action.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key, this.sort});

  final String? sort;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (user.role == UserRole.ceo) return CeoPortfolioScreen(sort: sort);
    if (user.role != UserRole.admin) return const MyDayScreen();
    final company = ref.watch(appConfigProvider).company;
    final firstName = user.name.split(' ').first;
    return PageScaffold(
      title: company.name,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Hello, $firstName',
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(user.role.label, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 20),
          const _AdminChecklist(),
        ],
      ),
    );
  }
}

class _AdminChecklist extends ConsumerWidget {
  const _AdminChecklist();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final users = ref.watch(allUsersProvider).value ?? const <AppUser>[];
    final projects = ref.watch(visibleProjectsProvider).value ?? const [];
    final config = ref.watch(appConfigProvider);
    int count(UserRole r) => users.where((u) => u.role == r && u.active).length;

    final steps = [
      _Step(
        done:
            config.company.name.isNotEmpty &&
            config.company.name != 'My company',
        title: 'Check company settings',
        detail: 'Name and the expense amount that needs the CEO\'s approval.',
        path: '/settings/company',
      ),
      _Step(
        done: count(UserRole.ceo) > 0,
        title: 'Add the CEO',
        detail: count(UserRole.ceo) > 0
            ? 'CEO account created.'
            : 'Create the CEO\'s login.',
        path: '/users/new',
      ),
      _Step(
        done: count(UserRole.manager) > 0,
        title: 'Add project managers',
        detail: '${count(UserRole.manager)} active manager(s).',
        path: '/users/new',
      ),
      _Step(
        done: projects.isNotEmpty,
        title: 'Create a project',
        detail: projects.isEmpty
            ? 'Add the first project to start your portfolio.'
            : '${projects.length} project(s) created.',
        path: '/projects/new',
      ),
      _Step(
        done:
            (config.revisions['projectStatuses'] ?? 0) > 1 ||
            (config.revisions['expenseCategories'] ?? 0) > 1,
        title: 'Review project stages and expense categories',
        detail: 'Match them to the words your company already uses.',
        path: '/settings',
      ),
      _Step(
        done: config.fields.values.any((f) => f.isNotEmpty),
        title: 'Add any extra project fields (optional)',
        detail: 'For example RERA number, plot area or architect.',
        path: '/settings/fields/project',
      ),
    ];
    final doneCount = steps.where((s) => s.done).length;

    return SectionCard(
      title: 'Get the company ready',
      subtitle:
          '$doneCount of ${steps.length} done. Projects and the CEO dashboard come next.',
      child: Column(
        children: [
          for (final s in steps)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                s.done ? Icons.check_circle : Icons.radio_button_unchecked,
                color: s.done
                    ? context.statusColors.ok
                    : Theme.of(context).colorScheme.outline,
              ),
              title: Text(s.title),
              subtitle: Text(s.detail),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go(s.path),
            ),
        ],
      ),
    );
  }
}

class _Step {
  const _Step({
    required this.done,
    required this.title,
    required this.detail,
    required this.path,
  });

  final bool done;
  final String title;
  final String detail;
  final String path;
}
