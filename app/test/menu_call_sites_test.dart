import 'package:chordia_api/chordia_api.dart';
import 'package:chordia_mobile/app/providers.dart'
    show activeHubProvider, hubClientProvider;
import 'package:chordia_mobile/features/catalog/data/catalog_api.dart';
import 'package:chordia_mobile/features/catalog/widgets/entity_menu.dart';
import 'package:chordia_mobile/features/downloads/data/downloads_providers.dart';
import 'package:chordia_mobile/features/home/widgets/cards.dart';
import 'package:chordia_mobile/features/insights/widgets/insights_primitives.dart';
import 'package:chordia_mobile/features/library/playlists_screen.dart';
import 'package:chordia_mobile/features/search/widgets/result_row.dart';
import 'package:chordia_mobile/i18n/keys.g.dart';
import 'package:chordia_mobile/i18n/translations.dart';
import 'package:chordia_mobile/i18n/translations_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Whether the rows that HAVE a menu actually raise it.
///
/// `menus_test.dart` asks what each menu offers, and every one of them passed while half the app's
/// rows had no way to open one: the builders were complete and the call sites were missing. That is
/// a gap no assertion about action ids can see, so these are long presses on the real widgets —
/// remove a wrapper and the sheet never appears, which is exactly the regression that happened.
///
/// "Share" is the marker asserted on throughout: every menu here has it, no row shows it, and it is
/// one string rather than a count that shifts whenever a section gains a row.
late Translations translations;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late String share;

  setUpAll(() async {
    translations = await Translations.load('en', bundle: rootBundle);
    share = translations(CommonKeys.actionsShare);
  });

  /// Pumps one widget under a scope with no hub — the Hub-backed rows then draw disabled rather
  /// than throwing, which is enough for "did a sheet open at all".
  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          translationsProvider.overrideWithValue(translations),
          activeHubProvider.overrideWithValue(null),
          hubClientProvider.overrideWithValue(null),
          catalogApiProvider.overrideWithValue(_FakeCatalog()),
          // A track menu draws its download row as it opens, and the real one wants a database,
          // a storage budget and a foreground service to answer "is this already held".
          downloadedTrackIdsProvider.overrideWith(
            (ref) => Stream.value(<String>{}),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(body: Center(child: child)),
        ),
      ),
    );
    await tester.pump();
  }

  /// Long-presses [target] and gives the sheet its entrance animation.
  Future<void> longPress(WidgetTester tester, Finder target) async {
    await tester.longPress(target);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('a playlist row in the Library tab raises the playlist menu', (
    tester,
  ) async {
    await pump(
      tester,
      const PlaylistRow(
        playlist: Playlist(
          createdAt: 0,
          id: 'pl-1',
          name: 'Late Night',
          trackCount: 12,
        ),
      ),
    );

    await longPress(tester, find.text('Late Night'));

    expect(find.text(share), findsOneWidget);
    // The playlist's own menu, not a neighbouring kind's: only it offers the whole list offline.
    expect(
      find.text(translations(LibraryKeys.downloadsActionDownloadPlaylist)),
      findsOneWidget,
    );
  });

  testWidgets('a smart playlist row offers more than its rule builder', (
    tester,
  ) async {
    await pump(
      tester,
      const SmartPlaylistRow(
        playlist: SmartPlaylist(
          createdAt: 0,
          id: 'sp-1',
          name: 'Fresh Finds',
          rules: SmartRules(),
        ),
      ),
    );

    await longPress(tester, find.text('Fresh Finds'));

    // The long press used to open the rule builder directly, so these five were unreachable from
    // the Library tab: a smart playlist plays, queues, pins, downloads and shares like any other.
    expect(find.text(share), findsOneWidget);
    expect(find.text(translations(CommonKeys.actionsPlay)), findsOneWidget);
    expect(
      find.text(translations(PlaylistsKeys.smartEditTitle)),
      findsOneWidget,
    );
  });

  testWidgets('a search result raises the menu its group gave it', (
    tester,
  ) async {
    await pump(
      tester,
      ResultRow(
        title: 'Ambient',
        onTap: () {},
        menu: (page, ref) =>
            genreMenu(page, ref, slug: 'ambient', name: 'Ambient'),
      ),
    );

    await longPress(tester, find.text('Ambient'));
    expect(find.text(share), findsOneWidget);
  });

  testWidgets('a search result with no menu swallows the long press', (
    tester,
  ) async {
    // The "Unlabeled" bucket is the real case: it has no id, so every row a menu could offer leads
    // to a page that does not exist. A row that opens an empty sheet instead would be worse than
    // one that does nothing.
    await pump(tester, ResultRow(title: 'Unlabeled', onTap: () {}));

    await longPress(tester, find.text('Unlabeled'));
    expect(find.text(share), findsNothing);
  });

  testWidgets('a home rail card carries the menu for its own kind', (
    tester,
  ) async {
    await pump(
      tester,
      const RecentCard(
        item: RecentItem(id: 'al-1', kind: RecentKind.album, name: 'Blonde'),
      ),
    );

    await longPress(tester, find.text('Blonde'));

    expect(find.text(share), findsOneWidget);
    // The ALBUM branch of the card's kind switch, not the artist one beside it: an artist menu
    // has no "Add to playlist", so this would fail if the switch fell through to the wrong arm.
    expect(
      find.text(translations(PlaylistsKeys.addToPlaylist)),
      findsOneWidget,
    );
  });

  testWidgets('a ranked insights row raises the menu for the kind it ranks', (
    tester,
  ) async {
    await pump(
      tester,
      const TopList(
        kind: EntityKind.artist,
        items: [
          TopItem(id: 'ar-1', msPlayed: 1000, name: 'Steve Lacy', plays: 4),
        ],
      ),
    );

    await longPress(tester, find.text('Steve Lacy'));
    expect(find.text(share), findsOneWidget);
  });

  testWidgets('a ranked track row fetches the catalog row before it opens', (
    tester,
  ) async {
    // The one path here that is not a plain wrapper: a chart row carries a name and a play count,
    // and a track menu needs the library and the ref its stream URL is built from. If the fetch
    // were dropped in favour of a fabricated row, Play and Download would be rows that do nothing.
    await pump(
      tester,
      const TopList(
        kind: EntityKind.track,
        items: [TopItem(id: 't1', msPlayed: 1000, name: 'Bad Habit', plays: 9)],
      ),
    );

    await longPress(tester, find.text('Bad Habit'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text(share), findsOneWidget);
    // Straight from the fetched row: the chart item never knew this track had an album.
    expect(
      find.text(translations(CommonKeys.actionsGoToAlbum)),
      findsOneWidget,
    );
  });

  testWidgets('a ranked genre row has no menu to raise', (tester) async {
    // A genre in a chart keys off a hash of its name that the catalog has never heard of, so there
    // is nothing for a menu to act on. The web's `EntityKindMenu` mounts no leaf for these either.
    //
    // Asserted on the absent wrapper rather than by long-pressing: a genre row's tap navigates,
    // and a long press that finds no long-press recognizer falls through to it.
    await pump(
      tester,
      const TopList.genres(
        items: [TopItem(id: 'g1', msPlayed: 1000, name: 'ambient', plays: 3)],
      ),
    );

    expect(find.text('Ambient'), findsOneWidget);
    expect(find.byType(EntityMenuGesture), findsNothing);
  });

  group('a playlist reaches its own figures only when a host can show them', () {
    testWidgets('the row is absent without one', (tester) async {
      final menu = await _buildMenu(
        tester,
        (page, ref) =>
            playlistMenu(page, ref, const PlaylistLike(id: 'pl-1', name: 'X')),
      );
      // A playlist is not an `EntityKind`, so `/v1/insights/entity` cannot answer for one: the
      // figures come from the playlist's own endpoint and the host renders them.
      expect(menu.has('stats'), isFalse);
    });

    testWidgets('and present with one', (tester) async {
      final menu = await _buildMenu(
        tester,
        (page, ref) => playlistMenu(
          page,
          ref,
          const PlaylistLike(id: 'pl-1', name: 'X'),
          onStats: () {},
        ),
      );
      expect(menu.has('stats'), isTrue);
    });
  });
}

Future<EntityMenu> _buildMenu(
  WidgetTester tester,
  EntityMenuBuilder builder,
) async {
  late EntityMenu menu;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        translationsProvider.overrideWithValue(translations),
        activeHubProvider.overrideWithValue(null),
        hubClientProvider.overrideWithValue(null),
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

/// Answers the one call a chart row makes, and refuses the rest loudly.
class _FakeCatalog implements CatalogApi {
  @override
  Future<BrowseTrack> track(String trackId) async => BrowseTrack(
    id: trackId,
    title: 'Bad Habit',
    artist: 'Steve Lacy',
    contentHash: 'hash-$trackId',
    durationMs: 218000,
    libraryId: 'lib-1',
    trackRef: 'ref-$trackId',
    albumId: 'al-1',
    artistId: 'ar-1',
  );

  @override
  Never noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}
