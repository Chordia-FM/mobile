import 'dart:convert';
import 'dart:io';

import '../errors.dart';
import '../hub.dart';
import '../json.dart';
import '../models.g.dart';
import 'decode.dart';

/// The caller's own account, and other people's public profiles.
extension UserEndpoints on HubClient {
  /// What this Hub is, before anyone has signed in.
  ///
  /// Unauthenticated by necessity: a client calls this on a URL the user has just typed, and a 200
  /// with this shape *is* the answer to "is there a Chordia Hub here".
  Future<InstanceInfo> instance() => get(
    '/v1/instance',
    (json) => InstanceInfo.fromJson(asObject(json)),
    authenticated: false,
  );

  Future<UserProfile> me() =>
      get('/v1/me', (json) => UserProfile.fromJson(asObject(json)));

  Future<UserProfile> updateProfile(UpdateProfile changes) => patch(
    '/v1/me',
    (json) => UserProfile.fromJson(asObject(json)),
    body: changes.toJson(),
  );

  /// Erases the account and everything attached to it. Irreversible, and the Hub asks nothing
  /// further — the confirmation is the client's job.
  Future<void> deleteAccount() => delete('/v1/me');

  /// Which credentials the account has (password, Discord, 2FA) and the address it logs in with.
  Future<AccountInfo> account() =>
      get('/v1/me/account', (json) => AccountInfo.fromJson(asObject(json)));

  Future<UserSettings> settings() =>
      get('/v1/me/settings', (json) => UserSettings.fromJson(asObject(json)));

  /// Replaces the settings wholesale. Send the full object read from [settings] with the fields
  /// changed, not a delta.
  Future<UserSettings> saveSettings(UserSettings updated) => put(
    '/v1/me/settings',
    (json) => UserSettings.fromJson(asObject(json)),
    body: updated.toJson(),
  );

  Future<PublicUser> user(String handle) => get(
    '/v1/users/${seg(handle)}',
    (json) => PublicUser.fromJson(asObject(json)),
  );

  /// The full public profile: identity, follow graph, shelves and listening activity in one round
  /// trip. What each section contains still depends on the target's privacy settings.
  Future<PublicProfile> userProfile(String handle) => get(
    '/v1/users/${seg(handle)}/profile',
    (json) => PublicProfile.fromJson(asObject(json)),
  );

  /// The badge directory: every badge, who holds it, and whether it is still gettable.
  ///
  /// Tagged `users` rather than `user` in the OpenAPI document; it lives here because it is the
  /// only member of that tag and it is read for profiles.
  Future<List<BadgeCatalogEntry>> badges() =>
      get('/v1/badges', (json) => listOf(json, BadgeCatalogEntry.fromJson));
}

/// Uploading an image blob to the Hub's content-addressed store.
///
/// Separate from [UserEndpoints] because it is the one Hub call that does **not** send JSON: the
/// body is the raw file, and the content type is what the Hub's decoder keys off. It lives beside
/// the profile because avatars and banners are the only reason this client uploads an image at
/// all — a banner is set by hash (`UpdateProfile.bannerHash`) and an avatar by the path the hash
/// resolves to (`UpdateProfile.avatarUrl`), and neither can be set without this call first.
extension ImageEndpoints on HubClient {
  /// What `POST /v1/images` refuses above — mirrors `MAX_BYTES` in backend/src/api/v1/images.rs.
  ///
  /// Checked here as well as there because a phone photo is routinely 10-15 MB: pushing it over a
  /// mobile uplink only to be told no wastes the whole upload, and the caller can downscale.
  static const maxImageBytes = 8 * 1024 * 1024;

  /// Stores [bytes] and answers with the sha256 the Hub filed them under.
  ///
  /// The Hub decodes the image itself and derives the stored mime from the decoder, so
  /// [contentType] is a hint rather than a declaration — but sending the picker's own type is what
  /// lets an animated GIF stay animated for an account entitled to one.
  Future<String> uploadImage(
    List<int> bytes, {
    String contentType = 'application/octet-stream',
  }) async {
    if (bytes.isEmpty) {
      throw const ApiException(
        status: 0,
        title: 'That file is empty.',
        method: 'POST',
        path: '/v1/images',
      );
    }
    if (bytes.length > maxImageBytes) {
      throw const ApiException(
        status: 0,
        title: 'That image is too large.',
        method: 'POST',
        path: '/v1/images',
      );
    }

    final url = baseUrl.replace(path: '${baseUrl.path}/v1/images');
    try {
      final first = await sessions.freshAccessToken();
      final response = await _postBytes(url, bytes, contentType, first);
      // One retry on 401, the same shape `HubClient` uses for every JSON call: an access token can
      // expire between the freshness check and the socket, and re-picking the photo is not a
      // reasonable thing to ask of somebody for that.
      if (response.status == 401) {
        final refreshed = await sessions.forceRefresh();
        if (refreshed != null) {
          final retry = await _postBytes(
            url,
            bytes,
            contentType,
            refreshed.accessToken,
          );
          return _hashOf(retry);
        }
      }
      return _hashOf(response);
    } on ApiException {
      rethrow;
    } on Object catch (e) {
      final mismatch = factory.takeLastMismatch();
      throw ApiException(
        status: 0,
        title: mismatch != null
            ? 'This server presented an unexpected certificate.'
            : 'Could not reach the server.',
        method: 'POST',
        path: '/v1/images',
        detail: (mismatch ?? e).toString(),
        cause: mismatch ?? e,
      );
    }
  }

  Future<_RawResponse> _postBytes(
    Uri url,
    List<int> bytes,
    String contentType,
    String? token,
  ) async {
    final client = factory.unpinned();
    try {
      final request = await client.postUrl(url);
      request.headers
        ..set(HttpHeaders.acceptHeader, 'application/json')
        ..set(HttpHeaders.contentTypeHeader, contentType);
      if (token != null) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }
      request.add(bytes);
      final response = await request.close();
      final text = await response.transform(utf8.decoder).join();
      return _RawResponse(response.statusCode, response.reasonPhrase, text);
    } finally {
      client.close(force: true);
    }
  }

  String _hashOf(_RawResponse response) {
    Object? decoded;
    try {
      decoded = response.body.isEmpty ? null : jsonDecode(response.body);
    } on FormatException {
      decoded = null;
    }
    if (response.status >= 400) {
      throw ApiException.fromProblem(
        status: response.status,
        method: 'POST',
        path: '/v1/images',
        body: decoded,
        fallbackTitle: response.reason,
      );
    }
    return CoverBody.fromJson(asObject(decoded)).hash;
  }
}

/// One raw HTTP answer, before it is known whether it is a hash or a problem document.
class _RawResponse {
  const _RawResponse(this.status, this.reason, this.body);

  final int status;
  final String reason;
  final String body;
}
