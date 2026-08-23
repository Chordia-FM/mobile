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

/// The pinned shelf and the three edits it supports.
///
/// Its own interface for the same reason [PlaylistApi] is one: what a test needs to say about a
/// pin is "this add failed", and saying that through a transport would need a session and a base
/// URL to say it. [reorder] takes the whole shelf because the Hub sets the order across every kind
/// at once — there is no "move this one" call.
abstract interface class PinsApi {
  Future<List<PinnedItem>> pins();

  Future<void> add(PinKind kind, String id);

  Future<void> remove(PinKind kind, String id);

  Future<void> reorder(List<PinnedItem> order);
}

/// The liked-songs list and the one edit it supports.
abstract interface class LikedApi {
  Future<List<BrowseTrack>> tracks();

  Future<void> unlike(String trackId);
}

class HubPinsApi implements PinsApi {
  const HubPinsApi(this._hub);

  final HubClient _hub;

  @override
  Future<List<PinnedItem>> pins() => _hub.pins();

  @override
  Future<void> add(PinKind kind, String id) => _hub.addPin(kind, id);

  @override
  Future<void> remove(PinKind kind, String id) => _hub.removePin(kind, id);

  @override
  Future<void> reorder(List<PinnedItem> order) => _hub.reorderPins(
    ReorderBody(
      items: [for (final pin in order) PinRef(id: pin.id, kind: pin.kind.wire)],
    ),
  );
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
