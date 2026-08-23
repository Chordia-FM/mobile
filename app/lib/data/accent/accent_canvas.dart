/// The page's ambient wash — a port of `.pane-canvas` (`frontend/src/styles.css:531-570`).
///
/// Two radial gradients over an opaque `--pane`: one at 13% of the accent from the top-left, one at
/// 7% of `--ambient-cool` from the top-right, and both move per section so that walking from the
/// library to your insights feels like moving somewhere rather than swapping the text. It is the
/// largest accent-derived surface the product has, and the phone simply did not have it — every
/// screen was the one flat near-black `scaffoldBackgroundColor`, which is most of what makes a dark
/// palette read as a slab.
///
/// It is also the only place a *palette* reaches the whole page: in Gradient mode the web
/// substitutes the palette's far stop into `--ambient-cool` (`styles.css:120-131`), so the wash is
/// lit by two of the listener's own colours instead of by one of them and a fixed blue.
///
/// ## Why the background is painted here rather than by the Scaffold
///
/// The wash has to sit UNDER the page and OVER nothing else, and Flutter has exactly one hook that
/// wraps the content of every route — the shell's, each tab's pushed screens, and the auth screens
/// outside the shell — which is the transitions theme ([AccentCanvasPageTransitions]). The obvious
/// alternative, one canvas above the Navigator in `MaterialApp.builder`, needs every Scaffold to be
/// transparent to show through, and a transparent route shows the route it is sliding over: the
/// previous page smears through the incoming one for the length of every push. Wrapping per route
/// keeps each route opaque and costs the same single fill the Scaffold was doing anyway.
library;

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'accent_engine.dart';
import 'accent_scope.dart';
import 'accent_surfaces.dart';

/// Which broad area of the app a route belongs to, and where its bloom sits.
///
/// The port of `frontend/src/lib/app/surface.ts` plus the `[data-surface=…]` rules that consume it
/// (`styles.css:548-570`). The numbers are that stylesheet's, unchanged: [x] and [x2] are the two
/// gradients' horizontal centres as a fraction of the page width, and values past 1 push a bloom
/// mostly off the edge so only its shoulder lights the page.
enum AccentBloom {
  /// The default pair, for the home feed and anything unclassified.
  home(0.12, 0.92),
  library(0.08, 1.20),
  discover(0.25, 0.80),
  insights(0.88, 0.10, litByCool: true),
  social(0.88, 0.10, litByCool: true),
  // The utility surfaces stay calmer: one low pool, centred, and the second highlight pushed off
  // the page entirely.
  manager(0.50, 1.50),
  settings(0.50, 1.50),
  admin(0.50, 1.50);

  const AccentBloom(this.x, this.x2, {this.litByCool = false});

  /// `--bloom-x`: the accent bloom's centre, as a fraction of the page width.
  final double x;

  /// `--bloom-x2`: the cool bloom's centre.
  final double x2;

  /// Whether the first bloom is lit by `--ambient-cool` too (`--bloom-hue: var(--ambient-cool)`),
  /// which is what makes the two social-facing sections read cooler than the rest of the app.
  final bool litByCool;
}

/// The section each path segment belongs to.
///
/// Keyed by segment rather than by full prefix because the phone's paths carry the tab they were
/// pushed onto: the web's `/app/settings` is `/home/settings` or `/library/settings` here,
/// depending on which tab the drawer was opened from.
const Map<String, AccentBloom> _sections = {
  'settings': AccentBloom.settings,
  'manager': AccentBloom.manager,
  'admin': AccentBloom.admin,
  'u': AccentBloom.social,
  'users': AccentBloom.social,
  'friends': AccentBloom.social,
  'insights': AccentBloom.insights,
  'you': AccentBloom.insights,
  'library': AccentBloom.library,
  'libraries': AccentBloom.library,
  'albums': AccentBloom.library,
  'artists': AccentBloom.library,
  'playlists': AccentBloom.library,
  'liked': AccentBloom.library,
  'downloads': AccentBloom.library,
  'smart': AccentBloom.library,
  'tracks': AccentBloom.library,
  'search': AccentBloom.discover,
  'genres': AccentBloom.discover,
  'labels': AccentBloom.discover,
  'discover': AccentBloom.discover,
  'releases': AccentBloom.discover,
  'home': AccentBloom.home,
};

/// The bloom a location belongs to.
///
/// The pushed section wins over the tab it was pushed onto, which is this client's shape of the
/// web's "longest prefix wins" rule: `/library/settings` is the settings surface for the same
/// reason `/app/manager/discover` is the manager's.
AccentBloom accentBloomFor(String path) {
  final segments = path.split('/').where((s) => s.isNotEmpty).take(2).toList();
  for (final segment in segments.reversed) {
    final section = _sections[segment];
    if (section != null) return section;
  }
  return AccentBloom.home;
}

/// The section the app is currently showing, published without rebuilding the tree.
///
/// Fed from the router in `app/app.dart`. Separate from [AccentScope] because it changes on
/// navigation rather than on a tick, and the two have nothing to say to each other.
class AccentBloomScope extends InheritedNotifier<ValueListenable<AccentBloom>> {
  const AccentBloomScope({
    required ValueListenable<AccentBloom> bloom,
    required super.child,
    super.key,
  }) : super(notifier: bloom);

  /// Falls back to the neutral pair when no scope is above — a widget test that builds one screen
  /// gets the home bloom rather than an assertion.
  static AccentBloom of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<AccentBloomScope>()
          ?.notifier
          ?.value ??
      AccentBloom.home;
}

/// One page, lit.
class AccentCanvas extends StatefulWidget {
  const AccentCanvas({required this.child, super.key});

  final Widget child;

  @override
  State<AccentCanvas> createState() => _AccentCanvasState();
}

class _AccentCanvasState extends State<AccentCanvas> {
  ThemeData? _source;
  late ThemeData _paneless;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Derived once per theme rather than per build: a page transition rebuilds this widget on every
    // frame of the animation, and `ThemeData.copyWith` is not the thing to do sixty times a second.
    if (!identical(theme, _source)) {
      _source = theme;
      // The canvas IS this page's background now, so the Scaffold above it must not paint one or the
      // flat pane covers the bloom. Scoped to the canvas rather than set on the theme globally,
      // because a Scaffold inside a sheet or a dialog has no canvas behind it and still needs its
      // fill.
      _paneless = theme.copyWith(scaffoldBackgroundColor: Colors.transparent);
    }

    final surfaces = context.surfaces;
    return CustomPaint(
      painter: _AmbientWash(
        frame: AccentScope.listenableOf(context),
        bloom: AccentBloomScope.of(context),
        pane: surfaces.pane,
        restingAccent: surfaces.accent,
        restingCool: surfaces.ambientCool,
      ),
      // The page gets its own layer so a fade tick repaints the wash and nothing else. Without it
      // the tick dirties the enclosing layer and the whole page repaints seven times a second,
      // which is the cost the engine's design went out of its way to avoid.
      child: RepaintBoundary(
        child: Theme(data: _paneless, child: widget.child),
      ),
    );
  }
}

/// The two light sources one frame gives a section.
///
/// [restingAccent] is the accent the theme was built from and [restingCool] its `--ambient-cool`;
/// both are what the browser would have in `:root` before the engine repainted `--primary` over the
/// top. The rules are the stylesheet's:
///
///   - The warm bloom is `--bloom-hue`, which defaults to `--primary` — the live accent, and in
///     Gradient mode the palette's blend. The gradient itself belongs on the small solid surfaces;
///     smeared across a whole page it reads as a flat colour.
///   - The cool bloom is `--ambient-cool`, which Gradient mode replaces with the palette's far stop
///     (`--accent-b`). That single substitution is what puts a palette on the largest surface in the
///     app rather than on its buttons alone.
///   - `--ambient-cool` is otherwise a `color-mix` off `--primary`, so a browser moves it in the
///     same frame that the accent moves. Mobile's theme holds the resting derivation, so this takes
///     the token while the accent is at rest and re-derives only while a mode is moving it.
({Color warm, Color cool}) ambientBloom(
  AccentFrame frame,
  AccentBloom bloom, {
  required Color restingAccent,
  required Color restingCool,
}) {
  final cool =
      frame.gradientEnd ??
      (frame.accent == restingAccent
          ? restingCool
          : ambientCoolFor(frame.accent));
  return (warm: bloom.litByCool ? cool : frame.accent, cool: cool);
}

/// A [CustomPainter] and not a widget that rebuilds, because the accent moves as often as every
/// 150ms: subscribing the painter's `repaint` to the frame moves the colour without marking a
/// single element dirty.
class _AmbientWash extends CustomPainter {
  _AmbientWash({
    required this.frame,
    required this.bloom,
    required this.pane,
    required this.restingAccent,
    required this.restingCool,
  }) : super(repaint: frame);

  final ValueListenable<AccentFrame> frame;
  final AccentBloom bloom;
  final Color pane;

  /// The accent the theme — and therefore [restingCool] — was built from.
  final Color restingAccent;

  /// `--ambient-cool` as the theme holds it.
  final Color restingCool;

  /// `26rem` and `20rem` at the browser's default root size, which is what the stylesheet's radii
  /// are written in.
  static const double _rem = 16;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = pane);
    final light = ambientBloom(
      frame.value,
      bloom,
      restingAccent: restingAccent,
      restingCool: restingCool,
    );
    _bloomAt(
      canvas,
      size,
      color: light.warm,
      centre: bloom.x,
      width: 0.78,
      height: 26 * _rem,
      alpha: 0.13,
      fadesAt: 0.72,
    );
    _bloomAt(
      canvas,
      size,
      color: light.cool,
      centre: bloom.x2,
      width: 0.62,
      height: 20 * _rem,
      alpha: 0.07,
      fadesAt: 0.76,
    );
  }

  /// One `radial-gradient(<width> <height> at <centre> 0%, <color> <alpha>, transparent <fadesAt>)`.
  void _bloomAt(
    Canvas canvas,
    Size size, {
    required Color color,
    required double centre,
    required double width,
    required double height,
    required double alpha,
    required double fadesAt,
  }) {
    final radiusX = size.width * width;
    if (radiusX <= 0 || size.height <= 0) return;
    // CSS radial gradients are ellipses and `ui.Gradient.radial` is a circle, so the shader carries
    // the vertical scale that turns one into the other. Scaling about y = 0 leaves the centre where
    // it is, which is where every one of these sits.
    final shader = ui.Gradient.radial(
      Offset(size.width * centre, 0),
      radiusX,
      // The far stop is the SAME hue at zero alpha, not `transparent`: fading toward transparent
      // black would drag a dark halo through the middle of the bloom.
      [color.withValues(alpha: alpha), color.withValues(alpha: 0)],
      [0, fadesAt],
      TileMode.clamp,
      Matrix4.diagonal3Values(1, height / radiusX, 1).storage,
    );
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_AmbientWash old) =>
      old.frame != frame ||
      old.bloom != bloom ||
      old.pane != pane ||
      old.restingAccent != restingAccent ||
      old.restingCool != restingCool;
}

/// Puts an [AccentCanvas] under every page route.
///
/// An odd home for a background and a deliberate one — see this file's header for why the
/// transitions theme is the hook that reaches every route. It delegates the transition itself to
/// the platform defaults, so the Android predictive back and the iOS back-swipe are untouched.
class AccentCanvasPageTransitions extends PageTransitionsTheme {
  const AccentCanvasPageTransitions();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => super.buildTransitions(
    route,
    context,
    animation,
    secondaryAnimation,
    AccentCanvas(child: child),
  );
}
