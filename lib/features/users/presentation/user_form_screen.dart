import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/common.dart';
import '../../auth/data/auth_errors.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/data/session.dart';
import '../../auth/domain/app_user.dart';
import '../../auth/presentation/auth_layout.dart';
import '../data/user_repository.dart';

/// Add a user (no [uid]) or edit one.
class UserFormScreen extends ConsumerWidget {
  const UserFormScreen({super.key, this.uid});

  final String? uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (uid == null) return const _UserForm(existing: null);
    final user = ref.watch(userProvider(uid!));
    return AsyncView(
      value: user,
      data: (u) => u == null
          ? const Scaffold(body: MessageView(icon: Icons.person_off_outlined, title: 'User not found'))
          : _UserForm(key: ValueKey(u.uid), existing: u),
    );
  }
}

class _UserForm extends ConsumerStatefulWidget {
  const _UserForm({super.key, required this.existing});

  final AppUser? existing;

  @override
  ConsumerState<_UserForm> createState() => _UserFormState();
}

class _UserFormState extends ConsumerState<_UserForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _email = TextEditingController(text: widget.existing?.email ?? '');
  late final _phone = TextEditingController(text: widget.existing?.phone ?? '');
  late final _designation = TextEditingController(text: widget.existing?.designation ?? '');
  final _password = TextEditingController(text: _generatePassword());
  late UserRole _role = widget.existing?.role ?? UserRole.manager;
  late bool _active = widget.existing?.active ?? true;
  bool _sendResetEmail = true;
  bool _busy = false;

  bool get _isNew => widget.existing == null;

  @override
  void dispose() {
    for (final c in [_name, _email, _phone, _designation, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  static String _generatePassword() {
    const letters = 'abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ';
    const digits = '23456789';
    final r = Random.secure();
    final chars = [
      for (var i = 0; i < 7; i++) letters[r.nextInt(letters.length)],
      for (var i = 0; i < 3; i++) digits[r.nextInt(digits.length)],
    ]..shuffle(r);
    return chars.join();
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    final me = ref.read(currentUserProvider);
    final existing = widget.existing;

    if (existing != null && existing.active && !_active) {
      final ok = await confirmAction(
        context,
        title: 'Turn off ${existing.name}?',
        message: 'They will lose access straight away. Their past records stay. You can turn them back on later.',
        confirmLabel: 'Turn off',
        destructive: true,
      );
      if (!ok) return;
    }

    setState(() => _busy = true);
    try {
      final repo = ref.read(userRepositoryProvider);
      if (existing == null) {
        await repo.createUser(
          adminUid: me.uid,
          name: _name.text,
          email: _email.text,
          password: _password.text,
          role: _role,
          phone: _phone.text,
          designation: _designation.text,
        );
        var emailed = false;
        if (_sendResetEmail) {
          try {
            await ref.read(authRepositoryProvider).sendPasswordReset(_email.text);
            emailed = true;
          } catch (_) {
            // The account exists either way; the admin can share the password.
          }
        }
        if (!mounted) return;
        await _showCreated(emailed: emailed);
      } else {
        await repo.updateUser(
          adminUid: me.uid,
          before: existing,
          name: _name.text,
          phone: _phone.text,
          designation: _designation.text,
          role: _role,
          active: _active,
        );
        if (!mounted) return;
        showMessage(context, 'Saved');
      }
      if (mounted) context.go('/users');
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showCreated({required bool emailed}) {
    final text = 'Chennapatanam login\nEmail: ${_email.text.trim()}\nTemporary password: ${_password.text}';
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('User added'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (emailed)
            Text('A link to set their own password was emailed to ${_email.text.trim()}.')
          else
            const Text('Share these sign-in details with them. This password is shown only once.'),
          const SizedBox(height: 12),
          SelectableText(text),
        ]),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              if (ctx.mounted) showMessage(ctx, 'Copied');
            },
            child: const Text('Copy details'),
          ),
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(currentUserProvider);
    final isSelf = widget.existing?.uid == me.uid;
    return PageScaffold(
      title: _isNew ? 'Add user' : 'Edit user',
      maxWidth: 640,
      body: Form(
        key: _form,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SectionCard(
            title: 'Details',
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Full name'),
                validator: (v) => (v ?? '').trim().isEmpty ? 'Enter a name' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _email,
                enabled: _isNew,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: 'Email (used to sign in)',
                  helperText: _isNew ? null : 'Email can\'t be changed. Add a new user instead.',
                ),
                validator: validateEmail,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Phone (optional)'),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _designation,
                decoration: const InputDecoration(labelText: 'Designation (optional)', hintText: 'e.g. Senior site engineer'),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: 'Role',
            subtitle: isSelf ? 'You can\'t change your own role. Ask another admin.' : 'Decides what this person sees.',
            child: RadioGroup<UserRole>(
              groupValue: _role,
              onChanged: (r) {
                if (!isSelf && r != null) setState(() => _role = r);
              },
              child: Column(children: [
                for (final r in UserRole.assignable)
                  RadioListTile<UserRole>(
                    contentPadding: EdgeInsets.zero,
                    value: r,
                    enabled: !isSelf,
                    title: Text(r.label),
                    subtitle: Text(r.description),
                  ),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          if (_isNew)
            SectionCard(
              title: 'Password',
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                TextFormField(
                  controller: _password,
                  decoration: InputDecoration(
                    labelText: 'Temporary password',
                    suffixIcon: IconButton(
                      tooltip: 'Generate another',
                      icon: const Icon(Icons.refresh),
                      onPressed: () => setState(() => _password.text = _generatePassword()),
                    ),
                  ),
                  validator: validateNewPassword,
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _sendResetEmail,
                  onChanged: (v) => setState(() => _sendResetEmail = v ?? false),
                  title: const Text('Email them a link to set their own password'),
                ),
              ]),
            )
          else
            SectionCard(
              title: 'Access',
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _active,
                onChanged: isSelf ? null : (v) => setState(() => _active = v),
                title: Text(_active ? 'Can sign in' : 'Turned off'),
                subtitle: Text(isSelf
                    ? 'You can\'t turn yourself off.'
                    : 'Turning off keeps their history but blocks access immediately.'),
              ),
            ),
          const SizedBox(height: 24),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(onPressed: () => context.go('/users'), child: const Text('Cancel')),
            const SizedBox(width: 12),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: Text(_busy ? 'Saving…' : (_isNew ? 'Add user' : 'Save changes')),
            ),
          ]),
        ]),
      ),
    );
  }
}
