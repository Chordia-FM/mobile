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
    decoration: BoxDecoration(
      color: frame.gradient.isEmpty ? frame.accent : null,
      // 135deg in CSS starts from "to top" and turns clockwise, so it runs corner to corner.
      gradient: frame.gradient.isEmpty
          ? null
          : LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: oklabRamp(frame.gradient),
            ),
    ),
    // `--primary-foreground` moves with `--primary`. The button resolved its label colour from the
    // resting accent, and in Fade the two ends of a palette can want opposite foregrounds, so
    // leaving it alone is how a cross-fade ends up with unreadable text halfway through.
    child: DefaultTextStyle.merge(
      style: TextStyle(color: frame.foreground),
      child: IconTheme.merge(
        data: IconThemeData(color: frame.foreground),
        child: child ?? const SizedBox.shrink(),
      ),
    ),
  );
}
