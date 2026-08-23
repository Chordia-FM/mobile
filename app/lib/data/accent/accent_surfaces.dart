import 'package:flutter/material.dart';

import 'accent_engine.dart' show foregroundFor;
import 'accent_palette.dart';
import 'oklab.dart';

/// Every surface in the app, derived from one accent.
///
/// This is the port of the `:root, .accent-scope` block in `frontend/src/styles.css`, and it is
/// the whole reason mobile read as a different product. The web builds `--pane`, `--pane-raised`,
/// `--background`, `--card`, `--muted`, `--border` and the rest with
/// `color-mix(in oklab, var(--primary) N%, <base>)`, so changing the accent re-tints the entire
/// interface. Mobile had those same values frozen as hex constants — a static dark theme wearing
/// the default accent's numbers, which is exactly why picking amber on the desktop left the phone
/// on cool violet panes.
///
/// Two rules carried over verbatim from the stylesheet's own comments:
///
///   - **The mix percentages are small (3-8%) and rise with lightness**, so raised surfaces read
///     as slightly more tinted rather than merely lighter.
///   - **Lightness is unchanged from the fixed values these replaced.** The surface hierarchy must
///     not move when the tint does. A new surface derives the same way; a hard-coded hue-280 value
///     looks wrong on six of the eleven presets.
///
/// The bases are near-neutral (chroma ≤ 0.009 for the shadcn tokens) precisely so the accent
/// supplies the temperature. They used to be pinned to a blue-violet, which fought the warm half
/// of the palette.
/// It is a [ThemeExtension], so every widget reaches the full token set through
/// `Theme.of(context).extension<ChordiaSurfaces>()` — or `context.surfaces` — rather than through
/// the handful of roles `ColorScheme` happens to have names for. `--pane-raised`,
/// `--surface-strong`, `--line` and `--ambient-cool` have no Material equivalent, and a widget
/// that hard-codes one of them is the bug this whole file exists to fix.
/// `--ambient-cool`: a companion hue for the page's ambient wash.
///
/// Still accent-derived, so the canvas re-tints with the account's colour, but pulled toward
/// `--neon-blue` so the page reads as lit from two sides rather than washed in one colour.
///
/// A free function as well as a token because the two callers want it at different moments. The
/// token is the RESTING derivation, baked into the theme; `accent_canvas.dart` re-derives it per
/// frame while a mode is actually moving the accent, which is what the browser gets for nothing —
/// `--ambient-cool` is a `color-mix` off `--primary`, so repainting `--primary` moves the wash
/// within the same frame.
Color ambientCoolFor(Color accent) =>
    mixOklab(accent, 0.45, oklch(0.79, 0.10, 210));

@immutable
class ChordiaSurfaces extends ThemeExtension<ChordiaSurfaces> {
  const ChordiaSurfaces._({
    required this.accent,
    required this.accentForeground,
    required this.pane,
    required this.paneRaised,
    required this.paneElevated,
    required this.background,
    required this.card,
    required this.popover,
    required this.secondary,
    required this.muted,
    required this.border,
    required this.input,
    required this.inputFill,
    required this.sidebar,
    required this.surfaceStrong,
    required this.line,
    required this.ambientCool,
  });

  /// Derive the whole set from one accent.
  ///
  /// [gradientEnd] is the palette's far stop in Gradient mode, which the web substitutes into
  /// `--ambient-cool` so the page's bloom is lit by two of the user's own colours rather than by
  /// one of them and a fixed blue.
  factory ChordiaSurfaces.of(Color accent, {Color? gradientEnd}) {
    return ChordiaSurfaces._(
      accent: accent,
      accentForeground: foregroundFor(accent),
      // `--pane` / `--pane-raised`: the shell panes. Opaque on purpose — they used to be
      // translucent cards, which is why the old dot-grid was visible through every panel.
      pane: mixOklab(accent, 0.04, oklch(0.075, 0.018, 282)),
      paneRaised: mixOklab(accent, 0.05, oklch(0.105, 0.024, 282)),
      // `--accent`, the lightest of the shadcn surfaces: a control resting on a raised pane.
      paneElevated: mixOklab(accent, 0.08, oklch(0.145, 0.009, 285)),
      background: mixOklab(accent, 0.03, oklch(0.048, 0.006, 285)),
      card: mixOklab(accent, 0.05, oklch(0.115, 0.008, 285)),
      popover: mixOklab(accent, 0.04, oklch(0.088, 0.007, 285)),
      secondary: mixOklab(accent, 0.06, oklch(0.125, 0.008, 285)),
      muted: mixOklab(accent, 0.06, oklch(0.125, 0.008, 285)),
      // `in srgb`, not oklab, exactly as the stylesheet writes it.
      border: mixSrgb(accent, 0.16, oklch(0.22, 0.02, 280)),
      // `--input` is the field BORDER and `--input-fill` its interior. They used to be one value,
      // which drew an edge almost identical to the surface behind it and made every field read as
      // a floating label with no box.
      input: mixOklab(accent, 0.16, oklch(0.30, 0.02, 282)),
      inputFill: mixOklab(accent, 0.04, oklch(0.098, 0.007, 285)),
      sidebar: mixOklab(accent, 0.04, oklch(0.078, 0.007, 285)),
      // Fixed chrome that content passes UNDER: the player bar, the tab bar, sheets. FULLY
      // OPAQUE, deliberately — at 94% a bright cover sliding beneath reads as dirty rather than
      // translucent, and there is no backdrop blur to soften it (that cost a whole session to
      // remove).
      surfaceStrong: mixOklab(accent, 0.04, const Color(0xFF0A0A0D)),
      // `color-mix(in srgb, var(--primary) 18%, transparent)`. Written out rather than run through
      // `mixSrgb`, because CSS mixes with `transparent` in PREMULTIPLIED alpha: the result is the
      // accent at 18% opacity, not the accent darkened toward black.
      line: accent.withValues(alpha: 0.18),
      ambientCool: gradientEnd ?? ambientCoolFor(accent),
    );
  }

  /// The set the app wears before any account has been read.
  static final ChordiaSurfaces fallback = ChordiaSurfaces.of(builtinAccent);

  /// `--primary` / `--ring`.
  final Color accent;

  /// `--primary-foreground`: what reads on top of [accent].
  final Color accentForeground;

  final Color pane;
  final Color paneRaised;
  final Color paneElevated;
  final Color background;
  final Color card;
  final Color popover;
  final Color secondary;
  final Color muted;
  final Color border;
  final Color input;
  final Color inputFill;
  final Color sidebar;
  final Color surfaceStrong;

  /// The accent-tinted hairline, `--line`. Translucent, so it works over any of the panes.
  final Color line;

  /// `--ambient-cool`, the second light source in the page's bloom.
  final Color ambientCool;

  /// Every token is a pure function of the accent, so "changing one" means deriving the set again.
  @override
  ChordiaSurfaces copyWith({Color? accent, Color? ambientCool}) =>
      ChordiaSurfaces.of(accent ?? this.accent, gradientEnd: ambientCool);

  /// Interpolating the accent and re-deriving, rather than interpolating forty tokens
  /// independently: the set has to stay internally consistent at every point of the animation.
  @override
  ChordiaSurfaces lerp(ThemeExtension<ChordiaSurfaces>? other, double t) {
    if (other is! ChordiaSurfaces) return this;
    return ChordiaSurfaces.of(Color.lerp(accent, other.accent, t) ?? accent);
  }

  @override
  bool operator ==(Object other) =>
      other is ChordiaSurfaces &&
      other.accent == accent &&
      other.ambientCool == ambientCool;

  @override
  int get hashCode => Object.hash(accent, ambientCool);
}

/// `Theme.of(context).extension<ChordiaSurfaces>()`, without the ceremony.
extension ChordiaSurfacesOf on BuildContext {
  /// The derived surface set for this subtree, falling back to the default accent's when no theme
  /// carries one — which is what a widget test that builds a bare `MaterialApp` gets.
  ChordiaSurfaces get surfaces =>
      Theme.of(this).extension<ChordiaSurfaces>() ?? ChordiaSurfaces.fallback;
}
