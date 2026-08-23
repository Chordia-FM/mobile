import 'package:chordia_api/chordia_api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';

/// Everything the catalog screens ask the Hub for.
///
/// An interface rather than `HubClient` directly, because `HubClient`'s call surface is a set of
/// **extension** methods: extensions dispatch statically, so no subclass or mock could ever
/// intercept them. Without this seam a widget test for "tapping a row queues the whole list" would
/// need a live server. It is deliberately narrow — one method per call these screens actually make,
/// so a fake is a few lines rather than 174 stubs.
abstract interface class CatalogApi {
  Future<ArtistDetail> artist(String artistId);

  /// Co-listen similarity ("Fans also like"), which is a different relation from
  /// [ArtistDetail.related] — that one is MusicBrainz aliases and memberships.
  Future<List<BrowseArtist>> similarArtists(String artistId);

  Future<AlbumDetail> album(String albumId);

  Future<BrowseTrack> track(String trackId);

  /// The caller's own numbers for one entity — plays, rank, first and last heard.
  Future<EntityStats> entityStats(EntityKind kind, String id);

  Future<List<GenreSummary>> genres();

  Future<GenreDetail> genre(String slug);

  Future<List<LabelSummary>> labels();

  /// [labelId] is [unlabeledLabelId] for the synthetic "no label linked" bucket, which the Hub
  /// serves from its own endpoint but shapes as an ordinary [LabelDetail].
  Future<LabelDetail> label(String labelId);

  /// A generated station around any seed. Backs the artist page's Radio entry point.
  Future<Station> station(StationKind kind, String seed);

  Future<List<BrowseTrack>> likedTracks();

  Future<void> likeTrack(String trackId);

  Future<void> unlikeTrack(String trackId);

  Future<List<Playlist>> playlists();

  Future<void> addPlaylistTrack(String playlistId, String trackId);
}

/// The route segment and [CatalogApi.label] argument for the "Unlabeled" bucket, which has no id
/// of its own — `LabelSummary.id` is null for it.
const unlabeledLabelId = 'unlabeled';

/// [CatalogApi] over the real Hub.
class HubCatalogApi implements CatalogApi {
  const HubCatalogApi(this._hub);

  final HubClient _hub;

  @override
  Future<ArtistDetail> artist(String artistId) => _hub.artist(artistId);

  @override
  Future<List<BrowseArtist>> similarArtists(String artistId) =>
      _hub.similarArtists(artistId);

  @override
  Future<AlbumDetail> album(String albumId) => _hub.album(albumId);

  @override
  Future<BrowseTrack> track(String trackId) => _hub.track(trackId);

  @override
  Future<EntityStats> entityStats(EntityKind kind, String id) =>
      _hub.entityStats(kind: kind, id: id);

  @override
  Future<List<GenreSummary>> genres() => _hub.genres();

  @override
  Future<GenreDetail> genre(String slug) => _hub.genre(slug);

  @override
  Future<List<LabelSummary>> labels() => _hub.labels();

  @override
  Future<LabelDetail> label(String labelId) => labelId == unlabeledLabelId
      ? _hub.unlabeledAlbums()
      : _hub.label(labelId);

  @override
  Future<Station> station(StationKind kind, String seed) =>
      _hub.station(kind, seed);

  @override
  Future<List<BrowseTrack>> likedTracks() => _hub.likedTracks();

  @override
  Future<void> likeTrack(String trackId) => _hub.likeTrack(trackId);

  @override
  Future<void> unlikeTrack(String trackId) => _hub.unlikeTrack(trackId);

  @override
  Future<List<Playlist>> playlists() => _hub.playlists();

  @override
  Future<void> addPlaylistTrack(String playlistId, String trackId) =>
      _hub.addPlaylistTrack(playlistId, TrackBody(trackId: trackId));
}

/// Thrown when a catalog screen is somehow reached with no hub selected.
///
/// Not a state any of these screens render a design for: the router only admits them behind a
/// signed-in session, which implies an active hub. Surfacing it as an error the retry button can
/// act on beats a null check that renders an empty page and explains nothing.
class NoActiveHubException implements Exception {
  const NoActiveHubException();

  @override
  String toString() => 'No hub is selected, so the catalog cannot be read.';
}

/// The catalog call surface for the active hub.
///
/// Overridden with a fake in tests. Throwing rather than answering null keeps every consumer a
/// plain `ref.watch` — the failure lands in the `AsyncValue` the screen already renders.
final catalogApiProvider = Provider<CatalogApi>((ref) {
  final hub = ref.watch(hubClientProvider);
  if (hub == null) throw const NoActiveHubException();
  return HubCatalogApi(hub);
});
