/// The web client's design tokens, ported by VALUE rather than by feel.
///
/// The complaint this exists to answer is that the phone "looks like a completely different app".
/// It did, and the reason was not colour alone: every radius, every type size and every hover fill
/// on the phone was a Material default, while the web derives all of them from one small set of
/// tokens in `frontend/src/styles.css`. Two apps built from two different scales cannot be made to
/// match by tuning one of them — they have to read from the same numbers.
///
/// Each constant below cites the rule it comes from. If a number here has no citation it is a bug:
/// nothing in this file is allowed to be invented.
library;

import 'package:flutter/material.dart';

import '../data/accent/oklab.dart';

/// The corner scale.
///
/// The web declares `--radius: 0.75rem` (styles.css:79) and derives four steps from it in
/// `@theme inline` (:249-252): `sm = radius - 4px`, `md = radius - 2px`, `lg = radius`,
/// `xl = radius + 4px`. Those are the ONLY four corner values the app uses, which is why a
/// `BorderRadius.circular(12)` scattered through the phone's widgets read as arbitrary — it was.
abstract final class ChordiaRadius {
  /// `--radius-sm` — badges, chips, the smallest inline markers.
  static const sm = 8.0;

  /// `--radius-md` — artwork (`CoverArt` defaults to `rounded-md`) and list rows.
  static const md = 10.0;

  /// `--radius-lg` — the base radius; menu rows, inline panels.
  static const lg = 12.0;

  /// `--radius-xl` — cards, the content pane, dialogs.
  static const xl = 16.0;

  static const smAll = BorderRadius.all(Radius.circular(sm));
  static const mdAll = BorderRadius.all(Radius.circular(md));
  static const lgAll = BorderRadius.all(Radius.circular(lg));
  static const xlAll = BorderRadius.all(Radius.circular(xl));

  /// A pill. The web writes `rounded-full`, which on a non-square box is "as round as it goes".
  static const pill = BorderRadius.all(Radius.circular(999));

  /// The two corners the web writes as ARBITRARY values, because nothing on the scale fits a mark
  /// this small: `--radius-sm` is 8px, which on a 10px square is a circle.
  ///
  /// They live here rather than at their call sites for the same reason as the four above — a
  /// number in a widget is a number nobody can check against the stylesheet. Both are cited.

  /// A chart mark: a heatmap cell or a legend swatch. `rx={2}` (`charts.tsx:539`) and
  /// `dayRadius={2}` (`charts.tsx:739`).
  static const mark = 2.0;

  /// A badge square: the explicit "E" and the variant chips beside a track title.
  /// `rounded-[3px]` (`ExplicitBadge.tsx:24`, and the variant chip in `TrackList.tsx`).
  static const badge = 3.0;

  static const markAll = BorderRadius.all(Radius.circular(mark));
  static const badgeAll = BorderRadius.all(Radius.circular(badge));

  /// A bottom sheet's top corners.
  ///
  /// `responsive-dialog.tsx:221` gives the sheet `rounded-t-2xl` — [xl], the same corner a dialog
  /// gets, because on the web a sheet and a dialog are one element. The phone's sheets had settled
  /// on 20, which is neither that nor Material's 28: a corner from nowhere, on the surface the app
  /// opens most.
  static const sheetTop = BorderRadius.vertical(top: Radius.circular(xl));
}

/// How tall an interactive control is.
///
/// styles.css:64-67 defines the desktop scale and :194-200 replaces it wholesale under
/// `@media (pointer: coarse)` — "every control clears the 44px minimum target". A phone is always
/// coarse, so the coarse column is the only one that applies here.
abstract final class ChordiaControl {
  /// `--control-h-xs` and `--control-h-sm` deliberately collapse into 44 on touch. That IS the rule.
  static const xs = 44.0;
  static const sm = 44.0;

  /// `--control-h-md` — buttons, inputs, select triggers.
  static const md = 48.0;

  /// `--control-h-lg` — the primary action on a collection header, a sheet's action rows.
  static const lg = 52.0;
}

/// The type scale, as Tailwind resolves it in the web client.
///
/// Sizes AND line heights, because the pairing is what makes a two-line row hold its height: the
/// web's track row is `text-sm` over `text-xs` (14/20 over 12/16), and the phone was rendering
/// `bodyLarge` over `bodySmall` (16/24 over 12/16) — a row a hair taller than the web's with a
/// title a size too big, on every list in the app.
///
/// Colour is deliberately absent. These carry metrics only, so they compose with whatever the theme
/// says the foreground is and cannot pin a colour the accent should be re-tinting.
///
/// The FAMILY is absent for the same reason. `buildChordiaTheme` installs [sans] on every slot of
/// the `textTheme`, so a `Text(style: ChordiaType.sm)` inherits it from the surrounding
/// `DefaultTextStyle` — and a title that wants the serif reaches for a `display*` slot rather than
/// naming a font here.
abstract final class ChordiaType {
  /// `--font-sans` (styles.css:222-223), the face `body` is set in and therefore everything is.
  ///
  /// Declared in `pubspec.yaml` at 400/500/600/700 as four static instances; see
  /// `assets/fonts/README.md` for why not the variable file.
  static const sans = 'Manrope';

  /// `.display-title` (styles.css:452-454). The web puts this on page H1s and on nothing else — 19
  /// call sites, every one of them an `<h1>` — so it belongs on the `display*` slots and stays off
  /// `headline*`, which the phone also uses for stat values and a now-playing title.
  static const display = 'Fraunces';

  /// `text-xs` — every secondary line: an artist under a title, a year under an album.
  static const xs = TextStyle(fontSize: 12, height: 16 / 12);

  /// `text-sm` — the default. Track titles, card titles, durations, menu rows.
  static const sm = TextStyle(fontSize: 14, height: 20 / 14);

  /// `text-base`
  static const base = TextStyle(fontSize: 16, height: 24 / 16);

  /// `text-lg` — an empty state's headline.
  static const lg = TextStyle(fontSize: 18, height: 28 / 18);

  /// `text-xl` — a rail heading (`RailHeader`: `font-semibold text-xl`).
  static const xl = TextStyle(fontSize: 20, height: 28 / 20);

  /// `text-2xl`
  static const xl2 = TextStyle(fontSize: 24, height: 32 / 24);

  /// `text-3xl` — a collection title.
  static const xl3 = TextStyle(fontSize: 30, height: 36 / 30);

  /// `text-4xl` — the largest H1 the phone column ever shows (`AlbumView.tsx:225`).
  static const xl4 = TextStyle(fontSize: 36, height: 40 / 36);

  static const medium = FontWeight.w500;
  static const semibold = FontWeight.w600;
  static const bold = FontWeight.w700;

  /// Numbers that must not jitter as they count: durations, track numbers, playhead.
  static const tabular = [FontFeature.tabularFigures()];
}

/// The handful of tokens `ColorScheme` has no role for, read off the roles it does.
///
/// **This file does not derive colour.** `data/accent/accent_surfaces.dart` is the one derivation —
/// it ports the whole `:root, .accent-scope` block, in OKLab, from the stylesheet's own bases — and
/// `buildChordiaTheme` maps its output onto the [ColorScheme]. Everything below either reads one of
/// those finished values back or applies a rule that CSS itself writes against `--primary`
/// directly, like a percentage of the accent over transparent.
///
/// It used to derive its own, and that was the bug: [line] was a *second* 16% accent mix on top of
/// `outline`, which is `--border` and already carries one, so the phone drew a markedly brighter,
/// more saturated hairline than the web (#4e124d against #36163a on the default accent). The panel
/// gradients had the same shape of error, mixing into `--pane-raised` and `--background` instead of
/// the island's own bases. Two derivations of one token set will always drift; there is now one.
extension ChordiaSchemeTokens on ColorScheme {
  /// `--border`: `color-mix(in srgb, var(--primary) 16%, oklch(0.22 0.02 280))`, which
  /// `buildChordiaTheme` puts on `outline`.
  ///
  /// A hairline that follows the chosen colour, which is what stops panel edges reading as grey
  /// furniture bolted onto a tinted app.
  ///
  /// Beware the name: the web has BOTH `--border` and `--line`, and this is `--border`. `--line`
  /// (the accent at 18% alpha) is `context.surfaces.line`.
  Color get line => outline;

  /// The softer edge the web writes as `border-border/60`.
  Color get lineSoft => outline.withValues(alpha: 0.6);

  /// `.island-shell`'s border: `color-mix(in srgb, var(--primary) 20%, transparent)`. CSS mixes
  /// with `transparent` in premultiplied alpha, so the result is the accent at 20% opacity.
  Color get panelBorder => primary.withValues(alpha: 0.2);

  /// `.island-shell`'s gradient stops (styles.css:467-471): a 165° sweep between two
  /// accent-tinted near-blacks. Solid, never translucent — a content panel must not let the page
  /// through, and a blur inside a scroll container re-blurs per scrolled frame.
  ///
  /// The bases are the rule's own literals rather than a nearby surface role: the island is not a
  /// tinted `--card`, it is its own two-stop pair, and substituting a role for them is what made
  /// the phone's panel bottom about half the lightness of the web's.
  Color get panelTop => mixOklab(primary, 0.06, oklch(0.135, 0.008, 285));
  Color get panelBottom => mixOklab(primary, 0.05, oklch(0.095, 0.007, 285));

  /// `.island-shell-modal` (styles.css:661-665): one step lighter and more saturated than
  /// [panelTop]/[panelBottom], so a dialog separates from the page by being *elevated*, not by
  /// being a different material. Still opaque; see the backdrop-filter warning in that rule.
  Color get modalTop => mixOklab(primary, 0.11, oklch(0.17, 0.013, 285));
  Color get modalBottom => mixOklab(primary, 0.07, oklch(0.115, 0.009, 285));

  /// A card's press fill. The web's cards are `hover:bg-accent/40`
  /// (AlbumGrid.tsx:63, ArtistGrid.tsx:52, rail.tsx `RAIL_CARD`).
  ///
  /// Tailwind's `accent` is `--accent`, the lightest of the shadcn surfaces — `paneElevated` here,
  /// which the theme maps to `surfaceContainerHighest`. It is NOT `--card`, which is a step darker.
  Color get cardHighlight => surfaceContainerHighest.withValues(alpha: 0.4);

  /// A list row's press fill: `hover:bg-accent/50` (TrackList.tsx:607).
  Color get rowHighlight => surfaceContainerHighest.withValues(alpha: 0.5);
}

/// The tight panel shadow from `.island-shell` (styles.css:472-474).
///
/// `0 8px 20px rgba(0,0,0,.5)` plus a zero-blur inset hairline. The blur radius is deliberately
/// small: the web measured large-radius shadows re-rastering per tile as cards crossed the viewport
/// and cut them, keeping only the hairline that actually carries the accent edge. The comment there
/// ends "do not reintroduce a blur radius above ~24px here", and that applies just as much to a
/// phone, where the GPU budget is smaller.
const chordiaPanelShadow = [
  BoxShadow(color: Color(0x80000000), blurRadius: 20, offset: Offset(0, 8)),
];

/// The opacity a hidden track carries (`hidden && "opacity-40"`, TrackList.tsx:609).
const chordiaHiddenOpacity = 0.4;

/// Artwork's own lift: Tailwind `shadow-lg`, which every card in the web client puts on its cover
/// (`AlbumGrid.tsx:63`, `ArtistGrid.tsx:56`, `cards.tsx`). It is what separates a dark cover from a
/// dark card — without it a browse grid on this palette is a field of squares with no edges.
const chordiaCoverShadow = [
  BoxShadow(color: Color(0x40000000), blurRadius: 15, offset: Offset(0, 10)),
  BoxShadow(color: Color(0x33000000), blurRadius: 6, offset: Offset(0, 4)),
];
