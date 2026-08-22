import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

enum DfButtonVariant { primary, tonal, outline, text, danger }

/// Dayflow button — one component, five variants, built-in loading state.
class DfButton extends StatelessWidget {
  const DfButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = DfButtonVariant.primary,
    this.loading = false,
    this.expand = true,
    this.icon,
    this.height = 50,
  });

  final String label;
  final VoidCallback? onPressed;
  final DfButtonVariant variant;
  final bool loading;
  final bool expand;
  final Widget? icon;
  final double height;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final enabled = onPressed != null && !loading;

    final (Color bg, Color fg, BorderSide side) = switch (variant) {
      DfButtonVariant.primary => (DfColors.primary, Colors.white, BorderSide.none),
      DfButtonVariant.tonal => (
          isDark ? DfColors.surfaceAltDark : DfColors.primarySubtle,
          isDark ? DfColors.textPrimaryDark : DfColors.primary,
          BorderSide.none,
        ),
      DfButtonVariant.outline => (
          isDark ? DfColors.surfaceDark : Colors.white,
          isDark ? DfColors.textPrimaryDark : DfColors.textPrimary,
          BorderSide(color: isDark ? DfColors.borderStrongDark : DfColors.borderStrong),
        ),
      DfButtonVariant.text => (Colors.transparent, DfColors.primary, BorderSide.none),
      DfButtonVariant.danger => (Colors.transparent, DfColors.danger, BorderSide.none),
    };

    final child = AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      child: loading
          ? SizedBox(
              key: const ValueKey('spinner'),
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2.4, color: fg),
            )
          : Row(
              key: const ValueKey('label'),
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[icon!, const SizedBox(width: DfSpacing.xs)],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(color: fg),
                  ),
                ),
              ],
            ),
    );

    final button = Material(
      color: enabled ? bg : bg.withValues(alpha: variant == DfButtonVariant.primary ? 0.45 : 0.6),
      borderRadius: BorderRadius.circular(DfRadius.md),
      child: InkWell(
        onTap: enabled ? onPressed : null,
        borderRadius: BorderRadius.circular(DfRadius.md),
        child: Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: DfSpacing.lg),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(DfRadius.md),
            border: side == BorderSide.none ? null : Border.fromBorderSide(side),
          ),
          alignment: Alignment.center,
          child: DefaultTextStyle.merge(
            style: TextStyle(color: enabled ? fg : fg.withValues(alpha: 0.7)),
            child: child,
          ),
        ),
      ),
    );

    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}
