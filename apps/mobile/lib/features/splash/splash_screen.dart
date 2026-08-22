import 'package:flutter/material.dart';

import '../../ui/widgets/df_logo.dart';

/// Brand splash shown while the session restores.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: FadeTransition(
          opacity: CurvedAnimation(parent: _controller, curve: Curves.easeOut),
          child: ScaleTransition(
            scale: Tween(begin: 0.86, end: 1.0)
                .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack)),
            child: const DfLogoMark(size: 88),
          ),
        ),
      ),
    );
  }
}
