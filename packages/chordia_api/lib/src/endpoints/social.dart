import '../hub.dart';
import '../json.dart';
import '../models.g.dart';
import 'decode.dart';

/// The social graph, live listening, and the Last.fm link.
///
/// Two different relationships live here and they are not the same thing: **friendship** is mutual
/// and gated by a request (and is what library sharing keys off), while **following** is one-way and
/// needs no consent.
///
/// Now-playing is held in the Hub's memory, never persisted — it is a presence signal, and the
/// durable record of a play is a scrobble.
extension SocialEndpoints on HubClient {
  Future<List<PublicUser>> friends() =>
      get('/v1/friends', (json) => listOf(json, PublicUser.fromJson));

  /// What friends are playing right now. Friends whose scrobble privacy is private are absent
  /// entirely rather than present-but-blank.
  Future<List<FriendNowPlaying>> friendsNowPlaying() => get(
    '/v1/friends/now-playing',
    (json) => listOf(json, FriendNowPlaying.fromJson),
  );

  /// Requests waiting on the caller — incoming only.
  Future<List<PublicUser>> friendRequests() =>
      get('/v1/friends/requests', (json) => listOf(json, PublicUser.fromJson));

  Future<void> sendFriendRequest(FriendRequest request) =>
      post<void>('/v1/friends/requests', discard, body: request.toJson());

  Future<void> acceptFriendRequest(String userId) =>
      post<void>('/v1/friends/requests/$userId/accept', discard);

  /// Ends the friendship both ways, and with it any library share that depended on it.
  Future<void> removeFriend(String userId) => delete('/v1/friends/$userId');

  /// The caller's own live entry, or null when nothing is playing anywhere.
  Future<DeviceNowPlaying?> myNowPlaying() => get(
    '/v1/me/now-playing',
    (json) => json == null ? null : DeviceNowPlaying.fromJson(asObject(json)),
  );

  Future<void> reportNowPlaying(NowPlayingReport report) =>
      post<void>('/v1/me/now-playing', discard, body: report.toJson());

  /// Drops the entry when playback stops. Entries also expire on their own, so a client that dies
  /// without calling this does not leave a ghost.
  Future<void> clearNowPlaying() => delete('/v1/me/now-playing');

  Future<LastfmStatus> lastfmStatus() =>
      get('/v1/lastfm/status', (json) => LastfmStatus.fromJson(asObject(json)));

  /// Trades the token Last.fm handed back at its callback for a durable session key held by the
  /// Hub.
  Future<LastfmStatus> connectLastfm(LastfmSessionRequest request) => post(
    '/v1/lastfm/session',
    (json) => LastfmStatus.fromJson(asObject(json)),
    body: request.toJson(),
  );

  Future<void> disconnectLastfm() =>
      post<void>('/v1/lastfm/disconnect', discard);

  Future<void> followUser(String handle) =>
      put<void>('/v1/users/${seg(handle)}/follow', discard);

  Future<void> unfollowUser(String handle) =>
      delete('/v1/users/${seg(handle)}/follow');

  Future<FollowPage> followers(String handle, {int? limit, int? offset}) => get(
    '/v1/users/${seg(handle)}/followers',
    (json) => FollowPage.fromJson(asObject(json)),
    query: {'limit': limit, 'offset': offset},
  );

  Future<FollowPage> following(String handle, {int? limit, int? offset}) => get(
    '/v1/users/${seg(handle)}/following',
    (json) => FollowPage.fromJson(asObject(json)),
    query: {'limit': limit, 'offset': offset},
  );

  Future<List<ProfileArtist>> userFollowedArtists(String handle) => get(
    '/v1/users/${seg(handle)}/followed-artists',
    (json) => listOf(json, ProfileArtist.fromJson),
  );

  /// Only the account's **published** playlists — private ones never appear here, even to a friend.
  Future<List<Playlist>> userPlaylists(String handle) => get(
    '/v1/users/${seg(handle)}/playlists',
    (json) => listOf(json, Playlist.fromJson),
  );
}
