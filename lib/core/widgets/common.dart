import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/data/auth_errors.dart';

/// Standard page: title bar plus a centred, width-limited, scrollable body.
class PageScaffold extends StatelessWidget {
  const PageScaffold({
    super.key,
    required this.title,
    required this.body,
    this.titleWidget,
    this.actions,
    this.floatingActionButton,
    this.maxWidth = 960,
    this.scrollable = true,
  });

  final String title;

  /// Replaces the plain [title] text, e.g. with the company brand.
  final Widget? titleWidget;
  final Widget body;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final double maxWidth;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    // On wide screens the title is a page heading lined up with the content
    // (no bar); phones keep a compact title bar.
    final heading = wide && (title.isNotEmpty || (actions?.isNotEmpty ?? false))
        ? Padding(
            padding: const EdgeInsets.only(bottom: 22),
            child: Row(
              children: [
                Expanded(
                  child: titleWidget ??
                      Text(title, style: Theme.of(context).textTheme.headlineMedium),
                ),
                ...?actions,
              ],
            ),
          )
        : null;
    Widget column(Widget child) => heading == null
        ? child
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: scrollable ? MainAxisSize.min : MainAxisSize.max,
            children: [heading, if (scrollable) child else Expanded(child: child)],
          );
    final content = Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: wide ? const EdgeInsets.fromLTRB(36, 32, 36, 48) : const EdgeInsets.fromLTRB(16, 8, 16, 32),
          child: column(body),
        ),
      ),
    );
    return Scaffold(
      appBar: wide
          ? null
          : AppBar(
              title: titleWidget ?? Text(title),
              actions: actions,
            ),
      floatingActionButton: floatingActionButton,
      body: SafeArea(child: scrollable ? SingleChildScrollView(child: content) : content),
    );
  }
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const CircularProgressIndicator(),
            if (message != null) ...[const SizedBox(height: 16), Text(message!)],
          ]),
        ),
      );
}

class MessageView extends StatelessWidget {
  const MessageView({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 48, color: theme.colorScheme.outline),
          const SizedBox(height: 16),
          Text(title, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
          if (message != null) ...[
            const SizedBox(height: 8),
            Text(message!, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
          ],
          if (action != null) ...[const SizedBox(height: 20), action!],
        ]),
      ),
    );
  }
}

/// Renders loading, error and data states of an [AsyncValue] the same way
/// everywhere.
class AsyncView<T> extends StatelessWidget {
  const AsyncView({super.key, required this.value, required this.data});

  final AsyncValue<T> value;
  final Widget Function(T data) data;

  @override
  Widget build(BuildContext context) {
    if (value.hasValue) return data(value.requireValue);
    if (value.hasError) {
      return MessageView(
        icon: Icons.cloud_off_outlined,
        title: 'Couldn\'t load this',
        message: friendlyError(value.error!),
      );
    }
    return const LoadingView();
  }
}

/// A titled group of content on a page.
class SectionCard extends StatelessWidget {
  const SectionCard({super.key, this.title, this.subtitle, required this.child, this.trailing});

  final String? title;
  final String? subtitle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (title != null) ...[
            Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title!, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  if (subtitle != null)
                    Text(subtitle!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ]),
              ),
              ?trailing,
            ]),
            const SizedBox(height: 14),
          ],
          child,
        ]),
      ),
    );
  }
}

void showMessage(BuildContext context, String message, {bool error = false}) {
  final scheme = Theme.of(context).colorScheme;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? scheme.error : null,
    ));
}

/// In-app confirmation (never the browser's confirm dialog).
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(
          style: destructive ? FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Small coloured label, e.g. a role or "Inactive".
class Pill extends StatelessWidget {
  const Pill(this.label, {super.key, this.color, this.background});

  final String label;
  final Color? color;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: background ?? scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color ?? scheme.onSecondaryContainer,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

/// The same Approve / Reject pair everywhere something waits on a decision:
/// an optional link on the left, Reject then Approve on the right (split
/// evenly on phones).
class DecisionButtons extends StatelessWidget {
  const DecisionButtons({
    super.key,
    required this.onApprove,
    required this.onReject,
    this.busy = false,
    this.secondary,
  });

  final VoidCallback onApprove;
  final VoidCallback onReject;
  final bool busy;

  /// e.g. "Open in project".
  final Widget? secondary;

  @override
  Widget build(BuildContext context) {
    final bad = Theme.of(context).colorScheme.error;
    final reject = OutlinedButton.icon(
      onPressed: busy ? null : onReject,
      style: OutlinedButton.styleFrom(foregroundColor: bad),
      icon: const Icon(Icons.close_rounded, size: 18),
      label: const Text('Reject'),
    );
    final approve = FilledButton.icon(
      onPressed: busy ? null : onApprove,
      icon: const Icon(Icons.check_rounded, size: 18),
      label: const Text('Approve'),
    );
    return LayoutBuilder(
      builder: (context, c) => c.maxWidth < 420
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: reject),
                    const SizedBox(width: 8),
                    Expanded(child: approve),
                  ],
                ),
                if (secondary != null) Align(alignment: Alignment.centerLeft, child: secondary),
              ],
            )
          : Row(
              children: [
                ?secondary,
                const Spacer(),
                reject,
                const SizedBox(width: 8),
                approve,
              ],
            ),
    );
  }
}
