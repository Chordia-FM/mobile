import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chordia_api/chordia_api.dart';
import 'package:chordia_mobile/app/providers.dart';
import 'package:chordia_mobile/app/theme.dart';
import 'package:chordia_mobile/data/art/art_cache.dart';
import 'package:chordia_mobile/data/hub.dart';
import 'package:chordia_mobile/features/home/data/daypart.dart';
import 'package:chordia_mobile/features/home/data/home_feed.dart';
import 'package:chordia_mobile/features/home/data/hub_cache.dart';
import 'package:chordia_mobile/features/home/data/see_all.dart';
import 'package:chordia_mobile/features/home/home_screen.dart';
import 'package:chordia_mobile/features/home/widgets/cards.dart';
import 'package:chordia_mobile/i18n/keys.g.dart';
import 'package:chordia_mobile/i18n/translations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Loaded once, in real async: `testWidgets` runs inside a fake-async zone where an asset read
/// never completes, so the catalogs have to be in hand before the first pump.
late Translations translations;

final hub = Hub(
  id: 'hub-1',
  url: Uri.parse('https://hub.example'),
  name: 'Hub',
  addedAt: 0,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory artDirectory;

  setUpAll(() async {
    translations = await Translations.load('en', bundle: rootBundle);
  });

  setUp(() async {
    artDirectory = await Directory.systemTemp.createTemp('chordia_home_art');
  });

  tearDown(() async {
    if (await artDirectory.exists()) await artDirectory.delete(recursive: true);
  });

  group('rail composition', () {
    test('rails render in a fixed order', () {
      final feed = HomeFeed(
        pins: [pin()],
        recent: [recentAlbum()],
        mixes: [mix()],
        recentlyAdded: [album('a')],
        recommended: [album('b')],
        trendingTracks: [track('t')],
        trendingAlbums: [album('c')],
        trendingArtists: [artist('x')],
        friends: [friend()],
      );

      // Personal, then new, then suggested, then global, then social. Asserted as a whole list
      // rather than pairwise, so inserting a rail in the wrong place fails here and not in review.
      expect(feed.rails, [
        HomeRail.quickAccess,
        HomeRail.madeForYou,
        HomeRail.recentlyAdded,
        HomeRail.recommended,
        HomeRail.trendingTracks,
        HomeRail.trendingAlbums,
        HomeRail.trendingArtists,
        HomeRail.friendsListening,
      ]);
    });

    test('recent listening is the hero, not a rail', () {
      // Where the web puts it, and why the web has no "Jump back in" shelf below the hero either.
      // Listing it in both places is what demoted this page's focal point to an ordinary row.
      final feed = HomeFeed(recent: [recentAlbum()], libraries: [library()]);

      expect(feed.rails, isEmpty);
      // Still a page worth painting, so the cache paints it and no empty state claims otherwise.
      expect(feed.isEmpty, isFalse);
      expect(feed.needsLibrary, isFalse);
    });

    test('the onboarding hero waits for silence from every rail, not just one', () {
      // Each rail is fetched independently and a failed one falls back to the cache, so the
      // directory call alone timing out must not hang a "pair a library" card over a page of music.
      expect(const HomeFeed().needsLibrary, isTrue);
      expect(HomeFeed(libraries: [library()]).needsLibrary, isFalse);
      expect(HomeFeed(mixes: [mix()]).needsLibrary, isFalse);
      expect(HomeFeed(recent: [recentAlbum()]).needsLibrary, isFalse);
    });

    test('a rail with nothing in it is dropped, not left blank', () {
      final feed = HomeFeed(mixes: [mix()], trendingAlbums: [album('c')]);

      expect(feed.rails, [HomeRail.madeForYou, HomeRail.trendingAlbums]);
      expect(feed.isEmpty, isFalse);
      expect(const HomeFeed().isEmpty, isTrue);
    });

    testWidgets('the screen shows exactly the rails that have content', (
      tester,
    ) async {
      // Tall enough that every rail is built; a sliver list only builds what a viewport reaches,
      // and an assertion about ordering has to see all of them.
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final source = FakeHomeSource(
        pinsValue: [pin()],
        mixesValue: [mix()],
        trendingValue: Trending(
          albums: [album('c')],
          artists: const [],
          tracks: const [],
        ),
      );

      await tester.pumpWidget(
        _app(
          source: source,
          cache: MemoryHubCache(),
          artDirectory: artDirectory,
        ),
      );
      await tester.pump();

      final headings = tester
          .widgetList<Text>(find.byType(Text))
          .map((text) => text.data)
          .where(_railTitles.contains)
          .toList();

      expect(headings, [
        translations(DiscoveryKeys.quickAccessTitle),
        translations(DiscoveryKeys.madeForYouTitle),
        translations(DiscoveryKeys.shelfTrendingAlbums),
      ]);
      // The rails with no data are absent entirely — no heading over an empty row.
      expect(
        find.text(translations(DiscoveryKeys.shelfRecentlyAdded)),
        findsNothing,
      );
      expect(
        find.text(translations(DiscoveryKeys.shelfFriendsListening)),
        findsNothing,
      );
    });

    testWidgets('every card on the shelves carries its menu', (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _app(
          source: FakeHomeSource(
            pinsValue: [pin(), radioPin()],
            mixesValue: [mix()],
            trendingValue: Trending(
              albums: const [],
              artists: const [],
              tracks: [track('t')],
            ),
          ),
          cache: MemoryHubCache(),
          artDirectory: artDirectory,
        ),
      );
      await tester.pump();

      // The web wraps every card it renders in a context menu
      // (`components/discovery/cards.tsx`), so a card without one simply answers less on the phone
      // than the same card on the desktop. The pins are the sharpest case: this shelf is the only
      // place the phone shows a pin, so a pill with no menu makes unpinning unreachable.
      final menus = <Object?>[
        ...tester
            .widgetList<EntityCard>(find.byType(EntityCard))
            .map((card) => card.menu),
        ...tester
            .widgetList<PinPill>(find.byType(PinPill))
            .map((pill) => pill.menu),
      ];

      expect(find.byType(PinPill), findsNWidgets(2));
      expect(find.byType(EntityCard), findsWidgets);
      expect(menus, everyElement(isNotNull));
    });
  });

  group('the hero', () {
    Future<void> pump(WidgetTester tester, FakeHomeSource source) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _app(
          source: source,
          cache: MemoryHubCache(),
          artDirectory: artDirectory,
        ),
      );
      await tester.pump();
    }

    testWidgets('a fresh account is offered the pairing flow, not a shrug', (
      tester,
    ) async {
      // What this page used to do with nothing on it was print one sentence with nothing to press.
      // The web hands the same person a card straight into `/library/setup`.
      await pump(tester, FakeHomeSource());

      expect(find.text(translations(DiscoveryKeys.heroOnboardTitle)), findsOne);
      expect(find.text(translations(DiscoveryKeys.heroOnboardCta)), findsOne);
    });

    testWidgets('a paired account with no history is offered its top mix', (
      tester,
    ) async {
      await pump(
        tester,
        FakeHomeSource(librariesValue: [library()], mixesValue: [mix()]),
      );

      expect(find.text(translations(DiscoveryKeys.heroStartTitle)), findsOne);
      expect(find.text('Daily Mix 1'), findsWidgets);
      expect(
        find.text(translations(DiscoveryKeys.heroOnboardTitle)),
        findsNothing,
      );
    });

    testWidgets('listening history is the focal point, not one more shelf', (
      tester,
    ) async {
      await pump(
        tester,
        FakeHomeSource(
          librariesValue: [library()],
          recentValue: [recentAlbum()],
        ),
      );

      expect(find.text(translations(DiscoveryKeys.heroResumeTitle)), findsOne);
      expect(find.text('Heard it'), findsOne);
      // And NOT also a rail underneath: the web says so at the top of `HomeHero.tsx` — "There is
      // deliberately no separate 'Jump back in' rail downstream".
      expect(
        find.text(translations(DiscoveryKeys.shelfJumpBackIn)),
        findsNothing,
      );
    });
  });

  group('"See all"', () {
    test('the pages ask for more than the shelves they came from', () async {
      // The rail is capped at what a thumb can reach; the page behind "See all" is not. Asserting
      // the ASK rather than the answer is the point — a page that renders twelve items because it
      // requested twelve looks identical to one that requested fifty and got twelve.
      final source = FakeHomeSource();
      final container = ProviderContainer(
        overrides: [
          activeHubProvider.overrideWithValue(hub),
          homeSourceProvider.overrideWithValue(source),
          hubCacheProvider.overrideWithValue(MemoryHubCache()),
        ],
      );
      addTearDown(container.dispose);
      // Listened to before being awaited: both are auto-disposed, and a bare read of `.future`
      // tears the provider down before the request it started has answered.
      container
        ..listen(jumpBackInPageProvider, (_, _) {})
        ..listen(madeForYouPageProvider, (_, _) {});

      await container.read(jumpBackInPageProvider.future);
      await container.read(madeForYouPageProvider.future);

      expect(source.asked['jumpBackIn'], jumpBackInPageLength);
      expect(source.asked['dailyMixes'], madeForYouPageLength);
      expect(
        jumpBackInPageLength,
        greaterThan(HubHomeSource.railLengthDefault),
      );
    });
  });

  group('the greeting', () {
    test('changes at the hours the web client changes at', () {
      // Same boundaries as `frontend/src/lib/discovery/daypart.ts`, so the two clients greet the
      // same person the same way at the same minute.
      DateTime at(int hour) => DateTime(2026, 8, 22, hour);

      expect(Daypart.at(at(0)), Daypart.night);
      expect(Daypart.at(at(4)), Daypart.night);
      expect(Daypart.at(at(5)), Daypart.morning);
      expect(Daypart.at(at(11)), Daypart.morning);
      expect(Daypart.at(at(12)), Daypart.afternoon);
      expect(Daypart.at(at(17)), Daypart.afternoon);
      expect(Daypart.at(at(18)), Daypart.evening);
      expect(Daypart.at(at(23)), Daypart.evening);
    });
  });

  group('stale-while-revalidate', () {
    test('cached rails paint before the Hub answers, then are replaced', () async {
      final cache = MemoryHubCache()
        ..seed('home/hub-1/recommended', [album('cached').toJson()]);
      final pending = Completer<List<BrowseAlbum>>();
      final source = FakeHomeSource(recommended: () => pending.future);

      final container = ProviderContainer(
        overrides: [
          activeHubProvider.overrideWithValue(hub),
          homeSourceProvider.overrideWithValue(source),
          hubCacheProvider.overrideWithValue(cache),
        ],
      );
      addTearDown(container.dispose);
      container.listen(homeFeedProvider, (_, _) {});

      await pumpEventQueue();

      // The cached body is on screen while the request that will replace it is still in flight —
      // which is the entire point of the cache on a cold start.
      final cached = container.read(homeFeedProvider);
      expect(cached.feed?.recommended.single.id, 'cached');
      expect(cached.isLoading, isTrue);

      pending.complete([album('fresh')]);
      await pumpEventQueue();

      final refreshed = container.read(homeFeedProvider);
      expect(refreshed.feed?.recommended.single.id, 'fresh');
      expect(refreshed.isLoading, isFalse);
      // And the answer was written back, so the next cold start paints the newer one.
      expect(await cache.read('home/hub-1/recommended'), isNotNull);
    });

    test('a rail that fails keeps what the cache held', () async {
      final cache = MemoryHubCache()
        ..seed('home/hub-1/recommended', [album('cached').toJson()]);
      final source = FakeHomeSource(
        recommended: () => Future.error(_offline),
        mixesValue: [mix()],
      );

      final container = ProviderContainer(
        overrides: [
          activeHubProvider.overrideWithValue(hub),
          homeSourceProvider.overrideWithValue(source),
          hubCacheProvider.overrideWithValue(cache),
        ],
      );
      addTearDown(container.dispose);
      container.listen(homeFeedProvider, (_, _) {});
      await pumpEventQueue();

      final state = container.read(homeFeedProvider);
      // One endpoint failing costs its own rail nothing and the others nothing at all.
      expect(state.feed?.recommended.single.id, 'cached');
      expect(state.feed?.mixes, hasLength(1));
      expect(state.error, isNull);
    });

    test(
      'with nothing cached and nothing answering, the failure is shown',
      () async {
        final source = FakeHomeSource.failing(_offline);
        final container = ProviderContainer(
          overrides: [
            activeHubProvider.overrideWithValue(hub),
            homeSourceProvider.overrideWithValue(source),
            hubCacheProvider.overrideWithValue(MemoryHubCache()),
          ],
        );
        addTearDown(container.dispose);
        container.listen(homeFeedProvider, (_, _) {});
        await pumpEventQueue();

        final state = container.read(homeFeedProvider);
        expect(state.feed, isNull);
        expect(state.error, same(_offline));
      },
    );
  });
}

const _offline = ApiException(
  status: 0,
  title: 'Could not reach the server.',
  method: 'GET',
  path: '/v1/discovery/recommended-albums',
);

/// The rail headings, so the ordering assertion can pick them out of every other string on screen.
final _railTitles = {
  translations(DiscoveryKeys.quickAccessTitle),
  translations(DiscoveryKeys.shelfJumpBackIn),
  translations(DiscoveryKeys.madeForYouTitle),
  translations(DiscoveryKeys.shelfRecentlyAdded),
  translations(DiscoveryKeys.shelfRecommended),
  translations(DiscoveryKeys.shelfTrendingTracks),
  translations(DiscoveryKeys.shelfTrendingAlbums),
  translations(DiscoveryKeys.shelfTrendingArtists),
  translations(DiscoveryKeys.shelfFriendsListening),
};

Widget _app({
  required HomeSource source,
  required HubCache cache,
  required Directory artDirectory,
}) => ProviderScope(
  overrides: [
    translationsProvider.overrideWithValue(translations),
    activeHubProvider.overrideWithValue(hub),
    homeSourceProvider.overrideWithValue(source),
    hubCacheProvider.overrideWithValue(cache),
    // The real one resolves a platform directory, which no test binding provides.
    artCacheProvider.overrideWithValue(
      ArtCache(
        directory: Future.value(artDirectory),
        fetch: (sha, width) => throw ArtMissingException(sha),
      ),
    ),
  ],
  child: MaterialApp(theme: buildChordiaTheme(), home: const HomeScreen()),
);

/// A [HubCache] with no database behind it.
class MemoryHubCache implements HubCache {
  final _entries = <String, String>{};

  void seed(String key, Object? json) => _entries[key] = jsonEncode(json);

  @override
  Future<CachedJson?> read(String key) async {
    final held = _entries[key];
    return held == null ? null : CachedJson(jsonDecode(held), isStale: false);
  }

  @override
  Future<void> write(
    String key,
    Object? json, {
    required Duration freshFor,
  }) async => _entries[key] = jsonEncode(json);
}

class FakeHomeSource implements HomeSource {
  FakeHomeSource({
    this.pinsValue = const [],
    this.recentValue = const [],
    this.mixesValue = const [],
    this.librariesValue = const [],
    this.recentlyAddedValue = const [],
    this.friendsValue = const [],
    this.trendingValue = const Trending(albums: [], artists: [], tracks: []),
    this.recommended,
    this.failure,
  });

  /// Every endpoint answering with the same failure — a Hub that is simply unreachable.
  FakeHomeSource.failing(Object error) : this(failure: error);

  final List<PinnedItem> pinsValue;
  final List<RecentItem> recentValue;
  final List<DailyMix> mixesValue;
  final List<LibrarySummary> librariesValue;
  final List<BrowseAlbum> recentlyAddedValue;
  final List<FriendNowPlaying> friendsValue;
  final Trending trendingValue;

  /// Supplied as a thunk so a test can hand over a future that has not settled yet.
  final Future<List<BrowseAlbum>> Function()? recommended;

  final Object? failure;

  /// Built per call, never in the constructor: a `Future.error` nobody is listening to yet is
  /// reported as an unhandled exception, which would fail the test for the wrong reason.
  Future<T> _answer<T>(T value) =>
      failure == null ? Future.value(value) : Future.error(failure!);

  @override
  Future<List<PinnedItem>> pins() => _answer(pinsValue);

  /// [limit] is recorded rather than applied: what these pages ASK for is the assertion — the
  /// shelf's twelve against the "See all" page's fifty — and truncating here would let the page
  /// look right while requesting the shelf's length.
  final asked = <String, int?>{};

  @override
  Future<List<RecentItem>> jumpBackIn({int? limit}) {
    asked['jumpBackIn'] = limit;
    return _answer(recentValue);
  }

  @override
  Future<List<DailyMix>> dailyMixes({int? limit}) {
    asked['dailyMixes'] = limit;
    return _answer(mixesValue);
  }

  @override
  Future<List<LibrarySummary>> libraries() => _answer(librariesValue);

  @override
  Future<List<BrowseAlbum>> recentlyAdded() => _answer(recentlyAddedValue);

  @override
  Future<List<BrowseAlbum>> recommendedAlbums() =>
      recommended == null ? _answer(const <BrowseAlbum>[]) : recommended!();

  @override
  Future<Trending> trending() => _answer(trendingValue);

  @override
  Future<List<FriendNowPlaying>> friendsNowPlaying() => _answer(friendsValue);
}

BrowseAlbum album(String id) =>
    BrowseAlbum(artist: 'Artist', id: id, title: 'Album $id', trackCount: 9);

BrowseArtist artist(String id) =>
    BrowseArtist(albumCount: 2, id: id, name: 'Artist $id', trackCount: 20);

BrowseTrack track(String id) => BrowseTrack(
  artist: 'Artist',
  contentHash: 'hash-$id',
  durationMs: 180000,
  id: id,
  libraryId: 'library',
  title: 'Track $id',
  trackRef: 'ref-$id',
);

DailyMix mix() => const DailyMix(
  seedArtistId: 'seed',
  subtitle: 'Artist and more',
  title: 'Daily Mix 1',
);

PinnedItem pin() =>
    const PinnedItem(id: 'pinned', kind: PinKind.album, name: 'Pinned album');

/// The one pin kind with no entity page behind it, and the one whose menu is the phone's own.
PinnedItem radioPin() =>
    const PinnedItem(id: 'seed', kind: PinKind.radio, name: 'Artist Radio');

LibrarySummary library() => const LibrarySummary(
  createdAt: 0,
  id: 'lib-1',
  name: 'The shelf',
  ownerId: 'kanin-id',
  serverId: 'srv-1',
  trackCount: 900,
);

RecentItem recentAlbum() =>
    const RecentItem(id: 'recent', kind: RecentKind.album, name: 'Heard it');

FriendNowPlaying friend() => const FriendNowPlaying(
  artist: 'Artist',
  displayName: 'Dee',
  handle: 'dee',
  startedAt: 0,
  title: 'Song',
  userId: 'user',
);
