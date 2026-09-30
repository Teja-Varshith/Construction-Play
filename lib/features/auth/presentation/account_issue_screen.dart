import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth_repository.dart';
import '../data/session.dart';
import 'auth_layout.dart';

/// Shown when someone can sign in but has no profile, or was switched off.
class AccountIssueScreen extends ConsumerWidget {
  const AccountIssueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final inactive = session.status == SessionStatus.inactive;
    final email = session.authUser?.email ?? '';
    return AuthLayout(
      title: inactive ? 'Your access is turned off' : 'Your account isn\'t set up yet',
      subtitle: inactive
          ? 'An admin has switched off $email. Contact your office if you think this is a mistake.'
          : '$email can sign in, but has no profile in this company. Ask your office admin to add you from the Users screen.',
      child: FilledButton(
        onPressed: () => ref.read(authRepositoryProvider).signOut(),
        child: const Text('Sign out'),
      ),
    );
  }
}
