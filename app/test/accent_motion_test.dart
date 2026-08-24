import 'package:chordia_mobile/app/providers.dart';
import 'package:chordia_mobile/app/theme.dart';
import 'package:chordia_mobile/data/accent/accent_engine.dart';
import 'package:chordia_mobile/data/accent/accent_fill.dart';
import 'package:chordia_mobile/data/accent/accent_palette.dart';
import 'package:chordia_mobile/data/accent/accent_scope.dart';
import 'package:chordia_mobile/data/mesh/mirror.dart';
import 'package:chordia_mobile/data/mesh/providers.dart';
import 'package:chordia_mobile/features/catalog/widgets/section.dart';
import 'package:chordia_mobile/features/library/widgets/collection_header.dart';
import 'package:chordia_mobile/features/player/mini_player.dart';
import 'package:chordia_mobile/i18n/translations.dart';
import 'package:chordia_sync/chordia_sync.dart'
    show PlayerTrack, RepeatMode, TrackArtist;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The hand-rolled accent surfaces, and whether a tick actually reaches them.
///
/// `accent_canvas_test.dart` proves the SEAM works — `AccentSurface`, `AccentArt` and the theme's
/// button style all follow the frame. This file is about the surfaces that were built before the
/// seam existed and kept reading the theme afterwards, which is a failure with a particular shape:
/// nothing looks wrong at rest, and each one only reveals itself for the second and a half of every
/// cross-fade in which it disagrees with the control beside it.
///
/// So every assertion here is made twice — once at rest and once after a tick the theme is
/// deliberately NOT told about, because leaving the theme behind is exactly what keeps a fade off
/// the rest of the tree, and a surface that reads it is a surface that will not move.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final crimson = accentPresets['crimson']!;
  final blue = accentPresets['blue']!;

  late Translations translations;

  setUpAll(() async {
    // In real async: `testWidgets` runs in a fake-async zone where an asset read never completes.
    translations = await Translations.load('en', bundle: rootBundle);
  });

  ValueNotifier<AccentFrame> restingOn(Color accent) {
    final frame = ValueNotifier(
      AccentFrame(accent: accent, foreground: foregroundFor(accent)),
    );
    addTearDown(frame.dispose);
    return frame;
  }

  Widget wrap(ValueListenable<AccentFrame> frame, Widget child) => MaterialApp(
    // The theme is built from the DEFAULT accent and never told about any of this, which is what
    // makes the assertions below sharp in both directions: the frames are crimson and blue, so a
    // widget that reached for `Theme.of(context)` reports the built-in magenta and fails at rest,
    // before the tick has even happened.
    theme: buildChordiaTheme(),
    home: AccentScope(frame: frame, child: child),
  );

  group('the artist banner', () {
    /// The base wash under the four glows: `--primary` at 6%.
    Color wash(WidgetTester tester) => tester
        .widget<ColoredBox>(
          find.descendant(
            of: find.byType(AccentBanner),
            matching: find.byType(ColoredBox),
          ),
        )
        .color;

    /// The first stop of one glow, which is its colour at its own alpha.
    Color glow(WidgetTester tester, int index) =>
        ((tester
                            .widget<DecoratedBox>(
                              find
                                  .descendant(
                                    of: find.byType(AccentBanner),
                                    matching: find.byType(DecoratedBox),
                                  )
                                  .at(index),
                            )
                            .decoration
                        as BoxDecoration)
                    .gradient!
                as RadialGradient)
            .colors
            .first;

    testWidgets('every layer of it follows the accent', (tester) async {
      final frame = restingOn(crimson);
      await tester.pumpWidget(
        wrap(
          frame,
          const Scaffold(body: SizedBox(height: 200, child: AccentBanner())),
        ),
      );

      expect(wash(tester), crimson.withValues(alpha: 0.06));
      expect(glow(tester, 0), crimson.withValues(alpha: 0.42));

      frame.value = AccentFrame(accent: blue, foreground: foregroundFor(blue));
      await tester.pump();

      // `DefaultArtistBanner.tsx` writes all five layers `var(--primary)`, so a browser repaints
      // the whole banner in the frame the accent moves in. This is the largest accent-derived area
      // on an artist page: holding it still is the most visible way to be half-way ported.
      expect(wash(tester), blue.withValues(alpha: 0.06));
      expect(glow(tester, 0), blue.withValues(alpha: 0.42));
      // The highlight hotspot is `color-mix(in srgb, var(--primary), white 32%)`, so it moves too
      // — and it is the one layer a careless port leaves derived from a stale colour.
      expect(
        glow(tester, 3),
        Color.lerp(blue, Colors.white, 0.32)!.withValues(alpha: 0.48),
      );
    });
  });

  group('the placeholder tile a collection wears', () {
    List<Color> sweep(WidgetTester tester) =>
        ((tester
                            .widget<Container>(
                              find.descendant(
                                of: find.byType(GradientArtwork),
                                matching: find.byType(Container),
                              ),
                            )
                            .decoration!
                        as BoxDecoration)
                    .gradient!
                as LinearGradient)
            .colors;

    Future<void> pump(
      WidgetTester tester,
      ValueListenable<AccentFrame> frame, {
      List<Color>? colors,
    }) => tester.pumpWidget(
      wrap(
        frame,
        Scaffold(
          body: GradientArtwork(
            icon: Icons.favorite_rounded,
            size: collectionArtSize,
            colors: colors,
          ),
        ),
      ),
    );

    testWidgets('is liked.tsx\'s pair, not the coverless-tile recipe', (
      tester,
    ) async {
      // `bg-linear-to-br from-primary to-accent/60`. The far end is `--accent` — `paneElevated`,
      // the lightest of the shadcn surfaces — and this tile used to read `surfaceContainerHigh`,
      // which is `card`. Two different surfaces, one of them visibly darker, and no test would
      // ever have noticed because both are plausible greys.
      final frame = restingOn(crimson);
      await pump(tester, frame);

      final surfaces = ChordiaSurfaces.of(crimson);
      expect(sweep(tester), [
        crimson,
        surfaces.paneElevated.withValues(alpha: 0.6),
      ]);
    });

    testWidgets('moves, glyph included', (tester) async {
      final frame = restingOn(crimson);
      await pump(tester, frame);

      frame.value = AccentFrame(accent: blue, foreground: foregroundFor(blue));
      await tester.pump();

      expect(sweep(tester), [
        blue,
        // `--accent` is a `color-mix` off `--primary`, so the far end has to be re-derived in the
        // same frame rather than left on the theme's resting copy.
        ChordiaSurfaces.of(blue).paneElevated.withValues(alpha: 0.6),
      ]);
      // `text-primary-foreground` moves with `--primary`: a palette whose ends want opposite sides
      // of the crossover leaves the glyph unreadable halfway through otherwise.
      expect(
        IconTheme.of(tester.element(find.byType(Icon))).color,
        foregroundFor(blue),
      );
    });

    testWidgets('a page with its own colours does not follow the accent', (
      tester,
    ) async {
      // Downloads is `from-emerald-500 to-sky-600` on the web — fixed colours that have nothing to
      // do with the account's accent, so a tick must leave them exactly where they are.
      const fixed = [Color(0xFF10B981), Color(0xFF0284C7)];
      final frame = restingOn(crimson);
      await pump(tester, frame, colors: fixed);

      frame.value = AccentFrame(accent: blue, foreground: foregroundFor(blue));
      await tester.pump();

      expect(sweep(tester), fixed);
    });
  });

  group('the player bar', () {
    testWidgets('draws its progress hairline on the live accent', (
      tester,
    ) async {
      final frame = restingOn(crimson);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            translationsProvider.overrideWithValue(translations),
            // No device owns playback, so the bar is the local one rather than the mirror.
            mirrorStateProvider.overrideWithValue(MirrorState.idle),
            playerStateProvider.overrideWith(_FixedPlayerState.new),
            playerPositionProvider.overrideWith(
              (ref) => Stream.value(const Duration(seconds: 60)),
            ),
          ],
          child: wrap(frame, const Scaffold(body: Align(child: MiniPlayer()))),
        ),
      );
      await tester.pump();

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

      // `PlayerBar.tsx:197` is `h-0.5 bg-primary`, which the blanket rule in `styles.css` repaints
      // along with every other solid accent surface. A `LinearProgressIndicator` — which is what
      // this was — takes one flat `color` and has nowhere to put the palette.
      expect(fill().color, crimson);

      frame.value = AccentFrame(accent: blue, foreground: foregroundFor(blue));
      await tester.pump();
      expect(fill().color, blue);
    });
  });
}

/// A track playing, halfway through, with no artwork.
///
/// No cover on purpose: `CoverArt` short-circuits on a null hash, so the bar draws without a
/// platform art directory behind it.
const _track = PlayerTrack(
  id: 'track-1',
  title: 'Take Care',
  artist: 'Drake',
  artistId: 'ar-1',
  artists: [TrackArtist(id: 'ar-1', name: 'Drake')],
  album: 'Take Care',
  durationMs: 210000,
  libraryId: 'lib-1',
  trackRef: 'ref-1',
  contentHash: 'hash-1',
);

/// The queue and the transport, frozen. The real notifier subscribes to the audio handler, which
/// no test binding can start.
class _FixedPlayerState extends PlayerStateNotifier {
  @override
  PlayerSnapshot build() => const PlayerSnapshot(
    current: _track,
    queue: [_track],
    currentIndex: 0,
    playing: true,
    buffering: false,
    shuffle: false,
    repeat: RepeatMode.off,
    sleepTimer: null,
    context: null,
  );
}
