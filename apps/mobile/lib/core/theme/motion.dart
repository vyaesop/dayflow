import 'package:flutter/animation.dart';

/// Dayflow motion tokens, lifted from monday.com's Vibe design system
/// (`packages/style/src/motion.scss`) so the app carries the same feel the
/// static design screenshots cannot show.
///
/// Two speeds:
///  - **Productive** (70–150ms) — task-focused state changes the user should
///    barely notice: hovers, cell value swaps, toggles.
///  - **Expressive** (250–400ms) — moments where the motion itself carries
///    meaning: entrances, sheets, celebrations.
abstract final class DfMotion {
  // Durations (Vibe: --motion-productive-* / --motion-expressive-*).
  static const productiveShort = Duration(milliseconds: 70);
  static const productiveMedium = Duration(milliseconds: 100);
  static const productiveLong = Duration(milliseconds: 150);
  static const expressiveShort = Duration(milliseconds: 250);
  static const expressiveLong = Duration(milliseconds: 400);

  // Easing (Vibe: --motion-timing-*).
  /// Entrances decelerate into place.
  static const enter = Cubic(0, 0, 0.35, 1);

  /// Exits accelerate away.
  static const exit = Cubic(0.4, 0, 1, 1);

  /// In-place transitions (color, size, position swaps).
  static const transition = Cubic(0.4, 0, 0.2, 1);

  /// The monday signature: overshoots ~5% then settles. Draws attention.
  static const emphasize = Cubic(0, 0, 0.2, 1.4);

  /// Stagger step between siblings entering as a list.
  static const staggerStep = Duration(milliseconds: 40);
}
