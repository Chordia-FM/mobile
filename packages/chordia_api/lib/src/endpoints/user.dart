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
