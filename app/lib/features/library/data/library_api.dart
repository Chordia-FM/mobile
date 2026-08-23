import 'package:chordia_api/chordia_api.dart';

/// The slice of the Hub the playlist screen actually uses.
///
/// Narrower than `HubClient` on purpose: the controller below owns the optimistic edit rules, and
/// those rules are what the tests are about. Pinning them to a four-method interface lets a test
/// state "this call fails" without standing up a transport, a session and a base URL to say it.
abstract interface class PlaylistApi {
  Future<PlaylistDetail> detail(String playlistId);

  /// Replaces the whole running order — the Hub takes the full list, not a move.
  Future<void> reorderTracks(String playlistId, List<String> trackIds);

  Future<void> removeTrack(String playlistId, String trackId);

  Future<void> update(String playlistId, PlaylistPatch changes);

  /// Picks one of the covers already in the playlist as its face.
  Future<void> setCover(String playlistId, String hash);

  /// Drops the chosen cover, so the playlist falls back to its generated mosaic.
  Future<void> clearCover(String playlistId);

  Future<void> addCollaborator(String playlistId, String handle);

  Future<void> removeCollaborator(String playlistId, String userId);
}

/// The liked-songs list and the one edit it supports.
abstract interface class LikedApi {
  Future<List<BrowseTrack>> tracks();

  Future<void> unlike(String trackId);
}

class HubPlaylistApi implements PlaylistApi {
  const HubPlaylistApi(this._hub);

  final HubClient _hub;

  @override
  Future<PlaylistDetail> detail(String playlistId) => _hub.playlist(playlistId);

  @override
  Future<void> reorderTracks(String playlistId, List<String> trackIds) =>
      _hub.reorderPlaylistTracks(
        playlistId,
        PlaylistTrackOrder(trackIds: trackIds),
      );

  @override
  Future<void> removeTrack(String playlistId, String trackId) =>
      _hub.removePlaylistTrack(playlistId, trackId);

  @override
  Future<void> update(String playlistId, PlaylistPatch changes) =>
      _hub.updatePlaylist(playlistId, changes);

  @override
  Future<void> setCover(String playlistId, String hash) =>
      _hub.setPlaylistCover(playlistId, CoverBody(hash: hash));

  @override
  Future<void> clearCover(String playlistId) =>
      _hub.clearPlaylistCover(playlistId);

  @override
  Future<void> addCollaborator(String playlistId, String handle) => _hub
      .addPlaylistCollaborator(playlistId, CollaboratorBody(handle: handle));

  @override
  Future<void> removeCollaborator(String playlistId, String userId) =>
      _hub.removePlaylistCollaborator(playlistId, userId);
}

class HubLikedApi implements LikedApi {
  const HubLikedApi(this._hub);

  final HubClient _hub;

  @override
  Future<List<BrowseTrack>> tracks() => _hub.likedTracks();

  @override
  Future<void> unlike(String trackId) => _hub.unlikeTrack(trackId);
}
