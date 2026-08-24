/// The accent presets, and how a stored `UserSettings.accent` becomes a colour.
///
/// A port of `ACCENTS` and `resolveAccent` from `frontend/src/lib/settings/store.ts`. The web
/// authors these in OKLCH and hands the string to CSS; here they are resolved through [oklch] so a
/// preset is the same colour on both clients by construction rather than by somebody transcribing
/// a hex code.
///
/// The trailing figure in each comment is measured contrast against the chart surface `#0f0f1e`,
/// which every accent must clear 3:1 — the accent doubles as the single-series chart colour.
/// `frontend/src/lib/settings/accent-contrast.test.ts` is what enforces that; do not nudge a value
/// here without moving it there.
///
/// **Append-only, and a key may only change its colour, never its spelling.** An unrecognised
/// `accent` is used verbatim as a CSS colour by the web client, and `pink`/`blue`/`green`/`purple`
/// are all real CSS colour names — so renaming one does not fall back to the default, it silently
/// repaints those accounts.
///
/// `app/lib/features/settings/data/settings_values.dart` carries the same twelve as swatches for
/// the picker, with their sRGB values written out. Those are exactly what this file computes; if
/// the two ever disagree, this one is the definition.
library;

import 'dart:ui' show Color;

import 'oklab.dart';

/// The colour the app wears when nobody has chosen anything: `oklch(0.56 0.28 337)`, clipped.
///
/// Byte-identical to `ChordiaColors.accent`, which is what keeps a signed-out phone and a
/// signed-in one on the default from being two different shades of pink.
const Color builtinAccent = Color(0xFFCD00AE);

/// The value `UserSettings.accent` takes when the listener has chosen no colour of their own.
///
/// Not a colour: it means "follow whatever this deployment's operator picked", so it keeps
/// tracking that choice if the operator changes it.
const String followInstanceAccent = 'default';

/// The presets, hue-ordered — insertion order IS the order of the swatch row.
final Map<String, Color> accentPresets = Map.unmodifiable({
  'crimson': oklch(0.63, 0.23, 22), //   4.83:1
  'ember': oklch(0.70, 0.19, 42), //     6.60:1
  'amber': oklch(0.78, 0.16, 85), //     9.37:1
  'lime': oklch(0.80, 0.19, 128), //    10.64:1
  'green': oklch(0.72, 0.19, 155), //    8.36:1
  'teal': oklch(0.72, 0.15, 178), //     8.36:1
  'blue': oklch(0.72, 0.16, 230), //     8.04:1
  'indigo': oklch(0.60, 0.25, 275), //   4.20:1
  'purple': oklch(0.58, 0.26, 300), //   3.87:1
  'magenta': oklch(0.68, 0.24, 340), //  5.82:1
  'pink': oklch(0.56, 0.28, 337), //     3.81:1  (the default)
});

/// A `#rgb` or `#rrggbb` string as a colour, or null for anything else.
///
/// Deliberately narrow. The web falls through to "use it verbatim as a CSS colour", which covers
/// `rebeccapurple` and `hsl(...)` too; a phone that guessed at those would paint something the web
/// does not, so anything unparseable resolves to the default instead.
Color? parseHexColor(String value) {
  var hex = value.trim();
  if (!hex.startsWith('#')) return null;
  hex = hex.substring(1);
  if (hex.length == 3) {
    hex = hex.split('').map((c) => '$c$c').join();
  }
  if (hex.length != 6) return null;
  final rgb = int.tryParse(hex, radix: 16);
  return rgb == null ? null : Color(0xFF000000 | rgb);
}

/// Resolve a stored `accent` value to the colour the app should wear.
///
/// [instanceAccent] is the operator's own choice, from `GET /v1/instance`. Null means they have
/// not made one and [builtinAccent] stands — which is different from their having chosen that
/// colour, because it keeps following the built-in if it moves.
Color resolveAccent(String? accent, {String? instanceAccent}) {
  final chosen =
      (accent == null || accent.isEmpty || accent == followInstanceAccent)
      ? instanceAccent
      : accent;
  if (chosen == null || chosen.isEmpty) return builtinAccent;
  return accentPresets[chosen] ?? parseHexColor(chosen) ?? builtinAccent;
}
