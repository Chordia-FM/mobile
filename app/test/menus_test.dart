import 'package:chordia_api/chordia_api.dart';
import 'package:chordia_mobile/app/providers.dart'
    show activeHubProvider, hubClientProvider;
import 'package:chordia_mobile/features/catalog/widgets/entity_menu.dart';
import 'package:chordia_mobile/i18n/translations.dart';
import 'package:chordia_mobile/i18n/translations_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// What an entity's menu OFFERS, which is the one question this layer exists to answer.
///
/// Every builder returns a description and draws nothing, so these are plain assertions about
/// action ids rather than sheet-tapping widget tests. The failure they are here to catch is the one
/// the whole file was written against: a surface quietly offering fewer actions than the same
/// entity offers somewhere else.
late Translations translations;

BrowseTrack aTrack() => const BrowseTrack(
  id: 't1',
  title: 'Bad Habits',
  artist: 'Steve Lacy',
  contentHash: 'hash-t1',
  durationMs: 218000,
  libraryId: 'lib-1',
  trackRef: 'ref-t1',
  albumId: 'al-1',
  artistId: 'ar-1',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    translations = await Translations.load('en', bundle: rootBundle);
  });

  /// Builds one menu against a scope with no hub: every Hub-backed row is then disabled rather
  /// than absent, which is exactly the distinction these assertions care about.
  Future<EntityMenu> build(
    WidgetTester tester,
    EntityMenuBuilder builder, {
    Set<String>? hidden,
  }) async {
    late EntityMenu menu;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          translationsProvider.overrideWithValue(translations),
          activeHubProvider.overrideWithValue(null),
          hubClientProvider.overrideWithValue(null),
          if (hidden != null)
            hiddenTrackIdsProvider.overrideWith(() => _FakeHidden(hidden)),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                menu = builder(context, ref);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return menu;
  }

  group('a track', () {
    testWidgets('can be hidden from anywhere it is listed', (tester) async {
      final menu = await build(
        tester,
        (page, ref) => trackMenu(page, ref, aTrack()),
      );

      // The web puts Hide beside the heart in the collect group; the phone's ⋮ is the ONLY place
      // it can live, since the row has no width for an eye button.
      expect(menu.has('hide'), isTrue);
      expect(
        menu.sections
            .firstWhere((s) => s.id == 'collect')
            .items
            .map((a) => a.id),
        containsAllInOrder(['like', 'hide']),
      );
    });

    testWidgets('says unhide for a track already hidden', (tester) async {
      final menu = await build(
        tester,
        (page, ref) => trackMenu(page, ref, aTrack()),
        hidden: {'t1'},
      );

      final hide = menu.sections
          .expand((s) => s.items)
          .firstWhere((a) => a.id == 'hide');
      expect(hide.label, translations('library:hidden.unhide'));
    });

    testWidgets('carries reordering, removal and reporting in ONE menu', (
      tester,
    ) async {
      final menu = await build(
        tester,
        (page, ref) => trackMenu(
          page,
          ref,
          aTrack(),
          onPlay: () {},
          onMoveUp: () {},
          onMoveDown: () {},
          onRemove: () {},
          onReport: () {},
        ),
      );

      // A playlist row used to answer with a Material popup for these three and the real sheet for
      // everything else, so which actions you got depended on which control you pressed.
      expect(
        menu.actionIds,
        containsAll([
          'play',
          'play-next',
          'queue',
          'like',
          'hide',
          'move-up',
          'move-down',
          'report',
          'remove',
        ]),
      );
    });

    testWidgets('offers only what a host can honour', (tester) async {
      final menu = await build(
        tester,
        (page, ref) => trackMenu(page, ref, aTrack()),
      );

      expect(menu.has('move-up'), isFalse);
      expect(menu.has('remove'), isFalse);
      expect(menu.has('report'), isFalse);
    });
  });

  group('an album', () {
    AlbumDetail album({String? mbid}) => AlbumDetail(
      id: 'al-1',
      title: 'Gemini Rights',
      artist: 'Steve Lacy',
      artistId: 'ar-1',
      mbid: mbid,
      tracks: [aTrack()],
    );

    testWidgets('reaches its own listening stats from its page', (
      tester,
    ) async {
      final menu = await build(
        tester,
        (page, ref) => albumDetailMenu(page, ref, album()),
      );

      // `showEntityStats` had exactly one caller — a chart row — so an album's stats were
      // unreachable from the album.
      expect(menu.has('stats'), isTrue);
    });

    testWidgets('opens in Discover only when it knows its release group', (
      tester,
    ) async {
      final known = await build(
        tester,
        (page, ref) => albumDetailMenu(page, ref, album(mbid: 'rg-123')),
      );
      final unknown = await build(
        tester,
        (page, ref) => albumDetailMenu(page, ref, album()),
      );

      expect(known.has('open-in-discover'), isTrue);
      // No MBID means no precise destination, and the phone's Manager takes no search term.
      expect(unknown.has('open-in-discover'), isFalse);
    });

    testWidgets('a card carries the MBID its browse row was built from', (
      tester,
    ) async {
      final menu = await build(
        tester,
        (page, ref) => albumMenu(
          page,
          ref,
          const AlbumLike(id: 'al-1', title: 'Gemini Rights', mbid: 'rg-123'),
        ),
      );

      expect(menu.has('open-in-discover'), isTrue);
    });
  });

  group('an artist', () {
    testWidgets('page menu reaches stats and the Manager', (tester) async {
      final menu = await build(
        tester,
        (page, ref) => artistDetailMenu(
          page,
          ref,
          const ArtistDetail(
            id: 'ar-1',
            name: 'Steve Lacy',
            albums: [],
            topTracks: [],
            mbid: 'ar-mbid',
          ),
          onReport: () {},
        ),
      );

      expect(
        menu.actionIds,
        containsAll(['stats', 'open-in-discover', 'report']),
      );
    });
  });

  group('a playlist', () {
    const card = PlaylistLike(id: 'pl-1', name: 'Late Night');

    testWidgets('answers the same from its page as from a card, plus what only'
        ' the page can offer', (tester) async {
      final fromCard = await build(
        tester,
        (page, ref) => playlistMenu(page, ref, card),
      );
      final fromPage = await build(
        tester,
        (page, ref) => playlistMenu(
          page,
          ref,
          card,
          onEditDetails: () {},
          onEditCover: () {},
          onCollaborators: () {},
          onReorder: () {},
          onDelete: () {},
        ),
      );

      // The page's ⋮ used to open a wholly different sheet: edit / cover / collaborators / pin /
      // delete, with no queue, radio, download or share anywhere on the playlist's own page.
      expect(fromPage.actionIds, containsAll(fromCard.actionIds));
      expect(
        fromPage.actionIds,
        containsAll([
          'edit-details',
          'edit-cover',
          'collaborators',
          'reorder',
          'delete',
        ]),
      );
      expect(
        fromCard.actionIds,
        containsAll(['queue', 'radio', 'download', 'share']),
      );
    });

    testWidgets('offers leaving instead of deleting to a collaborator', (
      tester,
    ) async {
      final menu = await build(
        tester,
        (page, ref) => playlistMenu(page, ref, card, onLeave: () {}),
      );

      expect(menu.has('leave'), isTrue);
      expect(menu.has('delete'), isFalse);
    });
  });

  group('a smart playlist', () {
    testWidgets('downloads like any other playlist', (tester) async {
      final menu = await build(
        tester,
        (page, ref) => smartPlaylistMenu(
          page,
          ref,
          const PlaylistLike(id: 'sp-1', name: 'Rediscover'),
          onEdit: () {},
          onRefresh: () {},
          onDelete: () {},
        ),
      );

      // A smart playlist is not a lesser object: it plays, queues, pins, downloads and seeds a
      // station exactly like a hand-made one.
      expect(
        menu.actionIds,
        containsAll([
          'edit',
          'refresh',
          'play',
          'queue',
          'radio',
          'pin',
          'download',
          'share',
          'delete',
        ]),
      );
    });
  });

  group('a library', () {
    testWidgets('can be shared and reordered from its card', (tester) async {
      final menu = await build(
        tester,
        (page, ref) => libraryMenu(
          page,
          ref,
          libraryId: 'lib-1',
          name: 'Home NAS',
          onManage: () {},
          onShare: () {},
          onMoveUp: () {},
          onMoveDown: () {},
          onRemove: () {},
        ),
      );

      // Reordering was hover-only on the web, so touch had no route to it at all; the phone never
      // had one either.
      expect(
        menu.actionIds,
        containsAll([
          'open',
          'edit',
          'share',
          'share-with-friend',
          'move-up',
          'move-down',
          'remove',
        ]),
      );
    });
  });
}

/// A hidden set that is already loaded, so the row's label can be asserted without a Hub.
class _FakeHidden extends HiddenTracksController {
  _FakeHidden(this.ids);

  final Set<String> ids;

  @override
  Future<Set<String>> build() async => ids;
}
