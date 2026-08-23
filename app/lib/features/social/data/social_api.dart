import 'package:chordia_api/chordia_api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';

/// Everything the social screens ask the Hub for.
///
/// An interface rather than `HubClient` directly, for the same reason the catalog has one:
/// `HubClient`'s call surface is a set of **extension** methods, and extensions dispatch
/// statically, so no subclass could ever intercept them. Without this seam a widget test for
/// "accepting a request moves the row" would need a live server.
abstract interface class SocialApi {
  /// The signed-in account, for the "is this me" checks every person row makes.
  Future<UserProfile> me();

  Future<List<PublicUser>> friends();

  /// Requests waiting on the caller. The Hub has no matching list of requests the caller has
  /// **sent** — see [FriendsController] for how the app tracks those.
  Future<List<PublicUser>> incomingRequests();

  Future<List<PublicUser>> blocked();

  Future<List<FriendNowPlaying>> friendsNowPlaying();

  Future<void> sendFriendRequest(String handle);

  Future<void> acceptFriendRequest(String userId);

  /// Deletes the friendship edge, whatever state it is in.
  ///
  /// One call covers three user-facing actions — unfriend, decline an incoming request, cancel one
  /// you sent — because the Hub stores a single row per pair and `DELETE /v1/friends/{id}` removes
  /// it regardless of `status`. The three are separate methods on the controller so the copy and
  /// the optimistic move can differ; they are not separate calls.
  Future<void> removeFriend(String userId);

  Future<void> block(String handle);

  Future<void> unblock(String handle);

  Future<List<DiscoveryResult>> searchUsers(String query);

  /// One account by handle — the fallback for "add by handle" when search matched nothing.
  Future<PublicUser> user(String handle);

  Future<PublicProfile> profile(String handle);

  Future<void> follow(String handle);

  Future<void> unfollow(String handle);
}

/// [SocialApi] over the real Hub.
class HubSocialApi implements SocialApi {
  const HubSocialApi(this._hub);

  final HubClient _hub;

  @override
  Future<UserProfile> me() => _hub.me();

  @override
  Future<List<PublicUser>> friends() => _hub.friends();

  @override
  Future<List<PublicUser>> incomingRequests() => _hub.friendRequests();

  // Moderation is the one group `chordia_api` has no typed extension for yet, so these three go
  // through `HubClient`'s generic verbs. They carry the same session, language header and refresh
  // behaviour as every generated call — the only thing missing upstream is the spelling.
  @override
  Future<List<PublicUser>> blocked() => _hub.get('/v1/me/blocks', _publicUsers);

  @override
  Future<void> block(String handle) =>
      _hub.post<void>('/v1/users/${Uri.encodeComponent(handle)}/block', _drop);

  @override
  Future<void> unblock(String handle) =>
      _hub.delete('/v1/users/${Uri.encodeComponent(handle)}/block');

  @override
  Future<List<FriendNowPlaying>> friendsNowPlaying() =>
      _hub.friendsNowPlaying();

  @override
  Future<void> sendFriendRequest(String handle) =>
      _hub.sendFriendRequest(FriendRequest(targetHandle: handle));

  @override
  Future<void> acceptFriendRequest(String userId) =>
      _hub.acceptFriendRequest(userId);

  @override
  Future<void> removeFriend(String userId) => _hub.removeFriend(userId);

  @override
  Future<List<DiscoveryResult>> searchUsers(String query) =>
      _hub.searchUsers(query);

  @override
  Future<PublicUser> user(String handle) => _hub.user(handle);

  @override
  Future<PublicProfile> profile(String handle) => _hub.userProfile(handle);

  @override
  Future<void> follow(String handle) => _hub.followUser(handle);

  @override
  Future<void> unfollow(String handle) => _hub.unfollowUser(handle);
}

/// A JSON array of [PublicUser], for the one endpoint decoded by hand here.
List<PublicUser> _publicUsers(Object? json) => json is List
    ? json
          .whereType<Map<Object?, Object?>>()
          .map((e) => PublicUser.fromJson(Map<String, Object?>.from(e)))
          .toList()
    : const [];

/// Reads nothing from a 204.
void _drop(Object? _) {}

/// Thrown when a social screen is somehow reached with no hub selected.
///
/// The router only admits these screens behind a signed-in session, which implies an active hub.
/// Surfacing it as an error the retry button can act on beats a null check that renders an empty
/// page and explains nothing.
class SocialUnavailableException implements Exception {
  const SocialUnavailableException();

  @override
  String toString() =>
      'No hub is selected, so the social graph cannot be read.';
}

/// The social call surface for the active hub. Overridden with a fake in tests.
final socialApiProvider = Provider<SocialApi>((ref) {
  final hub = ref.watch(hubClientProvider);
  if (hub == null) throw const SocialUnavailableException();
  return HubSocialApi(hub);
});
