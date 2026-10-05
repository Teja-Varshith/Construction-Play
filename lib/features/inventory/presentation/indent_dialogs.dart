import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/inventory.dart';

/// Asks for the note that goes with a decision on an indent. The note is
/// optional when approving and required when rejecting. Returns null when
/// cancelled.
Future<String?> askIndentDecision(BuildContext context, Indent indent, {required bool approve}) => askNote(
  context,
  title: approve ? 'Approve ${indent.number}' : 'Reject ${indent.number}',
  intro: indent.summary,
  label: approve ? 'Note for the site (optional) — vendor, budget head…' : 'Reason for rejecting',
  required: !approve,
  confirmLabel: approve ? 'Approve' : 'Reject',
  destructive: !approve,
);

/// A short note dialog. [required] notes can't be left empty.
Future<String?> askNote(
  BuildContext context, {
  required String title,
  required String label,
  String? intro,
  bool required = false,
  String confirmLabel = 'Save',
  bool destructive = false,
}) {
  final controller = TextEditingController();
  final formKey = GlobalKey<FormState>();
  return showDialog<String>(
    context: context,
    builder: (ctx) {
      void submit() {
        if (formKey.currentState!.validate()) Navigator.pop(ctx, controller.text.trim());
      }

      final bad = context.statusColors.bad;
      return AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 460,
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (intro != null && intro.isNotEmpty) ...[
                  Text(intro, style: const TextStyle(color: AppColors.muted)),
                  const SizedBox(height: 12),
                ],
                TextFormField(
                  controller: controller,
                  autofocus: true,
                  maxLines: 3,
                  minLines: 1,
                  decoration: InputDecoration(labelText: label),
                  validator: (v) => required && (v ?? '').trim().isEmpty ? 'Required' : null,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: destructive ? FilledButton.styleFrom(backgroundColor: bad) : null,
            onPressed: submit,
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
}
