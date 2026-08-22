import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/tokens.dart';
import '../../ui/widgets/df_button.dart';

/// Post-signup notification permission ask (permission wiring lands with FCM).
class NotificationsAskScreen extends StatelessWidget {
  const NotificationsAskScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: DfSpacing.xl),
          child: Column(children: [
            const Spacer(),
            const _MentionIllustration(),
            const Spacer(),
            Text(
              "Allow notifications to know when you're mentioned",
              textAlign: TextAlign.center,
              style: text.headlineSmall,
            ),
            const SizedBox(height: DfSpacing.xs),
            Text(
              'You can pause or turn them off anytime',
              textAlign: TextAlign.center,
              style: text.bodySmall,
            ),
            const Spacer(),
            DfButton(label: 'Continue', onPressed: () => context.go('/onboarding/done')),
            const SizedBox(height: DfSpacing.xl),
          ]),
        ),
      ),
    );
  }
}

class _MentionIllustration extends StatelessWidget {
  const _MentionIllustration();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      width: 240,
      height: 190,
      child: Stack(alignment: Alignment.center, children: [
        Container(
          width: 170,
          height: 170,
          decoration: BoxDecoration(
            color: isDark ? DfColors.surfaceAltDark : DfColors.primarySubtle,
            shape: BoxShape.circle,
          ),
        ),
        Positioned(
          top: 34,
          child: Container(
            width: 200,
            padding: const EdgeInsets.all(DfSpacing.sm),
            decoration: BoxDecoration(
              color: isDark ? DfColors.surfaceDark : Colors.white,
              borderRadius: BorderRadius.circular(DfRadius.md),
              boxShadow: DfShadows.card,
            ),
            child: Row(children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: DfColors.primary,
                  borderRadius: BorderRadius.circular(9),
                ),
                alignment: Alignment.center,
                child: const Text('@',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontVariations: [FontVariation('wght', 800)],
                      fontSize: 16,
                    )),
              ),
              const SizedBox(width: DfSpacing.xs),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    height: 8,
                    width: 110,
                    decoration: BoxDecoration(
                      color: isDark ? DfColors.surfaceAltDark : DfColors.surfaceAlt,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    height: 8,
                    width: 70,
                    decoration: BoxDecoration(
                      color: isDark ? DfColors.surfaceAltDark : DfColors.surfaceAlt,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ]),
              ),
            ]),
          ),
        ),
        const Positioned(top: 18, right: 30, child: _Sparkle(color: DfColors.accentAmber, size: 14)),
        const Positioned(bottom: 24, left: 26, child: _Sparkle(color: DfColors.accentPink, size: 10)),
        const Positioned(bottom: 44, right: 42, child: _Sparkle(color: DfColors.primary, size: 8)),
      ]),
    );
  }
}

class _Sparkle extends StatelessWidget {
  const _Sparkle({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Icon(Icons.auto_awesome_rounded, color: color, size: size + 6);
  }
}
