/// The accent as something that can move, not just a colour.
///
/// A port of `frontend/src/lib/settings/accent-engine.ts`, constant for constant. The web writes
/// `--primary`, `--ring` and `--primary-foreground`, and about forty derived tokens hang off them
/// through `color-mix` in `styles.css`; here the engine publishes an [AccentFrame] and
/// `accent_surfaces.dart` does the deriving. Same shape, same numbers, same degrade paths.
///
/// **Nothing in this app is allowed to animate permanently**, and a moving accent is exactly the
/// thing that rule was written about. So:
///
///   - Ticks are `Timer`, never a `Ticker`/`AnimationController`. The fastest step here is 150ms;
///     a vsync-driven loop would rebuild sixty times a second to move a colour nobody is watching.
///   - The engine stops dead while the app is backgrounded and repaints once on return. A
///     background app cross-fading a colour nobody can see is pure battery.
///   - "Reduce motion" collapses every mode to Static. A drifting hue is motion even though
///     nothing on screen translates.
///   - The frame is a [ValueListenable]. Widgets that want the moving colour subscribe to it
///     individually (see `accent_scope.dart`); the app's [ThemeData] is built from the *resting*
///     accent instead, so a fade does not rebuild the whole tree seven times a second.
///
/// The foreground is precomputed per palette stop, never per tick: it is a luminance decision, and
/// making it ten times a second would be worse than the animation it serves.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show Color, PlatformDispatcher;

import 'package:chordia_api/chordia_api.dart' show AccentMode, AccentSpeed;
import 'package:flutter/foundation.dart';

import 'accent_palette.dart';
import 'oklab.dart';

/// How the chosen speed scales the timers, at `Steady` = 1.
///
/// Applied to the HOLD and the chroma step, never to [fadeStepMs] — the cross-fade's step rate is
/// a repaint budget, not a speed, and letting it shrink is how "faster" would quietly become
/// "repaint three times as often".
const Map<AccentSpeed, double> accentSpeedFactor = {
  AccentSpeed.relaxed: 2,
  AccentSpeed.steady: 1,
  AccentSpeed.brisk: 0.45,
};

/// How long one palette stop is held before the next cross-fade begins, at `Steady`.
///
/// This was 20s on the web, chosen to be unobtrusive, and that made the mode look broken: anyone
/// switching to Fade watches for a few seconds, sees a completely static colour, and concludes it
/// does not work. At 8s the colour is moving for 1.5s out of every 9.5 — noticeable, still calm,
/// and `Relaxed` doubles it for people who want the original pacing.
const int holdMs = 8000;

/// How long a cross-fade takes.
const int fadeMs = 1500;

/// One step per this many ms during a cross-fade — about 7/s, well under the 10/s ceiling.
const int fadeStepMs = 150;

/// Chroma advances this far around the hue circle, this often. 6° every 2s = one lap in two
/// minutes.
const int chromaStepDeg = 6;
const int chromaStepMs = 2000;

/// Lightness and chroma for the rotating-hue mode.
///
/// Fixed rather than derived from the user's accent, which is what makes the mode legible: every
/// hue arrives at the same lightness, so the foreground decision is made once and every point on
/// the circle clears contrast. Deriving L and C from a chosen colour would produce a rainbow that
/// goes unreadable for a third of its cycle.
const double chromaL = 0.65;
const double chromaC = 0.2;

/// The luminance at which dark text beats light text.
///
/// At this value, contrast against `oklch(0.98 0 0)` and against `oklch(0.18 0 0)` are both
/// 4.21:1, so picking the better side guarantees every accent clears ~4.2:1 for its own
/// foreground. Shared with the web's `applySettings`; both must agree or a mode switch would
/// change the text colour on a button whose background did not change.
const double fgCrossover = 0.1852;

/// `oklch(0.18 0 0)`.
final Color fgDark = oklch(0.18, 0, 0);

/// `oklch(0.98 0 0)`.
final Color fgLight = oklch(0.98, 0, 0);

/// The readable foreground for a background colour.
Color foregroundFor(Color color) =>
    relativeLuminance(color) > fgCrossover ? fgDark : fgLight;

/// The midpoint of a palette, as a `#rrggbb` string, or null when it holds no usable hex.
///
/// A faithful port of the web's `blendHex`: it parses `#rgb`/`#rrggbb`, discards anything else,
/// and averages in **sRGB** rather than OKLab. That is not an oversight to correct — the web
/// computes this to feed a canvas, both clients must land on the same `--primary` for a gradient
/// palette, and an OKLab average here would put the phone on a different colour from the browser.
///
/// Preset names are not hex, so a palette written by the phone's own picker (which stores names)
/// falls through to [blendStops] instead.
String? blendHex(List<String> stops) {
  final parsed = <List<int>>[];
  for (final stop in stops) {
    final color = parseHexColor(stop.trim());
    if (color == null) continue;
    parsed.add([
      (color.r * 255).round(),
      (color.g * 255).round(),
      (color.b * 255).round(),
    ]);
  }
  if (parsed.isEmpty) return null;
  final buffer = StringBuffer('#');
  for (var channel = 0; channel < 3; channel++) {
    final sum = parsed.fold<int>(0, (total, c) => total + c[channel]);
    buffer.write(
      (sum / parsed.length).round().toRadixString(16).padLeft(2, '0'),
    );
  }
  return buffer.toString();
}

/// The midpoint of already-resolved stops, averaged in sRGB exactly as [blendHex] does.
Color? blendStops(List<Color> stops) {
  if (stops.isEmpty) return null;
  var r = 0.0;
  var g = 0.0;
  var b = 0.0;
  for (final stop in stops) {
    r += (stop.r * 255).round();
    g += (stop.g * 255).round();
    b += (stop.b * 255).round();
  }
  final n = stops.length;
  return Color.from(
    alpha: 1,
    red: (r / n).round() / 255,
    green: (g / n).round() / 255,
    blue: (b / n).round() / 255,
  );
}

/// One published moment of the accent.
@immutable
class AccentFrame {
  const AccentFrame({
    required this.accent,
    required this.foreground,
    this.gradient = const [],
  });

  /// `--primary` / `--ring`.
  final Color accent;

  /// `--primary-foreground`: what reads on top of [accent].
  final Color foreground;

  /// The gradient stops, in Gradient mode only; empty in every other mode.
  ///
  /// Published separately rather than folded into [accent] because `--primary` must stay a single
  /// colour — it is the base every surface mixes from, and a gradient there is not a colour at all.
  final List<Color> gradient;

  /// The gradient's ends, which the web publishes as `--accent-a` / `--accent-b` so the page's
  /// ambient wash and the placeholder artwork tiles can reach them.
  Color? get gradientStart => gradient.isEmpty ? null : gradient.first;
  Color? get gradientEnd => gradient.isEmpty ? null : gradient.last;

  @override
  bool operator ==(Object other) =>
      other is AccentFrame &&
      other.accent == accent &&
      other.foreground == foreground &&
      listEquals(other.gradient, gradient);

  @override
  int get hashCode => Object.hash(accent, foreground, Object.hashAll(gradient));

  @override
  String toString() =>
      'AccentFrame(${accent.toARGB32().toRadixString(16)}, '
      'stops: ${gradient.length})';
}

/// Everything the engine needs to know about the account's choice.
@immutable
class AccentConfig {
  const AccentConfig({
    this.accent = builtinAccent,
    this.mode = AccentMode.staticValue,
    this.palette = const [],
    this.albumColor,
    this.speed = AccentSpeed.steady,
  });

  /// The resolved static accent, already through `resolveAccent`.
  final Color accent;

  final AccentMode mode;

  /// The raw stops, as stored: preset names from this client's picker, `#rrggbb` from the web's.
  final List<String> palette;

  /// The current cover's characteristic colour, when Artwork mode has one.
  final Color? albumColor;

  /// How fast the moving modes move. Ignored by the still ones.
  final AccentSpeed speed;

  /// The stops a moving mode actually cycles through.
  ///
  /// A palette of fewer than two cannot fade, so it degrades to the static accent rather than to a
  /// broken animation — someone who switched to Fade before picking colours sees their existing
  /// accent, not a flicker between one colour and itself.
  List<Color> get stops {
    final raw = palette.where((s) => s.trim().isNotEmpty).toList();
    if (raw.length < 2) return [accent];
    return [for (final stop in raw) resolveAccent(stop)];
  }

  /// The accent the app's **surfaces** derive from.
  ///
  /// Deliberately stable for as long as the configuration is, which is what lets the whole theme
  /// hang off it without a rebuild per tick. In Fade and Gradient it is the palette's midpoint —
  /// the same value the web pins `--primary` to in Gradient mode, and the average of everything
  /// Fade will pass through — so the panes read as the palette rather than as one arbitrary stop.
  /// Chroma keeps the chosen accent for the same reason: re-tinting forty tokens twice a minute
  /// buys a difference nobody can see at a 3-8% mix, and costs a full rebuild each time.
  Color get surfaceAccent => switch (mode) {
    AccentMode.artwork => albumColor ?? accent,
    AccentMode.fade || AccentMode.gradient => blendStops(stops) ?? accent,
    _ => accent,
  };

  @override
  bool operator ==(Object other) =>
      other is AccentConfig &&
      other.accent == accent &&
      other.mode == mode &&
      listEquals(other.palette, palette) &&
      other.albumColor == albumColor &&
      other.speed == speed;

  @override
  int get hashCode =>
      Object.hash(accent, mode, Object.hashAll(palette), albumColor, speed);
}

/// A pending tick. `Timer` in the app; a test drives one by hand.
abstract interface class AccentTick {
  void cancel();
}

/// Schedules one tick. The seam that keeps the engine's timing testable without a real clock.
typedef AccentScheduler =
    AccentTick Function(Duration delay, void Function() run);

class _TimerTick implements AccentTick {
  _TimerTick(this._timer);

  final Timer _timer;

  @override
  void cancel() => _timer.cancel();
}

AccentTick _scheduleWithTimer(Duration delay, void Function() run) =>
    _TimerTick(Timer(delay, run));

/// A running accent. One instance for the app, owned by `accentEngineProvider`.
///
/// [apply] is idempotent and cheap to call on every settings change; it tears the previous timer
/// down before starting anything new, so a burst of changes cannot leave two engines painting over
/// each other.
class AccentEngine {
  AccentEngine({
    ValueGetter<bool>? reducedMotion,
    AccentScheduler schedule = _scheduleWithTimer,
  }) : _reducedMotion = reducedMotion ?? _platformReducedMotion,
       _schedule = schedule,
       _frame = ValueNotifier(
         AccentFrame(
           accent: builtinAccent,
           foreground: foregroundFor(builtinAccent),
         ),
       );

  /// Read straight off the platform dispatcher rather than through `MediaQuery`, because the
  /// engine has no `BuildContext` and outlives every widget that could give it one.
  static bool _platformReducedMotion() =>
      PlatformDispatcher.instance.accessibilityFeatures.disableAnimations;

  final ValueGetter<bool> _reducedMotion;
  final AccentScheduler _schedule;
  final ValueNotifier<AccentFrame> _frame;

  AccentTick? _tick;
  AccentConfig? _config;
  bool _hidden = false;

  /// Stops, plus their precomputed foregrounds, so a tick never does luminance maths.
  List<Color> _stops = const [];
  List<Color> _foregrounds = const [];
  int _index = 0;
  int _hue = 0;

  /// The live accent. Fires at most once every [fadeStepMs].
  ValueListenable<AccentFrame> get frame => _frame;

  /// The configuration currently being painted, or null before the first [apply].
  AccentConfig? get config => _config;

  /// Whether a tick is pending. Test seam — nothing in the app should need this.
  bool get isTicking => _tick != null;

  double get _factor =>
      accentSpeedFactor[_config?.speed ?? AccentSpeed.steady]!;
  Duration get _hold => Duration(milliseconds: (holdMs * _factor).round());
  Duration get _chromaStep =>
      Duration(milliseconds: (chromaStepMs * _factor).round());

  /// Point the engine at a new configuration. Safe to call on every settings change.
  void apply(AccentConfig next) {
    _config = next;
    if (_hidden) {
      // Paint the resting colour so the app is correct when it comes forward, but do not start a
      // timer no one can see.
      _clear();
      _paintStatic();
      return;
    }
    _start();
  }

  /// Called when the app moves between the foreground and the background.
  ///
  /// Repaints immediately on return rather than waiting out a hold: coming back to a colour frozen
  /// mid-fade for however long the app was away is worse than a single jump.
  void setHidden(bool hidden) {
    if (hidden == _hidden) return;
    _hidden = hidden;
    if (_config == null) return;
    if (hidden) {
      _clear();
    } else {
      _start();
    }
  }

  void dispose() {
    _clear();
    _config = null;
    _frame.dispose();
  }

  void _clear() {
    _tick?.cancel();
    _tick = null;
  }

  void _paint(
    Color accent, [
    Color? foreground,
    List<Color> gradient = const [],
  ]) {
    _frame.value = AccentFrame(
      accent: accent,
      foreground: foreground ?? foregroundFor(accent),
      gradient: gradient,
    );
  }

  /// What this configuration looks like when it is not moving.
  ///
  /// Used for the static mode, for a backgrounded app, and for reduced motion — and it has to be
  /// the same answer in all three, or the accent jumps when the app comes forward. It is also why
  /// a paused fade shows a colour from the PALETTE rather than the base accent: the palette is
  /// what was configured for this mode, and falling back past it would ignore the choice entirely.
  Color _restingColor(AccentConfig c) {
    // Artwork falls back to the static accent whenever the current cover has not produced a
    // colour — art that failed to load, a track with none, or the moment before extraction lands.
    if (c.mode == AccentMode.artwork) return c.albumColor ?? c.accent;
    if (c.mode == AccentMode.fade || c.mode == AccentMode.gradient) {
      final list = c.stops;
      return list[math.min(_index, list.length - 1)];
    }
    return c.accent;
  }

  void _paintStatic() {
    final c = _config;
    if (c == null) return;
    if (c.mode == AccentMode.gradient) {
      final list = c.stops;
      // `--primary` stays a single colour, and it is the palette's BLEND rather than its first
      // stop: every pane, card, border and chart surface derives from this one value, so stop zero
      // would tint the entire interface with a single colour and leave the gradient visible only
      // on the handful of solid accent surfaces.
      _paint(blendStops(list) ?? list.first, null, list);
      return;
    }
    _paint(_restingColor(c));
  }

  /// One cross-fade from [_index] to the next stop, stepped, then schedules the next hold.
  void _fadeStep(int step) {
    if (_config == null) return;
    final from = _stops[_index];
    final to = _stops[(_index + 1) % _stops.length];
    final steps = (fadeMs / fadeStepMs).ceil();

    if (step > steps) {
      _index = (_index + 1) % _stops.length;
      _paint(_stops[_index], _foregrounds[_index]);
      _tick = _schedule(_hold, () => _fadeStep(1));
      return;
    }

    final pct = (step / steps * 100).round();
    // The foreground switches at the halfway point rather than being interpolated: it is one of
    // two values, and mixing them would produce a grey that is unreadable on both ends.
    final fg = pct < 50
        ? _foregrounds[_index]
        : _foregrounds[(_index + 1) % _stops.length];
    _paint(mixOklab(to, pct / 100, from), fg);
    _tick = _schedule(
      const Duration(milliseconds: fadeStepMs),
      () => _fadeStep(step + 1),
    );
  }

  void _chromaTick() {
    _hue = (_hue + chromaStepDeg) % 360;
    // One fixed lightness across the whole circle, so this foreground is correct for every hue.
    _paint(oklch(chromaL, chromaC, _hue.toDouble()), fgDark);
    _tick = _schedule(_chromaStep, _chromaTick);
  }

  void _start() {
    _clear();
    final c = _config;
    if (c == null) return;

    // Reduced motion collapses every mode to its resting colour. A drifting hue is motion even
    // though nothing on screen moves.
    if (_reducedMotion() ||
        c.mode == AccentMode.staticValue ||
        c.mode == AccentMode.artwork ||
        c.mode == AccentMode.gradient) {
      _paintStatic();
      return;
    }

    if (c.mode == AccentMode.fade) {
      _stops = c.stops;
      if (_stops.length < 2) {
        _paintStatic();
        return;
      }
      _foregrounds = [for (final stop in _stops) foregroundFor(stop)];
      _index = math.min(_index, _stops.length - 1);
      _paint(_stops[_index], _foregrounds[_index]);
      _tick = _schedule(_hold, () => _fadeStep(1));
      return;
    }

    _chromaTick();
  }
}
