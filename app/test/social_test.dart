import 'package:chordia_api/chordia_api.dart';
import 'package:chordia_mobile/app/theme.dart';
import 'package:chordia_mobile/features/social/data/social_api.dart';
import 'package:chordia_mobile/features/social/data/social_providers.dart';
import 'package:chordia_mobile/features/insights/insights_routes.dart';
import 'package:chordia_mobile/features/settings/account_screen.dart';
import 'package:chordia_mobile/features/settings/data/image_picking.dart';
import 'package:chordia_mobile/features/settings/data/settings_api.dart';
import 'package:chordia_mobile/features/settings/data/settings_providers.dart';
import 'package:chordia_mobile/features/social/friends_screen.dart';
import 'package:chordia_mobile/features/social/profile_screen.dart';
import 'package:chordia_mobile/features/social/social_routes.dart';
import 'package:chordia_mobile/features/social/widgets/follow_list.dart';
import 'package:chordia_mobile/features/social/widgets/profile_reads.dart';
import 'package:chordia_mobile/features/social/widgets/person_row.dart';
import 'package:chordia_mobile/features/social/widgets/user_identity.dart';
import 'package:chordia_mobile/i18n/keys.g.dart';
import 'package:chordia_mobile/i18n/translations.dart';
import 'package:chordia_mobile/i18n/translations_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';

/// Loaded once, in real async: `testWidgets` runs inside a fake-async zone where an asset read
/// never completes, so the catalogs have to be in hand before the first pump.
late Translations translations;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // A profile header prints the month somebody joined; the app does this in bootstrap, and a
    // test that renders one has to do it too.
    await initializeDateFormatting();
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

  group('reaching your own profile', () {
    testWidgets('the You tab resolves a route onto it without knowing your handle', (
      tester,
    ) async {
      // The one thing that made this unreachable: a session restored from the keystore carries
      // tokens, not a profile, so no screen can link to `u/{handle}` from what it already holds.
      // The route has to resolve the account first — which is what this asserts it does.
      final api = FakeSocialApi();
      await tester.pumpWidget(_routed(api, '/you/insights'));
      await tester.pump();
      await tester.pump();

      expect(find.byType(ProfileScreen), findsOneWidget);
      // Their own profile, not a stranger's: the handle came from the account read.
      expect(find.textContaining('@me'), findsWidgets);
    });

    testWidgets('somebody else\'s profile is the same page under u/:handle', (
      tester,
    ) async {
      final api = FakeSocialApi();
      await tester.pumpWidget(_routed(api, '/you/u/dee'));
      await tester.pump();
      await tester.pump();

      expect(find.byType(ProfileScreen), findsOneWidget);
      expect(find.textContaining('@dee'), findsWidgets);
    });
  });

  group('the follower and following lists', () {
    testWidgets('load the next page under the rows already read', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final reads = FakeProfileReads(followerCount: 5, pageSize: 3);
      await tester.pumpWidget(
        _panel(
          reads,
          const FollowList(handle: 'dee', followers: true, own: false),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('@f0'), findsOneWidget);
      expect(find.text('@f3'), findsNothing);
      expect(reads.followerOffsets, [0]);

      await tester.tap(find.text(translations(SocialKeys.profileLoadMore)));
      await tester.pump();
      await tester.pump();

      // Asked for at the offset the first page ended at, and appended rather than swapped in.
      expect(reads.followerOffsets, [0, 3]);
      expect(find.text('@f0'), findsOneWidget);
      expect(find.text('@f4'), findsOneWidget);
      // Every row is in hand, so there is nothing left to offer.
      expect(find.text(translations(SocialKeys.profileLoadMore)), findsNothing);
    });

    testWidgets('following asks the other direction of the graph', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final reads = FakeProfileReads(followerCount: 2, pageSize: 3);
      await tester.pumpWidget(
        _panel(
          reads,
          const FollowList(handle: 'dee', followers: false, own: false),
        ),
      );
      await tester.pump();
      await tester.pump();

      // Two lists, two endpoints: reading the wrong one shows a person the follows they receive
      // under the heading for the ones they give.
      expect(reads.followingOffsets, [0]);
      expect(reads.followerOffsets, isEmpty);
    });
  });

  // Editing your public profile is a settings screen, but it is the same profile these tests are
  // about — and `settings_test.dart` belongs to another port, so the coverage lives here.
  group('editing your public profile', () {
    testWidgets('choosing a photo uploads the bytes and stores the hash', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final account = FakeAccountApi();
      _ignoreSettingsInkWarning();
      await tester.pumpWidget(_account(account));
      await tester.pump();
      await tester.pump();

      await tester.tap(
        find.widgetWithText(
          OutlinedButton,
          translations(SettingsKeys.accountChangePhoto),
        ),
      );
      await tester.pump();
      await tester.pump();

      // The raw file goes up as bytes, with the picker's own content type on it.
      expect(account.uploaded.single, [1, 2, 3]);
      expect(account.uploadedTypes.single, 'image/jpeg');
      // And the avatar is pointed at what came back. An avatar takes the PATH the hash resolves
      // to, not the bare hash — sending the wrong one of the two is a silent server-side no-op.
      expect(account.saved.single.avatarUrl, '/v1/images/abc123');
    });

    testWidgets('a banner is stored by bare hash, not by path', (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final account = FakeAccountApi();
      _ignoreSettingsInkWarning();
      await tester.pumpWidget(_account(account));
      await tester.pump();
      await tester.pump();

      await tester.tap(
        find.widgetWithText(
          OutlinedButton,
          translations(SettingsKeys.profileChooseBanner),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(account.saved.single.bannerHash, 'abc123');
      expect(account.saved.single.avatarUrl, isNull);
    });

    testWidgets('the bio and links save together, in one PATCH', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final account = FakeAccountApi();
      _ignoreSettingsInkWarning();
      await tester.pumpWidget(_account(account));
      await tester.pump();
      await tester.pump();

      await tester.enterText(
        find.widgetWithText(TextField, translations(SettingsKeys.profileBio)),
        'Mostly drums.',
      );
      await tester.pump();
      await tester.tap(
        find.widgetWithText(
          OutlinedButton,
          translations(SettingsKeys.profileAddLink),
        ),
      );
      await tester.pump();
      await tester.enterText(
        find.widgetWithText(
          TextFormField,
          translations(SettingsKeys.profileLinkUrl),
        ),
        'https://example.com',
      );
      await tester.pump();

      await tester.tap(
        find.widgetWithText(
          FilledButton,
          translations(SettingsKeys.accountSaveProfile),
        ),
      );
      await tester.pump();
      await tester.pump();

      // The Hub takes one PATCH, so bio and links ride together — a second request would be a
      // second chance to half-save an edit.
      expect(account.saved, hasLength(1));
      expect(account.saved.single.bio, 'Mostly drums.');
      expect(account.saved.single.links?.single.kind, 'website');
      expect(account.saved.single.links?.single.url, 'https://example.com');
    });

    testWidgets('a link that is not https holds the save', (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final account = FakeAccountApi();
      _ignoreSettingsInkWarning();
      await tester.pumpWidget(_account(account));
      await tester.pump();
      await tester.pump();

      await tester.tap(
        find.widgetWithText(
          OutlinedButton,
          translations(SettingsKeys.profileAddLink),
        ),
      );
      await tester.pump();
      await tester.enterText(
        find.widgetWithText(
          TextFormField,
          translations(SettingsKeys.profileLinkUrl),
        ),
        'example.com',
      );
      await tester.pump();

      // Bio, name, handle and links all ride in ONE PATCH, so one malformed row would fail the
      // whole save and lose the rest of the edit.
      final save = tester.widget<FilledButton>(
        find.widgetWithText(
          FilledButton,
          translations(SettingsKeys.accountSaveProfile),
        ),
      );
      expect(save.onPressed, isNull);
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

/// The You tab's route table, with nothing above it but a router.
///
/// The real shell is four branches deep and drags the player in with it; what is under test is
/// whether these paths RESOLVE to the right screen, which is a property of the route table.
Widget _routed(FakeSocialApi api, String location) => ProviderScope(
  overrides: [
    translationsProvider.overrideWithValue(translations),
    socialApiProvider.overrideWithValue(api),
    friendsPollIntervalProvider.overrideWithValue(null),
  ],
  child: MaterialApp.router(
    theme: buildChordiaTheme(),
    routerConfig: GoRouter(
      initialLocation: location,
      routes: [
        GoRoute(
          path: '/you',
          builder: (context, state) => const Scaffold(),
          routes: [...socialRoutes(), ...insightsRoutes()],
        ),
      ],
    ),
  ),
);

/// One profile panel, with a fake behind the reads it makes beyond the profile DTO.
Widget _panel(FakeProfileReads reads, Widget panel) => ProviderScope(
  overrides: [
    translationsProvider.overrideWithValue(translations),
    profileReadsProvider.overrideWithValue(reads),
  ],
  child: MaterialApp(
    theme: buildChordiaTheme(),
    home: Scaffold(body: SingleChildScrollView(child: panel)),
  ),
);

/// Swallows one debug-only assertion the settings list has always raised.
///
/// `SettingsSection` draws its card as a `DecoratedBox` and puts `ListTile`s inside it, which
/// Flutter warns about because the tile's ink splash paints on the nearest `Material` above that
/// box. It fires once per row on every settings screen, predates this port, and is not what these
/// tests are about — a widget test treats any framework error as a failure, so twenty copies of it
/// would bury a real one.
void _ignoreSettingsInkWarning() {
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exceptionAsString().contains('ink splashes may be invisible')) {
      return;
    }
    previous?.call(details);
  };
  addTearDown(() => FlutterError.onError = previous);
}

/// The Account screen with a fake Hub and a fake image picker behind it.
Widget _account(FakeAccountApi account) => ProviderScope(
  overrides: [
    translationsProvider.overrideWithValue(translations),
    accountApiProvider.overrideWithValue(account),
    // The test binding answers every platform channel with an error, so a real picker would fail
    // on the channel rather than on anything under test.
    imagePickerProvider.overrideWithValue(
      ({required int maxWidth}) async => PickedImage(
        bytes: Uint8List.fromList([1, 2, 3]),
        contentType: 'image/jpeg',
      ),
    ),
  ],
  child: MaterialApp(theme: buildChordiaTheme(), home: const AccountScreen()),
);

/// A [ProfileReads] with no Hub behind it, recording the offsets it was asked for.
class FakeProfileReads implements ProfileReads {
  FakeProfileReads({required this.followerCount, required this.pageSize});

  /// How many rows each list holds, across every page.
  final int followerCount;
  final int pageSize;

  final followerOffsets = <int>[];
  final followingOffsets = <int>[];

  FollowPage _page(int offset) {
    final rows = (followerCount - offset).clamp(0, pageSize);
    return FollowPage(
      items: [
        for (var i = 0; i < rows; i++)
          FollowUser(
            followsViewer: false,
            isFriend: false,
            user: user('f${offset + i}'),
            viewerFollows: false,
          ),
      ],
      total: followerCount,
      nextOffset: offset + rows >= followerCount ? null : offset + rows,
    );
  }

  @override
  Future<FollowPage> followers(String handle, {int offset = 0}) async {
    followerOffsets.add(offset);
    return _page(offset);
  }

  @override
  Future<FollowPage> following(String handle, {int offset = 0}) async {
    followingOffsets.add(offset);
    return _page(offset);
  }

  @override
  Future<List<Playlist>> playlists(String handle) async => const [];

  @override
  Future<List<ProfileArtist>> followedArtists(String handle) async => const [];

  @override
  Future<void> report(String handle, String reason) async {}
}

/// An [AccountApi] with no Hub behind it, recording every write.
class FakeAccountApi implements AccountApi {
  final uploaded = <List<int>>[];
  final uploadedTypes = <String>[];
  final saved = <UpdateProfile>[];

  @override
  Future<UserProfile> profile() async => const UserProfile(
    createdAt: 0,
    displayName: 'Me',
    handle: 'me',
    id: 'me-id',
  );

  @override
  Future<PublicProfile> publicProfile(String handle) async => PublicProfile(
    createdAt: 0,
    private: false,
    recent: const [],
    topArtists: const [],
    topTracks: const [],
    totalPlays: 0,
    user: user(handle),
    links: const [],
  );

  @override
  Future<String> uploadImage(
    List<int> bytes, {
    String contentType = 'application/octet-stream',
  }) async {
    uploaded.add(bytes);
    uploadedTypes.add(contentType);
    return 'abc123';
  }

  @override
  Future<UserProfile> updateProfile(UpdateProfile changes) async {
    saved.add(changes);
    return profile();
  }

  @override
  Future<AccountInfo> account() async => const AccountInfo(
    discordLinked: false,
    emailVerified: true,
    hasPassword: true,
    totpEnabled: false,
    email: 'me@example.com',
  );

  @override
  Future<void> requestEmailVerification() async {}

  @override
  Future<void> requestEmailChange(String email) async {}

  @override
  Future<void> changePassword(ChangePasswordRequest request) async {}

  @override
  Future<void> requestPasswordSet() async {}

  @override
  Future<void> deleteAccount() async {}
}

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
