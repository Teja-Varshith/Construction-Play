import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../demo/demo_accounts.dart';
import '../domain/app_user.dart';
import '../data/auth_errors.dart';
import '../data/auth_repository.dart';
import 'auth_layout.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).signIn(_email.text, _password.text);
      // The router moves to the right screen once the session is ready.
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _demo(DemoAccount account) async {
    _email.text = account.email;
    _password.text = demoPassword;
    await _submit();
    // Demo logins only exist after an admin loads demo data.
    if (mounted && _error != null) {
      setState(() => _error =
          'The ${account.role.label} demo login isn’t set up yet. An admin needs to open '
          'Settings → Demo data → Load demo data once. ($_error)');
    }
  }

  static IconData _roleIcon(UserRole role) => switch (role) {
    UserRole.ceo => Icons.workspace_premium_outlined,
    UserRole.admin => Icons.admin_panel_settings_outlined,
    UserRole.manager => Icons.engineering_outlined,
    UserRole.supervisor => Icons.construction_outlined,
    _ => Icons.badge_outlined,
  };

  @override
  Widget build(BuildContext context) {
    return AuthLayout(
      title: 'Sign in',
      subtitle: 'Use the email and password your office gave you.',
      child: AutofillGroup(
        child: Form(
          key: _form,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.alternate_email_rounded),
              ),
              validator: validateEmail,
            ),
            const SizedBox(height: 16),
            PasswordField(controller: _password, onSubmitted: _submit),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.error_outline_rounded, color: Theme.of(context).colorScheme.onErrorContainer, size: 20),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      _error!,
                      style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
                    ),
                  ),
                ]),
              ),
            ],
            const SizedBox(height: 20),
            AuthPrimaryButton(label: 'Sign in', onPressed: _busy ? null : _submit, busy: _busy),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => context.push('/forgot-password?email=${Uri.encodeComponent(_email.text.trim())}'),
              child: const Text('Forgot password?'),
            ),
            const SizedBox(height: 8),
            Row(children: [
              const Expanded(child: Divider()),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text('or sign in with a demo account', style: Theme.of(context).textTheme.labelMedium),
              ),
              const Expanded(child: Divider()),
            ]),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, c) {
                final columns = c.maxWidth >= 360 ? 2 : 1;
                final width = (c.maxWidth - (columns - 1) * 8) / columns;
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final a in demoAccounts)
                      SizedBox(
                        width: width,
                        child: _DemoLoginButton(
                          icon: _roleIcon(a.role),
                          role: a.role.label,
                          name: a.name.replaceAll(RegExp(r'\s*\(Demo.*\)'), ''),
                          busy: _busy && _email.text == a.email,
                          onTap: _busy ? null : () => _demo(a),
                        ),
                      ),
                  ],
                );
              },
            ),
          ]),
        ),
      ),
    );
  }
}

/// One tap signs straight in as this role.
class _DemoLoginButton extends StatelessWidget {
  const _DemoLoginButton({
    required this.icon,
    required this.role,
    required this.name,
    required this.busy,
    required this.onTap,
  });

  final IconData icon;
  final String role;
  final String name;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        alignment: Alignment.centerLeft,
      ),
      child: Row(children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(8),
          ),
          child: busy
              ? const Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator(strokeWidth: 2))
              : Icon(icon, size: 18, color: scheme.primary),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(role, style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ]),
        ),
      ]),
    );
  }
}
