import 'dart:async';

import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../home/data/hub_cache.dart';
import 'recent_searches.dart';

/// The reads the search screen makes.
///
/// [search] is the Hub's catalog search — tracks, albums, artists and labels. [playlists] and
/// [genres] are the caller's own small collections, matched on the device: the Hub has no search
/// over either, and fetching two short lists once beats adding two requests per keystroke.
abstract interface class SearchSource {
  Future<SearchResults> search(String query);

  Future<List<Playlist>> playlists();

  Future<List<GenreSummary>> genres();
}

class HubSearchSource implements SearchSource {
  const HubSearchSource(this._hub);

  final HubClient _hub;

  @override
  Future<SearchResults> search(String query) => _hub.searchCatalog(query);

  @override
  Future<List<Playlist>> playlists() => _hub.playlists();

  @override
  Future<List<GenreSummary>> genres() => _hub.genres();
}

/// The kinds a result set is grouped into, in the order they are shown.
enum SearchGroup { tracks, albums, artists, playlists, labels, genres }

/// One search's results.
@immutable
class SearchGroups {
  const SearchGroups({
    this.tracks = const [],
    this.albums = const [],
    this.artists = const [],
    this.playlists = const [],
    this.labels = const [],
    this.genres = const [],
  });

  final List<BrowseTrack> tracks;
  final List<BrowseAlbum> albums;
  final List<BrowseArtist> artists;
  final List<Playlist> playlists;
  final List<LabelSummary> labels;
  final List<GenreSummary> genres;

  int count(SearchGroup group) => switch (group) {
    SearchGroup.tracks => tracks.length,
    SearchGroup.albums => albums.length,
    SearchGroup.artists => artists.length,
    SearchGroup.playlists => playlists.length,
    SearchGroup.labels => labels.length,
    SearchGroup.genres => genres.length,
  };

  /// The groups with something in them, in [SearchGroup] order. A group that matched nothing is
  /// not rendered as an empty heading.
  List<SearchGroup> get groups =>
      SearchGroup.values.where((g) => count(g) > 0).toList(growable: false);

  bool get isEmpty => groups.isEmpty;
}

@immutable
class SearchState {
  const SearchState({
    this.term = '',
    this.results,
    this.isLoading = false,
    this.error,
    this.recent = const [],
  });

  /// The trimmed term the current results belong to — not what the field holds, which is the
  /// field's business and changes on every keystroke.
  final String term;

  /// Null until a term long enough to search has come back. Distinct from an empty [SearchGroups],
  /// which is the answer "nothing matched".
  final SearchGroups? results;

  final bool isLoading;
  final Object? error;

  /// Previously searched terms, newest first.
  final List<String> recent;

  SearchState copyWith({
    String? term,
    SearchGroups? results,
    bool? isLoading,
    Object? error,
    List<String>? recent,
    bool clearError = false,
  }) => SearchState(
    term: term ?? this.term,
    results: results ?? this.results,
    isLoading: isLoading ?? this.isLoading,
    error: clearError ? null : (error ?? this.error),
    recent: recent ?? this.recent,
  );
}

final searchSourceProvider = Provider<SearchSource?>((ref) {
  final hub = ref.watch(hubClientProvider);
  return hub == null ? null : HubSearchSource(hub);
});

final catalogSearchProvider =
    NotifierProvider<CatalogSearchController, SearchState>(
      CatalogSearchController.new,
    );

/// Turns keystrokes into at most one request.
class CatalogSearchController extends Notifier<SearchState> {
  /// Long enough that typing a word costs one request, short enough that the results feel like
  /// they are following the finger.
  static const debounce = Duration(milliseconds: 300);

  /// Below this a query matches most of the catalog, so it is not worth asking.
  static const minLength = 2;

  /// Playlists and genres are fresh for long enough to survive a session of searching; they are
  /// re-read on the next launch, not on the next keystroke.
  static const secondaryFreshFor = Duration(hours: 6);

  Timer? _debounce;

  /// Bumped whenever a search is superseded, so a slow answer to an abandoned term cannot land on
  /// screen after the results for what the user actually typed.
  ///
  /// It says nothing about whether this controller still exists, which is why every continuation
  /// below checks `ref.mounted` as well: signing out mid-search disposes the provider, and writing
  /// `state` after that throws.
  int _generation = 0;

  Future<SearchGroups>? _secondary;

  @override
  SearchState build() {
    // Watched, not read: a different hub is a different catalog, so the memoised collections and
    // anything still in flight belong to a server this screen is no longer pointed at.
    ref.watch(searchSourceProvider);
    _secondary = null;
    _generation++;
    ref.onDispose(() => _debounce?.cancel());
    unawaited(_loadRecent());
    return const SearchState();
  }

  /// The field changed. Starts (or restarts) the debounce.
  void typed(String raw) {
    final term = raw.trim();
    _debounce?.cancel();
    if (term.length < minLength) {
      // Abandon anything in flight: a result for "ra" must not appear over a cleared box.
      _generation++;
      state = SearchState(recent: state.recent);
      return;
    }
    state = state.copyWith(term: term, isLoading: true, clearError: true);
    _debounce = Timer(debounce, () => unawaited(_run(term)));
  }

  /// Searches [raw] immediately — the keyboard's search key, or a tap on a recent term. Neither
  /// should sit out a debounce the user has already ended by choosing.
  Future<void> submit(String raw) {
    final term = raw.trim();
    _debounce?.cancel();
    if (term.length < minLength) return Future.value();
    state = state.copyWith(term: term, isLoading: true, clearError: true);
    return _run(term);
  }

  /// Re-runs the term that failed.
  Future<void> retry() =>
      state.term.length < minLength ? Future.value() : submit(state.term);

  Future<void> clearRecent() async {
    await ref.read(recentSearchesProvider).clear();
    if (!ref.mounted) return;
    state = state.copyWith(recent: const []);
  }

  Future<void> _loadRecent() async {
    final recent = await ref.read(recentSearchesProvider).read();
    if (!ref.mounted) return;
    state = state.copyWith(recent: recent);
  }

  Future<void> _run(String term) async {
    final source = ref.read(searchSourceProvider);
    if (source == null) return;
    final generation = ++_generation;

    // Started before the await below so the two requests overlap.
    final secondary = _secondaryOnce(source);
    try {
      final found = await source.search(term);
      final extras = await secondary;
      if (generation != _generation || !ref.mounted) return;

      final needle = term.toLowerCase();
      state = state.copyWith(
        term: term,
        isLoading: false,
        clearError: true,
        results: SearchGroups(
          tracks: found.tracks,
          albums: found.albums,
          artists: found.artists,
          playlists: extras.playlists
              .where((p) => p.name.toLowerCase().contains(needle))
              .toList(growable: false),
          labels: found.labels ?? const [],
          genres: extras.genres
              .where((g) => g.name.toLowerCase().contains(needle))
              .toList(growable: false),
        ),
      );
      unawaited(_remember(term));
    } catch (error) {
      if (generation != _generation || !ref.mounted) return;
      state = SearchState(term: term, error: error, recent: state.recent);
    }
  }

  Future<void> _remember(String term) async {
    final store = ref.read(recentSearchesProvider);
    final recent = await store.remember(term);
    if (!ref.mounted) return;
    state = state.copyWith(recent: recent);
  }

  /// The caller's playlists and genres, fetched at most once per hub.
  ///
  /// Cache first: a fresh copy on disk answers without a request at all, and a failed refresh
  /// falls back to whatever the cache holds rather than dropping two groups from every result.
  Future<SearchGroups> _secondaryOnce(SearchSource source) =>
      _secondary ??= _loadSecondary(source);

  Future<SearchGroups> _loadSecondary(SearchSource source) async {
    final cache = readHubCache(ref);
    final hub = ref.read(activeHubProvider);
    final prefix = 'search/${hub?.id ?? 'none'}/';

    Future<List<T>> load<T>(
      String key,
      Future<List<T>> Function() fetch,
      T Function(Map<String, Object?>) fromJson,
      Object? Function(T) encode,
    ) async {
      final hit = await cache?.read(prefix + key);
      final held = hit == null ? null : decodeCachedList(hit.json, fromJson);
      if (hit != null && held != null && !hit.isStale) return held;
      try {
        final fresh = await fetch();
        await cache?.write(
          prefix + key,
          fresh.map(encode).toList(),
          freshFor: secondaryFreshFor,
        );
        return fresh;
      } catch (_) {
        // Secondary groups are a bonus on top of the Hub's search. Losing them must never lose
        // the search itself, so a failure here is answered with whatever was already known.
        return held ?? const [];
      }
    }

    final playlists = await load(
      'playlists',
      source.playlists,
      Playlist.fromJson,
      (p) => p.toJson(),
    );
    final genres = await load(
      'genres',
      source.genres,
      GenreSummary.fromJson,
      (g) => g.toJson(),
    );
    return SearchGroups(playlists: playlists, genres: genres);
  }
}
