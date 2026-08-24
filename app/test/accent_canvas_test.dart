import 'package:chordia_api/chordia_api.dart';
import 'package:chordia_mobile/app/providers.dart';
import 'package:chordia_mobile/app/theme.dart';
import 'package:chordia_mobile/data/accent/accent_canvas.dart';
import 'package:chordia_mobile/data/accent/accent_engine.dart';
import 'package:chordia_mobile/data/accent/accent_fill.dart';
import 'package:chordia_mobile/data/accent/accent_palette.dart';
import 'package:chordia_mobile/data/accent/accent_providers.dart';
import 'package:chordia_mobile/data/accent/accent_scope.dart';
import 'package:chordia_mobile/data/accent/accent_surfaces.dart';
import 'package:chordia_mobile/data/accent/oklab.dart';
import 'package:chordia_mobile/widgets/cover_art.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Where the accent that MOVES actually lands.
///
/// The engine was already faithful to the web constant for constant, and it still produced an app in
/// which Fade, Chroma and Gradient were indistinguishable from Static: every frame it published went
/// to an `AccentScope` that nothing subscribed to. So the assertions worth making here are not about
/// the colours — `accent_test.dart` owns those — but about the wiring: that a tick reaches a surface,
/// and that reaching it does not rebuild the page.
void main() {
  final crimson = accentPresets['crimson']!;
  final blue = accentPresets['blue']!;

  Widget wrap(ValueListenable<AccentFrame> frame, Widget child) => MaterialApp(
    theme: buildChordiaTheme(),
    home: AccentScope(frame: frame, child: child),
  );

  group('accentBloomFor', () {
    test('maps a tab root to its own section', () {
      expect(accentBloomFor('/home'), AccentBloom.home);
      expect(accentBloomFor('/search'), AccentBloom.discover);
      expect(accentBloomFor('/library'), AccentBloom.library);
      expect(accentBloomFor('/insights'), AccentBloom.insights);
    });

    test('the pushed section wins over the tab it was pushed onto', () {
      // The phone's paths carry the tab, so every one of these reaches the same screen from four
      // different prefixes and has to land on the same bloom regardless.
      for (final tab in ['home', 'search', 'library', 'insights']) {
        expect(
          accentBloomFor('/$tab/settings/appearance'),
          AccentBloom.settings,
        );
        expect(accentBloomFor('/$tab/albums/abc'), AccentBloom.library);
        expect(accentBloomFor('/$tab/u/kanin'), AccentBloom.social);
        expect(accentBloomFor('/$tab/genres'), AccentBloom.discover);
        expect(accentBloomFor('/$tab/manager'), AccentBloom.manager);
      }
    });

    test('anything unclassified gets the neutral pair', () {
      expect(accentBloomFor('/'), AccentBloom.home);
      expect(accentBloomFor(''), AccentBloom.home);
      expect(accentBloomFor('/home/somewhere-new'), AccentBloom.home);
    });

    test('the two social-facing sections are the cool-lit ones', () {
      // `[data-surface="insights"], [data-surface="social"]` are the only rules that swap
      // `--bloom-hue`, and losing that is how they would quietly become the same page as the rest.
      final cool = AccentBloom.values.where((b) => b.litByCool).toSet();
      expect(cool, {AccentBloom.insights, AccentBloom.social});
    });
  });

  group('the ambient wash', () {
    testWidgets('paints, and a tick repaints it without rebuilding the page', (
      tester,
    ) async {
      var builds = 0;
      final frame = ValueNotifier(
        AccentFrame(accent: crimson, foreground: foregroundFor(crimson)),
      );
      addTearDown(frame.dispose);

      await tester.pumpWidget(
        wrap(
          frame,
          AccentCanvas(
            child: Builder(
              builder: (context) {
                builds++;
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      );
      expect(builds, 1);

      expect(
        find.descendant(
          of: find.byType(AccentCanvas),
          matching: find.byType(CustomPaint),
        ),
        findsWidgets,
      );

      // The whole point of a `repaint` listenable: the frame drives the painter directly, so a
      // cross-fade moves the wash without any element in the tree being marked dirty.
      frame.value = AccentFrame(accent: blue, foreground: foregroundFor(blue));
      await tester.pump();
      expect(
        builds,
        1,
        reason: 'a tick must not rebuild the page under the canvas',
      );
    });

    testWidgets('takes the page background off the Scaffold', (tester) async {
      // The canvas is the background now. A Scaffold that still painted its own flat pane would
      // cover the bloom completely, which is the failure this override exists to prevent.
      final frame = ValueNotifier(
        AccentFrame(accent: crimson, foreground: foregroundFor(crimson)),
      );
      addTearDown(frame.dispose);

      late BuildContext inner;
      await tester.pumpWidget(
        wrap(
          frame,
          AccentCanvas(
            child: Builder(
              builder: (context) {
                inner = context;
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      );

      expect(Theme.of(inner).scaffoldBackgroundColor, Colors.transparent);
    });
  });

  group('the solid accent surfaces', () {
    ProviderContainer containerFor(UserSettings settings) {
      final container = ProviderContainer(
        overrides: [
          userSettingsProvider.overrideWith((ref) async => settings),
          // Artwork mode reads the playing cover, and reaching for it would build the whole
          // playback stack: an audio engine, a cache directory, a media session.
          currentTrackProvider.overrideWithValue(null),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    /// One ordinary button, wearing the theme the app actually builds.
    ///
    /// Through the real provider rather than a hand-assembled [ThemeData], because the thing under
    /// test IS the wiring: the web opts every accent surface in with one stylesheet rule, and this
    /// client's version of that rule is a builder on the theme's button style. A test that supplied
    /// its own button style would pass just as happily with the rule deleted.
    Future<void> pumpButton(
      WidgetTester tester,
      ProviderContainer container,
      ValueListenable<AccentFrame> frame,
    ) async {
      await container.read(userSettingsProvider.future);
      await tester.pumpWidget(
        MaterialApp(
          theme: container.read(chordiaThemeProvider),
          home: AccentScope(
            frame: frame,
            child: Scaffold(
              body: FilledButton(onPressed: () {}, child: const Text('Play')),
            ),
          ),
        ),
      );
    }

    BoxDecoration decoration(WidgetTester tester) =>
        tester.widget<Ink>(find.byType(Ink)).decoration! as BoxDecoration;

    testWidgets('a still accent leaves the button exactly as it was', (
      tester,
    ) async {
      // Static and Artwork already paint the right colour through the theme. Layering over them
      // anyway would put an opaque widget on top of Material's ink and cost every button in the app
      // its tap feedback for no visible gain.
      final container = containerFor(const UserSettings(accent: 'crimson'));
      final frame = ValueNotifier(
        AccentFrame(accent: crimson, foreground: foregroundFor(crimson)),
      );
      addTearDown(frame.dispose);

      await pumpButton(tester, container, frame);

      expect(find.byType(Ink), findsNothing);
      expect(find.text('Play'), findsOneWidget);
    });

    testWidgets('a cross-fade moves the colour on the button itself', (
      tester,
    ) async {
      final container = containerFor(const UserSettings(accent: 'crimson'));
      final frame = ValueNotifier(
        AccentFrame(accent: crimson, foreground: foregroundFor(crimson)),
      );
      addTearDown(frame.dispose);

      await pumpButton(tester, container, frame);

      // Mid-fade. The theme is still on the resting accent and must stay there, because that is what
      // keeps a tick off the rest of the tree, so the button is the only thing that may move.
      frame.value = AccentFrame(accent: blue, foreground: foregroundFor(blue));
      await tester.pump();
      expect(decoration(tester).color, blue);
    });

    testWidgets('gradient mode paints the palette, not its blend', (
      tester,
    ) async {
      // The blend is what `--primary` is pinned to so the forty derived tokens stay one colour; the
      // gradient is what the solid surfaces are supposed to show. Showing the blend here is exactly
      // the "gradient mode does nothing" bug.
      final container = containerFor(const UserSettings(accent: 'crimson'));
      final frame = ValueNotifier(
        AccentFrame(
          accent: blendStops([crimson, blue])!,
          foreground: foregroundFor(crimson),
          gradient: [crimson, blue],
        ),
      );
      addTearDown(frame.dispose);

      await pumpButton(tester, container, frame);

      final gradient = decoration(tester).gradient! as LinearGradient;
      expect(decoration(tester).color, isNull);
      expect(gradient.colors.first, crimson);
      expect(gradient.colors.last, blue);
    });
  });

  group('placeholder artwork', () {
    final resting = ChordiaSurfaces.of(crimson);

    ({Color start, Color end}) stopsFor(AccentFrame frame) => accentArtStops(
      frame,
      restingAccent: resting.accent,
      restingElevated: resting.paneElevated,
    );

    test('at rest it is the accent over the lightest surface', () {
      final still = stopsFor(
        AccentFrame(accent: crimson, foreground: foregroundFor(crimson)),
      );
      expect(still.start, crimson.withValues(alpha: 0.35));
      expect(still.end, resting.paneElevated.withValues(alpha: 0.22));
    });

    test('a moving accent drags the far end with it', () {
      // `--accent` is a `color-mix` off `--primary`, so a browser moves both ends of the tile in
      // the frame the accent moves in. Pinning the theme's copy would leave every placeholder in a
      // browse grid half-lit by a colour the app stopped wearing several seconds ago.
      final mid = stopsFor(
        AccentFrame(accent: blue, foreground: foregroundFor(blue)),
      );
      expect(mid.start, blue.withValues(alpha: 0.35));
      expect(mid.end, paneElevatedFor(blue).withValues(alpha: 0.22));
      expect(mid.end, isNot(resting.paneElevated.withValues(alpha: 0.22)));
    });

    test('gradient mode paints the palette, not its blend', () {
      // `--accent-a` / `--accent-b`, and the reason the stylesheet publishes them at all: these
      // tiles are the largest accent-derived area in the app, so a palette that reached the buttons
      // and stopped there would be missing from most of what someone looks at.
      final palette = stopsFor(
        AccentFrame(
          accent: blendStops([crimson, blue])!,
          foreground: foregroundFor(crimson),
          gradient: [crimson, blue],
        ),
      );
      expect(palette.start, crimson.withValues(alpha: 0.35));
      expect(palette.end, blue.withValues(alpha: 0.22));
    });

    List<Color> washUnder(WidgetTester tester, Finder of) =>
        (tester
                    .widget<DecoratedBox>(
                      find.descendant(
                        of: of,
                        matching: find.byType(DecoratedBox),
                      ),
                    )
                    .decoration
                as BoxDecoration)
            .gradient!
            .colors;

    testWidgets('a tick moves the wash and leaves the glyph on it alone', (
      tester,
    ) async {
      var builds = 0;
      final frame = ValueNotifier(
        AccentFrame(accent: crimson, foreground: foregroundFor(crimson)),
      );
      addTearDown(frame.dispose);

      await tester.pumpWidget(
        wrap(
          frame,
          Scaffold(
            body: Center(
              child: SizedBox.square(
                dimension: 96,
                child: AccentArt(
                  child: Builder(
                    builder: (context) {
                      builds++;
                      return const SizedBox.expand();
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(builds, 1);
      expect(
        washUnder(tester, find.byType(AccentArt)).first,
        crimson.withValues(alpha: 0.35),
      );

      frame.value = AccentFrame(accent: blue, foreground: foregroundFor(blue));
      await tester.pump();

      expect(
        washUnder(tester, find.byType(AccentArt)).first,
        blue.withValues(alpha: 0.35),
      );
      expect(
        builds,
        1,
        reason: 'the tile subscribes; what is drawn on it has no reason to',
      );
    });

    testWidgets('a coverless tile and its monogram both follow the accent', (
      tester,
    ) async {
      // Through `CoverArt` rather than `AccentArt` directly, because the wiring is the thing that
      // was missing: the tile had a gradient of its own and read the theme, so it was the one large
      // accent surface a cross-fade never reached.
      final frame = ValueNotifier(
        AccentFrame(accent: crimson, foreground: foregroundFor(crimson)),
      );
      addTearDown(frame.dispose);

      Future<void> pump(String? initial) async {
        await tester.pumpWidget(
          ProviderScope(
            child: wrap(
              frame,
              Scaffold(
                body: Center(
                  child: CoverArt(
                    sha256: null,
                    size: 96,
                    fallbackInitial: initial,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 16));
      }

      await pump(null);
      expect(find.byType(AccentArt), findsOneWidget);
      frame.value = AccentFrame(accent: blue, foreground: foregroundFor(blue));
      await tester.pump();
      expect(
        washUnder(tester, find.byType(CoverArt)).first,
        blue.withValues(alpha: 0.35),
      );

      // `MONOGRAM_BG` is three mixes of `var(--primary)` and the letter is
      // `fill-primary-foreground`, so the sphere moves for the same reason the tile does.
      await pump('björk');
      expect(find.text('B'), findsOneWidget);
      expect(washUnder(tester, find.byType(CoverArt))[1], blue);
      expect(
        tester.widget<Text>(find.text('B')).style?.color,
        foregroundFor(blue),
      );
    });

    testWidgets('a hand-rolled accent fill can opt in the same way', (
      tester,
    ) async {
      // The seam for the fills the theme's button style cannot reach. Without it each one either
      // stays on the resting accent or hand-rolls its own subscription, and the second of those is
      // how a colour ends up moving in five places at four different rates.
      final frame = ValueNotifier(
        AccentFrame(accent: crimson, foreground: foregroundFor(crimson)),
      );
      addTearDown(frame.dispose);

      await tester.pumpWidget(
        wrap(
          frame,
          const Scaffold(
            body: Center(
              child: SizedBox.square(
                dimension: 56,
                child: AccentSurface(
                  shape: BoxShape.circle,
                  child: Icon(Icons.play_arrow_rounded),
                ),
              ),
            ),
          ),
        ),
      );

      BoxDecoration fill() =>
          tester
                  .widget<DecoratedBox>(
                    find.descendant(
                      of: find.byType(AccentSurface),
                      matching: find.byType(DecoratedBox),
                    ),
                  )
                  .decoration
              as BoxDecoration;

      expect(fill().color, crimson);
      expect(fill().shape, BoxShape.circle);

      frame.value = AccentFrame(accent: blue, foreground: foregroundFor(blue));
      await tester.pump();
      expect(fill().color, blue);
      // `--primary-foreground` moves with `--primary`, or a palette whose ends want opposite
      // foregrounds goes unreadable halfway through the fade.
      expect(
        IconTheme.of(tester.element(find.byType(Icon))).color,
        foregroundFor(blue),
      );
    });
  });

  group('ambientBloom', () {
    final resting = ChordiaSurfaces.of(crimson);

    ({Color warm, Color cool}) light(
      AccentFrame frame, [
      AccentBloom bloom = AccentBloom.home,
    ]) => ambientBloom(
      frame,
      bloom,
      restingAccent: resting.accent,
      restingCool: resting.ambientCool,
    );

    test('at rest it is the tokens the theme already holds', () {
      final still = light(
        AccentFrame(accent: crimson, foreground: foregroundFor(crimson)),
      );
      expect(still.warm, crimson);
      expect(still.cool, resting.ambientCool);
    });

    test('a moving accent drags the cool companion with it', () {
      // `--ambient-cool` is a `color-mix` off `--primary`, so the browser moves both in one frame.
      // Holding the theme's copy through a cross-fade would light one side of the page from a
      // colour the app stopped wearing several seconds ago.
      final mid = light(
        AccentFrame(accent: blue, foreground: foregroundFor(blue)),
      );
      expect(mid.warm, blue);
      expect(mid.cool, ambientCoolFor(blue));
      expect(mid.cool, isNot(resting.ambientCool));
    });

    test('gradient mode lights it with the palette instead of a fixed blue', () {
      final palette = light(
        AccentFrame(
          accent: blendStops([crimson, blue])!,
          foreground: foregroundFor(crimson),
          gradient: [crimson, blue],
        ),
      );
      // The blend on the warm side, because `--primary` has to stay one colour; the palette's far
      // stop on the cool side, which is the whole of `--ambient-cool: var(--accent-b, …)`.
      expect(palette.warm, blendStops([crimson, blue]));
      expect(palette.cool, blue);
    });

    test('the cool-lit sections use one hue on both sides', () {
      final social = light(
        AccentFrame(accent: blue, foreground: foregroundFor(blue)),
        AccentBloom.social,
      );
      expect(social.warm, social.cool);
      expect(social.warm, ambientCoolFor(blue));
    });
  });

  group('oklabRamp', () {
    test('samples the OKLab path rather than the sRGB one', () {
      // Same pair as `accent_test.dart`'s mixing case: sRGB halfway between red and blue is a muddy
      // #800080, OKLab is #8c53a2. A LinearGradient interpolates in sRGB, so a two-stop gradient
      // would walk the muddy line — the extra samples are what keep it on the perceptual one.
      final red = parseHexColor('#ff0000')!;
      final deepBlue = parseHexColor('#0000ff')!;
      final ramp = oklabRamp([red, deepBlue]);

      expect(ramp.first, red);
      expect(ramp.last, deepBlue);
      expect(ramp[ramp.length ~/ 2], mixOklab(deepBlue, 0.5, red));
      expect(ramp[ramp.length ~/ 2], isNot(mixSrgb(deepBlue, 0.5, red)));
    });

    test('a single stop is not a gradient and is left alone', () {
      expect(oklabRamp([crimson]), [crimson]);
    });

    test('every segment of a longer palette is sampled', () {
      final ramp = oklabRamp([crimson, blue, crimson], perSegment: 4);
      expect(ramp.length, 9);
      expect(ramp[4], blue);
    });
  });
}
