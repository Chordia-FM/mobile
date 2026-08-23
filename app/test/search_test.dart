import 'package:chordia_api/chordia_api.dart';
import 'package:chordia_mobile/app/providers.dart';
import 'package:chordia_mobile/data/hub.dart';
import 'package:chordia_mobile/features/home/data/hub_cache.dart';
import 'package:chordia_mobile/features/search/data/recent_searches.dart';
import 'package:chordia_mobile/features/search/data/search_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'home_test.dart' show MemoryHubCache, album, artist, track;

final hub = Hub(
  id: 'hub-1',
  url: Uri.parse('https://hub.example'),
  name: 'Hub',
  addedAt: 0,
);

/// Past the debounce with room to spare, so a slow machine cannot turn a timing assertion into a
/// flake. Everything under test settles in microtasks once the timer has fired.
final _afterDebounce =
    CatalogSearchController.debounce + const Duration(milliseconds: 150);

void main() {
  group('debounce', () {
    test('a burst of keystrokes costs exactly one request', () async {
      final source = FakeSearchSource();
      final search = _controller(source);

      // Typing "radio", one character at a time, faster than anyone reads a result.
      for (final term in ['r', 'ra', 'rad', 'radi', 'radio']) {
        search.typed(term);
      }
      await Future<void>.delayed(_afterDebounce);

      // One request, and for the term that was actually left in the box.
      expect(source.queries, ['radio']);
    });

    test('a term too short to be worth asking about is never sent', () async {
      final source = FakeSearchSource();
      final search = _controller(source);

      search.typed('r');
      await Future<void>.delayed(_afterDebounce);

      expect(source.queries, isEmpty);
    });

    test('clearing the box drops the results that were on screen', () async {
      final source = FakeSearchSource(tracks: [track('t')]);
      final container = _container(source);
      final search = container.read(catalogSearchProvider.notifier);

      search.typed('radio');
      await Future<void>.delayed(_afterDebounce);
      expect(container.read(catalogSearchProvider).results, isNotNull);

      search.typed('');
      expect(container.read(catalogSearchProvider).results, isNull);
    });

    test(
      'a chosen term is searched at once, without waiting out the debounce',
      () async {
        final source = FakeSearchSource();
        final container = _container(source);

        await container.read(catalogSearchProvider.notifier).submit('radio');

        expect(source.queries, ['radio']);
      },
    );
  });

  group('results', () {
    test('groups keep their order and empty ones are dropped', () {
      final groups = SearchGroups(
        tracks: [track('t')],
        artists: [artist('a')],
        genres: const [
          GenreSummary(
            albumCount: 1,
            artistCount: 1,
            name: 'Jazz',
            slug: 'jazz',
          ),
        ],
      );

      expect(groups.groups, [
        SearchGroup.tracks,
        SearchGroup.artists,
        SearchGroup.genres,
      ]);
      expect(const SearchGroups().isEmpty, isTrue);
    });

    test('playlists and genres are matched on the device', () async {
      final source = FakeSearchSource(
        albums: [album('a')],
        playlistsValue: const [
          Playlist(createdAt: 0, id: 'p1', name: 'Radio hits', trackCount: 12),
          Playlist(createdAt: 0, id: 'p2', name: 'Dinner', trackCount: 4),
        ],
        genresValue: const [
          GenreSummary(
            albumCount: 1,
            artistCount: 1,
            name: 'Radio pop',
            slug: 'radio-pop',
          ),
          GenreSummary(
            albumCount: 1,
            artistCount: 1,
            name: 'Jazz',
            slug: 'jazz',
          ),
        ],
      );
      final container = _container(source);

      await container.read(catalogSearchProvider.notifier).submit('radio');

      final results = container.read(catalogSearchProvider).results!;
      expect(results.playlists.single.id, 'p1');
      expect(results.genres.single.slug, 'radio-pop');
      // The Hub answers the other four groups, so nothing was filtered locally there.
      expect(results.albums, hasLength(1));
      // Fetched once for the whole session, not once per keystroke.
      await container.read(catalogSearchProvider.notifier).submit('dinner');
      expect(source.playlistCalls, 1);
    });

    test('a search that fails is reported and can be retried', () async {
      final source = FakeSearchSource(failure: _offline);
      final container = _container(source);
      final search = container.read(catalogSearchProvider.notifier);

      await search.submit('radio');
      expect(container.read(catalogSearchProvider).error, same(_offline));

      source.failure = null;
      await search.retry();
      expect(container.read(catalogSearchProvider).error, isNull);
      expect(source.queries, ['radio', 'radio']);
    });
  });

  group('recent searches', () {
    test('a term is remembered once it has actually been searched', () async {
      final store = KvRecentSearches(MemoryScratch());
      final container = _container(FakeSearchSource(), store: store);

      await container.read(catalogSearchProvider.notifier).submit('radio');
      await pumpEventQueue();

      expect(await store.read(), ['radio']);
      expect(container.read(catalogSearchProvider).recent, ['radio']);
    });

    test(
      'the newest spelling wins and the list does not grow duplicates',
      () async {
        final store = KvRecentSearches(MemoryScratch());
        await store.remember('jazz');
        await store.remember('Radio');

        expect(await store.remember('radio'), ['radio', 'jazz']);
      },
    );

    test('the list is capped, oldest first', () async {
      final store = KvRecentSearches(MemoryScratch(), limit: 3);
      for (final term in ['one', 'two', 'three', 'four']) {
        await store.remember(term);
      }

      expect(await store.read(), ['four', 'three', 'two']);
    });

    test('clearing empties both the store and the screen', () async {
      final store = KvRecentSearches(MemoryScratch());
      await store.remember('radio');
      final container = _container(FakeSearchSource(), store: store);
      final search = container.read(catalogSearchProvider.notifier);
      await pumpEventQueue();
      expect(container.read(catalogSearchProvider).recent, ['radio']);

      await search.clearRecent();

      expect(await store.read(), isEmpty);
      expect(container.read(catalogSearchProvider).recent, isEmpty);
    });
  });
}

const _offline = ApiException(
  status: 0,
  title: 'Could not reach the server.',
  method: 'GET',
  path: '/v1/catalog/search',
);

ProviderContainer _container(
  FakeSearchSource source, {
  KvRecentSearches? store,
}) {
  final container = ProviderContainer(
    overrides: [
      activeHubProvider.overrideWithValue(hub),
      searchSourceProvider.overrideWithValue(source),
      recentSearchesProvider.overrideWithValue(
        store ?? KvRecentSearches(MemoryScratch()),
      ),
      hubCacheProvider.overrideWithValue(MemoryHubCache()),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

CatalogSearchController _controller(FakeSearchSource source) =>
    _container(source).read(catalogSearchProvider.notifier);

class FakeSearchSource implements SearchSource {
  FakeSearchSource({
    this.tracks = const [],
    this.albums = const [],
    this.artists = const [],
    this.playlistsValue = const [],
    this.genresValue = const [],
    this.failure,
  });

  final List<BrowseTrack> tracks;
  final List<BrowseAlbum> albums;
  final List<BrowseArtist> artists;
  final List<Playlist> playlistsValue;
  final List<GenreSummary> genresValue;

  /// Set to make [search] fail; cleared to let a retry succeed.
  Object? failure;

  /// Every term this source was actually asked about, in order — the debounce assertion.
  final queries = <String>[];

  int playlistCalls = 0;

  @override
  Future<SearchResults> search(String query) {
    queries.add(query);
    // Built at call time: a `Future.error` created before anyone listens is reported as an
    // unhandled exception and fails the test for the wrong reason.
    if (failure != null) return Future.error(failure!);
    return Future.value(
      SearchResults(albums: albums, artists: artists, tracks: tracks),
    );
  }

  @override
  Future<List<Playlist>> playlists() {
    playlistCalls++;
    return Future.value(playlistsValue);
  }

  @override
  Future<List<GenreSummary>> genres() => Future.value(genresValue);
}

/// The key/value table as a map, so the REAL [KvRecentSearches] is what every test here exercises
/// — a hand-written stand-in would only assert that the stand-in works.
class MemoryScratch implements ScratchStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> remove(String key) async => values.remove(key);
}
