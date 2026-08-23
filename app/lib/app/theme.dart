import 'package:flutter/material.dart';

import '../data/accent/accent_surfaces.dart';

export '../data/accent/accent_surfaces.dart'
    show ChordiaSurfaces, ChordiaSurfacesOf;

/// Chordia's palette, carried over from the web client so the two clients read as one product.
///
/// **These are the DEFAULT accent's values, not the app's palette.** Every one of them is now
/// computed by [ChordiaSurfaces] from whatever accent the account is wearing — which is the point:
/// the web derives its entire surface set from `--primary` with `color-mix(in oklab, …)`, so
/// choosing amber there re-tints every pane, card and hairline. Mobile froze these same numbers as
/// constants, and that single difference is most of why the phone "feels like a completely
/// different app".
///
/// They stay because they are the checked fallback: with no session, no settings and no accent,
/// the app must still be the app. `accent_test.dart` asserts that
/// `ChordiaSurfaces.of(builtinAccent)` reproduces them, so a drift in the colour maths fails a
/// test rather than shipping a slightly-off product.
///
/// **Do not reach for these in a widget.** Use `context.surfaces` (or `Theme.of(context)`), or the
/// widget will not follow the account's colour — which is the bug this file was rewritten to fix.
abstract final class ChordiaColors {
  /// `--primary`: oklch(0.56 0.28 337). Out-of-gamut vivid; it clips to a strong magenta on both
  /// platforms, which is the intended look.
  static const accent = Color(0xFFCD00AE);

  /// `--pane`: the app background, a near-black tinted toward the accent.
  static const pane = Color(0xFF040208);

  /// `--pane-raised`: cards, sheets, the player bar.
  static const paneRaised = Color(0xFF090411);

  /// One step brighter again, for controls resting on a raised pane.
  static const paneElevated = Color(0xFF170E18);

  /// `--accent-foreground`: primary text. Not accent-derived on the web either — it is
  /// `oklch(0.95 0.015 285)` in `:root`, outside the `.accent-scope` block.
  static const foreground = Color(0xFFEDEDF8);

  /// `--muted-foreground`. Also fixed on the web, and kept at the phone's slightly brighter value:
  /// the web's `oklch(0.56 0.03 285)` measures 4.2:1 on a desk monitor and is the first thing to
  /// disappear on a phone outdoors.
  static const mutedForeground = Color(0xFF9B97AE);

  /// The BASE of `--border`, before the accent is mixed into it. Kept only for reference — the
  /// hairline the app actually draws is [ChordiaSurfaces.border], which carries the tint.
  static const line = Color(0xFF241E33);

  /// `--destructive`. Fixed, and again kept at the phone's brighter value, because an error
  /// message is the worst place to save a little contrast.
  static const danger = Color(0xFFFF5C7A);
}

/// The app's Material theme, derived from one accent.
///
/// Pass the account's [ChordiaSurfaces] — `chordiaThemeProvider` does. The default argument is the
/// built-in accent's set, which is what a widget test with no session gets.
ThemeData buildChordiaTheme([ChordiaSurfaces? surfaces]) {
  final s = surfaces ?? ChordiaSurfaces.fallback;

  final scheme =
      ColorScheme.fromSeed(
        seedColor: s.accent,
        brightness: Brightness.dark,
      ).copyWith(
        primary: s.accent,
        onPrimary: s.accentForeground,
        surface: s.pane,
        onSurface: ChordiaColors.foreground,
        surfaceContainerLowest: s.background,
        surfaceContainerLow: s.pane,
        surfaceContainer: s.paneRaised,
        surfaceContainerHigh: s.card,
        surfaceContainerHighest: s.paneElevated,
        onSurfaceVariant: ChordiaColors.mutedForeground,
        outline: s.border,
        // The faint accent hairline. Translucent, so it reads on any of the panes.
        outlineVariant: s.line,
        error: ChordiaColors.danger,
      );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    // Carried on the theme so any widget can reach the tokens Material has no role for —
    // `paneRaised`, `surfaceStrong`, `line`, `ambientCool`.
    extensions: [s],
    scaffoldBackgroundColor: s.pane,
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
    ),
    navigationBarTheme: NavigationBarThemeData(
      // `--surface-strong`: fixed chrome that content passes UNDER, and fully opaque on purpose.
      backgroundColor: s.surfaceStrong,
      surfaceTintColor: Colors.transparent,
      indicatorColor: s.accent.withValues(alpha: 0.18),
      // The tab bar sits directly under the mini-player, so it stays compact.
      height: 64,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
    ),
    // `DropdownButton` paints its menu with `canvasColor`, not with a surface role, so without
    // this the menu arrives in Material's default near-white and reads as a different app.
    canvasColor: s.popover,
    popupMenuTheme: PopupMenuThemeData(
      color: s.popover,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      menuStyle: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(s.popover),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    ),
    cardTheme: CardThemeData(
      color: s.card,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    dividerTheme: DividerThemeData(color: s.border, space: 1, thickness: 1),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      // `--input-fill` is the field interior and `--input` its border. They used to be one value
      // on the web too, which drew an edge almost identical to the surface behind it and made
      // every input read as a floating label with no box.
      fillColor: s.inputFill,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: s.input),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: s.input),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: s.accent, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: ChordiaColors.mutedForeground,
      textColor: ChordiaColors.foreground,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: s.paneElevated,
      contentTextStyle: const TextStyle(color: ChordiaColors.foreground),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: s.paneRaised,
      surfaceTintColor: Colors.transparent,
      dragHandleColor: ChordiaColors.mutedForeground,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: s.popover,
      surfaceTintColor: Colors.transparent,
    ),
  );
}
