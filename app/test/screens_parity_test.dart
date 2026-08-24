import 'package:chordia_api/chordia_api.dart';
import 'package:chordia_mobile/features/catalog/data/catalog_providers.dart';
import 'package:chordia_mobile/features/catalog/widgets/list_row.dart';
import 'package:chordia_mobile/features/catalog/widgets/track_list.dart';
import 'package:chordia_mobile/features/catalog/widgets/track_row.dart';
import 'package:chordia_mobile/features/manager/data/releases.dart';
import 'package:chordia_mobile/features/settings/account_screen.dart';
import 'package:chordia_mobile/features/settings/data/image_picking.dart';
import 'package:chordia_mobile/features/settings/data/settings_api.dart';
import 'package:chordia_mobile/features/settings/data/settings_providers.dart';
import 'package:chordia_mobile/i18n/keys.g.dart';
import 'package:chordia_mobile/i18n/translations.dart';
import 'package:chordia_mobile/i18n/translations_provider.dart';
import 'package:chordia_mobile/widgets/tokens.dart';
import 'package:chordia_sync/chordia_sync.dart' show AlbumContext;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The per-screen omissions against the web client, each fixed and each pinned here.
///
/// Every one of these was a finished capability with nothing on the phone able to reach it, which
/// is a failure no test of the capability itself would ever see: `LikedTracksController.toggle`,
/// `groupReleases` and the animated-avatar entitlement all worked. What was missing was the call.
/// So these assertions press what a person would press.
late Translations translations;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    translations = await Translations.load('en', bundle: rootBundle);
  });

  group('a catalog track row carries the like heart', () {
    testWidgets('tapping it toggles that track, and only that track', (
      tester,
    ) async {
      final liked = _FakeLiked({'t2'});
      await _pumpTracks(tester, liked);

      // Two rows, two hearts — the second already filled.
      expect(find.byType(LikeHeart), findsNWidgets(2));
      expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
      expect(
        find.byIcon(Icons.favorite_rounded),
        findsOneWidget,
        reason: 'the row shows liked state at a glance, as the web does',
      );

      await tester.tap(find.byIcon(Icons.favorite_border_rounded));
      await tester.pump();

      // One tap, no sheet. Before this the only route was a long press, a sheet and a scan.
      expect(liked.toggled, ['t1']);
    });

    testWidgets('the heart takes the duration cell, as the web phone row does', (
      tester,
    ) async {
      await _pumpTracks(tester, _FakeLiked(const {}));

      // `hidden … sm:block` on the web (TrackList.tsx:798): keeping both cost ~210px of a 310px
      // row. If the duration comes back, the heart is what gets squeezed out.
      expect(find.text('3:00'), findsNothing);
    });
  });

  group('a discography is collapsed and filterable', () {
    DiscoverReleaseGroup release(
      String mbid, {
      required String title,
      String? type = 'Album',
      String? date,
      String? version,
      bool owned = false,
      String? cover,
    }) => DiscoverReleaseGroup(
      mbid: mbid,
      owned: owned,
      title: title,
      artistMbid: 'a1',
      coverUrl: cover,
      firstReleaseDate: date,
      primaryType: type,
      versionType: version,
    );

    test('editions and eras of one album collapse to a single entry', () {
      final grouped = groupReleases([
        release('1', title: 'Nurture', date: '2021-04-23'),
        release('2', title: 'Nurture (Deluxe)', date: '2021-09-01'),
        release('3', title: 'Nurture - Remastered', date: '2022-01-01'),
        release('4', title: 'Nurture Era', date: '2023-01-01'),
      ]);

      expect(grouped, hasLength(1));
      // The original wins on the shortest title, which is what every qualifier lengthens.
      expect(grouped.single.title, 'Nurture');
    });

    test('a version release survives the collapse', () {
      final grouped = groupReleases([
        release('1', title: 'Nurture', date: '2021-04-23'),
        release('2', title: 'Nurture', date: '2021-04-23', version: 'live'),
      ]);

      // Without the version in the key the live record shares the studio album's base title and
      // disappears entirely — which is the one way this collapse can lose information.
      expect(grouped, hasLength(2));
    });

    test('the owned edition is the one kept', () {
      final grouped = groupReleases([
        release('1', title: 'Nurture (Deluxe)', owned: true),
        release('2', title: 'Nurture'),
      ]);

      expect(grouped.single.mbid, '1');
    });

    test('chips are the types actually present, in the web order', () {
      final grouped = groupReleases([
        release('1', title: 'A Single', type: 'Single'),
        release('2', title: 'An Album'),
        release('3', title: 'A Session', type: 'Broadcast'),
        release('4', title: 'Untyped', type: null),
      ]);

      // RELEASE_TYPE_ORDER, filtered — never the discography's own arrival order, which would
      // reshuffle the control per artist.
      expect(presentReleaseTypes(grouped), [
        'Album',
        'Single',
        'Broadcast',
        'Other',
      ]);
    });

    test('newest first', () {
      final grouped = groupReleases([
        release('1', title: 'Older', date: '1997'),
        release('2', title: 'Newer', date: '2011-06-01'),
      ]);
      expect(grouped.map((r) => r.title), ['Newer', 'Older']);
    });
  });

  group('the animated-avatar entitlement reaches the picker', () {
    testWidgets('an entitled account picks the original bytes', (tester) async {
      final picker = _RecordingPicker();
      await _pumpAccount(tester, picker, features: [Feature.animatedAvatar]);

      await tester.tap(
        find.text(translations(SettingsKeys.accountChangePhoto)),
      );
      await tester.pump();

      // `ImagePicker`'s own resize decodes and re-encodes natively, which draws ONE frame. Asking
      // for it is what was flattening every GIF a subscriber chose.
      expect(picker.allowAnimated, [true]);
    });

    testWidgets('an unentitled account takes the ordinary resize path', (
      tester,
    ) async {
      final picker = _RecordingPicker();
      await _pumpAccount(tester, picker, features: []);

      await tester.tap(
        find.text(translations(SettingsKeys.accountChangePhoto)),
      );
      await tester.pump();

      expect(picker.allowAnimated, [false]);
    });

    testWidgets('a hub with no payment provider unlocks it', (tester) async {
      final picker = _RecordingPicker();
      await _pumpAccount(tester, picker, features: [], billingEnabled: false);

      await tester.tap(
        find.text(translations(SettingsKeys.accountChangePhoto)),
      );
      await tester.pump();

      // A self-hoster must never meet a lock on their own machine.
      expect(picker.allowAnimated, [true]);
    });
  });

  group('the shared list row', () {
    testWidgets('is the web row, not a ListTile', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ListRow(title: Text('Row'), subtitle: Text('Second line')),
          ),
        ),
      );
      await tester.pump();

      // The style is inherited rather than set on each `Text`, so it is read where the text is.
      double sizeOf(String text) =>
          DefaultTextStyle.of(tester.element(find.text(text))).style.fontSize!;

      // Material's row brings its own 56/72px heights, its own insets and its own ink ripple.
      expect(find.byType(ListTile), findsNothing);
      // `font-medium text-sm` over `text-muted-foreground text-xs`, the same pair `TrackRow` uses.
      // Material's `ListTile` gives 16/24 over 14/20 — a size too big on both lines.
      expect(sizeOf('Row'), ChordiaType.sm.fontSize);
      expect(sizeOf('Second line'), ChordiaType.xs.fontSize);
      expect(ChordiaType.sm.fontSize, 14);
      expect(ChordiaType.xs.fontSize, 12);
    });

    testWidgets('clears the coarse-pointer target even with one short line', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: ListRow(title: const Text('Row'), onTap: () {}),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        tester.getSize(find.byType(ListRow)).height,
        greaterThanOrEqualTo(ChordiaControl.xs),
      );
    });
  });
}

/// Two tracks in a `SliverTrackList`, with a liked set that records what it was told.
Future<void> _pumpTracks(WidgetTester tester, _FakeLiked liked) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        translationsProvider.overrideWithValue(translations),
        likedTrackIdsProvider.overrideWith(() => liked),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              SliverTrackList(
                tracks: [_track('t1', 'First'), _track('t2', 'Second')],
                playContext: const AlbumContext(id: 'al', name: 'Album'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  // Fixed frames rather than `pumpAndSettle`: the liked set resolves on a microtask.
  await tester.pump();
  await tester.pump();
}

BrowseTrack _track(String id, String title) => BrowseTrack(
  id: id,
  title: title,
  artist: 'Artist',
  contentHash: 'hash-$id',
  durationMs: 180000,
  libraryId: 'lib',
  trackRef: 'ref-$id',
);

/// The liked set with no Hub behind it. Subclassed rather than faked at the API, because the API
/// is a dozen unrelated reads and this is the only one the heart touches.
class _FakeLiked extends LikedTracksController {
  _FakeLiked(this._initial);

  final Set<String> _initial;
  final toggled = <String>[];

  @override
  Future<Set<String>> build() async => _initial;

  @override
  Future<void> toggle(String trackId) async {
    toggled.add(trackId);
    final before = state.value ?? const <String>{};
    state = AsyncData(
      before.contains(trackId)
          ? ({...before}..remove(trackId))
          : {...before, trackId},
    );
  }
}

/// A picker that never touches a platform channel and remembers how it was asked.
class _RecordingPicker {
  final allowAnimated = <bool>[];

  Future<PickedImage?> call({
    required int maxWidth,
    bool allowAnimated = false,
  }) async {
    this.allowAnimated.add(allowAnimated);
    return PickedImage(
      bytes: Uint8List.fromList([1, 2, 3]),
      contentType: 'image/jpeg',
    );
  }
}

Future<void> _pumpAccount(
  WidgetTester tester,
  _RecordingPicker picker, {
  required List<Feature> features,
  bool billingEnabled = true,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        translationsProvider.overrideWithValue(translations),
        accountApiProvider.overrideWithValue(
          _FakeAccount(
            Entitlements(
              billingEnabled: billingEnabled,
              features: features,
              tier: PlanTier.free,
            ),
          ),
        ),
        imagePickerProvider.overrideWithValue(picker.call),
      ],
      child: const MaterialApp(home: AccountScreen()),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

class _FakeAccount implements AccountApi {
  _FakeAccount(this.entitlements);

  final Entitlements entitlements;

  @override
  Future<UserProfile> profile() async => UserProfile(
    createdAt: 0,
    displayName: 'Me',
    handle: 'me',
    id: 'me-id',
    entitlements: entitlements,
  );

  @override
  Future<PublicProfile> publicProfile(String handle) async => PublicProfile(
    createdAt: 0,
    private: false,
    recent: const [],
    topArtists: const [],
    topTracks: const [],
    totalPlays: 0,
    user: PublicUser(displayName: 'Me', handle: handle, id: 'me-id'),
    links: const [],
  );

  @override
  Future<String> uploadImage(
    List<int> bytes, {
    String contentType = 'application/octet-stream',
  }) async => 'hash';

  @override
  Future<UserProfile> updateProfile(UpdateProfile changes) => profile();

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
