import 'package:chordia_api/chordia_api.dart';
import 'package:chordia_mobile/app/theme.dart';
import 'package:chordia_mobile/features/catalog/artist_screen.dart';
import 'package:chordia_mobile/features/catalog/data/catalog_providers.dart';
import 'package:chordia_mobile/features/catalog/data/playback.dart';
import 'package:chordia_mobile/features/catalog/live_album_screen.dart';
import 'package:chordia_mobile/features/catalog/widgets/album_grid.dart';
import 'package:chordia_mobile/i18n/keys.g.dart';
import 'package:chordia_mobile/i18n/translations.dart';
import 'package:chordia_mobile/i18n/translations_provider.dart';
import 'package:chordia_sync/chordia_sync.dart' show PlayerTrack, PlayContext;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

/// The artist's live collection: the shelf card that reaches it, and the page behind it.
///
/// The route `artists/:artistId/live` and the Hub's `live-album` endpoint both already existed;
/// what was missing was any way to ask for either from a phone. So these assertions press what a
/// person would press rather than testing the endpoint again.
late Translations translations;

/// The player, recording what it was told rather than making a sound.
class _RecordingPlayer implements CatalogPlayerActions {
  List<PlayerTrack>? queue;
  PlayContext? context;

  @override
  void playQueue(
    List<PlayerTrack> tracks, {
    int startIndex = 0,
    PlayContext? context,
  }) {
    queue = tracks;
    this.context = context;
  }

  @override
  void enqueue(PlayerTrack track) {}

  @override
  void playNext(PlayerTrack track) {}

  @override
  void setShuffle(bool shuffle) {}
}

BrowseTrack _track(String id, String title) => BrowseTrack(
  id: id,
  title: title,
  artist: 'Portishead',
  contentHash: 'hash-$id',
  durationMs: 240000,
  libraryId: 'lib-1',
  trackRef: 'ref-$id',
);

BrowseAlbum _album(String id, String title, {String? versionType}) =>
    BrowseAlbum(
      artist: 'Portishead',
      id: id,
      title: title,
      trackCount: 10,
      versionType: versionType,
    );

ArtistDetail _artist({
  int? liveTrackCount,
  List<BrowseAlbum> albums = const [],
}) => ArtistDetail(
  albums: albums,
  id: 'ar-1',
  name: 'Portishead',
  topTracks: [_track('t1', 'Roads')],
  liveTrackCount: liveTrackCount,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    translations = await Translations.load('en', bundle: rootBundle);
  });

  Future<void> pumpArtist(WidgetTester tester, ArtistDetail artist) async {
    // Tall enough that every shelf is built: a sliver list only builds what a viewport reaches,
    // and the Live shelf sits well below the fold on a phone.
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          translationsProvider.overrideWithValue(translations),
          artistDetailProvider('ar-1').overrideWith((ref) async => artist),
          similarArtistsProvider(
            'ar-1',
          ).overrideWith((ref) async => const <BrowseArtist>[]),
        ],
        child: MaterialApp(
          theme: buildChordiaTheme(),
          home: const ArtistScreen(artistId: 'ar-1'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
  }

  group('the Live shelf on an artist', () {
    testWidgets('leads with the collection card when there is live material', (
      tester,
    ) async {
      await pumpArtist(tester, _artist(liveTrackCount: 12));

      expect(
        find.text(translations(CatalogKeys.artistVersionsLive)),
        findsOne,
        reason: 'the shelf is headed, as the web heads it',
      );
      expect(find.byType(ArtistLiveCard), findsOne);
    });

    testWidgets('shows on live TRACKS alone, with no live release to shelve', (
      tester,
    ) async {
      // The case the count exists for: every live recording this artist owns is a bonus track on
      // an ordinary record, so nothing in the discography says the material is there at all.
      await pumpArtist(
        tester,
        _artist(liveTrackCount: 4, albums: [_album('al-1', 'Dummy')]),
      );

      expect(find.byType(ArtistLiveCard), findsOne);
      expect(find.byType(AlbumCard), findsOne, reason: 'the studio album');
    });

    testWidgets('stays away when the artist has no live material', (
      tester,
    ) async {
      await pumpArtist(tester, _artist(albums: [_album('al-1', 'Dummy')]));

      expect(find.byType(ArtistLiveCard), findsNothing);
      expect(
        find.text(translations(CatalogKeys.artistVersionsLive)),
        findsNothing,
      );
    });

    testWidgets('a live pressing leaves the main shelf for the Live one', (
      tester,
    ) async {
      // Sharing a title with the studio record is the whole reason for the split: side by side on
      // one shelf the pair reads as a duplicate.
      await pumpArtist(
        tester,
        _artist(
          albums: [
            _album('al-1', 'Dummy'),
            _album('al-2', 'Dummy', versionType: 'live'),
          ],
        ),
      );

      expect(find.text(translations(CatalogKeys.artistAlbums)), findsOne);
      expect(find.text(translations(CatalogKeys.artistVersionsLive)), findsOne);
      // Two cards, one under each heading — not two under the first.
      expect(find.byType(AlbumCard), findsNWidgets(2));
    });
  });

  group('the collection page', () {
    testWidgets('says what it is, and plays as one queue', (tester) async {
      final player = _RecordingPlayer();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            translationsProvider.overrideWithValue(translations),
            catalogPlayerActionsProvider.overrideWithValue(player),
            liveAlbumProvider('ar-1').overrideWith(
              (ref) async => LiveAlbum(
                artistId: 'ar-1',
                artistName: 'Portishead',
                sourceAlbumCount: 3,
                tracks: [_track('t1', 'Roads'), _track('t2', 'Glory Box')],
              ),
            ),
          ],
          child: MaterialApp(
            theme: buildChordiaTheme(),
            home: const ArtistLiveScreen(artistId: 'ar-1'),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));

      // The title is composed on the client: the Hub has no way to say it in the reader's
      // language, so a heading that came back from the server would always be English.
      expect(
        find.text(
          translations(CatalogKeys.artistLiveAlbumTitle, {
            'name': 'Portishead',
          }),
        ),
        findsOne,
      );
      // "From 3 albums" — the fact that explains what this is, given no such album exists.
      expect(
        find.text(
          translations(CatalogKeys.artistLiveAlbumSubtitle, {'count': 3}),
        ),
        findsOne,
      );

      await tester.tap(
        find.byIcon(PhosphorIcons.play(PhosphorIconsStyle.fill)),
      );
      await tester.pump();

      expect(player.queue?.map((t) => t.id), ['t1', 't2']);
      // An artist context, not a radio one: the collection is finite, so "Playing from" leads back
      // to the artist rather than to a station that would try to continue.
      expect(player.context?.kind, 'artist');
    });
  });
}
