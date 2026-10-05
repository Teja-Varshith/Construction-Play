import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Placeholder company mark: three rising building blocks on a gradient tile.
/// Swap for the company's own logo when there is one.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 36});

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: CustomPaint(painter: _BrandPainter()),
  );
}

class _BrandPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final tile = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(s * 0.26));
    canvas.drawRRect(
      tile,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF5B7CFA), AppColors.blue, Color(0xFF2338A0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(Offset.zero & size),
    );
    // Three blocks rising left to right, like a skyline or a growth chart.
    final base = s * 0.76;
    final w = s * 0.15;
    final gap = s * 0.07;
    final left = (s - (3 * w + 2 * gap)) / 2;
    const heights = [0.26, 0.40, 0.54];
    const alphas = [0.55, 0.78, 1.0];
    for (var n = 0; n < 3; n++) {
      final x = left + n * (w + gap);
      final h = s * heights[n];
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x, base - h, w, h), Radius.circular(s * 0.035)),
        Paint()..color = Colors.white.withValues(alpha: alphas[n]),
      );
    }
    // Accent: the "site" light on the tallest block.
    canvas.drawCircle(
      Offset(left + 2 * (w + gap) + w / 2, base - s * 0.54 - s * 0.1),
      s * 0.05,
      Paint()..color = const Color(0xFFFFC94D),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// The mark with the company name, for the sidebar and page headers.
class BrandLockup extends StatelessWidget {
  const BrandLockup({super.key, required this.name, this.tagline, this.size = 36, this.onDark = false});

  final String name;
  final String? tagline;
  final double size;

  /// White text, for the navy sidebar.
  final bool onDark;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      BrandMark(size: size),
      const SizedBox(width: 11),
      Flexible(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 15.5,
                letterSpacing: -0.2,
                color: onDark ? Colors.white : AppColors.ink,
              ),
            ),
            if (tagline != null)
              Text(
                tagline!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: onDark ? AppColors.navyText : AppColors.muted),
              ),
          ],
        ),
      ),
    ],
  );
}
