import 'package:chordia_api/chordia_api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';

/// Everything the Manager screens ask the Hub for.
///
/// An interface rather than `HubClient` directly, because `HubClient`'s call surface is a set of
/// **extension** methods: extensions dispatch statically, so no subclass or mock could intercept
/// them and a widget test would need a live server. Deliberately narrow — one method per call
/// these screens actually make.
///
/// The Manager is a viewing surface. It measures what the user owns against what MusicBrainz says
/// exists, and it follows artists so new releases show up in that measurement. Nothing here
/// acquires anything, and there is no endpoint left on the Hub that would.
abstract interface class ManagerApi {
  /// Album/artist completeness plus the per-library counts behind it.
  Future<CoverageSummary> coverage();

  /// Replaces the set of libraries left out of the coverage maths.
  ///
  /// Returns the set the Hub actually **stored**: ids the caller cannot see are dropped, so the
  /// answer is not necessarily the argument, and the caller must adopt it rather than assume the
  /// write echoed.
  Future<List<String>> setExclusions(List<String> libraryIds);

  Future<ManagerPrefs> prefs();

  Future<ManagerPrefs> setPrefs(ManagerPrefs prefs);

  /// The artists the caller owns at least one track by — the way into a coverage detail page.
  Future<List<BrowseArtist>> ownedArtists();

  /// One owned artist measured against their MusicBrainz discography.
  Future<ArtistCoverage> artistCoverage(String artistId);

  /// Per-edition track coverage for one release group. Keyed by release-group MBID, not by a
  /// Chordia album id.
  Future<AlbumTrackCoverage> releaseGroupCoverage(String releaseGroupMbid);

  /// Browse-all search over the Hub's MusicBrainz cache: artists and release groups alike.
  Future<DiscoverResults> discover(String query);

  Future<ExtArtistDetail> discoverArtist(String artistMbid);

  Future<List<FollowedArtist>> follows();

  Future<void> follow(String artistMbid, {String? name});

  Future<void> unfollow(String artistMbid);
}

/// [ManagerApi] over the real Hub.
class HubManagerApi implements ManagerApi {
  const HubManagerApi(this._hub);

  final HubClient _hub;

  @override
  Future<CoverageSummary> coverage() => _hub.managerCoverage();

  @override
  Future<List<String>> setExclusions(List<String> libraryIds) =>
      _hub.setManagerExclusions(ExclusionsUpdate(libraryIds: libraryIds));

  @override
  Future<ManagerPrefs> prefs() => _hub.managerPrefs();

  @override
  Future<ManagerPrefs> setPrefs(ManagerPrefs prefs) =>
      _hub.setManagerPrefs(prefs);

  @override
  Future<List<BrowseArtist>> ownedArtists() => _hub.artists();

  @override
  Future<ArtistCoverage> artistCoverage(String artistId) =>
      _hub.artistCoverage(artistId);

  @override
  Future<AlbumTrackCoverage> releaseGroupCoverage(String releaseGroupMbid) =>
      _hub.releaseGroupCoverage(releaseGroupMbid);

  @override
  Future<DiscoverResults> discover(String query) =>
      _hub.discoverReleases(query);

  @override
  Future<ExtArtistDetail> discoverArtist(String artistMbid) =>
      _hub.discoverArtist(artistMbid);

  @override
  Future<List<FollowedArtist>> follows() => _hub.followedArtists();

  @override
  Future<void> follow(String artistMbid, {String? name}) =>
      _hub.followArtist(FollowInput(artistMbid: artistMbid, name: name));

  @override
  Future<void> unfollow(String artistMbid) => _hub.unfollowArtist(artistMbid);
}

/// The Manager's slice of the Hub, or null when there is no session to speak through.
final managerApiProvider = Provider<ManagerApi?>((ref) {
  final hub = ref.watch(hubClientProvider);
  return hub == null ? null : HubManagerApi(hub);
});
