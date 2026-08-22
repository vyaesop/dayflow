import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

/// The Dayflow mark: three flowing capsules suggesting a sunrise over a
/// day-grid — original geometry, not derived from any existing logo.
class DfLogoMark extends StatelessWidget {
  const DfLogoMark({super.key, this.size = 48});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: Size.square(size), painter: _MarkPainter());
  }
}

class _MarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    RRect capsule(double x, double y, double width, double height) =>
        RRect.fromRectAndRadius(Rect.fromLTWH(x, y, width, height), Radius.circular(height / 2));

    // Three staggered flow bars.
    canvas.drawRRect(capsule(w * 0.08, w * 0.16, w * 0.56, w * 0.18), Paint()..color = DfColors.primary);
    canvas.drawRRect(capsule(w * 0.26, w * 0.42, w * 0.66, w * 0.18), Paint()..color = DfColors.accentGreen);
    canvas.drawRRect(capsule(w * 0.08, w * 0.68, w * 0.46, w * 0.18), Paint()..color = DfColors.accentAmber);
    // The "today" dot.
    canvas.drawCircle(Offset(w * 0.80, w * 0.77), w * 0.09, Paint()..color = DfColors.accentPink);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Wordmark: mark + lowercase "dayflow".
class DfWordmark extends StatelessWidget {
  const DfWordmark({super.key, this.markSize = 26, this.fontSize = 22, this.subtitle});

  final double markSize;
  final double fontSize;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        DfLogoMark(size: markSize),
        const SizedBox(width: DfSpacing.xs),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'dayflow',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: fontSize,
                fontWeight: FontWeight.w800,
                fontVariations: const [FontVariation('wght', 800)],
                letterSpacing: -0.6,
                height: 1.05,
                color: isDark ? DfColors.textPrimaryDark : DfColors.textPrimary,
              ),
            ),
            if (subtitle != null)
              Text(
                subtitle!,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: fontSize * 0.44,
                  fontWeight: FontWeight.w500,
                  fontVariations: const [FontVariation('wght', 500)],
                  color: isDark ? DfColors.textSecondaryDark : DfColors.textSecondary,
                ),
              ),
          ],
        ),
      ],
    );
  }
}
