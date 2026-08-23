import 'dart:io';

import 'package:chordia_mobile/app/theme.dart';
import 'package:chordia_mobile/features/catalog/widgets/track_row.dart';
import 'package:chordia_mobile/widgets/brand/logo.dart';
import 'package:chordia_mobile/widgets/cover_art.dart';
import 'package:chordia_mobile/widgets/states.dart';
import 'package:chordia_mobile/widgets/surface.dart';
import 'package:chordia_mobile/widgets/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The rules that keep the phone reading as the same product as the web client.
///
/// Every assertion here exists because breaking it is silent: nothing crashes when a row goes back
/// to `bodyLarge`, when a card picks up a Material ripple, or when a logo starts idling in an app
/// bar. The point of this file is that those stop being invisible.
///
/// Three of them are source-level greps rather than widget tests, deliberately. "No hard-coded
/// corner radius", "no backdrop filter on a scrolling surface" and "the accent is never a literal
/// hex" are statements about the whole widget layer, and a widget test can only ever check the one
/// tree it builds — which is exactly how the phone drifted in the first place.
void main() {
  // `pumpAndSettle` is unusable in this app (the player ticks at 2 Hz and the settle never comes),
  // so every pump below is a fixed frame count.
  const frame = Duration(milliseconds: 16);

  Widget host(Widget child) => MaterialApp(
    theme: buildChordiaTheme(),
    home: Scaffold(body: Center(child: child)),
  );

  group('the brand mark', () {
    testWidgets('at rest it schedules no frames — the spin is never idle', (
      tester,
    ) async {
      await tester.pumpWidget(host(const ChordiaLogo()));
      await tester.pump(frame);

      // The rule from docs/overhaul/13-brand.md: "the spin is event-scoped, never idle-permanent",
      // because a permanently animating element in the shell repaints on every screen. A ticker
      // that is merely PAUSED still holds a frame callback, so this asserts there is none — the
      // controller is stopped, not parked.
      expect(
        tester.binding.transientCallbackCount,
        0,
        reason: 'an idle mark must hold no ticker at all',
      );
    });

    testWidgets('playing, it animates, and stopping releases the ticker', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(const ChordiaLogo(state: ChordiaLogoState.playing)),
      );
      await tester.pump(frame);
      expect(tester.binding.transientCallbackCount, greaterThan(0));

      await tester.pumpWidget(host(const ChordiaLogo()));
      await tester.pump(frame);
      expect(
        tester.binding.transientCallbackCount,
        0,
        reason: 'flipping back to idle must stop the ticker, not pause it',
      );
    });

    testWidgets('the wide lockup is wider than the square one, at one height', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ChordiaLogo(key: ValueKey('square'), size: 64),
              ChordiaLogo(
                key: ValueKey('wide'),
                variant: ChordiaLogoVariant.wide,
                size: 64,
              ),
            ],
          ),
        ),
      );
      await tester.pump(frame);

      final square = tester.getSize(find.byKey(const ValueKey('square')));
      final wide = tester.getSize(find.byKey(const ValueKey('wide')));
      // The square lockup is its own viewBox; the wide one is the same 64 tall and carries the
      // wordmark beside it.
      expect(square.width, square.height);
      expect(wide.height, square.height);
      expect(wide.width, greaterThan(square.width * 2));
    });
  });

  group('the row', () {
    testWidgets('is the web row: 40px cover, sm over xs, no ListTile', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          const TrackRowLayout(
            title: 'Song',
            durationMs: 185000,
            subtitle: Text('Artist'),
          ),
        ),
      );
      await tester.pump(frame);

      // A `ListTile` brings its own heights, insets and ink ripple. A row built from one is a
      // Material row wearing this app's colours, which is the complaint in miniature.
      expect(find.byType(ListTile), findsNothing);

      final cover = tester.widget<CoverArt>(find.byType(CoverArt));
      expect(
        cover.size,
        TrackRowLayout.coverSize,
        reason: 'the web uses size-10',
      );
      expect(TrackRowLayout.coverSize, 40);

      // `truncate font-medium text-sm` over `text-muted-foreground text-xs`.
      final title = tester.widget<Text>(find.text('Song'));
      expect(title.style?.fontSize, ChordiaType.sm.fontSize);
      expect(title.style?.fontWeight, ChordiaType.medium);
      expect(ChordiaType.sm.fontSize, 14);
      expect(ChordiaType.xs.fontSize, 12);
    });

    testWidgets('the accent marks the playing row, and only that row', (
      tester,
    ) async {
      final theme = buildChordiaTheme();

      Future<Color?> titleColour({required bool active}) async {
        await tester.pumpWidget(
          host(
            TrackRowLayout(
              key: ValueKey(active),
              title: 'Song',
              durationMs: 1000,
              trackNumber: 3,
              active: active,
            ),
          ),
        );
        await tester.pump(frame);
        return tester.widget<Text>(find.text('Song')).style?.color;
      }

      expect(await titleColour(active: false), theme.colorScheme.onSurface);
      // `isActive && "text-primary"` (TrackList.tsx:610) — the one per-row use of the colour on
      // the web, and the answer to "which of these is playing".
      expect(await titleColour(active: true), theme.colorScheme.primary);
      // And the number slot becomes the marker, as it does on the web.
      expect(find.text('♪'), findsOneWidget);
      expect(find.text('3'), findsNothing);
    });
  });

  group('surfaces', () {
    testWidgets('a panel is opaque and carries no backdrop filter', (
      tester,
    ) async {
      await tester.pumpWidget(host(const IslandPanel(child: Text('body'))));
      await tester.pump(frame);

      // styles.css:636-666 — "Opaque is not a compromise here, it is the fix." A blurred panel
      // re-blurs its whole backdrop on any repaint inside it, and inside a scroll container it does
      // so every scrolled frame.
      expect(find.byType(BackdropFilter), findsNothing);

      final decoration =
          tester
                  .widget<Container>(
                    find
                        .descendant(
                          of: find.byType(IslandPanel),
                          matching: find.byType(Container),
                        )
                        .first,
                  )
                  .decoration!
              as BoxDecoration;
      // A gradient between two accent-tinted near-blacks, both fully opaque.
      final gradient = decoration.gradient! as LinearGradient;
      for (final colour in gradient.colors) {
        expect(
          colour.a,
          1.0,
          reason: 'a content panel must not be see-through',
        );
      }
    });

    testWidgets('a pressable card fills and never ripples', (tester) async {
      await tester.pumpWidget(
        host(PressFill(onTap: () {}, child: const Text('card'))),
      );
      await tester.pump(frame);

      final ink = tester.widget<InkWell>(find.byType(InkWell));
      // styles.css:914-928: list rows and cards opt out of the transition rule on purpose, and an
      // ink ripple is the same per-press animation in a different costume.
      expect(ink.splashFactory, NoSplash.splashFactory);
      expect(ink.splashColor, Colors.transparent);
      expect(ink.highlightColor, isNotNull);
    });
  });

  group('artwork', () {
    testWidgets('a missing cover is accent-derived, not grey', (tester) async {
      await tester.pumpWidget(host(const CoverArt(sha256: null, size: 96)));
      await tester.pump(frame);

      final scheme = buildChordiaTheme().colorScheme;
      final gradients = tester
          .widgetList<DecoratedBox>(
            find.descendant(
              of: find.byType(CoverArt),
              matching: find.byType(DecoratedBox),
            ),
          )
          .map((box) => (box.decoration as BoxDecoration).gradient)
          .whereType<Gradient>();

      // `.accent-art` (styles.css:1050) exists precisely so a browse grid — which is mostly
      // placeholder tiles — carries the chosen colour. This used to paint a flat
      // `surfaceContainerHighest`, which is why the phone's colour scheme read as not working.
      expect(gradients, isNotEmpty);
      expect(
        gradients
            .expand((gradient) => gradient.colors)
            .any(
              // Compared channel by channel: the stop carries the accent at 35% alpha, so it is the
              // same colour rather than the same `Color`.
              (colour) =>
                  colour.r == scheme.primary.r &&
                  colour.g == scheme.primary.g &&
                  colour.b == scheme.primary.b,
            ),
        isTrue,
        reason: 'a missing cover must be painted from the live accent',
      );
    });

    testWidgets('an imageless artist gets a monogram on an accent sphere', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          const CoverArt(
            sha256: null,
            size: 96,
            shape: BoxShape.circle,
            fallbackInitial: 'björk',
          ),
        ),
      );
      await tester.pump(frame);

      // `CoverArt.tsx`'s `fallbackInitial`: "so an imageless artist reads as a tasteful monogram"
      // rather than a flat wash. Upper-cased, first grapheme only.
      expect(find.text('B'), findsOneWidget);
    });
  });

  group('states', () {
    testWidgets('a skeleton sweeps rather than pulsing', (tester) async {
      await tester.pumpWidget(host(const ShimmerBox(width: 100, height: 12)));
      await tester.pump(frame);

      BoxDecoration decorationNow() =>
          tester
                  .widget<Container>(
                    find
                        .descendant(
                          of: find.byType(ShimmerBox),
                          matching: find.byType(Container),
                        )
                        .first,
                  )
                  .decoration!
              as BoxDecoration;

      final first = (decorationNow().gradient! as LinearGradient).begin;
      await tester.pump(const Duration(milliseconds: 400));
      final later = (decorationNow().gradient! as LinearGradient).begin;

      // `.skeleton` is a highlight travelling from -100% to 100%, not an opacity pulse. Asserting
      // the gradient MOVED is what would fail if someone swapped the sweep back for a fade — a
      // fade would leave `begin` untouched.
      expect(later, isNot(first));
    });

    testWidgets('an empty state is a dashed outline, not a bare paragraph', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(const EmptyState(message: 'Nothing yet', hint: 'Add something')),
      );
      await tester.pump(frame);

      expect(find.byType(DashedPanel), findsOneWidget);
      final headline = tester.widget<Text>(find.text('Nothing yet'));
      expect(headline.style?.fontSize, ChordiaType.lg.fontSize);
      expect(headline.style?.fontWeight, ChordiaType.semibold);
    });

    testWidgets('an error offers the retry inside a real panel', (
      tester,
    ) async {
      var retried = 0;
      await tester.pumpWidget(
        host(
          ErrorState(
            title: 'Could not reach the server.',
            detail: 'The library is offline.',
            actionLabel: 'Try again',
            onRetry: () => retried++,
          ),
        ),
      );
      await tester.pump(frame);

      expect(find.byType(IslandPanel), findsOneWidget);
      // The headline and the server's own words are two lines, not one run-on string: "unreachable"
      // and "you may not see this library" are the same headline and very different problems.
      expect(find.text('Could not reach the server.'), findsOneWidget);
      expect(find.text('The library is offline.'), findsOneWidget);

      await tester.tap(find.text('Try again'));
      await tester.pump(frame);
      expect(retried, 1);
    });
  });

  group('the widget layer as a whole', () {
    final sources = Directory('lib/widgets')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .toList(growable: false);

    setUpAll(() {
      // If this ever finds nothing, the three greps below would pass vacuously — which is the
      // failure mode a gate like this is most likely to die of.
      expect(sources, isNotEmpty);
    });

    /// A file's CODE, with every comment removed.
    ///
    /// Without this the first rule fails on its own explanation: `surface.dart` documents why it
    /// never uses a `BackdropFilter`, and a grep over raw source cannot tell a prohibition from a
    /// use. Naming a banned construct in order to ban it has to stay legal, or the only way to keep
    /// a gate green is to stop writing down why it exists.
    String codeOf(File file) => file
        .readAsLinesSync()
        .map((line) {
          final comment = line.indexOf('//');
          return comment == -1 ? line : line.substring(0, comment);
        })
        .join('\n');

    test('no scrolling surface carries a backdrop filter', () {
      // The one place glass is permitted at all is a fixed overlay, and even there the web removed
      // it after measuring (styles.css:636-666). Nothing in the shared widget layer may reintroduce
      // it, because anything here can end up inside a list.
      for (final file in sources) {
        expect(
          codeOf(file),
          isNot(contains('BackdropFilter')),
          reason: '${file.path} must not blur its backdrop',
        );
      }
    });

    test('corner radii come from the scale, not from a number', () {
      // `--radius` and its four derivations are the whole corner vocabulary. A stray
      // `BorderRadius.circular(14)` is how a card ends up almost — but not quite — matching the
      // card beside it, which is the species of wrongness that reads as "a different app".
      final literal = RegExp(r'BorderRadius\.circular\(\s*\d');
      for (final file in sources) {
        // tokens.dart is where the scale is DEFINED, so it is the one file allowed to say a number.
        if (file.path.endsWith('tokens.dart')) continue;
        expect(
          literal.hasMatch(codeOf(file)),
          isFalse,
          reason: '${file.path} hard-codes a corner radius; use ChordiaRadius',
        );
      }
    });

    test('the accent is never a literal colour', () {
      // Every surface in styles.css is `color-mix(… var(--primary) N% …)`, which is what makes the
      // whole app re-tint when the accent changes. A `Color(0xFF…)` in a widget is the static-theme
      // bug in one line — and it is exactly what the phone shipped.
      final hex = RegExp(r'Color\(0x[fF][fF]');
      for (final file in sources) {
        expect(
          hex.hasMatch(codeOf(file)),
          isFalse,
          reason:
              '${file.path} names a colour; read it off the ColorScheme instead',
        );
      }
    });
  });
}
