import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/tokens.dart';
import '../../ui/widgets/df_button.dart';
import '../../ui/widgets/df_logo.dart';
import '../../ui/widgets/df_misc.dart';

/// Landing screen: wordmark, tagline, hero illustration, Log in / Create account.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: DfSpacing.xl),
          child: Column(
            children: [
              const Spacer(),
              const DfWordmark(markSize: 34, fontSize: 30),
              const SizedBox(height: DfSpacing.xs),
              Text('Get your work done anytime, anywhere',
                  style: text.bodyMedium?.copyWith(color: DfColors.textSecondary)),
              const Spacer(),
              const _HeroIllustration(),
              const Spacer(flex: 2),
              DfButton(label: 'Log in', onPressed: () => context.push('/auth/email?mode=login')),
              const SizedBox(height: DfSpacing.sm),
              DfButton(
                label: 'Create new account',
                variant: DfButtonVariant.tonal,
                onPressed: () => context.push('/auth/email?mode=signup'),
              ),
              const SizedBox(height: DfSpacing.xl),
            ],
          ),
        ),
      ),
    );
  }
}

/// A stylized phone-with-board illustration, painted with design tokens.
class _HeroIllustration extends StatelessWidget {
  const _HeroIllustration();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 190,
      padding: const EdgeInsets.all(DfSpacing.md),
      decoration: BoxDecoration(
        color: isDark ? DfColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: isDark ? DfColors.borderDark : DfColors.border, width: 1.5),
        boxShadow: DfShadows.floating,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const DfBoardGlyph(size: 22),
            const SizedBox(width: 6),
            Expanded(
              child: Container(
                height: 8,
                decoration: BoxDecoration(
                  color: isDark ? DfColors.surfaceAltDark : DfColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ]),
          const SizedBox(height: DfSpacing.md),
          for (final color in [DfColors.statusAmber, DfColors.statusGreen, DfColors.statusRed, DfColors.statusBlue]) ...[
            Row(children: [
              Expanded(
                flex: 3,
                child: Container(
                  height: 9,
                  decoration: BoxDecoration(
                    color: isDark ? DfColors.surfaceAltDark : DfColors.surfaceAlt,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 34,
                height: 12,
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
              ),
            ]),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}
