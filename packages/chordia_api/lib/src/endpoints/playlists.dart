import '../hub.dart';
import '../json.dart';
import '../models.g.dart';
import 'decode.dart';

/// Hand-built playlists, plus the two per-user track sets the Hub models the same way: liked and
/// hidden.
///
/// Liked answers with whole tracks because it is a view the app renders directly; hidden answers
/// with bare ids because it is only ever a filter applied to other lists.
extension PlaylistEndpoints on HubClient {
  Future<List<Playlist>> playlists() =>
      get('/v1/playlists', (json) => listOf(json, Playlist.fromJson));

  Future<Playlist> createPlaylist(CreatePlaylistRequest request) => post(
    '/v1/playlists',
    (json) => Playlist.fromJson(asObject(json)),
    body: request.toJson(),
  );

  Future<PlaylistDetail> playlist(String playlistId) => get(
    '/v1/playlists/$playlistId',
    (json) => PlaylistDetail.fromJson(asObject(json)),
  );

  // The parameter is `changes`, not `patch`: a parameter called `patch` would shadow
  // `HubClient.patch` and this method could not reach the verb it needs.
  Future<void> updatePlaylist(String playlistId, PlaylistPatch changes) =>
      patch<void>('/v1/playlists/$playlistId', discard, body: changes.toJson());

  Future<void> deletePlaylist(String playlistId) =>
      delete('/v1/playlists/$playlistId');

  Future<void> addPlaylistTrack(String playlistId, TrackBody track) =>
      post<void>(
        '/v1/playlists/$playlistId/tracks',
        discard,
        body: track.toJson(),
      );

  Future<void> removePlaylistTrack(String playlistId, String trackId) =>
      delete('/v1/playlists/$playlistId/tracks/$trackId');

  /// Replaces the whole running order — the Hub takes the full list, not a move.
  Future<void> reorderPlaylistTracks(
    String playlistId,
    PlaylistTrackOrder order,
  ) => put<void>(
    '/v1/playlists/$playlistId/tracks/order',
    discard,
    body: order.toJson(),
  );

  Future<void> setPlaylistCover(String playlistId, CoverBody cover) =>
      put<void>(
        '/v1/playlists/$playlistId/cover',
        discard,
        body: cover.toJson(),
      );

  /// Drops a chosen cover, so the playlist falls back to its generated mosaic.
  Future<void> clearPlaylistCover(String playlistId) =>
      delete('/v1/playlists/$playlistId/cover');

  Future<List<PublicUser>> playlistCollaborators(String playlistId) => get(
    '/v1/playlists/$playlistId/collaborators',
    (json) => listOf(json, PublicUser.fromJson),
  );

  Future<void> addPlaylistCollaborator(
    String playlistId,
    CollaboratorBody collaborator,
  ) => post<void>(
    '/v1/playlists/$playlistId/collaborators',
    discard,
    body: collaborator.toJson(),
  );

  Future<void> removePlaylistCollaborator(String playlistId, String userId) =>
      delete('/v1/playlists/$playlistId/collaborators/$userId');

  /// How the playlist is being listened to — the caller's own plays with
  /// [StatsScope.me], everyone's with [StatsScope.global].
  Future<PlaylistStats> playlistStats(
    String playlistId, {
    Period? period,
    String? tz,
    StatsScope? scope,
  }) => get(
    '/v1/playlists/$playlistId/stats',
    (json) => PlaylistStats.fromJson(asObject(json)),
    query: {'period': period?.wire, 'tz': tz, 'scope': scope?.wire},
  );

  Future<List<BrowseTrack>> likedTracks() =>
      get('/v1/me/liked', (json) => listOf(json, BrowseTrack.fromJson));

  Future<void> likeTrack(String trackId) =>
      put<void>('/v1/me/liked/$trackId', discard);

  Future<void> unlikeTrack(String trackId) => delete('/v1/me/liked/$trackId');

  /// The ids the caller has hidden, to filter out of every list the app builds.
  ///
  /// The Hub declares no schema for this 200 (its handler returns a bare `Vec<String>`), so the
  /// element type is read as strings here rather than generated.
  Future<List<String>> hiddenTracks() => get('/v1/me/hidden', stringsOf);

  Future<void> hideTrack(String trackId) =>
      put<void>('/v1/me/hidden/$trackId', discard);

  Future<void> unhideTrack(String trackId) => delete('/v1/me/hidden/$trackId');
}
