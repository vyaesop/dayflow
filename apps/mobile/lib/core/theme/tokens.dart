import 'package:flutter/material.dart';

/// Dayflow design tokens.
///
/// The palette deliberately desaturates the candy-pastel reference design:
/// one restrained indigo primary, neutral surfaces, and status colors tuned
/// for WCAG AA contrast with white text.
abstract final class DfColors {
  // Brand
  static const primary = Color(0xFF5B5BD6);
  static const primaryPressed = Color(0xFF4E4EC4);
  static const primarySubtle = Color(0xFFEEEEFB); // chip fills, selected cards
  static const primaryBorder = Color(0xFFC9C9F0);

  // Hero gradient (favorites card) — softened lavender
  static const heroGradientStart = Color(0xFF8C8CE8);
  static const heroGradientEnd = Color(0xFF6E6EDC);

  // Light surfaces
  static const bg = Color(0xFFF7F8FA);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceAlt = Color(0xFFF1F2F6);
  static const border = Color(0xFFE9EAF0);
  static const borderStrong = Color(0xFFD8DAE4);

  // Light text
  static const textPrimary = Color(0xFF1B1D29);
  static const textSecondary = Color(0xFF6B6F80);
  static const textTertiary = Color(0xFF9CA0AF);
  static const textOnColor = Color(0xFFFFFFFF);

  // Dark surfaces
  static const bgDark = Color(0xFF121319);
  static const surfaceDark = Color(0xFF1B1D25);
  static const surfaceAltDark = Color(0xFF23252F);
  static const borderDark = Color(0xFF2E313D);
  static const borderStrongDark = Color(0xFF3B3F4E);

  // Dark text
  static const textPrimaryDark = Color(0xFFF2F3F7);
  static const textSecondaryDark = Color(0xFFA7ABBA);
  static const textTertiaryDark = Color(0xFF6E7383);

  // Status colors (desaturated, AA-safe with white text)
  static const statusAmber = Color(0xFFD08718);
  static const statusGreen = Color(0xFF2E9E6B);
  static const statusRed = Color(0xFFD65C6B);
  static const statusBlue = Color(0xFF4E7FD9);
  static const statusPurple = Color(0xFF8B66C9);
  static const statusGrey = Color(0xFFC4C7D4);

  // Group accent bars / avatars — muted family
  static const accentBlue = Color(0xFF4E7FD9);
  static const accentPurple = Color(0xFF8B66C9);
  static const accentGreen = Color(0xFF2E9E6B);
  static const accentPink = Color(0xFFD3679E);
  static const accentAmber = Color(0xFFD08718);
  static const accentRed = Color(0xFFD65C6B);
  static const accentTeal = Color(0xFF2E9E9E);
  static const accentIndigo = Color(0xFF5B5BD6);

  static const success = Color(0xFF2E9E6B);
  static const danger = Color(0xFFD65C6B);

  /// Resolves a server-side color token (group colors, status labels).
  static Color token(String name) => switch (name) {
        'blue' => accentBlue,
        'purple' => accentPurple,
        'green' => accentGreen,
        'pink' => accentPink,
        'amber' => accentAmber,
        'red' => accentRed,
        'teal' => accentTeal,
        'indigo' => accentIndigo,
        'grey' || 'gray' => statusGrey,
        _ => statusGrey,
      };

  /// Deterministic avatar color for a user id/name.
  static Color avatarFor(String seed) {
    const palette = [accentGreen, accentBlue, accentPurple, accentPink, accentAmber, accentTeal, accentIndigo];
    var hash = 0;
    for (final code in seed.codeUnits) {
      hash = (hash * 31 + code) & 0x7fffffff;
    }
    return palette[hash % palette.length];
  }
}

abstract final class DfSpacing {
  static const xxs = 4.0;
  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 20.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

abstract final class DfRadius {
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const pill = 999.0;
}

abstract final class DfShadows {
  static const card = [
    BoxShadow(color: Color(0x0A1B1D29), blurRadius: 12, offset: Offset(0, 2)),
    BoxShadow(color: Color(0x051B1D29), blurRadius: 3, offset: Offset(0, 1)),
  ];
  static const floating = [
    BoxShadow(color: Color(0x1F1B1D29), blurRadius: 24, offset: Offset(0, 8)),
  ];
}
