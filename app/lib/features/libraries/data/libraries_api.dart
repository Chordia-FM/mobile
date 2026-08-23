import 'package:chordia_api/chordia_api.dart';

/// Everything the library-management screens ask of the Hub.
///
/// One interface rather than a `HubClient` because the pairing state machine below is the part
/// worth testing, and a fake of eight methods says "the ticket expired" in a line where a fake
/// transport would need a session, a base URL and a socket to say the same thing.
abstract interface class LibrariesApi {
  Future<List<LibrarySummary>> mine();

  Future<List<LibrarySummary>> sharedWithMe();

  Future<LibrarySummary> detail(String libraryId);

  /// Rename, or set the icon. Omitted fields are left alone.
  Future<LibrarySummary> update(String libraryId, UpdateLibraryRequest changes);

  /// Removes the library from the Hub. The audio files on the server are untouched — the Hub
  /// never had them.
  Future<void> remove(String libraryId);

  /// Where the server hosting a library is, and what certificate it advertises.
  Future<ResolvedServer> resolveServer(String serverId);

  /// Owned counts per library, which is the only place exact album and artist totals come from.
  Future<CoverageSummary> coverage();

  Future<List<LibraryShare>> shares(String libraryId);

  /// Grants an accepted friend access. Only a friend — sharing has no invite path of its own.
  Future<void> share(String libraryId, ShareBody body);

  Future<void> revoke(String libraryId, String granteeId);

  Future<List<PublicUser>> friends();

  /// A single-use credential for one pairing handshake, to hand to a library server.
  Future<PairTicket> mintPairTicket();

  /// Registers a logical library on a server that has already been paired.
  Future<LibrarySummary> createLibrary(CreateLibraryRequest request);
}

/// Per-library metadata corrections.
///
/// Separate from [LibrariesApi] because these are a different resource with a different owner
/// question: a share is about who may listen, an override is about what the music is called.
abstract interface class OverridesApi {
  Future<List<LibraryOverrideSummary>> list(String libraryId);

  Future<ArtistOverrideView> artist(String libraryId, String artistId);

  Future<void> putArtist(
    String libraryId,
    String artistId,
    ArtistOverrideInput input,
  );

  Future<void> clearArtist(String libraryId, String artistId);

  Future<AlbumOverrideView> album(String libraryId, String albumId);

  Future<void> putAlbum(
    String libraryId,
    String albumId,
    AlbumOverrideInput input,
  );

  Future<void> clearAlbum(String libraryId, String albumId);

  Future<TrackOverrideView> track(String libraryId, String trackId);

  Future<void> putTrack(
    String libraryId,
    String trackId,
    TrackOverrideInput input,
  );

  Future<void> clearTrack(String libraryId, String trackId);
}

class HubLibrariesApi implements LibrariesApi {
  const HubLibrariesApi(this._hub);

  final HubClient _hub;

  @override
  Future<List<LibrarySummary>> mine() => _hub.libraries();

  @override
  Future<List<LibrarySummary>> sharedWithMe() => _hub.librariesSharedWithMe();

  @override
  Future<LibrarySummary> detail(String libraryId) =>
      _hub.libraryDetail(libraryId);

  @override
  Future<LibrarySummary> update(
    String libraryId,
    UpdateLibraryRequest changes,
  ) => _hub.updateLibrary(libraryId, changes);

  @override
  Future<void> remove(String libraryId) => _hub.deleteLibrary(libraryId);

  @override
  Future<ResolvedServer> resolveServer(String serverId) =>
      _hub.resolveServer(serverId);

  @override
  Future<CoverageSummary> coverage() => _hub.managerCoverage();

  @override
  Future<List<LibraryShare>> shares(String libraryId) =>
      _hub.libraryShares(libraryId);

  @override
  Future<void> share(String libraryId, ShareBody body) =>
      _hub.shareLibrary(libraryId, body);

  @override
  Future<void> revoke(String libraryId, String granteeId) =>
      _hub.revokeLibraryShare(libraryId, granteeId);

  @override
  Future<List<PublicUser>> friends() => _hub.friends();

  @override
  Future<PairTicket> mintPairTicket() => _hub.mintPairTicket();

  @override
  Future<LibrarySummary> createLibrary(CreateLibraryRequest request) =>
      _hub.createLibrary(request);
}

class HubOverridesApi implements OverridesApi {
  const HubOverridesApi(this._hub);

  final HubClient _hub;

  @override
  Future<List<LibraryOverrideSummary>> list(String libraryId) =>
      _hub.libraryOverrides(libraryId);

  @override
  Future<ArtistOverrideView> artist(String libraryId, String artistId) =>
      _hub.artistOverride(libraryId, artistId);

  @override
  Future<void> putArtist(
    String libraryId,
    String artistId,
    ArtistOverrideInput input,
  ) => _hub.putArtistOverride(libraryId, artistId, input);

  @override
  Future<void> clearArtist(String libraryId, String artistId) =>
      _hub.deleteArtistOverride(libraryId, artistId);

  @override
  Future<AlbumOverrideView> album(String libraryId, String albumId) =>
      _hub.albumOverride(libraryId, albumId);

  @override
  Future<void> putAlbum(
    String libraryId,
    String albumId,
    AlbumOverrideInput input,
  ) => _hub.putAlbumOverride(libraryId, albumId, input);

  @override
  Future<void> clearAlbum(String libraryId, String albumId) =>
      _hub.deleteAlbumOverride(libraryId, albumId);

  @override
  Future<TrackOverrideView> track(String libraryId, String trackId) =>
      _hub.trackOverride(libraryId, trackId);

  @override
  Future<void> putTrack(
    String libraryId,
    String trackId,
    TrackOverrideInput input,
  ) => _hub.putTrackOverride(libraryId, trackId, input);

  @override
  Future<void> clearTrack(String libraryId, String trackId) =>
      _hub.deleteTrackOverride(libraryId, trackId);
}
