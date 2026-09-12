import '../hub.dart';
import '../json.dart';
import '../models.g.dart';
import 'decode.dart';

/// The library directory: which collections exist, who they belong to, and who else may reach them.
///
/// A *library* here is a logical collection registered with the Hub, not the server hosting it —
/// one paired server can host several. None of these calls touch audio; reaching the bytes needs a
/// capability token, which `GrantManager` mints.
///
/// The pairing handshake itself (`POST /v1/libraries/pair`) is missing on purpose: it is
/// authenticated as a *server*, not a user, and a phone never performs it.
extension LibraryEndpoints on HubClient {
  /// Libraries the caller owns, in their chosen order.
  Future<List<LibrarySummary>> libraries() =>
      get('/v1/libraries', (json) => listOf(json, LibrarySummary.fromJson));

  /// Registers a logical library on a server the caller has already paired.
  Future<LibrarySummary> createLibrary(CreateLibraryRequest request) => post(
    '/v1/libraries',
    (json) => LibrarySummary.fromJson(asObject(json)),
    body: request.toJson(),
  );

  Future<List<LibrarySummary>> librariesSharedWithMe() => get(
    '/v1/libraries/shared-with-me',
    (json) => listOf(json, LibrarySummary.fromJson),
  );

  /// Sets the priority order. It decides which library serves a track that several of them hold.
  Future<void> reorderLibraries(ReorderRequest order) =>
      put<void>('/v1/libraries/order', discard, body: order.toJson());

  /// Mints a single-use credential for one pairing handshake, to hand to a library server that is
  /// being set up.
  ///
  /// [libraryUrl] is the address the ticket is for, and it is required: the Hub binds the ticket to
  /// that origin and refuses a redemption claiming a different one, so a caller that named no
  /// address would be asking for a ticket any host could spend. The redeeming library has to
  /// forward the same origin back (`X-Pair-Origin`), which is why the claim sends it too.
  Future<PairTicket> mintPairTicket({required String libraryUrl}) => post(
    '/v1/libraries/pair-ticket',
    (json) => PairTicket.fromJson(asObject(json)),
    body: {'library_url': libraryUrl},
  );

  Future<LibrarySummary> libraryDetail(String libraryId) => get(
    '/v1/libraries/$libraryId',
    (json) => LibrarySummary.fromJson(asObject(json)),
  );

  Future<LibrarySummary> updateLibrary(
    String libraryId,
    UpdateLibraryRequest changes,
  ) => patch(
    '/v1/libraries/$libraryId',
    (json) => LibrarySummary.fromJson(asObject(json)),
    body: changes.toJson(),
  );

  /// Removes a library the caller owns, and its catalog with it. The files on the library server
  /// are untouched — the Hub never had them.
  Future<void> deleteLibrary(String libraryId) =>
      delete('/v1/libraries/$libraryId');

  Future<List<LibraryShare>> libraryShares(String libraryId) => get(
    '/v1/libraries/$libraryId/shares',
    (json) => listOf(json, LibraryShare.fromJson),
  );

  /// Grants an accepted friend access. Only a friend — sharing has no invite path of its own.
  Future<void> shareLibrary(String libraryId, ShareBody share) => post<void>(
    '/v1/libraries/$libraryId/shares',
    discard,
    body: share.toJson(),
  );

  Future<void> revokeLibraryShare(String libraryId, String granteeId) =>
      delete('/v1/libraries/$libraryId/shares/$granteeId');
}
