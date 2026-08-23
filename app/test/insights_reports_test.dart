import 'dart:async';
import 'dart:io';

import 'package:chordia_api/chordia_api.dart';
import 'package:chordia_mobile/app/providers.dart';
import 'package:chordia_mobile/app/theme.dart';
import 'package:chordia_mobile/data/art/art_cache.dart';
import 'package:chordia_mobile/features/insights/data/insights_api.dart';
import 'package:chordia_mobile/features/insights/entity_stats_screen.dart';
import 'package:chordia_mobile/features/insights/reports/charts_report.dart';
import 'package:chordia_mobile/features/insights/reports/overview_report.dart';
import 'package:chordia_mobile/i18n/keys.g.dart';
import 'package:chordia_mobile/i18n/translations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';

/// The reports' own content: the charts the Overview draws, and the links its rows carry.
///
/// `insights_test.dart` covers the period selector, the paging and the formatting. This file is
/// about the things that were MISSING from the phone's reports — the listening fingerprint, the
/// genre flow, the music ratio, and the several rows that displayed a name without offering to
/// open it.
late Translations translations;

const _dayMs = 86400000;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeDateFormatting();
    translations = await Translations.load('en', bundle: rootBundle);
  });

  group('the Overview', () {
    testWidgets('draws the character charts, not only the headline numbers', (
      tester,
    ) async {
      await _pump(tester, const OverviewReport(handle: null));

      // Each of the three is a fact reachable nowhere else in the app: the fingerprint against the
      // hub average, genre drift over the window, and the unique-albums count.
      expect(
        find.text(translations(InsightsKeys.panelsFingerprint)),
        findsOneWidget,
      );
      // The legend only exists when a baseline came back, so this asserts the average was PLOTTED
      // rather than merely that a panel heading was typed.
      expect(
        find.text(translations(InsightsKeys.fingerprintAverage)),
        findsOneWidget,
      );
      expect(
        find.text(translations(InsightsKeys.panelsGenreFlow)),
        findsOneWidget,
      );
      // The flow's own legend, title-cased the way every other genre in the app is.
      expect(find.text('Rock'), findsOneWidget);
      expect(
        find.text(translations(InsightsKeys.panelsMusicRatio)),
        findsOneWidget,
      );
      expect(
        find.text(translations(InsightsKeys.ratioCaption, const {'count': 12})),
        findsOneWidget,
      );
    });

    testWidgets('a top-genre row opens that genre', (tester) async {
      await _pump(tester, const OverviewReport(handle: null));

      // Title-cased: the catalog stores "hip hop", and a row that says so beside a chip that says
      // "Hip Hop" reads as two different tags.
      final row = find.text('Hip Hop');
      await tester.ensureVisible(row);
      await tester.pump();
      await tester.tap(row);
      await _settle(tester);

      // The slug is the Hub's own fold — lowercase, runs of punctuation collapsed to a space —
      // not a hyphenated one, so this is the page every other genre link in the app opens.
      expect(find.text('genre page hip hop'), findsOneWidget);
    });

    testWidgets('a recently-played row opens the artist it names', (
      tester,
    ) async {
      await _pump(tester, const OverviewReport(handle: null));

      final artist = find.text('Recent Artist');
      await tester.ensureVisible(artist);
      await tester.pump();
      await tester.tap(artist);
      await _settle(tester);

      expect(find.text('artist page ra-1'), findsOneWidget);
    });
  });

  group('the ranked chart', () {
    testWidgets("drills through on somebody else's profile too", (
      tester,
    ) async {
      // The gap this closes: the rows were tap-gated on the chart being the reader's own, which
      // left rank 87 of a friend's chart with no destination at all.
      await _pump(tester, const ChartsReport(handle: 'dee', own: false));

      final row = find.text('Entry 2');
      await tester.ensureVisible(row);
      await tester.pump();
      await tester.tap(row);
      await _settle(tester);

      expect(find.byType(EntityStatsScreen), findsOneWidget);
    });
  });
}

// ── the harness ───────────────────────────────────────────────────────────────────────────────

/// Fixed frames rather than `pumpAndSettle`, which never completes under a router that animates.
Future<void> _settle(WidgetTester tester) async {
  for (var frame = 0; frame < 8; frame++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Future<void> _pump(WidgetTester tester, Widget report) async {
  // Tall enough that the whole Overview lays out: it is three hero cards, four charts and a feed,
  // and `ensureVisible` cannot reach a row inside a viewport that never built it.
  tester.view.physicalSize = const Size(1000, 6000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_app(report));
  await _settle(tester);
}

/// One report under a router, so a row's real destination is what gets exercised rather than a
/// stand-in the test wrote itself.
Widget _app(Widget report) => ProviderScope(
  overrides: [
    translationsProvider.overrideWithValue(translations),
    insightsApiProvider.overrideWithValue(FakeInsightsApi()),
    // The real cache resolves a platform directory, which no test binding provides.
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
      initialLocation: '/you',
      routes: [
        GoRoute(
          path: '/you',
          builder: (context, state) =>
              Scaffold(body: SingleChildScrollView(child: report)),
          routes: [
            GoRoute(
              path: 'genres/:slug',
              builder: (context, state) => Scaffold(
                body: Text('genre page ${state.pathParameters['slug']}'),
              ),
            ),
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

TopItem _item(String name, {int plays = 3}) =>
    TopItem(id: '$name-id', msPlayed: 60000 * plays, name: name, plays: plays);

/// A month-long window with enough shape in it to feed every chart-form gate.
WrappedReport _report() => WrappedReport(
  decades: const [DecadeBucket(decade: 1990, msPlayed: 60000, plays: 4)],
  fingerprint: const FingerprintReport(
    you: Fingerprint(
      concentration: 0.5,
      consistency: 0.4,
      discovery: 0.2,
      replay: 0.7,
      variance: 0.3,
    ),
    globalAverage: Fingerprint(
      concentration: 0.4,
      consistency: 0.5,
      discovery: 0.3,
      replay: 0.6,
      variance: 0.4,
    ),
  ),
  genreTrend: GenreTrend(
    genres: const ['rock', 'jazz', 'other'],
    buckets: [
      for (var day = 0; day < 30; day++)
        GenreTrendBucket(plays: [day % 4, day % 3, 1], start: day * _dayMs),
    ],
  ),
  period: Period.month,
  timezone: 'UTC',
  topAlbums: [_item('Album A'), _item('Album B')],
  topArtists: [_item('Artist A'), _item('Artist B')],
  topGenres: [_item('hip hop'), _item('jazz')],
  topTracks: [_item('Track A')],
  totalMsPlayed: 120000,
  totalMsPlayedCompared: const Compared(current: 120000, previous: 60000),
  totalPlays: 20,
  totalPlaysCompared: const Compared(current: 20, previous: 10),
  undatedReleaseShare: 0.2,
  uniqueAlbums: 6,
  uniqueAlbumsCompared: const Compared(current: 6, previous: 4),
  uniqueArtists: 4,
  uniqueArtistsCompared: const Compared(current: 4, previous: 3),
  uniqueTracks: 12,
  uniqueTracksCompared: const Compared(current: 12, previous: 9),
  userId: 'me-id',
  windowEnd: 30 * _dayMs,
  windowStart: 0,
);

/// An [InsightsApi] with no Hub behind it. Only the reads these tests make are answered; anything
/// else hangs, which leaves a failure about the thing being asserted rather than about a stub.
class FakeInsightsApi implements InsightsApi {
  @override
  Future<WrappedReport> wrapped(InsightsQuery query) async => _report();

  @override
  Future<ListeningCharts> charts(InsightsQuery query) async => ListeningCharts(
    clock: List.filled(24, 1),
    clockGrid: ClockGrid(cells: List.filled(168, 1), timezone: 'UTC', peak: 3),
    granularity: BucketGranularity.day,
    overTime: [
      for (var day = 0; day < 30; day++)
        TimeBucket(msPlayed: 60000, plays: day % 5, start: day * _dayMs),
    ],
    period: query.period,
    timezone: 'UTC',
    weekday: List.filled(7, 2),
    windowEnd: 30 * _dayMs,
    windowStart: 0,
  );

  @override
  Future<List<RecentPlay>> recentPlays(String? handle) async => const [
    RecentPlay(
      artist: 'Recent Artist',
      artistId: 'ra-1',
      eventId: 'ev-1',
      playedAt: 0,
      title: 'Recent Track',
      trackId: 'rt-1',
    ),
  ];

  @override
  Future<ChartPage> topChart(
    InsightsQuery query,
    EntityKind kind, {
    int? offset,
    int? limit,
  }) async => ChartPage(
    entries: const [
      ChartEntry(id: 'e0', msPlayed: 60000, name: 'Entry 1', plays: 2, rank: 1),
      ChartEntry(id: 'e1', msPlayed: 60000, name: 'Entry 2', plays: 1, rank: 2),
    ],
    kind: kind,
    offset: 0,
    period: query.period,
    total: 2,
    windowEnd: 30 * _dayMs,
    windowStart: 0,
  );

  @override
  Future<EntityStats> entityStats(
    EntityKind kind,
    String id, {
    Period? period,
    String? tz,
  }) async => EntityStats(
    granularity: BucketGranularity.day,
    id: id,
    kind: kind,
    period: period ?? Period.month,
    totalMsPlayed: 60000,
    totalPlays: 1,
    trend: const [],
    windowEnd: 30 * _dayMs,
    windowStart: 0,
    firstPlayed: 0,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => Completer<Never>().future;
}
