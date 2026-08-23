import '../hub.dart';
import '../json.dart';
import '../models.g.dart';
import 'decode.dart';

/// Rule-driven playlists.
///
/// A smart playlist is stored as rules and *materialised* into a snapshot on a schedule, so reading
/// one ([smartPlaylist]) shows the last snapshot rather than re-running the rules. [previewSmart]
/// evaluates rules without saving anything; [refreshSmartPlaylist] re-runs a saved one now.
extension SmartPlaylistEndpoints on HubClient {
  Future<List<SmartPlaylist>> smartPlaylists() => get(
    '/v1/smart-playlists',
    (json) => listOf(json, SmartPlaylist.fromJson),
  );

  Future<SmartPlaylist> createSmartPlaylist(SmartBody body) => post(
    '/v1/smart-playlists',
    (json) => SmartPlaylist.fromJson(asObject(json)),
    body: body.toJson(),
  );

  /// What these rules would match right now, saving nothing — the editor's live preview.
  Future<SmartPreview> previewSmart(SmartRules rules) => post(
    '/v1/smart-playlists/preview',
    (json) => SmartPreview.fromJson(asObject(json)),
    body: rules.toJson(),
  );

  /// The materialised snapshot, hydrated into tracks.
  Future<SmartPlaylistDetail> smartPlaylist(String playlistId) => get(
    '/v1/smart-playlists/$playlistId',
    (json) => SmartPlaylistDetail.fromJson(asObject(json)),
  );

  /// Replaces name, rules and schedule together — this is a PUT, so an omitted field is a cleared
  /// field, not an unchanged one.
  Future<void> updateSmartPlaylist(String playlistId, SmartBody body) =>
      put<void>(
        '/v1/smart-playlists/$playlistId',
        discard,
        body: body.toJson(),
      );

  Future<void> deleteSmartPlaylist(String playlistId) =>
      delete('/v1/smart-playlists/$playlistId');

  /// Re-runs the rules immediately and reports what entered and left.
  Future<SmartRefreshResult> refreshSmartPlaylist(String playlistId) => post(
    '/v1/smart-playlists/$playlistId/refresh',
    (json) => SmartRefreshResult.fromJson(asObject(json)),
  );
}
