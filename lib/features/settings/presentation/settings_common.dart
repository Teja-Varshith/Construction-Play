import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/config/config_repository.dart';
import '../../../core/widgets/common.dart';
import '../../auth/data/auth_errors.dart';

/// Waits for the real config from the server before an editor opens, so edits
/// start from the latest revision rather than the built-in defaults.
class ConfigGate extends ConsumerWidget {
  const ConfigGate({super.key, required this.title, required this.builder});

  final String title;
  final Widget Function(AppConfig config) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(appConfigStreamProvider);
    if (config.hasValue && config.requireValue.revisions.isNotEmpty) return builder(config.requireValue);
    return PageScaffold(
      title: title,
      body: config.hasError
          ? MessageView(icon: Icons.cloud_off_outlined, title: 'Couldn\'t load settings', message: friendlyError(config.error!))
          : const LoadingView(),
    );
  }
}

/// Runs a config save and turns a conflict into a friendly message.
/// Returns true when saved.
Future<bool> runConfigSave(BuildContext context, Future<void> Function() save) async {
  try {
    await save();
    if (context.mounted) showMessage(context, 'Saved');
    return true;
  } on ConfigConflictException catch (e) {
    if (context.mounted) showMessage(context, e.toString(), error: true);
  } catch (e) {
    if (context.mounted) showMessage(context, friendlyError(e), error: true);
  }
  return false;
}

/// Save / discard bar shown while there are unsaved edits.
class SaveBar extends StatelessWidget {
  const SaveBar({super.key, required this.dirty, required this.busy, required this.onSave, required this.onDiscard});

  final bool dirty;
  final bool busy;
  final VoidCallback onSave;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Row(children: [
        Expanded(
          child: Text(
            dirty ? 'You have unsaved changes' : 'All changes saved',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        TextButton(onPressed: dirty && !busy ? onDiscard : null, child: const Text('Discard')),
        const SizedBox(width: 8),
        FilledButton(onPressed: dirty && !busy ? onSave : null, child: Text(busy ? 'Saving…' : 'Save')),
      ]),
    );
  }
}

/// Asks before leaving a screen with unsaved changes.
class UnsavedGuard extends StatelessWidget {
  const UnsavedGuard({super.key, required this.dirty, required this.child});

  final bool dirty;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await confirmAction(
          context,
          title: 'Leave without saving?',
          message: 'Your changes on this screen will be lost.',
          confirmLabel: 'Leave',
          destructive: true,
        );
        if (leave && context.mounted) Navigator.of(context).pop();
      },
      child: child,
    );
  }
}

/// Simple one-field text dialog. Returns the trimmed text, or null.
Future<String?> askText(
  BuildContext context, {
  required String title,
  required String label,
  String initial = '',
  String? Function(String value)? validate,
}) {
  final controller = TextEditingController(text: initial);
  final formKey = GlobalKey<FormState>();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Form(
        key: formKey,
        child: TextFormField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: label),
          validator: (v) {
            final s = (v ?? '').trim();
            if (s.isEmpty) return 'Enter a name';
            return validate?.call(s);
          },
          onFieldSubmitted: (_) {
            if (formKey.currentState!.validate()) Navigator.pop(ctx, controller.text.trim());
          },
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            if (formKey.currentState!.validate()) Navigator.pop(ctx, controller.text.trim());
          },
          child: const Text('OK'),
        ),
      ],
    ),
  );
}
