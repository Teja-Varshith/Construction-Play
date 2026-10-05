import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

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
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(color: theme.colorScheme.primary, borderRadius: BorderRadius.circular(8)),
          child: Icon(Icons.apartment_rounded, color: theme.colorScheme.onPrimary),
        ),
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
          color: Colors.white,
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
          color: const Color(0xFFE8EEF2),
          border: Border.all(color: AppColors.line),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Stack(children: [
          const Positioned.fill(child: CustomPaint(painter: _ArchitecturePainter())),
          Positioned(
            left: 28,
            top: 28,
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(color: AppColors.blue, borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.apartment_rounded, color: Colors.white),
            ),
          ),
          Positioned(
            left: 28,
            bottom: 28,
            child: Text('CHENNAPATANAM',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: AppColors.blue,
                      fontWeight: FontWeight.w900,
                    )),
          ),
        ]),
      );
}

class _ArchitecturePainter extends CustomPainter {
  const _ArchitecturePainter();

  @override
  void paint(Canvas canvas, Size size) {
    const blue = AppColors.blue;
    final grid = Paint()
      ..color = blue.withValues(alpha: 0.07)
      ..strokeWidth = 1;
    for (var x = 24.0; x < size.width; x += 28) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (var y = 20.0; y < size.height; y += 28) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    final top = Path()
      ..moveTo(size.width * 0.19, size.height * 0.43)
      ..lineTo(size.width * 0.54, size.height * 0.23)
      ..lineTo(size.width * 0.83, size.height * 0.40)
      ..lineTo(size.width * 0.48, size.height * 0.61)
      ..close();
    final front = Path()
      ..moveTo(size.width * 0.19, size.height * 0.43)
      ..lineTo(size.width * 0.48, size.height * 0.61)
      ..lineTo(size.width * 0.48, size.height * 0.83)
      ..lineTo(size.width * 0.19, size.height * 0.65)
      ..close();
    final side = Path()
      ..moveTo(size.width * 0.48, size.height * 0.61)
      ..lineTo(size.width * 0.83, size.height * 0.40)
      ..lineTo(size.width * 0.83, size.height * 0.62)
      ..lineTo(size.width * 0.48, size.height * 0.83)
      ..close();
    final outline = Paint()
      ..color = blue.withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawPath(front, Paint()..color = const Color(0xFFF8FAFB));
    canvas.drawPath(side, Paint()..color = const Color(0xFFD8E3EA));
    canvas.drawPath(top, Paint()..color = const Color(0xFFFFFFFF));
    canvas.drawPath(front, outline);
    canvas.drawPath(side, outline);
    canvas.drawPath(top, outline);

    final detail = Paint()
      ..color = blue.withValues(alpha: 0.42)
      ..strokeWidth = 1.5;
    for (var index = 1; index <= 3; index++) {
      final x = size.width * (0.19 + index * 0.0725);
      final y = size.height * (0.43 + index * 0.045);
      canvas.drawLine(Offset(x, y), Offset(x, y + size.height * 0.17), detail);
    }
    for (var index = 1; index <= 3; index++) {
      final y = size.height * (0.45 + index * 0.045);
      canvas.drawLine(Offset(size.width * 0.52, y), Offset(size.width * 0.81, y - size.height * 0.17), detail);
    }

    final base = Paint()
      ..color = blue.withValues(alpha: 0.22)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawOval(
      Rect.fromCenter(center: Offset(size.width * 0.51, size.height * 0.84), width: size.width * 0.7, height: size.height * 0.13),
      base,
    );
  }

  @override
  bool shouldRepaint(covariant _ArchitecturePainter oldDelegate) => false;
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
