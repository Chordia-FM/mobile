import 'package:chordia_api/chordia_api.dart';
import 'package:chordia_mobile/features/catalog/data/playback.dart';
import 'package:chordia_mobile/features/catalog/format.dart';
import 'package:chordia_mobile/features/catalog/widgets/artist_links.dart';
import 'package:chordia_mobile/features/catalog/widgets/track_list.dart';
import 'package:chordia_mobile/i18n/translations.dart';
import 'package:chordia_mobile/i18n/translations_provider.dart';
import 'package:chordia_sync/chordia_sync.dart'
    show AlbumContext, PlayContext, PlayerTrack;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Loaded once, in real async: `testWidgets` runs inside a fake-async zone where a real asset read
/// never completes, so the catalogs have to be in hand before the first pump.
late Translations translations;

/// The player the catalog talks to, recording what it was told rather than making a sound.
class RecordingPlayer implements CatalogPlayerActions {
  List<PlayerTrack>? queue;
  int? startIndex;
  PlayContext? context;
  bool? shuffle;
  final List<PlayerTrack> queued = [];
  final List<PlayerTrack> nexted = [];

  @override
  void playQueue(
    List<PlayerTrack> tracks, {
    int startIndex = 0,
    PlayContext? context,
  }) {
    queue = tracks;
    this.startIndex = startIndex;
    this.context = context;
  }

  @override
  void enqueue(PlayerTrack track) => queued.add(track);

  @override
  void playNext(PlayerTrack track) => nexted.add(track);

  @override
  void setShuffle(bool shuffle) => this.shuffle = shuffle;
}

BrowseTrack track(
  String id, {
  required String title,
  int durationMs = 180000,
  int? trackNo,
  int? discNo,
  List<ArtistRef>? artists,
}) => BrowseTrack(
  id: id,
  title: title,
  artist: 'Artist',
  contentHash: 'hash-$id',
  durationMs: durationMs,
  libraryId: 'lib-1',
  trackRef: 'ref-$id',
  trackNo: trackNo,
  discNo: discNo,
  artists: artists,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    translations = await Translations.load('en', bundle: rootBundle);
  });

  Future<RecordingPlayer> pumpTrackList(
    WidgetTester tester, {
    required List<BrowseTrack> tracks,
    required PlayContext? playContext,
    bool groupByDisc = false,
  }) async {
    final player = RecordingPlayer();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          translationsProvider.overrideWithValue(translations),
          catalogPlayerActionsProvider.overrideWithValue(player),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                SliverTrackList(
                  tracks: tracks,
                  playContext: playContext,
                  groupByDisc: groupByDisc,
                  numbered: groupByDisc,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return player;
  }

  group('tapping a track', () {
    testWidgets('queues the whole list from that row, with its context', (
      tester,
    ) async {
      final tracks = [
        track('t1', title: 'First'),
        track('t2', title: 'Second'),
        track('t3', title: 'Third'),
      ];
      final player = await pumpTrackList(
        tester,
        tracks: tracks,
        playContext: const AlbumContext(id: 'al-1', name: 'The Album'),
      );

      await tester.tap(find.text('Third'));
      await tester.pump();

      // The whole list, not the tapped row: an album has to keep playing after the song you
      // started it from.
      expect(player.queue, isNotNull);
      expect(
        player.queue!.map((entry) => entry.id),
        ['t1', 't2', 't3'],
        reason: 'the queue is the list, not the tapped row',
      );
      expect(player.startIndex, 2);
      // Attribution: this is what "Playing from" reads and what the scrobble is credited to.
      expect(player.context, const AlbumContext(id: 'al-1', name: 'The Album'));
    });

    testWidgets('carries the fields the player needs to stream it', (
      tester,
    ) async {
      final player = await pumpTrackList(
        tester,
        tracks: [track('t1', title: 'Only')],
        playContext: null,
      );

      await tester.tap(find.text('Only'));
      await tester.pump();

      // Without these the queue entry cannot be turned into a stream URL or a capability grant,
      // and the failure would only surface at playback.
      final entry = player.queue!.single;
      expect(entry.libraryId, 'lib-1');
      expect(entry.trackRef, 'ref-t1');
      expect(entry.contentHash, 'hash-t1');
    });

    testWidgets('starts the right song on a multi-disc release', (
      tester,
    ) async {
      // Disc headings are rows too. Reading the track back from the LIST index rather than the
      // recorded one would play the song before each heading it sits past.
      final tracks = [
        track('a1', title: 'A One', trackNo: 1, discNo: 1),
        track('a2', title: 'A Two', trackNo: 2, discNo: 1),
        track('b1', title: 'B One', trackNo: 1, discNo: 2),
        track('b2', title: 'B Two', trackNo: 2, discNo: 2),
      ];
      final player = await pumpTrackList(
        tester,
        tracks: tracks,
        playContext: const AlbumContext(id: 'al-2', name: 'Two Discs'),
        groupByDisc: true,
      );

      expect(find.text('Disc 2'), findsOneWidget);

      await tester.tap(find.text('B One'));
      await tester.pump();

      expect(player.startIndex, 2);
      expect(player.queue!.length, 4);
    });
  });

  group('credited artists', () {
    /// Every span that navigates somewhere — one per credited artist.
    List<TextSpan> linkSpans(WidgetTester tester) {
      final rendered = tester.widget<Text>(find.byType(Text));
      final root = rendered.textSpan! as TextSpan;
      return [
        for (final span in root.children ?? const <InlineSpan>[])
          if (span is TextSpan && span.recognizer != null) span,
      ];
    }

    Future<void> pumpLinks(
      WidgetTester tester, {
      List<ArtistRef>? artists,
      required String fallbackName,
      String? fallbackId,
    }) => tester.pumpWidget(
      ProviderScope(
        overrides: [translationsProvider.overrideWithValue(translations)],
        child: MaterialApp(
          home: Scaffold(
            body: ArtistLinks(
              artists: artists,
              fallbackName: fallbackName,
              fallbackId: fallbackId,
            ),
          ),
        ),
      ),
    );

    testWidgets('render one link per credited artist', (tester) async {
      await pumpLinks(
        tester,
        artists: const [
          ArtistRef(id: 'ar-1', name: 'Drake'),
          ArtistRef(id: 'ar-2', name: 'Rihanna'),
        ],
        // The Hub's assembled line. Splitting THIS is what the per-artist list exists to avoid:
        // "feat." is not a separator any split would survive.
        fallbackName: 'Drake feat. Rihanna',
      );

      final links = linkSpans(tester);
      expect(links.length, 2);
      expect(links.map((span) => span.text), ['Drake', 'Rihanna']);
    });

    testWidgets('fall back to one link when the Hub sent no list', (
      tester,
    ) async {
      await pumpLinks(
        tester,
        fallbackName: 'Drake feat. Rihanna',
        fallbackId: 'ar-1',
      );

      final links = linkSpans(tester);
      expect(links.length, 1);
      expect(links.single.text, 'Drake feat. Rihanna');
    });

    testWidgets('render plain text when there is nobody to link to', (
      tester,
    ) async {
      await pumpLinks(tester, fallbackName: 'Unknown Artist');
      expect(linkSpans(tester), isEmpty);
    });
  });

  group('durations', () {
    test('a track length reads as a timecode', () {
      expect(formatTrackLength(0), '0:00');
      expect(formatTrackLength(9000), '0:09');
      expect(formatTrackLength(65000), '1:05');
      // Rounds to the nearest second, so 3:44.6 is not shown as 3:44.
      expect(formatTrackLength(224600), '3:45');
      expect(formatTrackLength(3723000), '1:02:03');
      expect(formatTrackLength(45296000), '12:34:56');
    });

    test('a runtime rounds to whole minutes', () {
      // 47m50s. Truncating would read "47 min", which is wrong by a minute on a header stat.
      expect(formatRuntime(translations, 2870000), '48 min');
      expect(formatRuntime(translations, 60000), '1 min');
      expect(formatRuntime(translations, 4320000), '1 hr 12 min');
      expect(formatRuntime(translations, 7200000), '2 hr 0 min');
    });

    test('a collection runtime is the sum of its tracks', () {
      expect(totalDurationMs([1000, 2000, 3000]), 6000);
      expect(totalDurationMs(const []), 0);
    });
  });

  group('partial dates', () {
    test('the year is sliced, never parsed', () {
      // A `YYYY-MM-DD` read as a DateTime is interpreted as UTC, which can move the year across a
      // time zone at New Year.
      expect(yearOf('1997-01-01'), '1997');
      expect(yearOf('1997-06'), '1997');
      expect(yearOf('1997'), '1997');
      expect(yearOf(null), isNull);
      expect(yearOf('unknown'), isNull);
    });
  });

  group('genre folding', () {
    test('display casing keeps acronyms whole', () {
      expect(titleCaseGenre('hip hop'), 'Hip Hop');
      expect(titleCaseGenre('edm'), 'EDM');
      expect(titleCaseGenre('uk garage'), 'UK Garage');
      // Unicode-aware: an ASCII word boundary would produce "MÚSica".
      expect(titleCaseGenre('música popular'), 'Música Popular');
    });

    test('the slug folds every spelling onto one page', () {
      expect(genreSlug('Hip-Hop'), 'hip hop');
      expect(genreSlug('hip hop'), 'hip hop');
      expect(genreSlug('  HIP   HOP  '), 'hip hop');
    });
  });
}
