import 'package:flutter/material.dart';

import '../data/accent/accent_surfaces.dart';
import '../widgets/tokens.dart';

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

/// The web's type scale, on Material's fifteen slots.
///
/// Installing this is what makes the app read as Chordia rather than as a Flutter app: without a
/// `textTheme` the phone fell back to Material's 2021 typography in Roboto, so the 35 sites that
/// opted into [ChordiaType] were the only ones set in the product's own scale and everything else
/// was a size, a weight and a face the web has never drawn.
///
/// Every slot is [ChordiaType.sans] except `display*`, which is the serif. That split is the web's:
/// `.display-title` appears on 19 elements and all 19 are page `<h1>`s, so a screen title reaches
/// for `textTheme.displayMedium` and a stat value or a now-playing line — both of which the phone
/// currently sets in `headlineSmall` — keeps the sans it should have.
///
/// The three `display*` sizes are the three the phone column actually renders: below `sm` the H1s
/// resolve to `text-4xl`, `text-3xl` and `text-2xl`. `ArtistView`'s unconditional `text-5xl` is not
/// among them because 48px of serif on a 390pt screen is a different design, not the same one.
///
/// `letterSpacing: 0` on every slot is deliberate and load-bearing. Material's defaults carry
/// tracking (bodyMedium is 0.25), Tailwind's `tracking-normal` is 0, and `TextTheme.merge` keeps
/// any field left null — so an unset letter-spacing here would silently inherit Roboto's.
final _chordiaTextTheme = () {
  TextStyle sans(TextStyle metrics, FontWeight weight) => metrics.copyWith(
    fontFamily: ChordiaType.sans,
    fontWeight: weight,
    letterSpacing: 0,
  );
  TextStyle display(TextStyle metrics) => metrics.copyWith(
    fontFamily: ChordiaType.display,
    fontWeight: ChordiaType.bold,
    letterSpacing: 0,
  );

  return TextTheme(
    displayLarge: display(ChordiaType.xl4),
    displayMedium: display(ChordiaType.xl3),
    displaySmall: display(ChordiaType.xl2),
    headlineLarge: sans(ChordiaType.xl3, ChordiaType.bold),
    headlineMedium: sans(ChordiaType.xl2, ChordiaType.bold),
    // `RailHeader` is `font-semibold text-xl`, and it is the heading the app has most of.
    headlineSmall: sans(ChordiaType.xl, ChordiaType.semibold),
    titleLarge: sans(ChordiaType.lg, ChordiaType.semibold),
    titleMedium: sans(ChordiaType.base, ChordiaType.semibold),
    titleSmall: sans(ChordiaType.sm, ChordiaType.semibold),
    bodyLarge: sans(ChordiaType.base, FontWeight.w400),
    // `text-sm` is the web's default body size, not `text-base` — a track row is `text-sm` over
    // `text-xs`, and `bodyMedium` is what an unstyled `Text` inherits.
    bodyMedium: sans(ChordiaType.sm, FontWeight.w400),
    bodySmall: sans(ChordiaType.xs, FontWeight.w400),
    // A button's label: `text-sm font-medium` (button.tsx:8).
    labelLarge: sans(ChordiaType.sm, ChordiaType.medium),
    labelMedium: sans(ChordiaType.xs, ChordiaType.medium),
    // Material's `labelSmall` is 11px. The web has no step below `text-xs`, so neither does this.
    labelSmall: sans(ChordiaType.xs, ChordiaType.medium),
  );
}();

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
    textTheme: _chordiaTextTheme,
    // Carried on the theme so any widget can reach the tokens Material has no role for —
    // `paneRaised`, `surfaceStrong`, `line`, `ambientCool`.
    extensions: [s],
    scaffoldBackgroundColor: s.pane,
    // No ripple, anywhere, unless a widget asks for one — see the note on `PressFill`. This was
    // `InkSparkle.splashFactory`, which turned the Android-12 spreading sparkle ON for the whole
    // app while the app's own rule said the opposite; the six primitives that had opted out with
    // `NoSplash` were carrying a convention the theme was busy contradicting.
    splashFactory: NoSplash.splashFactory,
    // With the splash gone the highlight IS the press feedback, so it has to be the right colour:
    // Material's default is a light grey wash that reads as dust on these near-black panes. This
    // is the web's own row fill, `hover:bg-accent/50`. Buttons never see it — `ButtonStyle`
    // resolves its own `overlayColor` — so it lands exactly where it should, on the bare
    // `InkWell`s and `ListTile`s that have no style of their own.
    highlightColor: scheme.rowHighlight,
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
      shape: const RoundedRectangleBorder(borderRadius: ChordiaRadius.lgAll),
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      menuStyle: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(s.popover),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: const WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: ChordiaRadius.lgAll),
        ),
      ),
    ),
    cardTheme: CardThemeData(
      color: s.card,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: const RoundedRectangleBorder(borderRadius: ChordiaRadius.lgAll),
    ),
    dividerTheme: DividerThemeData(color: s.border, space: 1, thickness: 1),
    // Every button family, not just the filled one.
    //
    // `button.tsx:8` puts `rounded-md` on the base class and :29-39 gives every size a
    // `h-(--control-h-*)` box, which the coarse block grows so the control clears 44px. Only
    // `FilledButton` was themed here, so the app's 45 `TextButton`s and 10 `OutlinedButton`s kept
    // Material's `StadiumBorder` — pills, at 40px, sitting next to 48px rectangles. Two design
    // systems in one row.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, ChordiaControl.md),
        shape: const RoundedRectangleBorder(borderRadius: ChordiaRadius.mdAll),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(0, ChordiaControl.md),
        shape: const RoundedRectangleBorder(borderRadius: ChordiaRadius.mdAll),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      // The web's `outline` variant is `border border-input bg-input-fill` — a real field-coloured
      // box, not a hairline over the pane. Both halves matter: `--input` was split off `--border`
      // precisely because an edge the same value as the surface behind it made the control
      // disappear.
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, ChordiaControl.md),
        shape: const RoundedRectangleBorder(borderRadius: ChordiaRadius.mdAll),
        side: BorderSide(color: s.input),
        backgroundColor: s.inputFill,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      // `size-(--control-h-md)` = 48, against Flutter's 40. The glyph is untouched: the coarse
      // block grows the BOX only, and so does this.
      style: IconButton.styleFrom(
        minimumSize: const Size.square(ChordiaControl.md),
        shape: const RoundedRectangleBorder(borderRadius: ChordiaRadius.mdAll),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      // `--input-fill` is the field interior and `--input` its border. They used to be one value
      // on the web too, which drew an edge almost identical to the surface behind it and made
      // every input read as a floating label with no box.
      fillColor: s.inputFill,
      border: OutlineInputBorder(
        borderRadius: ChordiaRadius.mdAll,
        borderSide: BorderSide(color: s.input),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: ChordiaRadius.mdAll,
        borderSide: BorderSide(color: s.input),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: ChordiaRadius.mdAll,
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
      shape: const RoundedRectangleBorder(borderRadius: ChordiaRadius.mdAll),
    ),
    // A sheet and a dialog are the same panel on the web — `responsive-dialog.tsx:206` renders one
    // element with `island-shell island-shell-modal`, and :221/:228 give it `rounded-2xl`, which
    // resolves to Tailwind's own 16px because the `@theme` block stops at `--radius-xl`. Flutter's
    // Material 3 default is 28, a corner the web has nowhere.
    //
    // The MATERIAL is still missing: `.island-shell-modal` is an accent border over a two-stop
    // gradient, and `BottomSheetThemeData` has no decoration to hang either on. That belongs to
    // `ModalPanel` at the 26 `showModalBottomSheet` call sites, which live outside this file.
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: s.paneRaised,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(ChordiaRadius.xl),
        ),
      ),
      // `h-1 w-9 rounded-full bg-muted-foreground/40`. At full strength the handle reads as a
      // component; at 40% it reads as the grab affordance it is.
      dragHandleColor: ChordiaColors.mutedForeground.withValues(alpha: 0.4),
      dragHandleSize: const Size(36, 4),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: s.popover,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: ChordiaRadius.xlAll),
    ),
  );
}
