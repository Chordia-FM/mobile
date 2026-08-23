import 'dart:ui' show Color;

import 'package:chordia_api/chordia_api.dart';
import 'package:chordia_mobile/app/providers.dart';
import 'package:chordia_mobile/app/theme.dart';
import 'package:chordia_mobile/data/accent/accent_engine.dart';
import 'package:chordia_mobile/data/accent/accent_palette.dart';
import 'package:chordia_mobile/data/accent/accent_providers.dart';
import 'package:chordia_mobile/data/accent/oklab.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// A hand-driven replacement for `Timer`.
///
/// The engine's whole design is that it ticks on a timer rather than on a vsync callback, so the
/// interesting assertions are about *when* it schedules as much as what it paints. A fake clock
/// makes both exact and keeps the suite instant — `pumpAndSettle` would hang here anyway.
class _Clock implements AccentTick {
  Duration? delay;
  void Function()? _pending;

  AccentTick schedule(Duration delay, void Function() run) {
    this.delay = delay;
    _pending = run;
    return this;
  }

  /// Fire the pending tick.
  void tick() {
    final run = _pending;
    _pending = null;
    delay = null;
    expect(run, isNotNull, reason: 'nothing was scheduled');
    run!();
  }

  @override
  void cancel() {
    _pending = null;
    delay = null;
  }
}

AccentEngine _engine(_Clock clock, {bool reducedMotion = false}) =>
    AccentEngine(reducedMotion: () => reducedMotion, schedule: clock.schedule);

Color _hex(String value) => parseHexColor(value)!;

void main() {
  final crimson = accentPresets['crimson']!;
  final blue = accentPresets['blue']!;
  final amber = accentPresets['amber']!;

  group('oklab', () {
    test('reproduces the accent presets the stylesheet authors in oklch', () {
      // If this fails the colour transform drifted, and every derived surface with it.
      expect(accentPresets['pink'], _hex('#cd00ae'));
      expect(crimson, _hex('#f52e44'));
      expect(amber, _hex('#e6ad00'));
      expect(accentPresets['indigo'], _hex('#5e61ff'));
    });

    test('color-mix(in oklab) is not the same as mixing in sRGB', () {
      // The reason the whole file exists. Halfway between red and blue, sRGB gives #800080 — a
      // dark muddy purple with less than half the luminance of either end, because the straight
      // line between them passes through the middle of the cube. OKLab stays on the perceptual
      // line and gives #8c53a2. A regression to `Color.lerp` would be invisible in a diff of the
      // code and unmistakable on a phone.
      expect(mixSrgb(_hex('#ff0000'), 0.5, _hex('#0000ff')), _hex('#800080'));
      expect(mixOklab(_hex('#ff0000'), 0.5, _hex('#0000ff')), _hex('#8c53a2'));
      expect(
        relativeLuminance(_hex('#8c53a2')),
        greaterThan(relativeLuminance(_hex('#800080')) * 2),
      );
    });
  });

  group('foregroundFor', () {
    // 0.1852 relative luminance is where contrast against oklch(0.98 0 0) and oklch(0.18 0 0) are
    // both 4.21:1. These two greys sit either side of it: #777777 is 0.1845, #787878 is 0.1878.
    test('picks light text just below the crossover', () {
      expect(relativeLuminance(_hex('#777777')), lessThan(0.1852));
      expect(foregroundFor(_hex('#777777')), fgLight);
    });

    test('picks dark text just above the crossover', () {
      expect(relativeLuminance(_hex('#787878')), greaterThan(0.1852));
      expect(foregroundFor(_hex('#787878')), fgDark);
    });

    test('the crossover lands where the presets need it to', () {
      // Two neighbouring presets straddle it, which is what makes this worth pinning: indigo is
      // 0.1815 and crimson 0.2178.
      expect(foregroundFor(accentPresets['indigo']!), fgLight);
      expect(foregroundFor(crimson), fgDark);
      expect(foregroundFor(amber), fgDark);
    });
  });

  group('blendHex', () {
    test('averages hex stops in sRGB, as the web does', () {
      expect(blendHex(['#ff0000', '#0000ff']), '#800080');
    });

    test('expands the three-digit form', () {
      expect(blendHex(['#f00', '#00f']), '#800080');
    });

    test('discards anything that is not hex', () {
      expect(blendHex(['#ff0000', 'rebeccapurple', '']), '#ff0000');
    });

    test('is null when no stop is usable', () {
      // A palette written by this client's own picker holds preset NAMES, which is why the engine
      // blends resolved colours rather than leaning on this.
      expect(blendHex(['crimson', 'blue']), isNull);
    });

    test('blendStops matches it for the same colours', () {
      expect(blendStops([_hex('#ff0000'), _hex('#0000ff')]), _hex('#800080'));
    });
  });

  group('static mode', () {
    test('paints the accent once and schedules nothing', () {
      final clock = _Clock();
      final engine = _engine(clock)
        ..apply(AccentConfig(accent: amber, mode: AccentMode.staticValue));

      expect(engine.frame.value.accent, amber);
      expect(engine.frame.value.foreground, fgDark);
      expect(engine.frame.value.gradient, isEmpty);
      expect(engine.isTicking, isFalse);
    });
  });

  group('fade mode', () {
    AccentConfig config({
      List<String> palette = const ['crimson', 'blue'],
      AccentSpeed speed = AccentSpeed.steady,
    }) => AccentConfig(
      accent: amber,
      mode: AccentMode.fade,
      palette: palette,
      speed: speed,
    );

    test('holds the first stop, then steps through the cross-fade', () {
      final clock = _Clock();
      final engine = _engine(clock)..apply(config());

      expect(engine.frame.value.accent, crimson);
      expect(clock.delay, const Duration(milliseconds: 8000));

      // 1500ms of fade at one step per 150ms is ten steps, so 10% of the way each time. The
      // expected colours are `color-mix(in oklab, blue N%, crimson)` computed independently.
      const expected = [
        '#ea4c59',
        '#df606c',
        '#d26f7f',
        '#c47d90',
        '#b588a1',
        '#a493b2',
        '#909dc3',
        '#77a5d4',
        '#56ade4',
        '#00b5f5',
      ];
      for (final want in expected) {
        clock.tick();
        expect(engine.frame.value.accent, _hex(want), reason: want);
        expect(clock.delay, const Duration(milliseconds: 150));
      }

      // One more tick lands on the stop itself and starts the next hold.
      clock.tick();
      expect(engine.frame.value.accent, blue);
      expect(clock.delay, const Duration(milliseconds: 8000));
    });

    test('the foreground switches at the halfway point rather than blending', () {
      final clock = _Clock();
      // crimson wants dark text, blue wants dark text too — indigo does not, so fade to that.
      final engine = _engine(clock)
        ..apply(config(palette: ['indigo', 'amber']));

      expect(engine.frame.value.foreground, fgLight);
      for (var step = 1; step <= 4; step++) {
        clock.tick();
        expect(engine.frame.value.foreground, fgLight, reason: 'step $step');
      }
      // Step 5 is 50%: the foreground flips to the destination's in one go, because the two values
      // are all there is and a mix of them is a grey that reads on neither end.
      clock.tick();
      expect(engine.frame.value.foreground, fgDark);
    });

    test('speed scales the hold but never the step rate', () {
      final relaxed = _Clock();
      _engine(relaxed).apply(config(speed: AccentSpeed.relaxed));
      expect(relaxed.delay, const Duration(milliseconds: 16000));

      final brisk = _Clock();
      final engine = _engine(brisk)..apply(config(speed: AccentSpeed.brisk));
      expect(brisk.delay, const Duration(milliseconds: 3600));

      // The step is a repaint budget, not a speed. Letting it shrink is how "faster" would quietly
      // become "repaint three times as often".
      brisk.tick();
      expect(brisk.delay, const Duration(milliseconds: 150));
      expect(engine.frame.value.accent, isNot(crimson));
    });

    test(
      'a palette of one degrades to the static accent, not to a flicker',
      () {
        final clock = _Clock();
        final engine = _engine(clock)..apply(config(palette: ['crimson']));

        expect(engine.frame.value.accent, amber);
        expect(engine.isTicking, isFalse);
      },
    );

    test('an empty palette degrades the same way', () {
      final clock = _Clock();
      final engine = _engine(clock)..apply(config(palette: const []));

      expect(engine.frame.value.accent, amber);
      expect(engine.isTicking, isFalse);
    });

    test('reduced motion collapses it to the resting colour', () {
      final clock = _Clock();
      final engine = _engine(clock, reducedMotion: true)..apply(config());

      // The palette's first stop, not the base accent: a paused fade must still show what was
      // configured for the mode.
      expect(engine.frame.value.accent, crimson);
      expect(engine.isTicking, isFalse);
    });

    test('backgrounding stops the clock and returning repaints', () {
      final clock = _Clock();
      final engine = _engine(clock)..apply(config());
      clock.tick();
      expect(engine.frame.value.accent, isNot(crimson));

      engine.setHidden(true);
      expect(engine.isTicking, isFalse);

      engine.setHidden(false);
      // Back to a stop rather than resuming mid-fade: a colour frozen part-way through for however
      // long the app was away is worse than one jump.
      expect(engine.frame.value.accent, crimson);
      expect(engine.isTicking, isTrue);
    });
  });

  group('gradient mode', () {
    test('publishes the stops and pins the accent to their blend', () {
      final clock = _Clock();
      final engine = _engine(clock)
        ..apply(
          AccentConfig(
            accent: amber,
            mode: AccentMode.gradient,
            palette: const ['crimson', 'blue'],
          ),
        );

      expect(engine.frame.value.gradient, [crimson, blue]);
      expect(engine.frame.value.gradientStart, crimson);
      expect(engine.frame.value.gradientEnd, blue);
      // The BLEND, not stop zero. Forty tokens derive from this one value, so the first stop would
      // tint the whole interface with one colour and leave the gradient on buttons alone.
      expect(engine.frame.value.accent, _hex('#7b729d'));
      expect(engine.isTicking, isFalse);
    });

    test('a palette of one degrades to the accent with no gradient', () {
      final clock = _Clock();
      final engine = _engine(clock)
        ..apply(
          AccentConfig(
            accent: amber,
            mode: AccentMode.gradient,
            palette: const ['crimson'],
          ),
        );

      expect(engine.frame.value.gradient, [amber]);
      expect(engine.frame.value.accent, amber);
    });
  });

  group('artwork mode', () {
    test("wears the cover's colour when there is one", () {
      final clock = _Clock();
      final cover = _hex('#3388cc');
      final engine = _engine(clock)
        ..apply(
          AccentConfig(
            accent: amber,
            mode: AccentMode.artwork,
            albumColor: cover,
          ),
        );

      expect(engine.frame.value.accent, cover);
      expect(engine.isTicking, isFalse);
    });

    test('falls back to the chosen accent when the cover gives none', () {
      final clock = _Clock();
      final engine = _engine(clock)
        ..apply(AccentConfig(accent: amber, mode: AccentMode.artwork));

      expect(engine.frame.value.accent, amber);
    });

    // Turning a cover into a colour is `artwork_color.dart`'s job and is covered by
    // `artwork_color_test.dart`; what matters here is only what the engine does with the answer.
  });

  group('chroma mode', () {
    test('advances six degrees at a time around a fixed lightness', () {
      final clock = _Clock();
      final engine = _engine(clock)
        ..apply(AccentConfig(accent: amber, mode: AccentMode.chroma));

      // The first paint is already one step in, exactly as the web's does.
      expect(engine.frame.value.accent, oklch(0.65, 0.2, 6));
      expect(clock.delay, const Duration(milliseconds: 2000));
      // One lightness for the whole circle is what lets the foreground be decided once.
      expect(engine.frame.value.foreground, fgDark);

      clock.tick();
      expect(engine.frame.value.accent, oklch(0.65, 0.2, 12));

      final (l, _, _) = oklchOf(engine.frame.value.accent);
      expect(l, closeTo(0.65, 0.01));
    });

    test('speed scales the step', () {
      final relaxed = _Clock();
      _engine(relaxed).apply(
        AccentConfig(
          accent: amber,
          mode: AccentMode.chroma,
          speed: AccentSpeed.relaxed,
        ),
      );
      expect(relaxed.delay, const Duration(milliseconds: 4000));

      final brisk = _Clock();
      _engine(brisk).apply(
        AccentConfig(
          accent: amber,
          mode: AccentMode.chroma,
          speed: AccentSpeed.brisk,
        ),
      );
      expect(brisk.delay, const Duration(milliseconds: 900));
    });

    test('reduced motion stops the rotation dead', () {
      final clock = _Clock();
      final engine = _engine(clock, reducedMotion: true)
        ..apply(AccentConfig(accent: amber, mode: AccentMode.chroma));

      expect(engine.frame.value.accent, amber);
      expect(engine.isTicking, isFalse);
    });
  });

  group('surfaces', () {
    test('the default accent reproduces the frozen palette exactly', () {
      // `ChordiaColors` is the checked fallback. If the maths drifts, this fails rather than the
      // product quietly shipping a slightly-off dark theme.
      final s = ChordiaSurfaces.of(builtinAccent);
      expect(s.accent, ChordiaColors.accent);
      expect(s.pane, ChordiaColors.pane);
      expect(s.paneRaised, ChordiaColors.paneRaised);
      expect(s.paneElevated, ChordiaColors.paneElevated);
    });

    test('every surface re-derives when the accent changes', () {
      final warm = ChordiaSurfaces.of(amber);
      final cool = ChordiaSurfaces.of(blue);

      expect(warm.pane, isNot(cool.pane));
      expect(warm.paneRaised, isNot(cool.paneRaised));
      expect(warm.card, isNot(cool.card));
      expect(warm.border, isNot(cool.border));
      expect(warm.inputFill, isNot(cool.inputFill));
      expect(warm.surfaceStrong, isNot(cool.surfaceStrong));
    });

    test('a surface leans toward its accent rather than to a fixed violet', () {
      // The bug this whole task is about: the panes used to be pinned to hue 280, so an amber
      // accent sat on a cool violet card. The base still supplies most of a 4% mix, so the claim
      // is relative — the same surface must be redder under a warm accent and bluer under a cool
      // one.
      final warm = ChordiaSurfaces.of(amber);
      final cool = ChordiaSurfaces.of(blue);
      expect(warm.pane.r, greaterThan(cool.pane.r));
      expect(cool.pane.b, greaterThan(warm.pane.b));
      // At the lightest surface, where the mix is 8%, it is absolute.
      expect(warm.paneElevated.r, greaterThan(warm.paneElevated.b));
      expect(cool.paneElevated.b, greaterThan(cool.paneElevated.r));
    });

    test('lightness is unchanged by the tint, so the hierarchy holds', () {
      for (final accent in accentPresets.values) {
        final s = ChordiaSurfaces.of(accent);
        expect(
          relativeLuminance(s.pane),
          lessThan(relativeLuminance(s.paneRaised)),
          reason: 'pane < paneRaised',
        );
        expect(
          relativeLuminance(s.paneRaised),
          lessThan(relativeLuminance(s.paneElevated)),
          reason: 'paneRaised < paneElevated',
        );
      }
    });

    test('the hairline is the accent at 18%, not the accent darkened', () {
      final s = ChordiaSurfaces.of(amber);
      expect(s.line.a, closeTo(0.18, 0.005));
      expect(s.line.r, amber.r);
    });
  });

  group('wired to the account', () {
    ProviderContainer containerFor(UserSettings settings) {
      final container = ProviderContainer(
        overrides: [
          userSettingsProvider.overrideWith((ref) async => settings),
          // Artwork mode reads the playing cover, and reaching for it would build the whole
          // playback stack — an audio engine, a cache directory, a media session.
          currentTrackProvider.overrideWithValue(null),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test(
      'a colour chosen on another device re-tints every surface here',
      () async {
        final container = containerFor(const UserSettings(accent: 'amber'));
        await container.read(userSettingsProvider.future);

        final surfaces = container.read(accentSurfacesProvider);
        expect(surfaces.accent, amber);
        expect(surfaces.pane, ChordiaSurfaces.of(amber).pane);
        expect(surfaces.pane, isNot(ChordiaColors.pane));
        expect(container.read(chordiaThemeProvider).colorScheme.primary, amber);
      },
    );

    test('the theme carries the full token set as an extension', () async {
      final container = containerFor(const UserSettings(accent: 'blue'));
      await container.read(userSettingsProvider.future);

      final theme = container.read(chordiaThemeProvider);
      expect(
        theme.extension<ChordiaSurfaces>()?.paneRaised,
        ChordiaSurfaces.of(blue).paneRaised,
      );
      expect(theme.scaffoldBackgroundColor, ChordiaSurfaces.of(blue).pane);
    });

    test('no session leaves the app on the built-in accent', () async {
      final container = ProviderContainer(
        overrides: [
          userSettingsProvider.overrideWith((ref) async => null),
          currentTrackProvider.overrideWithValue(null),
        ],
      );
      addTearDown(container.dispose);
      await container.read(userSettingsProvider.future);

      expect(container.read(accentSurfacesProvider).pane, ChordiaColors.pane);
      expect(container.read(accentConfigProvider).mode, AccentMode.staticValue);
    });

    test('a moving palette still gives the surfaces one stable colour', () async {
      final container = containerFor(
        const UserSettings(
          accent: 'amber',
          accentMode: AccentMode.fade,
          accentPalette: ['crimson', 'blue'],
        ),
      );
      await container.read(userSettingsProvider.future);

      // The surfaces derive from the palette's midpoint, which does not move while the accent
      // cross-fades — that is what keeps a fade from rebuilding the whole tree seven times a
      // second.
      expect(
        container.read(accentConfigProvider).surfaceAccent,
        _hex('#7b729d'),
      );
      final before = container.read(accentSurfacesProvider);
      expect(container.read(accentSurfacesProvider), same(before));
    });

    test('an unknown accent falls back rather than painting nothing', () async {
      final container = containerFor(const UserSettings(accent: 'chartreuse'));
      await container.read(userSettingsProvider.future);
      expect(container.read(accentSurfacesProvider).accent, builtinAccent);
    });

    test('a custom hex from the web picker is honoured verbatim', () async {
      final container = containerFor(const UserSettings(accent: '#3366ff'));
      await container.read(userSettingsProvider.future);
      expect(container.read(accentSurfacesProvider).accent, _hex('#3366ff'));
    });
  });
}
