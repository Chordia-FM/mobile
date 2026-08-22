import 'dart:io';

import 'package:chordia_api/chordia_api.dart';
import 'package:chordia_mobile/app/providers.dart';
import 'package:chordia_mobile/app/theme.dart';
import 'package:chordia_mobile/data/art/art_cache.dart';
import 'package:chordia_mobile/features/admin/admin_entry_tile.dart';
import 'package:chordia_mobile/features/admin/admin_screen.dart';
import 'package:chordia_mobile/features/admin/data/admin_api.dart';
import 'package:chordia_mobile/features/admin/data/admin_models.dart';
import 'package:chordia_mobile/features/manager/data/coverage_format.dart';
import 'package:chordia_mobile/features/manager/data/manager_api.dart';
import 'package:chordia_mobile/features/manager/data/manager_providers.dart';
import 'package:chordia_mobile/features/manager/widgets/coverage_view.dart';
import 'package:chordia_mobile/i18n/keys.g.dart';
import 'package:chordia_mobile/i18n/translations.dart';
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

  group('coverage percentages', () {
    test('zero of zero is unknown, not zero percent', () {
      // The Hub sends 0.0 for a percentage it could not compute, because a float has no way to
      // say "unknown". Rendering that as 0% claims a completeness figure nobody measured.
      expect(coveragePercent(0, 0), isNull);
      expect(coveragePercent(3, 0), isNull);
      expect(coveragePercent(0, 4), 0);
      expect(coveragePercent(7, 10), 70);
      // Rounded, and never out of range even if the counts disagree with each other.
      expect(coveragePercent(1, 3), 33);
      expect(coveragePercent(12, 10), 100);
    });

    test('a summary with nothing tracked is unmeasured', () {
      expect(
        coverageIsUnmeasured(
          _summary(ownedRgs: 0, totalRgs: 0, touchedArtists: 0),
        ),
        isTrue,
      );
      expect(
        coverageIsUnmeasured(_summary(ownedRgs: 7, totalRgs: 10)),
        isFalse,
      );
      expect(albumCoveragePercent(_summary(ownedRgs: 0, totalRgs: 0)), isNull);
      expect(albumCoveragePercent(_summary(ownedRgs: 7, totalRgs: 10)), 70);
      expect(
        artistCoveragePercent(_summary(completeArtists: 3, touchedArtists: 12)),
        25,
      );
    });

    test('an artist with no MusicBrainz match has no percentage', () {
      // Two ways to have nothing to say, and both would otherwise render as a confident 0%.
      expect(artistCoveragePercentOf(_artistCoverage(coveragePct: 0)), isNull);
      expect(
        artistCoveragePercentOf(
          _artistCoverage(coveragePct: 0, mbid: 'mb-artist'),
        ),
        isNull,
      );
      expect(
        artistCoveragePercentOf(
          _artistCoverage(
            coveragePct: 50,
            mbid: 'mb-artist',
            owned: [_album('a')],
            missing: [_release('rg-1')],
          ),
        ),
        50,
      );
    });

    testWidgets('the dashboard shows a percentage it has counts for', (
      tester,
    ) async {
      final api = _FakeManagerApi(_summary(ownedRgs: 7, totalRgs: 10));
      await tester.pumpWidget(_managerApp(api));
      await _settle(tester);

      expect(find.text('70%'), findsOneWidget);
      expect(
        find.text(
          translations(ManagerKeys.coverageOwnedOfTotal, {
            'owned': 7,
            'total': 10,
          }),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a library with nothing counted says so instead of 0%', (
      tester,
    ) async {
      final api = _FakeManagerApi(
        _summary(ownedRgs: 0, totalRgs: 0, touchedArtists: 0),
      );
      await tester.pumpWidget(_managerApp(api));
      await _settle(tester);

      // The whole point: an unscanned library reads as "no coverage yet", never as a verdict of
      // zero on what the user owns.
      expect(
        find.text(translations(ManagerKeys.coverageEmpty)),
        findsOneWidget,
      );
      expect(find.text('0%'), findsNothing);
      expect(find.text('—'), findsNothing);
    });
  });

  group('the coverage exclusion list', () {
    test('unchecking a library sends it and adopts what was stored', () async {
      final api = _FakeManagerApi(
        _summary(
          ownedRgs: 7,
          totalRgs: 10,
          // Carries a stale exclusion for a library this account can no longer see — the case
          // that separates "adopt the answer" from "assume the write echoed".
          excluded: {'lib-gone'},
          libraries: const ['lib-a', 'lib-b'],
        ),
        visibleLibraryIds: {'lib-a', 'lib-b'},
      );
      final container = _container(api);
      addTearDown(container.dispose);
      await container.read(coverageControllerProvider.future);

      final controller = container.read(coverageControllerProvider.notifier);
      expect(await controller.setExcluded('lib-a', excluded: true), isTrue);

      // The whole set goes up, not a delta: the endpoint replaces it.
      expect(api.sentExclusions, ['lib-a', 'lib-gone']);
      // And what lands is what the Hub kept, which is not what was sent.
      final after = container.read(coverageControllerProvider).requireValue;
      expect(after.excludedLibraryIds, ['lib-a']);
      expect(
        after.perLibrary.where((l) => l.excluded).map((l) => l.libraryId),
        ['lib-a'],
      );
    });

    test('re-checking it takes it back out', () async {
      final api = _FakeManagerApi(
        _summary(
          ownedRgs: 7,
          totalRgs: 10,
          excluded: {'lib-a'},
          libraries: const ['lib-a', 'lib-b'],
        ),
        visibleLibraryIds: {'lib-a', 'lib-b'},
      );
      final container = _container(api);
      addTearDown(container.dispose);
      await container.read(coverageControllerProvider.future);

      final controller = container.read(coverageControllerProvider.notifier);
      expect(await controller.setExcluded('lib-a', excluded: false), isTrue);

      expect(api.sentExclusions, isEmpty);
      expect(
        container
            .read(coverageControllerProvider)
            .requireValue
            .excludedLibraryIds,
        isEmpty,
      );
    });

    test('a refused write puts the checkbox back and keeps the reason', () async {
      final api =
          _FakeManagerApi(
              _summary(ownedRgs: 7, totalRgs: 10, libraries: const ['lib-a']),
              visibleLibraryIds: {'lib-a'},
            )
            ..failWrites = const ApiException(
              status: 500,
              title: 'Nope',
              method: 'PUT',
              path: '/v1/manager/coverage/exclusions',
            );
      final container = _container(api);
      addTearDown(container.dispose);
      await container.read(coverageControllerProvider.future);

      final controller = container.read(coverageControllerProvider.notifier);
      expect(await controller.setExcluded('lib-a', excluded: true), isFalse);

      // Not merely "something": the exact state from before the tap. Without the reason kept, the
      // revert is indistinguishable from a tap that never registered.
      expect(
        container
            .read(coverageControllerProvider)
            .requireValue
            .excludedLibraryIds,
        isEmpty,
      );
      expect((controller.failure as ApiException?)?.title, 'Nope');
    });
  });

  group('the admin gate', () {
    testWidgets('an ordinary listener is offered nothing', (tester) async {
      await tester.pumpWidget(
        _adminApp(_FakeAdminApi(isAdmin: false), const AdminEntryTile()),
      );
      await _settle(tester);

      expect(find.text(translations(CommonKeys.userMenuAdmin)), findsNothing);
      expect(find.byType(ListTile), findsNothing);
    });

    testWidgets('an admin is', (tester) async {
      // The counter-case, so the assertion above cannot pass because the tile never renders at all.
      await tester.pumpWidget(
        _adminApp(_FakeAdminApi(isAdmin: true), const AdminEntryTile()),
      );
      await _settle(tester);

      expect(find.text(translations(CommonKeys.userMenuAdmin)), findsOneWidget);
    });

    testWidgets('reaching the section directly gets a refusal, not tabs', (
      tester,
    ) async {
      final api = _FakeAdminApi(isAdmin: false);
      await tester.pumpWidget(_adminApp(api, const AdminScreen()));
      await _settle(tester);

      expect(
        find.text(translations(AdminKeys.noAccessPlainBody)),
        findsOneWidget,
      );
      // No tab ever mounts, so no admin endpoint is called on the way to being refused.
      expect(find.text(translations(AdminKeys.tabsOverview)), findsNothing);
      expect(api.calls, ['me']);
    });
  });
}

// ── harness ───────────────────────────────────────────────────────────────────────────────────

/// Pumps a fixed number of frames.
///
/// `pumpAndSettle` is unusable here: the player ticks twice a second, so the frame queue never
/// drains and the call hangs rather than failing.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

ProviderContainer _container(ManagerApi api) => ProviderContainer(
  overrides: [
    managerApiProvider.overrideWithValue(api),
    translationsProvider.overrideWithValue(translations),
  ],
);

Widget _managerApp(ManagerApi api) => ProviderScope(
  overrides: [
    managerApiProvider.overrideWithValue(api),
    translationsProvider.overrideWithValue(translations),
    // The real one resolves a platform directory, which no test binding provides.
    artCacheProvider.overrideWithValue(
      ArtCache(
        directory: Future.value(Directory.systemTemp),
        fetch: (sha, width) => throw ArtMissingException(sha),
      ),
    ),
  ],
  child: MaterialApp(
    theme: buildChordiaTheme(),
    home: const Scaffold(body: CoverageView()),
  ),
);

Widget _adminApp(AdminApi api, Widget child) => ProviderScope(
  overrides: [
    adminApiProvider.overrideWithValue(api),
    translationsProvider.overrideWithValue(translations),
  ],
  child: MaterialApp(
    theme: buildChordiaTheme(),
    home: Scaffold(body: child),
  ),
);

CoverageSummary _summary({
  int ownedRgs = 0,
  int totalRgs = 0,
  int touchedArtists = 4,
  int completeArtists = 1,
  int pendingArtists = 0,
  Set<String> excluded = const {},
  List<String> libraries = const ['lib-a'],
}) => CoverageSummary(
  // The Hub's own floats are carried through untouched; the screens divide the counts themselves
  // so the percentage and the ratio printed beside it cannot round differently.
  albumPct: totalRgs == 0 ? 0 : ownedRgs / totalRgs * 100,
  artistPct: touchedArtists == 0 ? 0 : completeArtists / touchedArtists * 100,
  completeArtists: completeArtists,
  excludedLibraryIds: excluded.toList()..sort(),
  includeShared: true,
  ownedRgs: ownedRgs,
  pendingArtists: pendingArtists,
  perLibrary: [
    for (final id in libraries)
      LibraryCoverage(
        albumCount: 2,
        artistCount: 1,
        excluded: excluded.contains(id),
        libraryId: id,
        name: 'Library $id',
        owned: true,
        trackCount: 20,
      ),
  ],
  totalRgs: totalRgs,
  touchedArtists: touchedArtists,
);

ArtistCoverage _artistCoverage({
  required double coveragePct,
  String? mbid,
  List<BrowseAlbum> owned = const [],
  List<ExtReleaseGroup> missing = const [],
}) => ArtistCoverage(
  artistId: 'artist-1',
  coveragePct: coveragePct,
  missing: missing,
  name: 'An Artist',
  owned: owned,
  refreshing: false,
  artistMbid: mbid,
);

BrowseAlbum _album(String id) =>
    BrowseAlbum(artist: 'An Artist', id: id, title: 'An Album', trackCount: 10);

ExtReleaseGroup _release(String mbid) =>
    ExtReleaseGroup(mbid: mbid, title: 'A Release');

class _FakeManagerApi implements ManagerApi {
  _FakeManagerApi(this._summary, {this.visibleLibraryIds = const {}})
    : _excluded = _summary.excludedLibraryIds.toSet();

  final CoverageSummary _summary;

  /// The libraries this account can actually see. The Hub silently drops the rest from a write,
  /// which is the behaviour these tests are about.
  final Set<String> visibleLibraryIds;

  Set<String> _excluded;

  /// What the last write sent, so a test can tell "the whole set went up" from "a delta did".
  List<String>? sentExclusions;

  /// When set, every write is refused with it.
  ApiException? failWrites;

  @override
  Future<CoverageSummary> coverage() async =>
      withExclusions(_summary, _excluded);

  @override
  Future<List<String>> setExclusions(List<String> libraryIds) async {
    sentExclusions = libraryIds;
    final failure = failWrites;
    if (failure != null) throw failure;
    _excluded = libraryIds.where(visibleLibraryIds.contains).toSet();
    return _excluded.toList()..sort();
  }

  @override
  Future<ManagerPrefs> prefs() async => const ManagerPrefs(includeShared: true);

  @override
  Future<ManagerPrefs> setPrefs(ManagerPrefs prefs) async => prefs;

  @override
  Future<List<BrowseArtist>> ownedArtists() async => const [];

  @override
  Future<ArtistCoverage> artistCoverage(String artistId) async =>
      _artistCoverage(coveragePct: 0);

  @override
  Future<AlbumTrackCoverage> releaseGroupCoverage(String mbid) async =>
      AlbumTrackCoverage(
        editions: const [],
        refreshing: false,
        rgMbid: mbid,
        title: 'A Release',
      );

  @override
  Future<DiscoverResults> discover(String query) async =>
      const DiscoverResults(artists: [], releaseGroups: []);

  @override
  Future<ExtArtistDetail> discoverArtist(String artistMbid) async =>
      ExtArtistDetail(
        following: false,
        mbid: artistMbid,
        name: 'An Artist',
        refreshing: false,
        releaseGroups: const [],
      );

  @override
  Future<List<FollowedArtist>> follows() async => const [];

  @override
  Future<void> follow(String artistMbid, {String? name}) async {}

  @override
  Future<void> unfollow(String artistMbid) async {}
}

class _FakeAdminApi implements AdminApi {
  _FakeAdminApi({required this.isAdmin});

  final bool isAdmin;

  /// Which methods were reached, so a test can assert that a refused caller never got as far as
  /// asking the Hub for admin data.
  final calls = <String>[];

  @override
  Future<UserProfile> me() async {
    calls.add('me');
    return UserProfile(
      createdAt: 0,
      displayName: 'A Listener',
      handle: 'listener',
      id: 'user-1',
      isAdmin: isAdmin,
    );
  }

  Never _unreached(String name) {
    calls.add(name);
    throw StateError('$name should not be reached by a non-admin');
  }

  @override
  Future<AdminOverview> overview({int days = 30}) async =>
      _unreached('overview');

  @override
  Future<AdminSystemHealth> system() async => _unreached('system');

  @override
  Future<AdminUserPage> users(AdminUserQuery query) async =>
      _unreached('users');

  @override
  Future<AdminUserProfile> userProfile(String userId) async =>
      _unreached('userProfile');

  @override
  Future<List<ModerationReport>> reports(String status) async =>
      _unreached('reports');

  @override
  Future<void> resolveReport(String reportId, String action) async =>
      _unreached('resolveReport');

  @override
  Future<AuditPage> audit({
    String? category,
    int? beforeId,
    int limit = 50,
  }) async => _unreached('audit');

  @override
  Future<AuditFacets> auditFacets() async => _unreached('auditFacets');

  @override
  Future<List<BrowseArtist>> searchArtists(String query) async =>
      _unreached('searchArtists');

  @override
  Future<List<BrowseAlbum>> searchAlbums(String query) async =>
      _unreached('searchAlbums');
}
