import '../hub.dart';
import '../json.dart';
import '../models.g.dart';
import 'decode.dart';

/// Per-library metadata corrections.
///
/// An override is scoped to one library, not to the catalog: two owners can disagree about the same
/// album and both stay right. The Hub layers the override over what enrichment found, so clearing
/// one ([deleteAlbumOverride] and friends) restores the enriched value rather than blanking it.
extension OverrideEndpoints on HubClient {
  /// Everything this library has overridden, across all three kinds.
  Future<List<LibraryOverrideSummary>> libraryOverrides(String libraryId) =>
      get(
        '/v1/libraries/$libraryId/overrides',
        (json) => listOf(json, LibraryOverrideSummary.fromJson),
      );

  Future<AlbumOverrideView> albumOverride(String libraryId, String albumId) =>
      get(
        '/v1/libraries/$libraryId/overrides/albums/$albumId',
        (json) => AlbumOverrideView.fromJson(asObject(json)),
      );

  Future<void> putAlbumOverride(
    String libraryId,
    String albumId,
    AlbumOverrideInput input,
  ) => put<void>(
    '/v1/libraries/$libraryId/overrides/albums/$albumId',
    discard,
    body: input.toJson(),
  );

  Future<void> deleteAlbumOverride(String libraryId, String albumId) =>
      delete('/v1/libraries/$libraryId/overrides/albums/$albumId');

  Future<ArtistOverrideView> artistOverride(
    String libraryId,
    String artistId,
  ) => get(
    '/v1/libraries/$libraryId/overrides/artists/$artistId',
    (json) => ArtistOverrideView.fromJson(asObject(json)),
  );

  Future<void> putArtistOverride(
    String libraryId,
    String artistId,
    ArtistOverrideInput input,
  ) => put<void>(
    '/v1/libraries/$libraryId/overrides/artists/$artistId',
    discard,
    body: input.toJson(),
  );

  Future<void> deleteArtistOverride(String libraryId, String artistId) =>
      delete('/v1/libraries/$libraryId/overrides/artists/$artistId');

  Future<TrackOverrideView> trackOverride(String libraryId, String trackId) =>
      get(
        '/v1/libraries/$libraryId/overrides/tracks/$trackId',
        (json) => TrackOverrideView.fromJson(asObject(json)),
      );

  Future<void> putTrackOverride(
    String libraryId,
    String trackId,
    TrackOverrideInput input,
  ) => put<void>(
    '/v1/libraries/$libraryId/overrides/tracks/$trackId',
    discard,
    body: input.toJson(),
  );

  Future<void> deleteTrackOverride(String libraryId, String trackId) =>
      delete('/v1/libraries/$libraryId/overrides/tracks/$trackId');
}
