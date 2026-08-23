import 'package:chordia_api/chordia_api.dart' show ArtistRef;
import 'package:chordia_mobile/features/catalog/widgets/artist_links.dart';
import 'package:chordia_sync/chordia_sync.dart' show TrackArtist;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// A tab holding the links, with the artist page they reach underneath it.
///
/// A real router rather than a stub, because the thing under test is where the tap LANDS: the
/// destination is built from the tab the listener is in, and a fake that records a string would
/// pass just as happily for a link that opened the wrong artist.
Widget _app(Widget links) => MaterialApp.router(
  routerConfig: GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(
        path: '/home',
        builder: (_, _) => Scaffold(body: links),
        routes: [
          GoRoute(
            path: 'artists/:artistId',
            builder: (_, state) => Scaffold(
              body: Text('artist:${state.pathParameters['artistId']}'),
            ),
          ),
        ],
      ),
    ],
  ),
);

/// The one `Text.rich` the links render.
Text _rendered(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .firstWhere((text) => text.textSpan != null);

/// Every span that navigates somewhere — one per credited artist.
List<TextSpan> _linkSpans(WidgetTester tester) {
  final root = _rendered(tester).textSpan! as TextSpan;
  return [
    for (final span in root.children ?? const <InlineSpan>[])
      if (span is TextSpan && span.recognizer != null) span,
  ];
}

void main() {
  testWidgets('a credited line is one link per artist, comma-joined', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const ArtistLinks(
          artists: [
            ArtistRef(id: 'ar-1', name: 'Drake'),
            ArtistRef(id: 'ar-2', name: 'Rihanna'),
          ],
          // The Hub's assembled line. Splitting THIS is what the per-artist list exists to avoid:
          // "feat." is not a separator any split survives, and neither is an artist whose own name
          // contains a comma.
          fallbackName: 'Drake feat. Rihanna',
        ),
      ),
    );

    expect(_linkSpans(tester).map((span) => span.text), ['Drake', 'Rihanna']);
    // ", " between names, which is what `ArtistLink.tsx` renders. The join phrase the Hub used to
    // build the display line is not reproduced here on either client.
    expect(_rendered(tester).textSpan!.toPlainText(), 'Drake, Rihanna');
  });

  testWidgets('tapping a credited name opens THAT artist, not the primary', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const ArtistLinks(
          artists: [
            ArtistRef(id: 'ar-1', name: 'Drake'),
            ArtistRef(id: 'ar-2', name: 'Rihanna'),
          ],
          fallbackName: 'Drake feat. Rihanna',
        ),
      ),
    );

    await tester.tapOnText(find.textRange.ofSubstring('Rihanna'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // The featured artist, from the tab the link was tapped in.
    expect(find.text('artist:ar-2'), findsOneWidget);
  });

  testWidgets('the no-list fallback is one link to the primary artist', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const ArtistLinks(
          artists: null,
          fallbackName: 'Drake feat. Rihanna',
          fallbackId: 'ar-1',
        ),
      ),
    );

    expect(_linkSpans(tester).single.text, 'Drake feat. Rihanna');

    await tester.tapOnText(find.textRange.ofSubstring('Drake feat. Rihanna'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('artist:ar-1'), findsOneWidget);
  });

  test('a queue entry\'s credits convert without losing anybody', () {
    // The player, the queue and the lyrics header all draw `PlayerTrack.artists`, which is
    // `chordia_sync`'s twin of `ArtistRef`. Losing the id in that conversion would render the same
    // names as plain text and take every player-side link away silently.
    final refs = playerArtistRefs(const [
      TrackArtist(id: 'ar-1', name: 'Drake'),
      TrackArtist(id: 'ar-2', name: 'Rihanna', imageUrl: '/v1/images/abc'),
    ]);

    expect(refs!.map((ref) => ref.id), ['ar-1', 'ar-2']);
    expect(refs.map((ref) => ref.name), ['Drake', 'Rihanna']);
    expect(refs.last.imageUrl, '/v1/images/abc');
    // Null is "the Hub sent no list", which the widget answers with the assembled line; an empty
    // list would claim the track has nobody credited.
    expect(playerArtistRefs(null), isNull);
  });
}
