import '../hub.dart';
import '../json.dart';
import '../models.g.dart';
import 'decode.dart';

/// Browsing the catalog the Hub assembles from every library the caller can reach.
///
/// The recurring `libraryId` argument narrows a view to one library. Left out — the usual case —
/// the Hub answers across all of them, having already merged the same recording appearing in
/// several. It is a filter on one collection, not a choice of which collection to read.
extension CatalogEndpoints on HubClient {
  Future<SearchResults> searchCatalog(String query) => get(
    '/v1/catalog/search',
    (json) => SearchResults.fromJson(asObject(json)),
    query: {'q': query},
  );

  Future<List<BrowseArtist>> artists({String? libraryId}) => get(
    '/v1/catalog/artists',
    (json) => listOf(json, BrowseArtist.fromJson),
    query: {'library_id': libraryId},
  );

  Future<ArtistDetail> artist(String artistId, {String? libraryId}) => get(
    '/v1/catalog/artists/$artistId',
    (json) => ArtistDetail.fromJson(asObject(json)),
    query: {'library_id': libraryId},
  );

  Future<List<BrowseAlbum>> artistAlbums(
    String artistId, {
    String? libraryId,
  }) => get(
    '/v1/catalog/artists/$artistId/albums',
    (json) => listOf(json, BrowseAlbum.fromJson),
    query: {'library_id': libraryId},
  );

  /// Artwork candidates from fanart.tv, for the metadata editor's picker. Empty when the artist has
  /// no MusicBrainz id or the Hub has no fanart.tv key — not an error.
  Future<ArtOptions> artistArtOptions(String artistId) => get(
    '/v1/catalog/artists/$artistId/art',
    (json) => ArtOptions.fromJson(asObject(json)),
  );

  /// A collection built on the fly from the caller's owned live material, not a stored album row.
  Future<LiveAlbum> artistLiveAlbum(String artistId, {String? libraryId}) =>
      get(
        '/v1/catalog/artists/$artistId/live-album',
        (json) => LiveAlbum.fromJson(asObject(json)),
        query: {'library_id': libraryId},
      );

  Future<List<Playlist>> artistPlaylists(String artistId) => get(
    '/v1/catalog/artists/$artistId/playlists',
    (json) => listOf(json, Playlist.fromJson),
  );

  Future<List<BrowseArtist>> similarArtists(
    String artistId, {
    String? libraryId,
  }) => get(
    '/v1/catalog/artists/$artistId/similar',
    (json) => listOf(json, BrowseArtist.fromJson),
    query: {'library_id': libraryId},
  );

  Future<AlbumDetail> album(String albumId, {String? libraryId}) => get(
    '/v1/catalog/albums/$albumId',
    (json) => AlbumDetail.fromJson(asObject(json)),
    query: {'library_id': libraryId},
  );

  /// Cover candidates from the Cover Art Archive. Empty without an MBID.
  Future<ArtOptions> albumArtOptions(String albumId) => get(
    '/v1/catalog/albums/$albumId/art',
    (json) => ArtOptions.fromJson(asObject(json)),
  );

  Future<List<BrowseTrack>> albumTracks(String albumId, {String? libraryId}) =>
      get(
        '/v1/catalog/albums/$albumId/tracks',
        (json) => listOf(json, BrowseTrack.fromJson),
        query: {'library_id': libraryId},
      );

  /// One track with a freshly counted play total — how the now-playing panel keeps its count
  /// current without re-fetching the whole album.
  Future<BrowseTrack> track(String trackId) => get(
    '/v1/catalog/tracks/$trackId',
    (json) => BrowseTrack.fromJson(asObject(json)),
  );

  Future<List<GenreSummary>> genres({String? libraryId}) => get(
    '/v1/catalog/genres',
    (json) => listOf(json, GenreSummary.fromJson),
    query: {'library_id': libraryId},
  );

  Future<GenreDetail> genre(String slug, {String? libraryId}) => get(
    '/v1/catalog/genres/${seg(slug)}',
    (json) => GenreDetail.fromJson(asObject(json)),
    query: {'library_id': libraryId},
  );

  Future<List<LabelSummary>> labels({String? libraryId}) => get(
    '/v1/catalog/labels',
    (json) => listOf(json, LabelSummary.fromJson),
    query: {'library_id': libraryId},
  );

  Future<LabelDetail> label(String labelId, {String? libraryId}) => get(
    '/v1/catalog/labels/$labelId',
    (json) => LabelDetail.fromJson(asObject(json)),
    query: {'library_id': libraryId},
  );

  /// The "Unlabeled" bucket: albums with no label linked. A [LabelDetail] like any other so the
  /// screen that renders a label renders this too.
  Future<LabelDetail> unlabeledAlbums({String? libraryId}) => get(
    '/v1/catalog/labels/unlabeled',
    (json) => LabelDetail.fromJson(asObject(json)),
    query: {'library_id': libraryId},
  );

  /// Clears the enrichment stamps on the caller's catalog so the Hub's workers look everything up
  /// again. Answers with how many rows were reset.
  ///
  /// The count is read out of an undeclared `{"reset": n}` body — the handler returns raw JSON, so
  /// the schema has no shape for the generator to emit.
  Future<int> reenrichCatalog() =>
      post('/v1/catalog/reenrich', (json) => asInt(asObject(json)['reset']));
}
