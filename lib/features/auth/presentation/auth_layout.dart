import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/art.dart';
import '../../../core/widgets/brand_mark.dart';

/// Centred card used by the sign-in, setup and password screens.
class AuthLayout extends StatelessWidget {
  const AuthLayout({super.key, required this.title, this.subtitle, required this.child});

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 900) {
              return SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: _AuthContent(title: title, subtitle: subtitle, child: child),
                  ),
                ),
              );
            }

            final panelHeight = (constraints.maxHeight - 48).clamp(360.0, 760.0).toDouble();
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1280),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                  child: SizedBox(
                    height: panelHeight,
                    child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      const Expanded(flex: 5, child: _AuthBrandPanel()),
                      const SizedBox(width: 36),
                      Expanded(
                        flex: 4,
                        child: LayoutBuilder(
                          builder: (context, formConstraints) => SingleChildScrollView(
                            child: ConstrainedBox(
                              constraints: BoxConstraints(minHeight: formConstraints.maxHeight),
                              child: Center(
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(maxWidth: 440),
                                  child: _AuthContent(title: title, subtitle: subtitle, child: child),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ]),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _AuthContent extends StatelessWidget {
  const _AuthContent({required this.title, required this.subtitle, required this.child});

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        const BrandMark(size: 48),
        const SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Chennapatanam', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          Text('PROJECT OPERATIONS', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ]),
      ]),
      const SizedBox(height: 32),
      Text(title, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
      if (subtitle != null) ...[
        const SizedBox(height: 8),
        Text(subtitle!, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ],
      const SizedBox(height: 22),
      Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.line),
          boxShadow: appSoftShadow,
        ),
        padding: const EdgeInsets.all(24),
        child: child,
      ),
    ]);
  }
}

class _AuthBrandPanel extends StatelessWidget {
  const _AuthBrandPanel();

  @override
  Widget build(BuildContext context) => Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: const Color(0xFFEEF2FF), // the illustration's sky, above it
          borderRadius: BorderRadius.circular(AppRadius.lg + 4),
          border: Border.all(color: AppColors.line),
        ),
        child: Stack(children: [
          const Positioned.fill(
            child: Illustration(
              Art.siteSkyline,
              fit: BoxFit.fitWidth,
              alignment: Alignment.bottomCenter,
              height: double.infinity,
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            top: 24,
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(AppRadius.md),
                boxShadow: appCardShadow,
              ),
              child: Row(children: [
                const BrandMark(size: 44),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Every site, every rupee, every day.',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    const Text('Progress, delays, materials and money for all your projects in one place.',
                        style: TextStyle(color: AppColors.muted, fontSize: 13)),
                  ]),
                ),
              ]),
            ),
          ),
        ]),
      );
}

class AuthPrimaryButton extends StatelessWidget {
  const AuthPrimaryButton({super.key, required this.label, required this.onPressed, this.busy = false});

  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        height: 50,
        child: FilledButton(
          onPressed: busy ? null : onPressed,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: busy
                ? const SizedBox(
                    key: ValueKey('busy'),
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Text(label, key: const ValueKey('label'), style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
      );
}

String? validateEmail(String? v) {
  final s = (v ?? '').trim();
  if (s.isEmpty) return 'Enter an email address';
  if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s)) return 'Enter a valid email address';
  return null;
}

String? validateNewPassword(String? v) {
  final s = v ?? '';
  if (s.length < 8) return 'Use at least 8 characters';
  if (!RegExp(r'[A-Za-z]').hasMatch(s) || !RegExp(r'\d').hasMatch(s)) return 'Use both letters and numbers';
  return null;
}

/// Password box with a show/hide button.
class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.controller,
    this.label = 'Password',
    this.validator,
    this.onSubmitted,
    this.autofillHints = const [AutofillHints.password],
  });

  final TextEditingController controller;
  final String label;
  final String? Function(String?)? validator;
  final VoidCallback? onSubmitted;
  final Iterable<String> autofillHints;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _hidden = true;

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: widget.controller,
        obscureText: _hidden,
        autofillHints: widget.autofillHints,
        decoration: InputDecoration(
          labelText: widget.label,
          prefixIcon: const Icon(Icons.lock_outline_rounded),
          suffixIcon: IconButton(
            tooltip: _hidden ? 'Show password' : 'Hide password',
            icon: Icon(_hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined),
            onPressed: () => setState(() => _hidden = !_hidden),
          ),
        ),
        validator: widget.validator ?? (v) => (v ?? '').isEmpty ? 'Enter your password' : null,
        onFieldSubmitted: (_) => widget.onSubmitted?.call(),
      );
}
