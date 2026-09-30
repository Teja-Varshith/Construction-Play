import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/auth_errors.dart';
import '../data/auth_repository.dart';
import '../data/session.dart';
import 'auth_layout.dart';

/// First-run setup: creates the company and its first admin account.
/// Only shown while no company exists yet, and protected by a setup code.
class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  final _form = GlobalKey<FormState>();
  final _company = TextEditingController();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_company, _name, _email, _password, _confirm, _code]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final progress = ref.read(setupInProgressProvider.notifier);
    progress.set(true);
    try {
      await ref.read(authRepositoryProvider).createOwner(
            companyName: _company.text,
            name: _name.text,
            email: _email.text,
            password: _password.text,
            setupCode: _code.text,
          );
      progress.set(false);
      if (mounted) context.go('/home');
    } catch (e) {
      progress.set(false);
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _required(String? v, String what) => (v ?? '').trim().isEmpty ? 'Enter $what' : null;

  @override
  Widget build(BuildContext context) {
    return AuthLayout(
      title: 'Set up your company',
      subtitle: 'This runs once. It creates the company and the first admin account, '
          'who can then add the CEO, managers and supervisors.',
      child: Form(
        key: _form,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextFormField(
            controller: _company,
            decoration: const InputDecoration(labelText: 'Company name'),
            validator: (v) => _required(v, 'the company name'),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Your name'),
            validator: (v) => _required(v, 'your name'),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Your email'),
            validator: validateEmail,
          ),
          const SizedBox(height: 16),
          PasswordField(
            controller: _password,
            label: 'Choose a password',
            autofillHints: const [AutofillHints.newPassword],
            validator: validateNewPassword,
          ),
          const SizedBox(height: 16),
          PasswordField(
            controller: _confirm,
            label: 'Confirm password',
            autofillHints: const [AutofillHints.newPassword],
            validator: (v) => v != _password.text ? 'Passwords don\'t match' : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _code,
            decoration: const InputDecoration(
              labelText: 'Setup code',
              helperText: 'Provided by your development team',
            ),
            validator: (v) => _required(v, 'the setup code'),
            onFieldSubmitted: (_) => _submit(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 20),
          AuthPrimaryButton(label: 'Create company', onPressed: _busy ? null : _submit, busy: _busy),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => context.go('/login'),
            child: const Text('Already set up? Sign in'),
          ),
        ]),
      ),
    );
  }
}
