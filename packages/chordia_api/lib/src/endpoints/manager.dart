import '../hub.dart';
import '../json.dart';
import '../models.g.dart';
import 'decode.dart';

/// The Manager: what the caller owns measured against what MusicBrainz says exists.
///
/// Coverage is computed over the caller's *in-scope* libraries — every one they can see, minus the
/// exclusions set by [setManagerExclusions]. A shared library full of someone else's taste would
/// otherwise drag every completeness figure down.
///
/// Discovery here reads the Hub's cached MusicBrainz discographies (the `ext_*` tables), which is
/// why its ids are MBIDs rather than Chordia UUIDs.
extension ManagerEndpoints on HubClient {
  Future<CoverageSummary> managerCoverage() => get(
    '/v1/manager/coverage',
    (json) => CoverageSummary.fromJson(asObject(json)),
  );

  /// Library ids left out of the coverage maths.
  Future<List<String>> managerExclusions() =>
      get('/v1/manager/coverage/exclusions', stringsOf);

  /// Replaces the exclusion set.
  ///
  /// Ids the caller cannot see are dropped, so the answer is the set that was actually stored —
  /// compare it against what you sent rather than assuming it echoes.
  Future<List<String>> setManagerExclusions(ExclusionsUpdate update) =>
      put('/v1/manager/coverage/exclusions', stringsOf, body: update.toJson());

  Future<ManagerPrefs> managerPrefs() =>
      get('/v1/manager/prefs', (json) => ManagerPrefs.fromJson(asObject(json)));

  /// Replaces the preferences. A `default_library_id` must be one the caller can see.
  Future<ManagerPrefs> setManagerPrefs(ManagerPrefs prefs) => put(
    '/v1/manager/prefs',
    (json) => ManagerPrefs.fromJson(asObject(json)),
    body: prefs.toJson(),
  );

  /// Per-edition track coverage for one release group: every edition MusicBrainz knows, each track
  /// flagged owned or not. Keyed by release-group MBID, not by a Chordia album id.
  Future<AlbumTrackCoverage> releaseGroupCoverage(String releaseGroupMbid) =>
      get(
        '/v1/manager/albums/${seg(releaseGroupMbid)}/tracks',
        (json) => AlbumTrackCoverage.fromJson(asObject(json)),
      );

  /// What the caller owns of one artist, and what the discography says is missing.
  Future<ArtistCoverage> artistCoverage(String artistId) => get(
    '/v1/manager/artists/$artistId/missing',
    (json) => ArtistCoverage.fromJson(asObject(json)),
  );

  /// Searches the discography cache — artists and release groups alike, owned or not.
  Future<DiscoverResults> discoverReleases(String query) => get(
    '/v1/manager/discover',
    (json) => DiscoverResults.fromJson(asObject(json)),
    query: {'q': query},
  );

  /// One discovered artist and their full release-group list, overlaid with what the caller owns.
  Future<ExtArtistDetail> discoverArtist(String artistMbid) => get(
    '/v1/manager/discover/artists/${seg(artistMbid)}',
    (json) => ExtArtistDetail.fromJson(asObject(json)),
  );

  Future<List<FollowedArtist>> followedArtists() => get(
    '/v1/manager/follows',
    (json) => listOf(json, FollowedArtist.fromJson),
  );

  /// Follows an artist for release monitoring. `monitor_types` defaults to Album + EP when the
  /// input leaves it out.
  Future<void> followArtist(FollowInput follow) =>
      post<void>('/v1/manager/follows', discard, body: follow.toJson());

  Future<void> updateArtistFollow(String artistMbid, FollowInput follow) =>
      patch<void>(
        '/v1/manager/follows/${seg(artistMbid)}',
        discard,
        body: follow.toJson(),
      );

  /// Idempotent: unfollowing an artist who is not followed is a success, not a 404.
  Future<void> unfollowArtist(String artistMbid) =>
      delete('/v1/manager/follows/${seg(artistMbid)}');
}
