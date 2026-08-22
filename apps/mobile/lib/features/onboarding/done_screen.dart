import 'dart:math' as math;

import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/theme/tokens.dart';
import '../../ui/widgets/df_button.dart';

/// Confetti finale after signup, then into the app.
class OnboardingDoneScreen extends ConsumerStatefulWidget {
  const OnboardingDoneScreen({super.key});

  @override
  ConsumerState<OnboardingDoneScreen> createState() => _OnboardingDoneScreenState();
}

class _OnboardingDoneScreenState extends ConsumerState<OnboardingDoneScreen> {
  late final ConfettiController _confetti =
      ConfettiController(duration: const Duration(seconds: 2))..play();

  @override
  void dispose() {
    _confetti.dispose();
    super.dispose();
  }

  void _finish() {
    ref.read(authControllerProvider.notifier).completeFirstRun();
    context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: Stack(children: [
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: DfSpacing.xl),
            child: Column(children: [
              const Spacer(flex: 2),
              Container(
                width: 96,
                height: 96,
                decoration: const BoxDecoration(color: DfColors.success, shape: BoxShape.circle),
                child: const Icon(Icons.check_rounded, color: Colors.white, size: 56),
              ),
              const SizedBox(height: DfSpacing.xl),
              Text('Done!', style: text.displaySmall),
              const SizedBox(height: DfSpacing.xs),
              Text(
                'Your workspace is ready.\nLet’s get your work flowing.',
                textAlign: TextAlign.center,
                style: text.bodyMedium?.copyWith(color: DfColors.textSecondary),
              ),
              const Spacer(flex: 3),
              DfButton(label: 'Start exploring', onPressed: _finish),
              const SizedBox(height: DfSpacing.xl),
            ]),
          ),
        ),
        Align(
          alignment: Alignment.topCenter,
          child: ConfettiWidget(
            confettiController: _confetti,
            blastDirection: math.pi / 2,
            emissionFrequency: 0.28,
            numberOfParticles: 14,
            maxBlastForce: 24,
            minBlastForce: 8,
            gravity: 0.25,
            colors: const [
              DfColors.primary,
              DfColors.accentGreen,
              DfColors.accentAmber,
              DfColors.accentPink,
              DfColors.accentBlue,
            ],
          ),
        ),
      ]),
    );
  }
}
