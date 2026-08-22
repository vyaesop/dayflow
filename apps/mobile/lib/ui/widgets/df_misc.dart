import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

/// Status pill exactly as on boards: filled label color, white text.
class DfStatusPill extends StatelessWidget {
  const DfStatusPill({super.key, required this.label, required this.colorToken, this.width, this.height = 30});

  final String label;
  final String colorToken;
  final double? width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final isEmpty = label.isEmpty;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: width,
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: DfSpacing.sm),
      decoration: BoxDecoration(
        color: isEmpty ? (isDark ? DfColors.surfaceAltDark : DfColors.surfaceAlt) : DfColors.token(colorToken),
        borderRadius: BorderRadius.circular(6),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: 12,
          fontWeight: FontWeight.w600,
          fontVariations: const [FontVariation('wght', 600)],
          color: isEmpty ? DfColors.textTertiary : Colors.white,
        ),
      ),
    );
  }
}

/// Circular setup-progress ring with a percent label.
class DfProgressRing extends StatelessWidget {
  const DfProgressRing({super.key, required this.percent, this.size = 56});

  final int percent;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: percent / 100),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOutCubic,
            builder: (context, value, _) => CircularProgressIndicator(
              value: value,
              strokeWidth: 5,
              strokeCap: StrokeCap.round,
              backgroundColor: DfColors.primarySubtle,
              color: DfColors.primary,
            ),
          ),
          Text('$percent%', style: Theme.of(context).textTheme.titleSmall),
        ],
      ),
    );
  }
}

/// Rounded surface card used across Home / lists.
class DfCard extends StatelessWidget {
  const DfCard({super.key, required this.child, this.padding = const EdgeInsets.all(DfSpacing.md), this.onTap});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: isDark ? DfColors.surfaceDark : DfColors.surface,
      borderRadius: BorderRadius.circular(DfRadius.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DfRadius.lg),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(DfRadius.lg),
            border: Border.all(color: isDark ? DfColors.borderDark : DfColors.border),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Small colored board glyph used in board lists (mini "table" icon).
class DfBoardGlyph extends StatelessWidget {
  const DfBoardGlyph({super.key, this.size = 36});

  final double size;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.22),
      decoration: BoxDecoration(
        color: isDark ? DfColors.surfaceAltDark : Colors.white,
        borderRadius: BorderRadius.circular(size * 0.25),
        border: Border.all(color: isDark ? DfColors.borderDark : DfColors.border),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _bar(DfColors.accentBlue),
          _bar(DfColors.accentGreen),
          _bar(DfColors.accentAmber),
        ],
      ),
    );
  }

  Widget _bar(Color color) => Container(
        height: 2.6,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
      );
}

void showDfToast(BuildContext context, String message, {IconData icon = Icons.check_circle_rounded}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Row(children: [
        Icon(icon, color: DfColors.success, size: 20),
        const SizedBox(width: DfSpacing.xs),
        Expanded(child: Text(message)),
      ]),
      duration: const Duration(seconds: 3),
    ));
}
