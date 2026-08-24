/// The solid accent surfaces, opted into the accent that moves.
///
/// The web does this with one rule (`frontend/src/styles.css:1039-1041`):
///
/// ```css
/// :where([class~="bg-primary"]) { background-image: var(--accent-gradient, none); }
/// ```
///
/// and with `paintAccent` rewriting `--primary` on every tick, which every `bg-primary` element
/// picks up for free. The stylesheet's own comment says why it is a blanket rule rather than a list
/// of components: "a new primary button written next year is covered without anybody remembering it
/// exists." Mobile's equivalent blanket is the button style on the theme — set once, inherited by
/// every button in the app — with the subscription itself pushed down into the background widget so
/// that a tick rebuilds one element per button and nothing else.
///
/// The gradient is sized to EACH element, deliberately, and that is the stylesheet's finding rather
/// than a guess: a viewport-wide wash leaves a 40px play button rendering a 3% slice of the palette,
/// which reads as a flat colour and makes the mode look broken.
///
/// The stylesheet's next rule down is `.accent-art` (:1050-1056), the placeholder artwork tile, and
/// it lives here too: it is the same idea aimed at the other half of the accent's area. The buttons
/// are the small bright surfaces; the coverless tiles are the large dim ones, and between them they
/// are most of what an accent is for.
library;

import 'package:flutter/material.dart';

import 'accent_engine.dart';
import 'accent_scope.dart';
import 'accent_surfaces.dart';
import 'oklab.dart';

/// `linear-gradient(135deg in oklab, …)` sampled into stops Flutter can interpolate between.
///
/// Flutter's [LinearGradient] interpolates in sRGB, which is the one thing the stylesheet is
/// explicit about not doing: the straight line between two distant hues passes through the middle of
/// the colour cube and dips through grey, which is exactly what `blendHex`'s comment describes and
/// what `mixOklab` exists to avoid. Sampling the OKLab path gets the browser's ramp out of a widget
/// that can only walk a straight line.
///
/// [perSegment] must be even for the samples to land on the segment's own midpoint.
List<Color> oklabRamp(List<Color> stops, {int perSegment = 6}) {
  if (stops.length < 2) return stops;
  final ramp = <Color>[stops.first];
  for (var i = 0; i < stops.length - 1; i++) {
    final from = stops[i];
    final to = stops[i + 1];
    for (var step = 1; step <= perSegment; step++) {
      ramp.add(mixOklab(to, step / perSegment, from));
    }
  }
  return ramp;
}

/// One frame of `bg-primary`: the flat accent, or the palette across the element's own face.
///
/// The two shapes are one decoration rather than two branches at every call site, because the
/// stylesheet's rule is one declaration and the modes are supposed to be interchangeable — a
/// surface opts in once and behaves correctly in all five.
BoxDecoration accentFillDecoration(
  AccentFrame frame, {
  BoxShape shape = BoxShape.rectangle,
  BorderRadius? borderRadius,
}) => BoxDecoration(
  shape: shape,
  // `BoxDecoration` asserts on a radius it cannot apply, and a circle has none.
  borderRadius: shape == BoxShape.circle ? null : borderRadius,
  color: frame.gradient.isEmpty ? frame.accent : null,
  // 135deg in CSS starts from "to top" and turns clockwise, so it runs corner to corner.
  gradient: frame.gradient.isEmpty
      ? null
      : LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: oklabRamp(frame.gradient),
        ),
);

/// A [ButtonLayerBuilder] that paints the live accent behind a button's label.
///
/// Attached to the theme's button style in `accent_providers.dart`, which is what makes it the
/// blanket rule rather than something 36 call sites have to remember.
Widget accentFillBackground(
  BuildContext context,
  Set<WidgetState> states,
  Widget? child,
) => AccentBuilder(builder: _fill, child: child);

Widget _fill(BuildContext context, AccentFrame frame, Widget? child) {
  // Static and Artwork publish exactly the colour the theme was built from, and the button already
  // paints it. Handing those back untouched keeps the default configuration bit-for-bit what it was
  // — this widget only exists for the three modes that actually move.
  if (frame.gradient.isEmpty && frame.accent == context.surfaces.accent) {
    return child ?? const SizedBox.shrink();
  }
  return Ink(
    // `Ink`, not a `DecoratedBox`: this sits inside the button's [Material], and `Ink` paints its
    // decoration into that material's ink layer — UNDERNEATH the splash. A plain box would be an
    // opaque child drawn over the ink and would swallow the feedback from every tap.
    decoration: accentFillDecoration(frame),
    child: _labelled(frame, child ?? const SizedBox.shrink()),
  );
}

/// `--primary-foreground` moves with `--primary`. A surface resolved its label colour from the
/// resting accent, and in Fade the two ends of a palette can want opposite foregrounds, so leaving
/// it alone is how a cross-fade ends up with unreadable text halfway through.
Widget _labelled(AccentFrame frame, Widget child) => DefaultTextStyle.merge(
  style: TextStyle(color: frame.foreground),
  child: IconTheme.merge(
    data: IconThemeData(color: frame.foreground),
    child: child,
  ),
);

/// A solid accent surface that is not a button, following the live accent.
///
/// The theme's button style covers every [FilledButton] in the app without a call site knowing it
/// exists, and nothing else is reachable that way — a hand-rolled circular play control, a filled
/// chip, a progress bar's own fill. Those wrap themselves in this instead: the same subscription at
/// the same granularity, so a tick rebuilds this element and [child] rides through untouched.
///
/// Not every accent fill should take it, and that is a judgement rather than an oversight. A
/// scrubber that cross-fades under the thumb you are dragging is worse than one that holds still,
/// and a chart series that recolours while someone reads its legend is worse again; those are right
/// to keep `colorScheme.primary`, which is the resting accent and costs nothing.
class AccentSurface extends StatelessWidget {
  const AccentSurface({
    required this.child,
    super.key,
    this.shape = BoxShape.rectangle,
    this.borderRadius,
  });

  final Widget child;
  final BoxShape shape;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) => AccentBuilder(
    builder: (context, frame, child) => DecoratedBox(
      decoration: accentFillDecoration(
        frame,
        shape: shape,
        borderRadius: borderRadius,
      ),
      child: _labelled(frame, child!),
    ),
    child: child,
  );
}

/// `--accent-a` / `--accent-b`: the two ends of `.accent-art`'s sweep, for one frame.
///
/// The stylesheet writes both with a fallback — `var(--accent-a, var(--primary))` and
/// `var(--accent-b, var(--accent))` — so outside Gradient mode the tile is the accent over the
/// lightest of the surfaces, and inside it the tile is the listener's own two colours.
///
/// `--accent` is itself a `color-mix` off `--primary`, which a browser recomputes in the same frame
/// the accent moves in. [restingElevated] is the theme's copy, taken while the accent is at rest
/// and re-derived only while a mode is actually moving it — the trade `ambientBloom` makes, for the
/// same reason.
({Color start, Color end}) accentArtStops(
  AccentFrame frame, {
  required Color restingAccent,
  required Color restingElevated,
}) {
  final accent = frame.accent;
  final elevated = accent == restingAccent
      ? restingElevated
      : paneElevatedFor(accent);
  // `color-mix(in oklab, X 35%, transparent)`. CSS mixes with `transparent` in PREMULTIPLIED alpha,
  // so each end is its colour at that opacity rather than that colour pulled toward black.
  return (
    start: (frame.gradientStart ?? accent).withValues(alpha: 0.35),
    end: (frame.gradientEnd ?? elevated).withValues(alpha: 0.22),
  );
}

/// The placeholder tile a track, album, artist or collection with no artwork wears: `.accent-art`
/// (`styles.css:1050-1056`).
///
/// The stylesheet's own argument for the rule is the one that matters here: a browse grid is mostly
/// these, so they are among the largest accent-derived areas in the app and an accent that skips
/// them is missing from most of what someone actually looks at.
///
/// Translucent over whatever is behind it, exactly as the web leaves it — `CoverArt.tsx` puts
/// `accent-art` on a div with no background colour of its own, so the card or pane under the tile
/// supplies the base and the two mixes only tint it. It used to paint an opaque surface role first,
/// which is why a placeholder read as a grey box with a faint wash on it rather than as a tint of
/// the page.
///
/// Subscribed through [AccentBuilder], the same granularity the button fill runs at: a tick
/// rebuilds this element per visible tile and stops there. [child] is built once and rides through
/// every tick untouched, which matters here more than on a button — the thing over the wash is a
/// glyph nobody has asked to move.
class AccentArt extends StatelessWidget {
  const AccentArt({super.key, this.child, this.borderRadius});

  /// Drawn over the wash — the fallback glyph, usually. It also gives the tile its size, so a
  /// caller with no child has to be inside a box that constrains this one.
  final Widget? child;

  /// Rounds the wash itself, for a caller that is not already clipping it.
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final surfaces = context.surfaces;
    return AccentBuilder(
      builder: (context, frame, child) {
        final stops = accentArtStops(
          frame,
          restingAccent: surfaces.accent,
          restingElevated: surfaces.paneElevated,
        );
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            // 135deg in CSS starts from "to top" and turns clockwise, so it runs corner to corner.
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              // Two stops far apart in hue is precisely the case a Flutter gradient walks through
              // grey, and a tile the size of an album cover shows the whole path.
              colors: oklabRamp([stops.start, stops.end]),
            ),
          ),
          child: child,
        );
      },
      child: child,
    );
  }
}
