import 'package:chordia_api/chordia_api.dart';
import 'package:chordia_mobile/app/theme.dart';
import 'package:chordia_mobile/features/social/data/social_api.dart';
import 'package:chordia_mobile/features/social/data/social_providers.dart';
import 'package:chordia_mobile/features/social/friends_screen.dart';
import 'package:chordia_mobile/features/social/widgets/person_row.dart';
import 'package:chordia_mobile/features/social/widgets/user_identity.dart';
import 'package:chordia_mobile/i18n/keys.g.dart';
import 'package:chordia_mobile/i18n/translations.dart';
import 'package:chordia_mobile/i18n/translations_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Loaded once, in real async: `testWidgets` runs inside a fake-async zone where an asset read
/// never completes, so the catalogs have to be in hand before the first pump.
late Translations translations;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    translations = await Translations.load('en', bundle: rootBundle);
  });

  group('the friend-request state machine', () {
    test('a sent request appears under "sent" and nowhere else', () async {
      final api = FakeSocialApi();
      final container = _container(api);
      final friends = container.read(friendsControllerProvider.notifier);
      await container.read(friendsControllerProvider.future);

      await friends.sendRequest(user('dee'));

      final state = container.read(friendsControllerProvider).requireValue;
      expect(state.outgoing.single.handle, 'dee');
      expect(state.friends, isEmpty);
      expect(state.incoming, isEmpty);
      expect(api.sent, ['dee']);
    });

    test('accepting moves the row from requests into friends', () async {
      final api = FakeSocialApi(incoming: [user('dee')]);
      final container = _container(api);
      final friends = container.read(friendsControllerProvider.notifier);
      await container.read(friendsControllerProvider.future);

      expect(
        container.read(friendsControllerProvider).requireValue.incoming,
        hasLength(1),
      );

      await friends.accept(user('dee'));

      final state = container.read(friendsControllerProvider).requireValue;
      // One row, one place: a move that adds without removing shows the same person twice.
      expect(state.incoming, isEmpty);
      expect(state.friends.single.handle, 'dee');
      expect(api.accepted, ['dee-id']);
    });

    test('declining deletes the edge and drops the row', () async {
      final api = FakeSocialApi(incoming: [user('dee')]);
      final container = _container(api);
      final friends = container.read(friendsControllerProvider.notifier);
      await container.read(friendsControllerProvider.future);

      await friends.decline(user('dee'));

      final state = container.read(friendsControllerProvider).requireValue;
      expect(state.incoming, isEmpty);
      expect(state.friends, isEmpty);
      // Decline and unfriend are the same call: the Hub stores one row per pair.
      expect(api.removed, ['dee-id']);
    });

    test('blocking clears the person from every list at once', () async {
      final api = FakeSocialApi(friends: [user('dee')]);
      final container = _container(api);
      final friends = container.read(friendsControllerProvider.notifier);
      await container.read(friendsControllerProvider.future);

      await friends.block(user('dee'));

      final state = container.read(friendsControllerProvider).requireValue;
      expect(state.friends, isEmpty);
      expect(state.blocked.single.handle, 'dee');
      expect(api.blockedHandles, ['dee']);
    });

    test('a refresh forgets a request the other side has accepted', () async {
      final api = FakeSocialApi();
      final container = _container(api);
      final friends = container.read(friendsControllerProvider.notifier);
      await container.read(friendsControllerProvider.future);
      await friends.sendRequest(user('dee'));

      // The Hub now lists them as a friend, which is the only signal the app gets that a request
      // it sent was answered — there is no "requests I sent" endpoint to ask.
      api.friendsValue = [user('dee')];
      await friends.refresh();

      final state = container.read(friendsControllerProvider).requireValue;
      expect(state.outgoing, isEmpty);
      expect(state.friends.single.handle, 'dee');
    });
  });

  group('optimistic actions', () {
    test('a failed accept puts both lists back and reports why', () async {
      final api = FakeSocialApi(incoming: [user('dee')], failure: _offline);
      final container = _container(api);
      final friends = container.read(friendsControllerProvider.notifier);
      await container.read(friendsControllerProvider.future);

      await expectLater(
        friends.accept(user('dee')),
        throwsA(isA<ApiException>()),
      );

      final state = container.read(friendsControllerProvider).requireValue;
      // Exactly the state before the tap — the row is back where it was, and it did NOT also land
      // in friends on the way through.
      expect(state.incoming.single.handle, 'dee');
      expect(state.friends, isEmpty);
    });

    test('a failed block restores the friendship it had removed', () async {
      final api = FakeSocialApi(friends: [user('dee')], failure: _offline);
      final container = _container(api);
      final friends = container.read(friendsControllerProvider.notifier);
      await container.read(friendsControllerProvider.future);

      await expectLater(
        friends.block(user('dee')),
        throwsA(isA<ApiException>()),
      );

      final state = container.read(friendsControllerProvider).requireValue;
      expect(state.friends.single.handle, 'dee');
      expect(state.blocked, isEmpty);
    });
  });

  group('which way a pending request points', () {
    test('a pending edge in the incoming list is incoming', () {
      final lists = FriendsState(incoming: [user('dee')]);
      expect(
        FriendTie.of(FriendshipStatus.pending, lists, 'dee-id'),
        FriendTie.incoming,
      );
    });

    test('a pending edge that is not in it was sent by the viewer', () {
      const lists = FriendsState();
      expect(
        FriendTie.of(FriendshipStatus.pending, lists, 'dee-id'),
        FriendTie.outgoing,
      );
    });

    test('the viewer\'s own lists outrank what a search result claims', () {
      final lists = FriendsState(blocked: [user('dee')]);
      // The search index can be a moment behind an action taken on this device; the lists cannot.
      expect(
        FriendTie.of(FriendshipStatus.accepted, lists, 'dee-id'),
        FriendTie.blocked,
      );
    });
  });

  group('the friends screen', () {
    testWidgets('accepting a request moves the row into the friends list', (
      tester,
    ) async {
      final api = FakeSocialApi(incoming: [user('dee')]);
      await tester.pumpWidget(_app(api));
      // Two pumps: one for the first frame, one for the lists the controller fetched.
      await tester.pump();
      await tester.pump();

      expect(find.text('Pending requests (1)'), findsOneWidget);
      expect(find.text('Friends (0)'), findsOneWidget);

      await tester.tap(find.text(translations(SocialKeys.requestsAccept)));
      await tester.pump();
      await tester.pump();

      expect(find.text('Pending requests (1)'), findsNothing);
      expect(find.text('Friends (1)'), findsOneWidget);
      expect(api.accepted, ['dee-id']);
    });

    testWidgets('a failed accept leaves the row where it was', (tester) async {
      final api = FakeSocialApi(incoming: [user('dee')], failure: _refused);
      await tester.pumpWidget(_app(api));
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text(translations(SocialKeys.requestsAccept)));
      await tester.pump();
      await tester.pump();

      expect(find.text('Pending requests (1)'), findsOneWidget);
      expect(find.text('Friends (1)'), findsNothing);
      // And the failure is said out loud rather than the row silently snapping back. The Hub's own
      // words, not a client-side guess: the request carried an `Accept-Language` it understands.
      expect(find.text(_refused.title), findsOneWidget);
    });
  });

  group('display flair', () {
    test('reads the colour notations the Hub actually stores', () {
      expect(parseCssColor('#f0a'), const Color(0xffff00aa));
      expect(parseCssColor('#00ff88'), const Color(0xff00ff88));
      expect(parseCssColor('rgb(0, 128, 255)'), const Color(0xff0080ff));
      expect(parseCssColor('rgba(0, 0, 0, 0.5)')?.a, closeTo(0.5, 0.01));
    });

    test('refuses to guess at one it cannot read', () {
      // Inventing a colour would show a paying user a flair they did not choose.
      expect(parseCssColor('oklch(0.7 0.1 200)'), isNull);
      expect(parseCssColor('rebeccapurple'), isNull);
      expect(parseCssColor(null), isNull);
    });
  });
}

const _offline = ApiException(
  status: 0,
  title: 'Could not reach the server.',
  method: 'POST',
  path: '/v1/friends/requests',
);

/// A refusal the Hub worded itself, which is what a screen is meant to repeat back.
const _refused = ApiException(
  status: 403,
  title: 'That account is not accepting friend requests.',
  method: 'POST',
  path: '/v1/friends/requests/dee-id/accept',
);

ProviderContainer _container(FakeSocialApi api) {
  final container = ProviderContainer(
    overrides: [
      socialApiProvider.overrideWithValue(api),
      friendsPollIntervalProvider.overrideWithValue(null),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Widget _app(FakeSocialApi api) => ProviderScope(
  overrides: [
    translationsProvider.overrideWithValue(translations),
    socialApiProvider.overrideWithValue(api),
    // A periodic refresh outliving the test is reported as an unrelated teardown failure.
    friendsPollIntervalProvider.overrideWithValue(null),
  ],
  child: MaterialApp(theme: buildChordiaTheme(), home: const FriendsScreen()),
);

PublicUser user(String handle) => PublicUser(
  displayName: handle.toUpperCase(),
  handle: handle,
  id: '$handle-id',
);

/// A [SocialApi] with no Hub behind it, recording what it was asked to do.
class FakeSocialApi implements SocialApi {
  FakeSocialApi({
    List<PublicUser> friends = const [],
    this.incoming = const [],
    this.blockedValue = const [],
    this.searchResults = const [],
    this.failure,
  }) : friendsValue = friends;

  List<PublicUser> friendsValue;
  final List<PublicUser> incoming;
  final List<PublicUser> blockedValue;
  final List<DiscoveryResult> searchResults;

  /// Thrown by every mutation, for the revert tests. Reads still answer, so the screen has lists
  /// to revert *to*.
  final Object? failure;

  final sent = <String>[];
  final accepted = <String>[];
  final removed = <String>[];
  final blockedHandles = <String>[];
  final unblocked = <String>[];

  Future<void> _mutate(void Function() record) async {
    if (failure != null) throw failure!;
    record();
  }

  @override
  Future<UserProfile> me() async => const UserProfile(
    createdAt: 0,
    displayName: 'Me',
    handle: 'me',
    id: 'me-id',
  );

  @override
  Future<List<PublicUser>> friends() async => friendsValue;

  @override
  Future<List<PublicUser>> incomingRequests() async => incoming;

  @override
  Future<List<PublicUser>> blocked() async => blockedValue;

  @override
  Future<List<FriendNowPlaying>> friendsNowPlaying() async => const [];

  @override
  Future<void> sendFriendRequest(String handle) =>
      _mutate(() => sent.add(handle));

  @override
  Future<void> acceptFriendRequest(String userId) =>
      _mutate(() => accepted.add(userId));

  @override
  Future<void> removeFriend(String userId) =>
      _mutate(() => removed.add(userId));

  @override
  Future<void> block(String handle) =>
      _mutate(() => blockedHandles.add(handle));

  @override
  Future<void> unblock(String handle) => _mutate(() => unblocked.add(handle));

  @override
  Future<List<DiscoveryResult>> searchUsers(String query) async =>
      searchResults;

  @override
  Future<PublicUser> user(String handle) async =>
      PublicUser(displayName: handle, handle: handle, id: '$handle-id');

  @override
  Future<PublicProfile> profile(String handle) async => PublicProfile(
    createdAt: 0,
    private: false,
    recent: const [],
    topArtists: const [],
    topTracks: const [],
    totalPlays: 0,
    user: await user(handle),
  );

  @override
  Future<void> follow(String handle) => _mutate(() {});

  @override
  Future<void> unfollow(String handle) => _mutate(() {});
}
