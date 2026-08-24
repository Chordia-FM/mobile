import '../errors.dart';
import '../hub.dart';
import '../json.dart';
import '../models.g.dart';
import 'decode.dart';
import 'images.dart';

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
/// Separate from [UserEndpoints] because it does **not** send JSON: the body is the raw file, and
/// the content type is what the Hub's decoder keys off, so it rides [ByteBodyEndpoints.postBytes]
/// rather than the JSON transport. It lives beside the profile because avatars and banners are the
/// only reason this client uploads an image at all — a banner is set by hash
/// (`UpdateProfile.bannerHash`) and an avatar by the path the hash resolves to
/// (`UpdateProfile.avatarUrl`), and neither can be set without this call first.
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
    // `async` is here for the two guards, not for the send: without it a refused file would be a
    // synchronous throw, which a caller that holds the future and catches later would miss.
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

    return postBytes(
      '/v1/images',
      (json) => CoverBody.fromJson(asObject(json)).hash,
      bytes: bytes,
      contentType: contentType,
    );
  }
}
