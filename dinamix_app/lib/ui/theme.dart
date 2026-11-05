import 'package:flutter/material.dart';

/// Near-black surfaces with the electric cyan of the DinamiX prototype.
class Palette {
  static const Color brand = Color(0xFF0B6FDB);
  static const Color brandBright = Color(0xFF38C6F4);
  static const Color cyan = Color(0xFF00D0FF);

  static const List<Color> brandGradient = [Color(0xFF12D8FF), Color(0xFF0A7BE8)];

  static const Color darkBackground = Color(0xFF04070C);
  static const Color darkSurface = Color(0xFF0E141D);
  static const Color darkSurfaceHigh = Color(0xFF172130);
  static const Color darkCard = Color(0xB80F1722);
  static const Color darkOutline = Color(0x1FFFFFFF);

  static const Color lightBackground = Color(0xFFF2F6FB);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightCard = Color(0xE6FFFFFF);
  static const Color lightOutline = Color(0xFFDCE4EE);

  static const Color ok = Color(0xFF27E0A3);
  static const Color warning = Color(0xFFFFB547);
  static const Color danger = Color(0xFFFF4D5E);
  static const Color simulation = Color(0xFFFFB547);

  /// X, Y, Z and 4th channel: distinguishable also with color vision deficiency.
  static const List<Color> axes = [
    Color(0xFF38C6F4),
    Color(0xFFFF8A4C),
    Color(0xFF27E0A3),
    Color(0xFFC59BFF),
  ];
}

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: Palette.brand,
    brightness: brightness,
  ).copyWith(
    primary: dark ? Palette.brandBright : Palette.brand,
    onPrimary: dark ? const Color(0xFF00202E) : Colors.white,
    surface: dark ? Palette.darkSurface : Palette.lightSurface,
    surfaceContainerHighest: dark ? Palette.darkSurfaceHigh : const Color(0xFFE9EFF6),
    outlineVariant: dark ? Palette.darkOutline : Palette.lightOutline,
    error: Palette.danger,
  );
  final outline = BorderSide(color: scheme.outlineVariant);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    // The animated background sits behind the navigator.
    scaffoldBackgroundColor: Colors.transparent,
    canvasColor: scheme.surface,
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {TargetPlatform.android: FadeForwardsPageTransitionsBuilder()},
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 26,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.6,
        color: scheme.onSurface,
      ),
    ),
    cardTheme: CardThemeData(
      color: dark ? Palette.darkCard : Palette.lightCard,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: outline,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 52),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 52),
        side: outline,
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
}

/// Tabular figures: live numbers do not move sideways when they change.
const TextStyle numericStyle = TextStyle(
  fontFeatures: [FontFeature.tabularFigures()],
  fontWeight: FontWeight.w600,
);
