import 'dart:async';

import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import 'hub_cache.dart';

/// The reads home is made of.
///
/// An interface, not the [HubClient] itself, so the feed can be driven by a scripted source in a
/// test without a socket, a session or a certificate.
abstract interface class HomeSource {
  Future<List<PinnedItem>> pins();

  Future<List<RecentItem>> jumpBackIn();

  Future<List<DailyMix>> dailyMixes();

  Future<List<BrowseAlbum>> recentlyAdded();

  Future<List<BrowseAlbum>> recommendedAlbums();

  Future<Trending> trending();

  Future<List<FriendNowPlaying>> friendsNowPlaying();
}

/// [HomeSource] over the Hub's discovery, pin and social endpoints.
///
/// The limits are the shelf's, not the screen's: a rail is a single horizontal row, and asking for
/// more rows than a thumb will ever reach costs the phone a bigger response on every launch.
class HubHomeSource implements HomeSource {
  const HubHomeSource(this._hub, {this.railLength = 12});

  final HubClient _hub;
  final int railLength;

  @override
  Future<List<PinnedItem>> pins() => _hub.pins();

  @override
  Future<List<RecentItem>> jumpBackIn() => _hub.jumpBackIn(limit: railLength);

  @override
  Future<List<DailyMix>> dailyMixes() => _hub.dailyMixes(limit: railLength);

  @override
  Future<List<BrowseAlbum>> recentlyAdded() =>
      _hub.recentlyAdded(limit: railLength);

  @override
  Future<List<BrowseAlbum>> recommendedAlbums() =>
      _hub.recommendedAlbums(limit: railLength);

  @override
  Future<Trending> trending() => _hub.trending();

  @override
  Future<List<FriendNowPlaying>> friendsNowPlaying() =>
      _hub.friendsNowPlaying();
}

/// The rails home can show, in the order it shows them.
///
/// Order runs personal → new → suggested → global → social: what the listener already chose comes
/// before what the Hub thinks they might like, and a popularity chart comes before other people's
/// listening. The web client permutes this by time of day; here the clock only picks the greeting.
/// A phone home screen is scrolled by thumb from a fixed starting point, and a rail that moves
/// between launches reads as content that disappeared.
enum HomeRail {
  quickAccess,
  jumpBackIn,
  madeForYou,
  recentlyAdded,
  recommended,
  trendingTracks,
  trendingAlbums,
  trendingArtists,
  friendsListening,
}

/// Everything home renders, one field per rail.
@immutable
class HomeFeed {
  const HomeFeed({
    this.pins = const [],
    this.recent = const [],
    this.mixes = const [],
    this.recentlyAdded = const [],
    this.recommended = const [],
    this.trendingTracks = const [],
    this.trendingAlbums = const [],
    this.trendingArtists = const [],
    this.friends = const [],
  });

  final List<PinnedItem> pins;
  final List<RecentItem> recent;
  final List<DailyMix> mixes;
  final List<BrowseAlbum> recentlyAdded;
  final List<BrowseAlbum> recommended;
  final List<BrowseTrack> trendingTracks;
  final List<BrowseAlbum> trendingAlbums;
  final List<BrowseArtist> trendingArtists;
  final List<FriendNowPlaying> friends;

  /// How many cards [rail] holds.
  int count(HomeRail rail) => switch (rail) {
    HomeRail.quickAccess => pins.length,
    HomeRail.jumpBackIn => recent.length,
    HomeRail.madeForYou => mixes.length,
    HomeRail.recentlyAdded => recentlyAdded.length,
    HomeRail.recommended => recommended.length,
    HomeRail.trendingTracks => trendingTracks.length,
    HomeRail.trendingAlbums => trendingAlbums.length,
    HomeRail.trendingArtists => trendingArtists.length,
    HomeRail.friendsListening => friends.length,
  };

  /// The rails that actually have something in them, in [HomeRail] order.
  ///
  /// An empty rail is dropped entirely rather than rendered as a heading over nothing: a fresh
  /// account has no history, no mixes and no friends, and eight empty headings is not a home
  /// screen. This is the only list the screen builds from, so the rule cannot be forgotten at a
  /// call site.
  List<HomeRail> get rails =>
      HomeRail.values.where((r) => count(r) > 0).toList(growable: false);

  bool get isEmpty => rails.isEmpty;
}

/// What the home tab is showing right now.
@immutable
class HomeState {
  const HomeState({this.feed, this.isLoading = false, this.error});

  /// Null until something is known — cached or fetched. Distinct from an empty feed, which is a
  /// real answer about an account with nothing in it.
  final HomeFeed? feed;

  /// A request is in flight. True alongside a [feed] during the revalidate half of a cached load.
  final bool isLoading;

  /// The failure to show, set only when there is nothing to show instead. A refresh that fails
  /// over a feed already on screen leaves the feed alone — losing last night's home because a
  /// train went through a tunnel is worse than showing it a few minutes late.
  final Object? error;

  HomeState copyWith({
    HomeFeed? feed,
    bool? isLoading,
    Object? error,
    bool clearError = false,
  }) => HomeState(
    feed: feed ?? this.feed,
    isLoading: isLoading ?? this.isLoading,
    error: clearError ? null : (error ?? this.error),
  );
}

/// The Hub-backed source for the active hub, or null when there is no hub to read.
final homeSourceProvider = Provider<HomeSource?>((ref) {
  final hub = ref.watch(hubClientProvider);
  return hub == null ? null : HubHomeSource(hub);
});

final homeFeedProvider = NotifierProvider<HomeFeedController, HomeState>(
  HomeFeedController.new,
);

/// Loads home: the cache first, the Hub behind it.
///
/// Each rail is fetched and cached independently. One endpoint failing costs its own rail and
/// nothing else — a Hub whose trending query times out should not blank the four rails that
/// answered — and only a load where *everything* failed with nothing cached is an error the user
/// is asked to retry.
class HomeFeedController extends Notifier<HomeState> {
  /// How long a cached rail counts as fresh. Only [HubCache.read] consults it; home revalidates on
  /// every mount regardless, so this governs how long the body survives eviction, not whether the
  /// Hub is asked.
  static const freshFor = Duration(hours: 6);

  /// Bumped on every [build]. Async work started for one hub must never write state that belongs
  /// to the next — switching hubs mid-load would otherwise land the old server's catalog on the
  /// new server's home.
  ///
  /// It says nothing about whether this controller still exists, which is why the continuations
  /// below check `ref.mounted` too: signing out mid-load disposes the provider, and writing
  /// `state` after that throws.
  int _generation = 0;

  late String _keyPrefix;

  @override
  HomeState build() {
    final source = ref.watch(homeSourceProvider);
    // Cache keys carry the hub id: two hubs are two catalogs, and a shared key would paint one
    // server's albums on the other's home for as long as it took the refresh to land.
    final hub = ref.watch(activeHubProvider);
    final generation = ++_generation;

    if (source == null || hub == null) return const HomeState();
    _keyPrefix = 'home/${hub.id}/';

    // Safe from a synchronous `build`: `_load` suspends on its first await, so every `state =`
    // below happens after this method has returned.
    unawaited(_load(generation, source));
    return const HomeState(isLoading: true);
  }

  /// Re-reads every rail from the Hub. Drives both pull-to-refresh and the error card's retry.
  Future<void> refresh() {
    final source = ref.read(homeSourceProvider);
    if (source == null) return Future.value();
    state = state.copyWith(isLoading: true, clearError: true);
    return _fetch(_generation, source);
  }

  Future<void> _load(int generation, HomeSource source) async {
    final cached = await _readCache();
    if (generation != _generation || !ref.mounted) return;
    if (cached != null && !cached.isEmpty) state = state.copyWith(feed: cached);
    await _fetch(generation, source);
  }

  Future<void> _fetch(int generation, HomeSource source) async {
    final cache = readHubCache(ref);
    final previous = state.feed;

    // Typed as `_Slot<Object?>` because the seven rails answer with seven different shapes and
    // `Future.wait` needs one element type; `_pick` puts each back into its own.
    Future<_Slot<Object?>> one<T>(
      String key,
      Future<T> Function() fetch,
      Object? Function(T) encode,
    ) async {
      try {
        final value = await fetch();
        await cache?.write(_keyPrefix + key, encode(value), freshFor: freshFor);
        return _Slot<Object?>(value: value);
      } catch (error) {
        return _Slot<Object?>(error: error);
      }
    }

    final results = await Future.wait<_Slot<Object?>>([
      one('pins', source.pins, (v) => v.map((e) => e.toJson()).toList()),
      one(
        'recent',
        source.jumpBackIn,
        (v) => v.map((e) => e.toJson()).toList(),
      ),
      one('mixes', source.dailyMixes, (v) => v.map((e) => e.toJson()).toList()),
      one(
        'recently-added',
        source.recentlyAdded,
        (v) => v.map((e) => e.toJson()).toList(),
      ),
      one(
        'recommended',
        source.recommendedAlbums,
        (v) => v.map((e) => e.toJson()).toList(),
      ),
      one('trending', source.trending, (v) => v.toJson()),
      one(
        'friends',
        source.friendsNowPlaying,
        (v) => v.map((e) => e.toJson()).toList(),
      ),
    ]);
    if (generation != _generation || !ref.mounted) return;

    final failures = results.where((r) => r.error != null).toList();
    if (failures.length == results.length) {
      // Nothing answered. With a feed on screen this is a blip; without one it is the whole story.
      state = HomeState(
        feed: previous,
        error: previous == null ? failures.first.error : null,
      );
      return;
    }

    final trending = results[5].value as Trending?;
    state = HomeState(
      feed: HomeFeed(
        pins: _pick(results[0], previous?.pins),
        recent: _pick(results[1], previous?.recent),
        mixes: _pick(results[2], previous?.mixes),
        recentlyAdded: _pick(results[3], previous?.recentlyAdded),
        recommended: _pick(results[4], previous?.recommended),
        trendingTracks:
            trending?.tracks ?? previous?.trendingTracks ?? const [],
        trendingAlbums:
            trending?.albums ?? previous?.trendingAlbums ?? const [],
        trendingArtists:
            trending?.artists ?? previous?.trendingArtists ?? const [],
        friends: _pick(results[6], previous?.friends),
      ),
    );
  }

  /// The fresh value, or what was already on screen when this rail's request failed.
  List<T> _pick<T>(_Slot<Object?> slot, List<T>? previous) {
    final value = slot.value;
    if (value is List<T>) return value;
    return previous ?? const [];
  }

  Future<HomeFeed?> _readCache() async {
    final cache = readHubCache(ref);
    if (cache == null) return null;

    Future<List<T>?> list<T>(
      String key,
      T Function(Map<String, Object?>) fromJson,
    ) async {
      final hit = await cache.read(_keyPrefix + key);
      return hit == null ? null : decodeCachedList(hit.json, fromJson);
    }

    final trendingHit = await cache.read('${_keyPrefix}trending');
    final trending = trendingHit == null
        ? null
        : decodeCachedObject(trendingHit.json, Trending.fromJson);

    return HomeFeed(
      pins: await list('pins', PinnedItem.fromJson) ?? const [],
      recent: await list('recent', RecentItem.fromJson) ?? const [],
      mixes: await list('mixes', DailyMix.fromJson) ?? const [],
      recentlyAdded:
          await list('recently-added', BrowseAlbum.fromJson) ?? const [],
      recommended: await list('recommended', BrowseAlbum.fromJson) ?? const [],
      trendingTracks: trending?.tracks ?? const [],
      trendingAlbums: trending?.albums ?? const [],
      trendingArtists: trending?.artists ?? const [],
      friends: await list('friends', FriendNowPlaying.fromJson) ?? const [],
    );
  }
}

/// One rail's result: what came back, or what stopped it.
@immutable
class _Slot<T> {
  const _Slot({this.value, this.error});

  final T? value;
  final Object? error;
}
