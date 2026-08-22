import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'tokens.dart';

/// Inter is bundled as a variable font, so every style must carry the wght
/// axis explicitly — [FontWeight] alone does not move variable axes.
TextStyle _inter(double size, FontWeight weight, Color color, {double? height, double letterSpacing = 0}) {
  final wght = switch (weight) {
    FontWeight.w400 => 400.0,
    FontWeight.w500 => 500.0,
    FontWeight.w600 => 600.0,
    FontWeight.w700 => 700.0,
    FontWeight.w800 => 800.0,
    _ => 400.0,
  };
  return TextStyle(
    fontFamily: 'Inter',
    fontSize: size,
    fontWeight: weight,
    fontVariations: [FontVariation('wght', wght)],
    color: color,
    height: height,
    letterSpacing: letterSpacing,
  );
}

TextTheme _textTheme(Color primary, Color secondary) => TextTheme(
      displaySmall: _inter(28, FontWeight.w800, primary, height: 1.2, letterSpacing: -0.5),
      headlineMedium: _inter(24, FontWeight.w700, primary, height: 1.25, letterSpacing: -0.4),
      headlineSmall: _inter(20, FontWeight.w700, primary, height: 1.3, letterSpacing: -0.2),
      titleLarge: _inter(17, FontWeight.w600, primary, height: 1.3),
      titleMedium: _inter(15, FontWeight.w600, primary, height: 1.35),
      titleSmall: _inter(13, FontWeight.w600, primary, height: 1.35),
      bodyLarge: _inter(16, FontWeight.w400, primary, height: 1.45),
      bodyMedium: _inter(14, FontWeight.w400, primary, height: 1.45),
      bodySmall: _inter(12, FontWeight.w400, secondary, height: 1.4),
      labelLarge: _inter(15, FontWeight.w600, primary, height: 1.2),
      labelMedium: _inter(13, FontWeight.w500, secondary, height: 1.2),
      labelSmall: _inter(11, FontWeight.w500, secondary, height: 1.2, letterSpacing: 0.2),
    );

ThemeData dayflowLightTheme() {
  final text = _textTheme(DfColors.textPrimary, DfColors.textSecondary);
  final scheme = ColorScheme.fromSeed(
    seedColor: DfColors.primary,
    brightness: Brightness.light,
    primary: DfColors.primary,
    surface: DfColors.surface,
    error: DfColors.danger,
  );
  return _base(scheme, text).copyWith(
    scaffoldBackgroundColor: DfColors.bg,
    appBarTheme: AppBarTheme(
      backgroundColor: DfColors.bg,
      foregroundColor: DfColors.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      titleTextStyle: text.titleLarge,
      systemOverlayStyle: SystemUiOverlayStyle.dark,
    ),
    dividerTheme: const DividerThemeData(color: DfColors.border, thickness: 1, space: 1),
  );
}

ThemeData dayflowDarkTheme() {
  final text = _textTheme(DfColors.textPrimaryDark, DfColors.textSecondaryDark);
  final scheme = ColorScheme.fromSeed(
    seedColor: DfColors.primary,
    brightness: Brightness.dark,
    primary: DfColors.primary,
    surface: DfColors.surfaceDark,
    error: DfColors.danger,
  );
  return _base(scheme, text).copyWith(
    scaffoldBackgroundColor: DfColors.bgDark,
    appBarTheme: AppBarTheme(
      backgroundColor: DfColors.bgDark,
      foregroundColor: DfColors.textPrimaryDark,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      titleTextStyle: text.titleLarge,
      systemOverlayStyle: SystemUiOverlayStyle.light,
    ),
    dividerTheme: const DividerThemeData(color: DfColors.borderDark, thickness: 1, space: 1),
  );
}

ThemeData _base(ColorScheme scheme, TextTheme text) {
  final isDark = scheme.brightness == Brightness.dark;
  final border = isDark ? DfColors.borderDark : DfColors.border;
  final surface = isDark ? DfColors.surfaceDark : DfColors.surface;
  final hint = isDark ? DfColors.textTertiaryDark : DfColors.textTertiary;

  OutlineInputBorder inputBorder(Color color, {double width = 1}) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(DfRadius.md),
        borderSide: BorderSide(color: color, width: width),
      );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    textTheme: text,
    fontFamily: 'Inter',
    splashFactory: InkSparkle.splashFactory,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: DfSpacing.md, vertical: 14),
      hintStyle: text.bodyLarge?.copyWith(color: hint),
      labelStyle: text.labelMedium,
      floatingLabelStyle: text.labelMedium?.copyWith(color: DfColors.primary),
      border: inputBorder(border),
      enabledBorder: inputBorder(border),
      focusedBorder: inputBorder(DfColors.primary, width: 1.5),
      errorBorder: inputBorder(DfColors.danger),
      focusedErrorBorder: inputBorder(DfColors.danger, width: 1.5),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: isDark ? DfColors.surfaceAltDark : DfColors.textPrimary,
      contentTextStyle: text.bodyMedium?.copyWith(color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DfRadius.md)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(DfRadius.xl)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DfRadius.lg)),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
    }),
  );
}
