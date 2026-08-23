import 'dart:async';
import 'dart:io';

import 'package:chordia_api/chordia_api.dart';
import 'package:chordia_mobile/app/providers.dart';
import 'package:chordia_mobile/app/theme.dart';
import 'package:chordia_mobile/data/art/art_cache.dart';
import 'package:chordia_mobile/features/insights/data/insights_api.dart';
import 'package:chordia_mobile/features/insights/widgets/insights_tabs.dart';
import 'package:chordia_mobile/features/social/data/social_api.dart';
import 'package:chordia_mobile/features/social/profile_screen.dart';
import 'package:chordia_mobile/features/social/widgets/profile_banner.dart';
import 'package:chordia_mobile/features/social/widgets/profile_reads.dart';
import 'package:chordia_mobile/i18n/keys.g.dart';
import 'package:chordia_mobile/i18n/translations.dart';
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
    translations = await Translations.load('en', bundle: rootBundle);
    // The joined-date line formats a month name, which `intl` refuses to do until its locale
    // data is loaded — `bootstrap` does this before the first frame for the same reason.
    await initializeDateFormatting();
  });

  group('the profile is the insights surface', () {
    testWidgets('somebody else: identity, then the reports as tabs inside it', (
      tester,
    ) async {
      await tester.pumpWidget(_app(FakeSocialApi(), handle: 'dee'));
      await _settle(tester);

      // Identity first — this is a profile, not a table of numbers about a person.
      expect(find.text('DEE'), findsWidgets);
      expect(find.textContaining('@dee'), findsOneWidget);
      // …and the report is a tab strip WITHIN it, not a screen of its own.
      expect(find.byType(InsightsTabView), findsOneWidget);
      expect(
        find.text(translations(InsightsKeys.tabsOverview)),
        findsOneWidget,
      );
      expect(find.text(translations(InsightsKeys.tabsCharts)), findsOneWidget);
      // Someone else's page offers the action that only makes sense there.
      expect(find.text(translations(SocialKeys.followFollow)), findsOneWidget);
      // Social is measured against the VIEWER, so it never appears under another person's name.
      expect(find.text(translations(InsightsKeys.tabsSocial)), findsNothing);
    });

    testWidgets('your own: the same page, with your own actions', (
      tester,
    ) async {
      await tester.pumpWidget(_app(FakeSocialApi(), handle: 'me'));
      await _settle(tester);

      expect(find.text('Me'), findsWidgets);
      expect(find.byType(InsightsTabView), findsOneWidget);
      // Follow is not offered on yourself, and neither is the "not accepting follows" line that
      // stands in for it on a closed account.
      expect(find.text(translations(SocialKeys.followFollow)), findsNothing);
      expect(find.text(translations(SocialKeys.followNotOpen)), findsNothing);
      // The one tab that is only ever about the viewer.
      expect(find.text(translations(InsightsKeys.tabsSocial)), findsOneWidget);
    });
  });

  group('the header', () {
    testWidgets('a banner reserves its box before the image resolves', (
      tester,
    ) async {
      // Nothing decodes here — the fake art cache has no file for any hash — so a box of the right
      // height at this point is the guard the web comment describes: the page must not grow under
      // the reader when the picture lands.
      await tester.pumpWidget(
        _app(FakeSocialApi(banner: '/v1/images/${'a' * 64}'), handle: 'dee'),
      );
      await _settle(tester);

      final box = tester.getSize(find.byType(ProfileBanner));
      expect(box.height, greaterThan(0));
      expect(box.height, closeTo(box.width / 3, 0.5));
    });

    testWidgets('a profile with no banner does not collapse', (tester) async {
      await tester.pumpWidget(_app(FakeSocialApi(), handle: 'dee'));
      await _settle(tester);

      // No picture is no box — and the identity under it is still all there.
      expect(tester.getSize(find.byType(ProfileBanner)).height, 0);
      expect(find.text('DEE'), findsWidgets);
      expect(find.textContaining('@dee'), findsOneWidget);
    });

    testWidgets('badges render, staff by its role', (tester) async {
      await tester.pumpWidget(
        _app(
          FakeSocialApi(
            badges: const [
              ProfileBadgeStaff(role: StaffRole.moderator),
              ProfileBadgeDeveloper(title: 'Developer'),
            ],
          ),
          handle: 'dee',
        ),
      );
      await _settle(tester);

      // "Staff" alone leaves the reader with the question the badge exists to answer.
      expect(
        find.text(translations(SocialKeys.badgesStaffModerator)),
        findsOne,
      );
      expect(
        find.text(translations(SocialKeys.badgesDirectoryNameDeveloper)),
        findsOne,
      );
    });

    testWidgets('links open a sheet that names every destination', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          FakeSocialApi(
            links: const [
              ProfileLink(kind: 'instagram', url: 'https://example.test/i'),
              ProfileLink(kind: 'spotify', url: 'https://example.test/s'),
            ],
          ),
          handle: 'dee',
        ),
      );
      await _settle(tester);

      await tester.tap(find.text(translations(SocialKeys.followLinksOpen)));
      await _settle(tester);

      // Named, and in the web's platform order rather than the order the Hub happened to store.
      expect(find.text('Spotify'), findsOneWidget);
      expect(find.text('Instagram'), findsOneWidget);
      final spotify = tester.getTopLeft(find.text('Spotify')).dy;
      final instagram = tester.getTopLeft(find.text('Instagram')).dy;
      expect(spotify, lessThan(instagram));
    });
  });

  group('the shelves', () {
    testWidgets('tapping a followed artist opens their page', (tester) async {
      await tester.pumpWidget(
        _app(
          FakeSocialApi(
            followingVisible: true,
            artists: const [
              ProfileArtist(
                artistMbid: 'mbid-1',
                name: 'Boards of Canada',
                artistId: 'artist-1',
              ),
            ],
          ),
          handle: 'dee',
        ),
      );
      await _settle(tester);

      // Followed artists live under the Following tab, because following is one question.
      await tester.tap(
        find.textContaining(translations(SocialKeys.profileStatsFollowing)),
      );
      await _settle(tester);

      // The shelf is below the fold on an 800px viewport; a tap that lands outside it hits
      // nothing, and a navigation assertion would then pass or fail for the wrong reason.
      await tester.ensureVisible(find.text('Boards of Canada'));
      await _settle(tester);
      await tester.tap(find.text('Boards of Canada'));
      await _settle(tester);

      expect(find.text('artist page artist-1'), findsOneWidget);
    });

    testWidgets('an artist this hub cannot resolve is not tappable', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          FakeSocialApi(
            followingVisible: true,
            // Followed by MBID alone: nowhere in this hub's catalog to open.
            artists: const [
              ProfileArtist(artistMbid: 'mbid-2', name: 'Unresolved'),
            ],
          ),
          handle: 'dee',
        ),
      );
      await _settle(tester);
      await tester.tap(
        find.textContaining(translations(SocialKeys.profileStatsFollowing)),
      );
      await _settle(tester);

      // The shelf is below the fold on an 800px viewport; a tap that lands outside it hits
      // nothing, and a navigation assertion would then pass or fail for the wrong reason.
      await tester.ensureVisible(find.text('Unresolved'));
      await _settle(tester);
      await tester.tap(find.text('Unresolved'));
      await _settle(tester);

      expect(find.text('Unresolved'), findsOneWidget);
      expect(find.textContaining('artist page'), findsNothing);
    });

    testWidgets('the playlist shelf is what the playlists tab shows', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          FakeSocialApi(
            playlists: const [
              Playlist(
                createdAt: 0,
                id: 'pl-1',
                name: 'Late night',
                trackCount: 9,
                visibility: PlaylistVisibility.public,
              ),
            ],
          ),
          handle: 'dee',
        ),
      );
      await _settle(tester);

      expect(
        find.text(translations(SocialKeys.profileShelvesPlaylists)),
        findsOneWidget,
      );
      expect(find.text('Late night'), findsOneWidget);
    });
  });
}

// ── the harness ───────────────────────────────────────────────────────────────────────────────

/// Fixed frames rather than `pumpAndSettle`: the player ticks twice a second, so settling never
/// completes anywhere this app is mounted.
Future<void> _settle(WidgetTester tester) async {
  for (var frame = 0; frame < 6; frame++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

/// The profile under a router, so the shelves' real "open this artist" path is what gets exercised
/// rather than a stand-in the test wrote itself.
Widget _app(FakeSocialApi api, {required String handle}) => ProviderScope(
  overrides: [
    translationsProvider.overrideWithValue(translations),
    socialApiProvider.overrideWithValue(api),
    profileReadsProvider.overrideWithValue(const FakeProfileReads()),
    insightsApiProvider.overrideWithValue(SilentInsightsApi()),
    // The real one resolves a platform directory, which no test binding provides.
    artCacheProvider.overrideWithValue(
      ArtCache(
        directory: Future.value(Directory.systemTemp),
        fetch: (sha, width) => throw ArtMissingException(sha),
      ),
    ),
  ],
  child: MaterialApp.router(
    theme: buildChordiaTheme(),
    routerConfig: GoRouter(
      initialLocation: '/you/u/$handle',
      routes: [
        GoRoute(
          path: '/you',
          builder: (context, state) => const SizedBox.shrink(),
          routes: [
            GoRoute(
              path: 'u/:handle',
              builder: (context, state) =>
                  ProfileScreen(handle: state.pathParameters['handle']!),
            ),
            // Stands in for the catalog's artist screen, which would go to the Hub.
            GoRoute(
              path: 'artists/:artistId',
              builder: (context, state) => Scaffold(
                body: Text('artist page ${state.pathParameters['artistId']}'),
              ),
            ),
          ],
        ),
      ],
    ),
  ),
);

/// A [SocialApi] with no Hub behind it, answering about one person.
class FakeSocialApi implements SocialApi {
  FakeSocialApi({
    this.banner,
    this.badges,
    this.links,
    this.playlists,
    this.artists,
    this.followingVisible = false,
  });

  final String? banner;
  final List<ProfileBadge>? badges;
  final List<ProfileLink>? links;
  final List<Playlist>? playlists;
  final List<ProfileArtist>? artists;
  final bool followingVisible;

  @override
  Future<UserProfile> me() async => const UserProfile(
    createdAt: 0,
    displayName: 'Me',
    handle: 'me',
    id: 'me-id',
  );

  @override
  Future<PublicUser> user(String handle) async => PublicUser(
    displayName: handle == 'me' ? 'Me' : handle.toUpperCase(),
    handle: handle,
    id: '$handle-id',
  );

  @override
  Future<PublicProfile> profile(String handle) async => PublicProfile(
    createdAt: 0,
    private: false,
    recent: const [],
    topArtists: const [],
    topTracks: const [],
    totalPlays: 12,
    user: await user(handle),
    bannerUrl: banner,
    badges: badges,
    links: links,
    playlists: playlists ?? const [],
    playlistCount: playlists?.length ?? 0,
    followedArtists: artists,
    followingVisible: followingVisible,
    followingCount: artists?.length ?? 0,
    // Never on your own profile — the Hub answers false there, and the page must not offer it.
    canFollow: handle != 'me',
  );

  @override
  Future<List<PublicUser>> friends() async => const [];

  @override
  Future<List<PublicUser>> incomingRequests() async => const [];

  @override
  Future<List<PublicUser>> blocked() async => const [];

  @override
  Future<List<FriendNowPlaying>> friendsNowPlaying() async => const [];

  @override
  Future<List<DiscoveryResult>> searchUsers(String query) async => const [];

  @override
  Future<void> sendFriendRequest(String handle) async {}

  @override
  Future<void> acceptFriendRequest(String userId) async {}

  @override
  Future<void> removeFriend(String userId) async {}

  @override
  Future<void> block(String handle) async {}

  @override
  Future<void> unblock(String handle) async {}

  @override
  Future<void> follow(String handle) async {}

  @override
  Future<void> unfollow(String handle) async {}
}

/// The paged reads nothing in these tests presses. Answering with empty pages rather than throwing
/// keeps a failure here about the thing being asserted.
class FakeProfileReads implements ProfileReads {
  const FakeProfileReads();

  @override
  Future<FollowPage> followers(String handle, {int offset = 0}) async =>
      const FollowPage(items: [], total: 0);

  @override
  Future<FollowPage> following(String handle, {int offset = 0}) async =>
      const FollowPage(items: [], total: 0);

  @override
  Future<List<Playlist>> playlists(String handle) async => const [];

  @override
  Future<List<ProfileArtist>> followedArtists(String handle) async => const [];

  @override
  Future<void> report(String handle, String reason) async {}
}

/// An [InsightsApi] that never answers.
///
/// The reports are somebody else's port and are asserted in `insights_test.dart`; what this file
/// is about is that they hang off the PROFILE. A request that never completes leaves each report
/// in its loading state, with no timer left behind for the teardown to complain about.
class SilentInsightsApi implements InsightsApi {
  @override
  dynamic noSuchMethod(Invocation invocation) => Completer<Never>().future;
}
