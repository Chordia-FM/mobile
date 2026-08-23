import 'package:chordia_api/chordia_api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../data/social_api.dart' show SocialUnavailableException;
import '../data/social_providers.dart' show noAutoRetry;

/// The reads a profile makes **beyond** the one `PublicProfile` round trip.
///
/// The profile DTO already carries the first page of every shelf, so none of this is needed to
/// paint the page — it is what "See all" and the follower/following tabs ask for once somebody
/// opens them. On the web these are `useFollowers` / `useFollowing` / `useUserPlaylists` /
/// `useFollowedArtists` in `lib/api/queries.ts`, plus `hub.report`.
///
/// A seam of its own rather than four more methods on [SocialApi] (`data/social_api.dart`): that
/// interface is implemented by hand in the social tests, so widening it there would break a file
/// this port does not own. The shape is the same — an interface a widget test can substitute,
/// because the test binding answers every real request with a 400.
abstract interface class ProfileReads {
  /// One page of a listener's followers. A 404 here is the visibility gate, not a missing person:
  /// the Hub answers "not visible to you" and "no such handle" identically so neither can be
  /// probed.
  Future<FollowPage> followers(String handle, {int offset});

  Future<FollowPage> following(String handle, {int offset});

  /// Every published playlist, for "See all" — the profile shelf carries only the first twelve.
  Future<List<Playlist>> playlists(String handle);

  Future<List<ProfileArtist>> followedArtists(String handle);

  /// Files a moderation report. The Hub answers 204 whether or not it acted, so there is nothing
  /// here to read back.
  Future<void> report(String handle, String reason);
}

/// [ProfileReads] over the real Hub.
class HubProfileReads implements ProfileReads {
  const HubProfileReads(this._hub);

  final HubClient _hub;

  @override
  Future<FollowPage> followers(String handle, {int offset = 0}) =>
      _hub.followers(handle, offset: offset);

  @override
  Future<FollowPage> following(String handle, {int offset = 0}) =>
      _hub.following(handle, offset: offset);

  @override
  Future<List<Playlist>> playlists(String handle) => _hub.userPlaylists(handle);

  @override
  Future<List<ProfileArtist>> followedArtists(String handle) =>
      _hub.userFollowedArtists(handle);

  // Moderation has no typed extension in `chordia_api` yet, so this goes through `HubClient`'s
  // generic verbs — same session, same language header, same refresh behaviour.
  @override
  Future<void> report(String handle, String reason) => _hub.post<void>(
    '/v1/reports',
    (_) {},
    body: {'target_handle': handle, 'reason': reason},
  );
}

final profileReadsProvider = Provider<ProfileReads>((ref) {
  final hub = ref.watch(hubClientProvider);
  if (hub == null) throw const SocialUnavailableException();
  return HubProfileReads(hub);
});

/// A page of one direction of the follow graph, keyed by handle **and** offset.
///
/// The offset is part of the key on purpose: a page already fetched stays cached while the next
/// one is in flight, which is what lets the list keep its rows instead of blanking on "Load more".
typedef FollowQuery = ({String handle, bool followers, int offset});

final followPageProvider = FutureProvider.autoDispose
    .family<FollowPage, FollowQuery>(
      (ref, query) => query.followers
          ? ref
                .watch(profileReadsProvider)
                .followers(query.handle, offset: query.offset)
          : ref
                .watch(profileReadsProvider)
                .following(query.handle, offset: query.offset),
      retry: noAutoRetry,
    );

/// Every published playlist of one account. Only read once "See all" is pressed.
final allUserPlaylistsProvider = FutureProvider.autoDispose
    .family<List<Playlist>, String>(
      (ref, handle) => ref.watch(profileReadsProvider).playlists(handle),
      retry: noAutoRetry,
    );

/// Every artist one account follows. Only read once "See all" is pressed.
final allFollowedArtistsProvider = FutureProvider.autoDispose
    .family<List<ProfileArtist>, String>(
      (ref, handle) => ref.watch(profileReadsProvider).followedArtists(handle),
      retry: noAutoRetry,
    );
