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

  /// An album's running order on its own, for a menu opened on a CARD — a card carries no track
  /// list, so Play and Add to queue fetch one on demand rather than every visible card paying for
  /// tracks almost none of them will be asked for.
  Future<List<BrowseTrack>> albumTracks(String albumId);

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

  /// One playlist with its viewer-filtered tracks, for the menu of a playlist row that carries only
  /// a name and an id.
  Future<PlaylistDetail> playlist(String playlistId);

  /// A smart playlist's current snapshot, for the same reason.
  Future<SmartPlaylistDetail> smartPlaylist(String playlistId);

  /// The tracks behind a daily mix, so a mix row can be played from its own menu.
  Future<DailyMixDetail> dailyMix(String seedArtistId);

  Future<void> addPlaylistTrack(String playlistId, String trackId);

  /// Pins are the "keep this to hand" list the Library tab leads with. Both endpoints existed on
  /// the wire and nothing in the app had ever called either.
  Future<void> addPin(PinKind kind, String id);

  Future<void> removePin(PinKind kind, String id);
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
  Future<List<BrowseTrack>> albumTracks(String albumId) =>
      _hub.albumTracks(albumId);

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
  Future<PlaylistDetail> playlist(String playlistId) =>
      _hub.playlist(playlistId);

  @override
  Future<SmartPlaylistDetail> smartPlaylist(String playlistId) =>
      _hub.smartPlaylist(playlistId);

  @override
  Future<DailyMixDetail> dailyMix(String seedArtistId) =>
      _hub.dailyMix(seedArtistId);

  @override
  Future<void> addPlaylistTrack(String playlistId, String trackId) =>
      _hub.addPlaylistTrack(playlistId, TrackBody(trackId: trackId));

  @override
  Future<void> addPin(PinKind kind, String id) => _hub.addPin(kind, id);

  @override
  Future<void> removePin(PinKind kind, String id) => _hub.removePin(kind, id);
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
