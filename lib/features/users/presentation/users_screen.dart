import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../auth/domain/app_user.dart';
import '../data/user_repository.dart';

class UsersScreen extends ConsumerStatefulWidget {
  const UsersScreen({super.key});

  @override
  ConsumerState<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends ConsumerState<UsersScreen> {
  String _query = '';
  UserRole? _role;
  bool _showInactive = false;

  @override
  Widget build(BuildContext context) {
    final users = ref.watch(allUsersProvider);
    return PageScaffold(
      title: 'Users',
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go('/users/new'),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Add user'),
      ),
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Search by name, email or phone',
          ),
          onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          ChoiceChip(label: const Text('All roles'), selected: _role == null, onSelected: (_) => setState(() => _role = null)),
          for (final r in UserRole.assignable)
            ChoiceChip(label: Text(r.label), selected: _role == r, onSelected: (_) => setState(() => _role = r)),
          FilterChip(
            label: const Text('Show turned-off users'),
            selected: _showInactive,
            onSelected: (v) => setState(() => _showInactive = v),
          ),
        ]),
        const SizedBox(height: 16),
        AsyncView(
          value: users,
          data: (all) {
            final list = all.where((u) {
              if (!_showInactive && !u.active) return false;
              if (_role != null && u.role != _role) return false;
              if (_query.isEmpty) return true;
              return '${u.name} ${u.email} ${u.phone}'.toLowerCase().contains(_query);
            }).toList();
            if (list.isEmpty) {
              return const MessageView(
                icon: Icons.people_outline,
                title: 'No users match',
                message: 'Try another search or filter, or add a user.',
              );
            }
            return Card(
              child: Column(children: [
                for (var i = 0; i < list.length; i++) ...[
                  if (i > 0) const Divider(),
                  _UserTile(user: list[i]),
                ],
              ]),
            );
          },
        ),
        const SizedBox(height: 72),
      ]),
    );
  }
}

class _UserTile extends StatelessWidget {
  const _UserTile({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    final status = context.statusColors;
    return ListTile(
      leading: CircleAvatar(child: Text(user.initials)),
      title: Text(user.name.isEmpty ? user.email : user.name),
      subtitle: Text([user.designation, user.email].where((s) => s.isNotEmpty).join(' · ')),
      trailing: Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Pill(user.role.label),
        if (!user.active) Pill('Off', color: status.bad, background: status.badSoft),
      ]),
      onTap: () => context.go('/users/${user.uid}'),
    );
  }
}
