import '../hub.dart';
import '../json.dart';
import '../models.g.dart';
import 'decode.dart';

/// The home screen's shelves, and the station generator behind them.
///
/// Two generations of station live here. [dailyMixes]/[artistRadio] are the artist-seeded originals
/// the home screen still renders; [station] is the general one, seeded by anything — and only it
/// pages, via [stationMore].
extension DiscoveryEndpoints on HubClient {
  /// "Made for you": one mix per top artist.
  Future<List<DailyMix>> dailyMixes({int? limit}) => get(
    '/v1/discovery/daily-mixes',
    (json) => listOf(json, DailyMix.fromJson),
    query: {'limit': limit},
  );

  /// One daily mix opened as a playlist — its stable identity plus a freshly generated track list.
  Future<DailyMixDetail> dailyMix(String seedArtistId) => get(
    '/v1/discovery/daily-mix/$seedArtistId',
    (json) => DailyMixDetail.fromJson(asObject(json)),
  );

  /// Just the queue an artist seeds, with no title or cover around it.
  Future<List<BrowseTrack>> radioQueue(String artistId) => get(
    '/v1/discovery/radio',
    (json) => listOf(json, BrowseTrack.fromJson),
    query: {'artist': artistId},
  );

  /// The same generated tracks as [radioQueue], wrapped as a viewable, pinnable station.
  Future<DailyMixDetail> artistRadio(String artistId) => get(
    '/v1/discovery/radio/$artistId',
    (json) => DailyMixDetail.fromJson(asObject(json)),
  );

  /// "Jump back in": recently played albums and artists merged with the caller's own playlists.
  Future<List<RecentItem>> jumpBackIn({int? limit}) => get(
    '/v1/discovery/recent',
    (json) => listOf(json, RecentItem.fromJson),
    query: {'limit': limit},
  );

  /// Albums that most recently appeared in a reachable library — new to the caller, not new
  /// releases.
  Future<List<BrowseAlbum>> recentlyAdded({int? limit}) => get(
    '/v1/discovery/recently-added',
    (json) => listOf(json, BrowseAlbum.fromJson),
    query: {'limit': limit},
  );

  Future<List<BrowseAlbum>> recommendedAlbums({int? limit}) => get(
    '/v1/discovery/recommended-albums',
    (json) => listOf(json, BrowseAlbum.fromJson),
    query: {'limit': limit},
  );

  /// Finds people, annotated with the caller's existing relationship to each — distinct from
  /// [CatalogEndpoints.searchCatalog], which finds music.
  Future<List<DiscoveryResult>> searchUsers(String query) => get(
    '/v1/discovery/search',
    (json) => listOf(json, DiscoveryResult.fromJson),
    query: {'q': query},
  );

  Future<List<SimilarUser>> similarUsers() => get(
    '/v1/discovery/similar-users',
    (json) => listOf(json, SimilarUser.fromJson),
  );

  /// Globally trending artists, albums and tracks over the last 30 days.
  Future<Trending> trending() => get(
    '/v1/discovery/trending',
    (json) => Trending.fromJson(asObject(json)),
  );

  /// Builds a station around any seed.
  ///
  /// [seed] is an id for every kind but [StationKind.genre], where it is the genre slug — hence a
  /// string rather than a UUID.
  Future<Station> station(
    StationKind kind,
    String seed, {
    StationFlavour? flavour,
    int? limit,
  }) => get(
    '/v1/radio/${kind.wire}/${seg(seed)}',
    (json) => Station.fromJson(asObject(json)),
    query: {'flavour': flavour?.wire, 'limit': limit},
  );

  /// The next page of a station. [cursor] comes from the previous [Station]; the seed and flavour
  /// must match it, since the cursor only means anything within one generated sequence.
  Future<Station> stationMore(
    StationKind kind,
    String seed, {
    required String cursor,
    StationFlavour? flavour,
    int? limit,
  }) => get(
    '/v1/radio/${kind.wire}/${seg(seed)}/more',
    (json) => Station.fromJson(asObject(json)),
    query: {'cursor': cursor, 'flavour': flavour?.wire, 'limit': limit},
  );
}
