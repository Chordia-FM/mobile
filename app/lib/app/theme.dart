import 'package:flutter/material.dart';

/// Chordia's palette, carried over from the web client so the two clients read as one product.
///
/// The web tokens are authored in OKLCH (`frontend/src/styles.css`); these are the sRGB values
/// they resolve to. The accent is deliberately out-of-gamut-vivid — it clips to a strong magenta
/// on both platforms, which is the intended look.
abstract final class ChordiaColors {
  /// `--primary`: oklch(0.56 0.28 337)
  static const accent = Color(0xFFCD00AE);

  /// `--pane`: the app background, a near-black tinted toward the accent.
  static const pane = Color(0xFF040208);

  /// `--pane-raised`: cards, sheets, the player bar.
  static const paneRaised = Color(0xFF090411);

  /// One step brighter again, for controls resting on a raised pane.
  static const paneElevated = Color(0xFF141020);

  /// `--accent-foreground`: primary text.
  static const foreground = Color(0xFFEDEDF8);

  static const mutedForeground = Color(0xFF9B97AE);
  static const line = Color(0xFF241E33);
  static const danger = Color(0xFFFF5C7A);
}

ThemeData buildChordiaTheme() {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: ChordiaColors.accent,
        brightness: Brightness.dark,
      ).copyWith(
        primary: ChordiaColors.accent,
        onPrimary: Colors.white,
        surface: ChordiaColors.pane,
        onSurface: ChordiaColors.foreground,
        surfaceContainerLowest: ChordiaColors.pane,
        surfaceContainer: ChordiaColors.paneRaised,
        surfaceContainerHigh: ChordiaColors.paneElevated,
        onSurfaceVariant: ChordiaColors.mutedForeground,
        outline: ChordiaColors.line,
        error: ChordiaColors.danger,
      );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: ChordiaColors.pane,
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: ChordiaColors.paneRaised,
      surfaceTintColor: Colors.transparent,
      indicatorColor: ChordiaColors.accent.withValues(alpha: 0.18),
      // The tab bar sits directly under the mini-player, so it stays compact.
      height: 64,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
    ),
    cardTheme: CardThemeData(
      color: ChordiaColors.paneRaised,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    dividerTheme: const DividerThemeData(
      color: ChordiaColors.line,
      space: 1,
      thickness: 1,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: ChordiaColors.paneElevated,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: ChordiaColors.mutedForeground,
      textColor: ChordiaColors.foreground,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: ChordiaColors.paneElevated,
      contentTextStyle: const TextStyle(color: ChordiaColors.foreground),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
  );
}
