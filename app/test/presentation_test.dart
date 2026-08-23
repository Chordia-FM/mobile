import 'dart:io';

import 'package:chordia_api/chordia_api.dart';
import 'package:chordia_mobile/app/providers.dart';
import 'package:chordia_mobile/app/theme.dart';
import 'package:chordia_mobile/data/art/art_cache.dart';
import 'package:chordia_mobile/features/catalog/album_screen.dart';
import 'package:chordia_mobile/features/catalog/artist_screen.dart';
import 'package:chordia_mobile/features/catalog/widgets/album_grid.dart';
import 'package:chordia_mobile/features/catalog/widgets/section.dart';
import 'package:chordia_mobile/i18n/keys.g.dart';
import 'package:chordia_mobile/i18n/translations.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// How the catalog PRESENTS things: entity headers, hero surfaces and shelves.
///
/// These assert structure, not pixels. Every one of them fails on a header that stops doing
/// something the web's header does — a credited artist that stops being a link, a banner-less
/// artist that stops laying out, a shelf that shows a subset with no way to reach the rest.

/// Loaded once, in real async: `testWidgets` runs inside a fake-async zone where a real asset read
/// never completes, so the catalogs have to be in hand before the first pump.
late Translations translations;

BrowseTrack track(String id, {int durationMs = 180000}) => BrowseTrack(
  id: id,
  title: 'Track $id',
  artist: 'Artist',
  contentHash: 'hash-$id',
  durationMs: durationMs,
  libraryId: 'lib-1',
  trackRef: 'ref-$id',
);

BrowseAlbum album(String id) =>
    BrowseAlbum(id: id, title: 'Album $id', artist: 'Artist', trackCount: 10);

/// Every span in the rendered tree that carries a tap recognizer — i.e. every link.
List<String> linkTexts(WidgetTester tester) {
  final texts = <String>[];
  for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
    rich.text.visitChildren((span) {
      if (span is TextSpan &&
          span.recognizer is TapGestureRecognizer &&
          span.text != null) {
        texts.add(span.text!);
      }
      return true;
    });
  }
  return texts;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory artDirectory;

  setUpAll(() async {
    translations = await Translations.load('en', bundle: rootBundle);
  });

  setUp(() async {
    artDirectory = await Directory.systemTemp.createTemp('chordia_present');
  });

  tearDown(() async {
    if (await artDirectory.exists()) await artDirectory.delete(recursive: true);
  });

  /// Pumps [child] with translations and an art cache that has nothing in it.
  ///
  /// Fixed frames, never `pumpAndSettle`: the player ticks at 2Hz and settling never returns. Two
  /// pumps is enough for the art cache to answer "missing" and the placeholders to settle.
  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          translationsProvider.overrideWithValue(translations),
          artCacheProvider.overrideWithValue(
            ArtCache(
              directory: Future.value(artDirectory),
              fetch: (sha, width) => throw ArtMissingException(sha),
            ),
          ),
        ],
        child: MaterialApp(
          theme: buildChordiaTheme(),
          home: Scaffold(body: SingleChildScrollView(child: child)),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  group('album header', () {
    testWidgets('renders one link per credited artist', (tester) async {
      // `AlbumDetail` carries ONE credited-artist line, assembled by the Hub ("X feat. Y"), plus
      // the primary artist's id — the same pair the web's `AlbumView` hands to `ArtistLink`. So
      // "one link per credited artist" is one link here, and it must be the credited line itself,
      // never a comma-split of it.
      await pump(
        tester,
        AlbumHeader(
          album: AlbumDetail(
            id: 'al-1',
            title: 'A Record',
            artist: 'Someone feat. Another',
            artistId: 'ar-1',
            tracks: [track('t1'), track('t2')],
          ),
        ),
      );

      expect(linkTexts(tester), ['Someone feat. Another']);
    });

    testWidgets('names the artist as plain text when there is no id to open', (
      tester,
    ) async {
      await pump(
        tester,
        const AlbumHeader(
          album: AlbumDetail(
            id: 'al-1',
            title: 'A Record',
            artist: 'Someone',
            tracks: [],
          ),
        ),
      );

      expect(linkTexts(tester), isEmpty);
      expect(find.textContaining('Someone', findRichText: true), findsWidgets);
    });

    testWidgets('carries the release facts on one line after the artist', (
      tester,
    ) async {
      await pump(
        tester,
        AlbumHeader(
          album: AlbumDetail(
            id: 'al-1',
            title: 'A Record',
            artist: 'Someone',
            artistId: 'ar-1',
            year: 1999,
            tracks: [track('t1'), track('t2')],
          ),
        ),
      );

      // Song count and runtime sit in the same line as the year, joined by the app's separator —
      // the web renders them as one `<p>` and the phone must not spread them over three rows.
      final facts = tester.widget<Text>(
        find.textContaining('1999', findRichText: false),
      );
      expect(facts.data, contains('·'));
      expect(facts.data, contains('6 min'));
    });
  });

  group('artist header', () {
    testWidgets('an artist with no banner still lays out', (tester) async {
      await pump(
        tester,
        const ArtistHeader(
          artist: ArtistDetail(
            id: 'ar-1',
            name: 'Bandname',
            albums: [],
            topTracks: [],
          ),
        ),
      );

      // No banner art → the accent mesh fills the hero, and no banner widget is built at all.
      expect(find.byType(AccentBanner), findsOneWidget);
      expect(find.byType(ArtistBanner), findsNothing);
      expect(find.text('Bandname'), findsOneWidget);
      // A hero that overflowed or divided by a null height would have thrown by now.
      expect(tester.takeException(), isNull);
    });

    testWidgets('an artist with banner art gets the banner, not the mesh', (
      tester,
    ) async {
      await pump(
        tester,
        const ArtistHeader(
          artist: ArtistDetail(
            id: 'ar-1',
            name: 'Bandname',
            albums: [],
            topTracks: [],
            // A Hub image reference: `artHashOf` only recognises a 64-hex content address.
            bannerUrl:
                'https://hub.example/v1/images/'
                'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
                'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          ),
        ),
      );

      expect(find.byType(ArtistBanner), findsOneWidget);
      expect(find.byType(AccentBanner), findsNothing);
    });

    testWidgets('the hero holds the web\'s minimum height', (tester) async {
      await pump(
        tester,
        const ArtistHeader(
          artist: ArtistDetail(
            id: 'ar-1',
            name: 'A',
            albums: [],
            topTracks: [],
          ),
        ),
      );

      // `min-h-80`. A one-word artist with no bio still gets a hero, not a strip.
      expect(
        tester.getSize(find.byType(HeroSurface)).height,
        greaterThanOrEqualTo(320),
      );
    });
  });

  group('shelves', () {
    testWidgets('a rail with more items than it shows offers "See all"', (
      tester,
    ) async {
      var tapped = false;
      final albums = [for (var i = 0; i < 15; i++) album('a$i')];

      await pump(
        tester,
        Column(
          children: [
            SectionHeader(title: 'Discography', onSeeAll: () => tapped = true),
            AlbumShelf(albums: albums, limit: catalogShelfPreview),
          ],
        ),
      );

      // The shelf offers its preview and no more; the rest are reached through the heading's
      // link, which is why that link is not gated on a count. Asserted on the shelf's SLOT count
      // rather than on built cards — the strip is lazy, so what a phone has actually built is a
      // fact about the viewport, not about the shelf.
      expect(
        tester.widget<CatalogShelf>(find.byType(CatalogShelf)).itemCount,
        catalogShelfPreview,
      );
      final seeAll = find.text(translations(CommonKeys.actionsSeeAll));
      expect(seeAll, findsOneWidget);
      await tester.tap(seeAll);
      await tester.pump();
      expect(tapped, isTrue);
    });

    testWidgets('a shelf that fits still offers "See all"', (tester) async {
      await pump(
        tester,
        Column(
          children: [
            SectionHeader(title: 'Discography', onSeeAll: () {}),
            AlbumShelf(albums: [album('a')], limit: catalogShelfPreview),
          ],
        ),
      );

      // Unconditional, per `ArtistView.tsx`: a section with a page of its own always says so.
      // Gating it on the data left a phone showing two of five albums and no route to the rest.
      expect(find.text(translations(CommonKeys.actionsSeeAll)), findsOneWidget);
    });

    testWidgets('a leading card takes a slot rather than adding one', (
      tester,
    ) async {
      final albums = [for (var i = 0; i < 15; i++) album('a$i')];

      await pump(
        tester,
        AlbumShelf(
          albums: albums,
          limit: catalogShelfPreview,
          leading: const SizedBox.shrink(),
        ),
      );

      // Still the preview's worth of slots, one of which is now the leading card — a leading cell
      // takes the first slot rather than adding an eleventh (`CardShelf.tsx`).
      expect(
        tester.widget<CatalogShelf>(find.byType(CatalogShelf)).itemCount,
        catalogShelfPreview,
      );
    });

    testWidgets('every card is one card wide, whatever it holds', (
      tester,
    ) async {
      await pump(tester, AlbumShelf(albums: [album('a'), album('b')]));

      for (final card in find.byType(AlbumCard).evaluate()) {
        expect(tester.getSize(find.byWidget(card.widget)).width, 160);
      }
    });
  });
}
