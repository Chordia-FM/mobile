import 'dart:async';

import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/mesh/providers.dart' show realtimeEventBusProvider;
import '../../../data/mesh/realtime_event.dart';
import 'social_api.dart';

/// Riverpod 3 retries an errored provider on its own, with a backoff.
///
/// Switched off for every read here, for the reason the catalog switched it off: these screens
/// already show a failure with a Retry button, and a silent background retry both contradicts that
/// button and leaves a pending timer behind in widget tests.
Duration? noAutoRetry(int attempt, Object error) => null;

/// The signed-in account.
///
/// Read from the Hub rather than from `authControllerProvider`, whose `user` is only populated when
/// the session was established in this run of the app — a session restored from the keystore
/// carries tokens, not a profile, and every "is this me" check on a person row would then be false.
final viewerProvider = FutureProvider<UserProfile>(
  (ref) => ref.watch(socialApiProvider).me(),
  retry: noAutoRetry,
);

/// The friends list, the requests either side of it, and who the viewer has blocked.
///
/// One value rather than four providers because every action moves a row **between** these lists,
/// and an optimistic move that lands in two providers at two different frames is a row that
/// visibly exists twice.
@immutable
class FriendsState {
  const FriendsState({
    this.friends = const [],
    this.incoming = const [],
    this.outgoing = const [],
    this.blocked = const [],
  });

  final List<PublicUser> friends;

  /// Requests waiting on the viewer.
  final List<PublicUser> incoming;

  /// Requests the viewer has sent that are still pending.
  ///
  /// **This app's own record, not the Hub's.** The Hub exposes incoming requests only, so the one
  /// honest thing a client can show is what it has sent in this run — see [FriendsController].
  final List<PublicUser> outgoing;

  final List<PublicUser> blocked;

  bool get isEmpty =>
      friends.isEmpty &&
      incoming.isEmpty &&
      outgoing.isEmpty &&
      blocked.isEmpty;

  FriendsState copyWith({
    List<PublicUser>? friends,
    List<PublicUser>? incoming,
    List<PublicUser>? outgoing,
    List<PublicUser>? blocked,
  }) => FriendsState(
    friends: friends ?? this.friends,
    incoming: incoming ?? this.incoming,
    outgoing: outgoing ?? this.outgoing,
    blocked: blocked ?? this.blocked,
  );
}

/// The friend-request state machine, with every action applied optimistically.
///
/// Each action moves the row **before** the request goes out and restores the whole previous state
/// if it fails, then rethrows so the screen can say why. Snapshotting the entire [FriendsState]
/// rather than the one list it touched is what makes a revert exact: blocking someone removes them
/// from three lists at once, and restoring only the list the action started in would leave the
/// other two holding a person who is now blocked.
class FriendsController extends AsyncNotifier<FriendsState> {
  /// Requests sent in this run of the app.
  ///
  /// A field on the notifier rather than part of the fetched state, because it has to survive
  /// [build] re-running on a refresh — Riverpod keeps the notifier instance and only re-runs the
  /// method. It is deliberately **not** persisted to disk: the Hub has no "requests I sent"
  /// endpoint, so a stored entry could only be re-checked by asking about a row that no longer
  /// exists, and an app that reopens showing a request the other person declined last week is
  /// worse than one that shows nothing.
  final _sent = <String, PublicUser>{};

  @override
  Future<FriendsState> build() async {
    final api = ref.watch(socialApiProvider);
    final results = await Future.wait([
      api.friends(),
      api.incomingRequests(),
      api.blocked(),
    ]);
    final friends = results[0];
    final incoming = results[1];
    final blocked = results[2];

    // Anyone who has since accepted appears in `friends`, and anyone blocked either way has had
    // their edge deleted — so a refresh is also how a stale "sent" row clears itself.
    final settled = {
      for (final user in friends) user.id,
      for (final user in incoming) user.id,
      for (final user in blocked) user.id,
    };
    _sent.removeWhere((id, _) => settled.contains(id));

    return FriendsState(
      friends: friends,
      incoming: incoming,
      outgoing: _sent.values.toList(),
      blocked: blocked,
    );
  }

  SocialApi get _api => ref.read(socialApiProvider);

  /// Sends a request and shows it under "Sent" straight away.
  Future<void> sendRequest(PublicUser user) => _mutate(
    (s) => s.copyWith(outgoing: [user, ...s.outgoing]),
    () => _api.sendFriendRequest(user.handle),
    onSuccess: () => _sent[user.id] = user,
  );

  /// Accepts an incoming request: the row leaves Requests and arrives in Friends.
  Future<void> accept(PublicUser user) => _mutate(
    (s) => s.copyWith(
      incoming: _without(s.incoming, user),
      friends: [user, ...s.friends],
    ),
    () => _api.acceptFriendRequest(user.id),
  );

  /// Declines an incoming request. Deletes the same edge [remove] does.
  Future<void> decline(PublicUser user) => _mutate(
    (s) => s.copyWith(incoming: _without(s.incoming, user)),
    () => _api.removeFriend(user.id),
  );

  /// Withdraws a request the viewer sent.
  Future<void> cancelRequest(PublicUser user) => _mutate(
    (s) => s.copyWith(outgoing: _without(s.outgoing, user)),
    () => _api.removeFriend(user.id),
    onSuccess: () => _sent.remove(user.id),
  );

  Future<void> remove(PublicUser user) => _mutate(
    (s) => s.copyWith(friends: _without(s.friends, user)),
    () => _api.removeFriend(user.id),
  );

  /// Blocks an account, which on the Hub also severs the friendship, the shares and the follows in
  /// both directions — so the row leaves every list here at once.
  Future<void> block(PublicUser user) => _mutate(
    (s) => s.copyWith(
      friends: _without(s.friends, user),
      incoming: _without(s.incoming, user),
      outgoing: _without(s.outgoing, user),
      blocked: [user, ...s.blocked],
    ),
    () => _api.block(user.handle),
    onSuccess: () => _sent.remove(user.id),
  );

  Future<void> unblock(PublicUser user) => _mutate(
    (s) => s.copyWith(blocked: _without(s.blocked, user)),
    () => _api.unblock(user.handle),
  );

  Future<void> refresh() async {
    state = await AsyncValue.guard(build);
  }

  static List<PublicUser> _without(List<PublicUser> users, PublicUser user) =>
      users.where((u) => u.id != user.id).toList();

  /// Applies [apply], runs [server], and puts the previous state back if it throws.
  ///
  /// The error is rethrown rather than swallowed: the row snapping back is the app saying
  /// something went wrong, and a message saying *what* is the screen's job.
  Future<void> _mutate(
    FriendsState Function(FriendsState) apply,
    Future<void> Function() server, {
    VoidCallback? onSuccess,
  }) async {
    final snapshot = state.value;
    if (snapshot == null) {
      // No lists loaded to move a row within — a profile screen can be the first social surface a
      // session opens. The action still has to reach the Hub; the next read picks the change up.
      await server();
      onSuccess?.call();
      return;
    }
    state = AsyncData(apply(snapshot));
    try {
      await server();
    } on Object {
      state = AsyncData(snapshot);
      rethrow;
    }
    onSuccess?.call();
  }
}

final friendsControllerProvider =
    AsyncNotifierProvider<FriendsController, FriendsState>(
      FriendsController.new,
      retry: noAutoRetry,
    );

/// How often the "listening now" strip re-asks when no socket push has arrived.
///
/// Overridable so a widget test can switch polling off — a periodic timer outliving the test is
/// reported as a teardown failure rather than as the thing it is.
final friendsPollIntervalProvider = Provider<Duration?>(
  (ref) => const Duration(seconds: 30),
);

/// What friends are playing right now.
///
/// Pushed rather than polled where possible: the Hub emits a `social` event when a friend's
/// now-playing or scrobble lands, and the interval below is only a backstop for a dropped socket.
/// Friends whose scrobble privacy is private are absent from the answer entirely, so there is
/// nothing here to filter.
final friendsListeningProvider =
    StreamProvider.autoDispose<List<FriendNowPlaying>>((ref) {
      final api = ref.watch(socialApiProvider);
      final controller = StreamController<List<FriendNowPlaying>>();
      var disposed = false;

      Future<void> load() async {
        try {
          final live = await api.friendsNowPlaying();
          if (!disposed) controller.add(live);
        } on Object catch (error, stack) {
          if (!disposed) controller.addError(error, stack);
        }
      }

      unawaited(load());

      final interval = ref.watch(friendsPollIntervalProvider);
      final timer = interval == null
          ? null
          : Timer.periodic(interval, (_) => unawaited(load()));
      final pushes = ref
          .watch(realtimeEventBusProvider)
          .keys
          .where((key) => key == RealtimeEventKind.social.wire)
          .listen((_) => unawaited(load()));

      ref.onDispose(() {
        disposed = true;
        timer?.cancel();
        unawaited(pushes.cancel());
        unawaited(controller.close());
      });
      return controller.stream;
    });

/// People matching a typed query, annotated with the viewer's relationship to each.
final peopleSearchProvider = FutureProvider.autoDispose
    .family<List<DiscoveryResult>, String>((ref, query) {
      final trimmed = query.trim();
      if (trimmed.isEmpty) return Future.value(const <DiscoveryResult>[]);
      return ref.watch(socialApiProvider).searchUsers(trimmed);
    }, retry: noAutoRetry);

/// One account by handle, for adding somebody search did not surface.
final userByHandleProvider = FutureProvider.autoDispose
    .family<PublicUser, String>(
      (ref, handle) => ref.watch(socialApiProvider).user(handle),
      retry: noAutoRetry,
    );

/// A listener's public profile: identity, follow graph, shelves and activity in one round trip.
final publicProfileProvider = FutureProvider.autoDispose
    .family<PublicProfile, String>(
      (ref, handle) => ref.watch(socialApiProvider).profile(handle),
      retry: noAutoRetry,
    );

/// Follow and unfollow, applied optimistically over the fetched profile.
///
/// Keyed by handle so two profiles open in one navigation stack cannot share a pending state.
class FollowController extends Notifier<bool?> {
  FollowController(this.handle);

  final String handle;

  /// Null until the viewer has changed something here; the profile's own `viewer_follows` is the
  /// truth otherwise, and defaulting to false would render "Follow" on someone you follow for as
  /// long as the profile took to load.
  @override
  bool? build() => null;

  Future<void> setFollowing({required bool following}) async {
    final previous = state;
    state = following;
    try {
      final api = ref.read(socialApiProvider);
      if (following) {
        await api.follow(handle);
      } else {
        await api.unfollow(handle);
      }
    } on Object {
      state = previous;
      rethrow;
    }
    // The counts on the profile moved with it, so the fetched copy is now stale.
    ref.invalidate(publicProfileProvider(handle));
  }
}

final followControllerProvider =
    NotifierProvider.family<FollowController, bool?, String>(
      FollowController.new,
    );
