import 'dart:convert';
import 'dart:io';

import 'package:chordia_api/chordia_api.dart';

/// Everything the playlist EDITING surfaces ask of the Hub.
///
/// Narrower than `HubClient` on purpose, and separate from `features/library`'s `PlaylistApi`,
/// which covers reading one playlist and reordering it. The split is by what a test needs to say:
/// the controllers here are about creating, deleting and inviting, and pinning them to an
/// interface lets a test state "this call fails" without a transport, a session or a base URL.
abstract interface class PlaylistsApi {
  Future<List<Playlist>> playlists();

  Future<Playlist> create(CreatePlaylistRequest request);

  Future<void> delete(String playlistId);

  Future<void> update(String playlistId, PlaylistPatch changes);

  Future<void> addTrack(String playlistId, String trackId);

  Future<List<PublicUser>> collaborators(String playlistId);

  /// Invites by handle. The Hub resolves it to a user, so a bad handle is a server error rather
  /// than something this client can check first.
  Future<void> addCollaborator(String playlistId, String handle);

  Future<void> removeCollaborator(String playlistId, String userId);

  /// Stores an image and answers with the content hash to reference it by.
  Future<String> uploadImage(List<int> bytes);

  Future<void> setCover(String playlistId, String hash);

  Future<void> clearCover(String playlistId);

  /// The signed-in user's own id — what "leave this playlist" removes.
  Future<String> myUserId();
}

/// The rule-driven half, which has its own resource on the Hub and none of the calls above.
abstract interface class SmartPlaylistsApi {
  Future<SmartPlaylist> create(SmartBody body);

  /// A PUT: an omitted field is a CLEARED field, not an unchanged one. Callers send the whole
  /// body every time.
  Future<void> update(String playlistId, SmartBody body);

  Future<void> delete(String playlistId);

  /// What these rules would match right now, saving nothing.
  Future<SmartPreview> preview(SmartRules rules);
}

class HubPlaylistsApi implements PlaylistsApi {
  const HubPlaylistsApi(this._hub);

  final HubClient _hub;

  @override
  Future<List<Playlist>> playlists() => _hub.playlists();

  @override
  Future<Playlist> create(CreatePlaylistRequest request) =>
      _hub.createPlaylist(request);

  @override
  Future<void> delete(String playlistId) => _hub.deletePlaylist(playlistId);

  @override
  Future<void> update(String playlistId, PlaylistPatch changes) =>
      _hub.updatePlaylist(playlistId, changes);

  @override
  Future<void> addTrack(String playlistId, String trackId) =>
      _hub.addPlaylistTrack(playlistId, TrackBody(trackId: trackId));

  @override
  Future<List<PublicUser>> collaborators(String playlistId) =>
      _hub.playlistCollaborators(playlistId);

  @override
  Future<void> addCollaborator(String playlistId, String handle) => _hub
      .addPlaylistCollaborator(playlistId, CollaboratorBody(handle: handle));

  @override
  Future<void> removeCollaborator(String playlistId, String userId) =>
      _hub.removePlaylistCollaborator(playlistId, userId);

  @override
  Future<String> uploadImage(List<int> bytes) => uploadHubImage(_hub, bytes);

  @override
  Future<void> setCover(String playlistId, String hash) =>
      _hub.setPlaylistCover(playlistId, CoverBody(hash: hash));

  @override
  Future<void> clearCover(String playlistId) =>
      _hub.clearPlaylistCover(playlistId);

  @override
  Future<String> myUserId() async => (await _hub.me()).id;
}

class HubSmartPlaylistsApi implements SmartPlaylistsApi {
  const HubSmartPlaylistsApi(this._hub);

  final HubClient _hub;

  @override
  Future<SmartPlaylist> create(SmartBody body) =>
      _hub.createSmartPlaylist(body);

  @override
  Future<void> update(String playlistId, SmartBody body) =>
      _hub.updateSmartPlaylist(playlistId, body);

  @override
  Future<void> delete(String playlistId) =>
      _hub.deleteSmartPlaylist(playlistId);

  @override
  Future<SmartPreview> preview(SmartRules rules) => _hub.previewSmart(rules);
}

/// `POST /v1/images` — the one Hub call that sends bytes rather than JSON.
///
/// It lives here rather than in `chordia_api` because that package's transport is a JSON
/// transport by design: it sets `Content-Type: application/json` on every body it writes, and
/// widening it so one endpoint can post a PNG would make every other call able to do the same by
/// accident. The socket still comes from the shared factory, so this is not a second, unpinned way
/// onto the network — the Hub is a public host and is validated against the system trust store,
/// exactly as `HubClient` validates it.
///
/// Answers with the content hash the Hub stored the image under. That hash — not a URL — is what
/// every cover, avatar and override input takes.
Future<String> uploadHubImage(HubClient hub, List<int> bytes) async {
  const maxBytes = 8 * 1024 * 1024;
  if (bytes.isEmpty) {
    throw const ApiException(
      status: 0,
      title: 'The chosen image was empty.',
      method: 'POST',
      path: '/v1/images',
    );
  }
  if (bytes.length > maxBytes) {
    // Checked here as well as server-side so an eight-megabyte photo fails before it is uploaded
    // over a phone connection to be refused at the far end.
    throw const ApiException(
      status: 413,
      title: 'That image is too large.',
      method: 'POST',
      path: '/v1/images',
    );
  }

  final client = hub.factory.unpinned();
  try {
    final token = await hub.sessions.freshAccessToken();
    final url = hub.baseUrl.replace(path: '${hub.baseUrl.path}/v1/images');
    final request = await client.postUrl(url);
    request.headers
      ..set(HttpHeaders.acceptHeader, 'application/json')
      ..set(HttpHeaders.contentTypeHeader, imageMimeOf(bytes));
    if (token != null) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
    request.add(bytes);

    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();
    final decoded = text.isEmpty ? null : jsonDecode(text);
    if (response.statusCode >= 400) {
      throw ApiException.fromProblem(
        status: response.statusCode,
        method: 'POST',
        path: '/v1/images',
        body: decoded,
        fallbackTitle: response.reasonPhrase,
      );
    }
    final hash = decoded is Map ? decoded['hash'] : null;
    if (hash is! String || hash.isEmpty) {
      throw ApiException(
        status: response.statusCode,
        title: 'The server stored the image but did not say where.',
        method: 'POST',
        path: '/v1/images',
      );
    }
    return hash;
  } finally {
    client.close(force: true);
  }
}

/// The mime type for [bytes], read from the file's own magic number.
///
/// The Hub decodes the image and takes the mime from ITS decoder, so this header is only a hint —
/// but sending `application/octet-stream` for a JPEG makes the request look like an upload of
/// something unknown in every log and proxy between here and there.
String imageMimeOf(List<int> bytes) {
  bool startsWith(List<int> magic) {
    if (bytes.length < magic.length) return false;
    for (var i = 0; i < magic.length; i++) {
      if (bytes[i] != magic[i]) return false;
    }
    return true;
  }

  if (startsWith(const [0x89, 0x50, 0x4E, 0x47])) return 'image/png';
  if (startsWith(const [0xFF, 0xD8, 0xFF])) return 'image/jpeg';
  if (startsWith(const [0x47, 0x49, 0x46])) return 'image/gif';
  // RIFF….WEBP — the four bytes at offset 8 are what separate WebP from every other RIFF file.
  if (startsWith(const [0x52, 0x49, 0x46, 0x46]) &&
      bytes.length > 12 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50) {
    return 'image/webp';
  }
  return 'application/octet-stream';
}
