import 'package:chordia_api/chordia_api.dart';
import 'package:chordia_mobile/app/theme.dart';
import 'package:chordia_mobile/features/insights/data/insights_api.dart';
import 'package:chordia_mobile/features/insights/data/insights_providers.dart';
import 'package:chordia_mobile/features/insights/entity_stats_screen.dart';
import 'package:chordia_mobile/features/insights/format.dart';
import 'package:chordia_mobile/features/insights/reports/charts_report.dart';
import 'package:chordia_mobile/features/insights/reports/records_report.dart';
import 'package:chordia_mobile/features/insights/widgets/insights_primitives.dart';
import 'package:chordia_mobile/features/insights/wrapped_card.dart';
import 'package:chordia_mobile/i18n/keys.g.dart';
import 'package:chordia_mobile/i18n/translations.dart';
import 'package:chordia_mobile/i18n/translations_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

/// Loaded once, in real async: `testWidgets` runs inside a fake-async zone where an asset read
/// never completes, so the catalogs have to be in hand before the first pump.
late Translations translations;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // The app does this in bootstrap; a test that formats a date has to do it too.
    await initializeDateFormatting();
    translations = await Translations.load('en', bundle: rootBundle);
  });

  group('the period selector', () {
    testWidgets('picking a window re-asks the Hub for that window', (
      tester,
    ) async {
      // Wide enough that all seven pills are laid out; the strip scrolls on a phone, and a chip
      // that is off-screen cannot be tapped.
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final api = FakeInsightsApi();
      await tester.pumpWidget(_app(api));
      await tester.pump();

      // The default window, asked for once.
      expect(api.wrappedCalls.map((q) => q.period), [Period.month]);

      await tester.tap(find.text(translations(InsightsKeys.periodYear)));
      await tester.pump();

      expect(api.wrappedCalls.last.period, Period.year);
      // A different window is a different question, not a re-render of the same answer.
      expect(api.wrappedCalls, hasLength(2));
    });

    testWidgets('the same window is not asked for twice', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final api = FakeInsightsApi();
      await tester.pumpWidget(_app(api));
      await tester.pump();

      await tester.tap(find.text(translations(InsightsKeys.periodMonth)));
      await tester.pump();

      expect(api.wrappedCalls, hasLength(1));
    });
  });

  group('the query a report is built from', () {
    test('somebody else\'s report carries no timezone of ours', () {
      // A listening clock describes when *they* listen, so bucketing their plays against the
      // viewer's midnight would describe nobody's day.
      final container = ProviderContainer(
        overrides: [insightsTimezoneProvider.overrideWithValue('Europe/Oslo')],
      );
      addTearDown(container.dispose);

      expect(
        container.read(insightsQueryProvider(null)).timezone,
        'Europe/Oslo',
      );
      expect(container.read(insightsQueryProvider('dee')).timezone, isNull);
      expect(container.read(insightsQueryProvider('dee')).handle, 'dee');
    });

    test('is a value, so two identical questions share one cache entry', () {
      const a = InsightsQuery(period: Period.week, timezone: 'UTC');
      const b = InsightsQuery(period: Period.week, timezone: 'UTC');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a.withPeriod(Period.year), isNot(b));
    });
  });

  group('the shareable card', () {
    testWidgets('renders to a non-empty PNG at the card\'s own size', (
      tester,
    ) async {
      final key = GlobalKey();
      await tester.pumpWidget(_card(key, data: _cardData()));
      await tester.pump();

      // `runAsync`: encoding an image is real engine work, which the fake-async zone a widget
      // test runs in never gets round to.
      final png = await tester.runAsync(() => captureWrappedCard(key));

      expect(png, isNotNull);
      expect(png!.lengthInBytes, greaterThan(0));
      expect(_pngSize(png), const Size(wrappedCardWidth, wrappedCardHeight));
    });

    testWidgets('a missing cover becomes a tinted tile, not a failed render', (
      tester,
    ) async {
      final key = GlobalKey();
      // Every entry art-less, which is the shape the Hub returns for genres and for anything its
      // enrichment has not reached yet.
      await tester.pumpWidget(_card(key, data: _cardData()));
      await tester.pump();

      expect(tester.takeException(), isNull);
      // The initial stands in for the artwork, so a row still reads as that entry.
      expect(find.text('A'), findsWidgets);

      final png = await tester.runAsync(() => captureWrappedCard(key));
      expect(png!.lengthInBytes, greaterThan(0));
    });

    test('the card is built from the report, with nothing invented', () {
      final data = _dataFrom(_report());
      expect(data.heroValue, '2');
      expect(data.topArtists.map((e) => e.name), ['Artist A', 'Artist B']);
      expect(data.topTracks.single.name, 'Track A');
      // No genres in the report means no genre line at all, rather than a blank one.
      expect(data.topGenre, isNull);
    });
  });

  group('the full ranked chart', () {
    test('asks for the next page and keeps the rows already on screen', () async {
      // 60 entities and a 25-row page: without an offset, rank 26 was unreachable on a phone while
      // the line above the list went on saying "of 60".
      final api = FakeInsightsApi()..chartTotal = 60;
      final container = ProviderContainer(
        overrides: [insightsApiProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);
      const request = ChartRequest(
        query: InsightsQuery(),
        kind: EntityKind.artist,
      );

      final first = await container.read(topChartProvider(request).future);
      expect(first.entries, hasLength(chartPageSize));
      expect(first.total, 60);
      expect(first.nextOffset, chartPageSize);
      // The first page asks for no offset at all, which is the Hub's own default.
      expect(api.topChartOffsets, [null]);

      await container.read(topChartProvider(request).notifier).loadMore();

      final more = container.read(topChartProvider(request)).requireValue;
      // The second page is asked for at the offset the first one ended at...
      expect(api.topChartOffsets, [null, chartPageSize]);
      // ...and lands UNDER the rows already read, rather than replacing them.
      expect(more.entries, hasLength(50));
      expect(more.entries.first.rank, 1);
      expect(more.entries.last.rank, 50);
      expect(more.nextOffset, 50);
    });

    test('stops once every row is loaded', () async {
      final api = FakeInsightsApi()..chartTotal = 30;
      final container = ProviderContainer(
        overrides: [insightsApiProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);
      const request = ChartRequest(
        query: InsightsQuery(),
        kind: EntityKind.track,
      );

      await container.read(topChartProvider(request).future);
      final notifier = container.read(topChartProvider(request).notifier);
      await notifier.loadMore();
      expect(
        container.read(topChartProvider(request)).requireValue.nextOffset,
        isNull,
      );

      // A second tap on a button that is no longer offered must not spend a request either.
      await notifier.loadMore();
      expect(api.topChartOffsets, [null, chartPageSize]);
    });

    test('a failed page costs the page, not the rows on screen', () async {
      final api = FakeInsightsApi()..chartTotal = 60;
      final container = ProviderContainer(
        overrides: [insightsApiProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);
      const request = ChartRequest(
        query: InsightsQuery(),
        kind: EntityKind.album,
      );
      await container.read(topChartProvider(request).future);

      api.chartFailure = const ApiException(
        status: 0,
        title: 'Could not reach the server.',
        method: 'GET',
        path: '/v1/insights/top',
      );
      await expectLater(
        container.read(topChartProvider(request).notifier).loadMore(),
        throwsA(isA<ApiException>()),
      );

      final feed = container.read(topChartProvider(request)).requireValue;
      expect(feed.entries, hasLength(chartPageSize));
      // And the button comes back, rather than the list being stuck mid-load.
      expect(feed.loadingMore, isFalse);
    });

    testWidgets('a chart row opens that entity\'s own stats page', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final api = FakeInsightsApi()..chartTotal = 3;
      await tester.pumpWidget(
        _reportApp(api, const ChartsReport(handle: null, own: true)),
      );
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('Entry 2'));
      await tester.pump();
      await tester.pump();

      // Reached, and asking about the row that was tapped rather than about the chart.
      expect(find.byType(EntityStatsScreen), findsOneWidget);
      expect(api.entityStatsCalls, [('artist', 'e1')]);
    });
  });

  group('the milestone lookup', () {
    testWidgets('asks the Hub for the position that was typed', (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      // A listener with some history: an account with none renders the "nothing yet" card, and
      // there is nothing to look a play up in.
      final api = FakeInsightsApi()..recordsActiveDays = 12;
      await tester.pumpWidget(
        _reportApp(api, const RecordsReport(handle: null, own: true)),
      );
      await tester.pump();
      await tester.pump();

      await tester.enterText(
        find.widgetWithText(
          TextField,
          translations(InsightsKeys.recordsMilestonesLookupLabel),
        ),
        '5000',
      );
      await tester.pump();
      await tester.tap(
        find.widgetWithText(
          OutlinedButton,
          translations(InsightsKeys.recordsMilestonesLookupSubmit),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(api.milestoneCalls, [5000]);
      // And the answer is shown, rather than only counted.
      expect(find.textContaining('Play 5000'), findsOneWidget);
    });

    testWidgets('past the end of the history says so, in those words', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final api = FakeInsightsApi()
        ..recordsActiveDays = 12
        ..milestoneFailure = const ApiException(
          status: 404,
          title: 'Not Found',
          method: 'GET',
          path: '/v1/insights/milestone',
        );
      await tester.pumpWidget(
        _reportApp(api, const RecordsReport(handle: null, own: true)),
      );
      await tester.pump();
      await tester.pump();

      await tester.enterText(
        find.widgetWithText(
          TextField,
          translations(InsightsKeys.recordsMilestonesLookupLabel),
        ),
        '900000',
      );
      await tester.pump();
      await tester.tap(
        find.widgetWithText(
          OutlinedButton,
          translations(InsightsKeys.recordsMilestonesLookupSubmit),
        ),
      );
      await tester.pump();
      await tester.pump();

      // The Hub's bare "Not Found" would tell a reader nothing about what they asked.
      expect(
        find.text(translations(InsightsKeys.recordsMilestonesLookupOutOfRange)),
        findsOneWidget,
      );
    });
  });

  group('durations', () {
    test('read the way a listener reads them', () {
      final t = translations.call;
      // Seconds only under a minute: a short play should read "40s", not the broken-looking "0m".
      expect(msToTime(40000, t), '40s');
      expect(msToTime(60000, t), '1m');
      expect(msToTime(3600000 * 2 + 60000 * 41, t), '2h 41m');
      // Minutes are dropped once days are involved.
      expect(msToTime(86400000 * 3 + 3600000 * 4, t), '3d 4h');
      expect(msToTime(86400000 * 3, t), '3d');
    });
  });

  group('relative play times', () {
    test('age a play against a fixed now', () {
      final t = translations.call;
      final now = DateTime(2026, 8, 22, 12);
      String at(Duration ago) => relativePlayTime(
        now.subtract(ago).millisecondsSinceEpoch,
        t,
        locale: 'en',
        now: now,
      );

      expect(at(const Duration(seconds: 20)), 'just now');
      expect(at(const Duration(minutes: 12)), '12m ago');
      expect(at(const Duration(hours: 5)), '5h ago');
      expect(at(const Duration(days: 1)), 'yesterday');
      // Past a couple of days it is a date, not a countdown.
      expect(at(const Duration(days: 9)), 'Aug 13');
    });
  });
}

// ── the harness ───────────────────────────────────────────────────────────────────────────────

/// The period strip plus a probe that asks for a report, which is the pair the selector exists to
/// connect. Nothing else of the insights screen is involved, so a failure here is about the
/// selector rather than about whichever report happened to be on screen.
Widget _app(FakeInsightsApi api) => ProviderScope(
  overrides: [
    translationsProvider.overrideWithValue(translations),
    insightsApiProvider.overrideWithValue(api),
  ],
  child: MaterialApp(
    theme: buildChordiaTheme(),
    home: const Scaffold(
      body: Column(children: [PeriodSelector(), _ReportProbe()]),
    ),
  ),
);

/// One report, on its own, with a fake Hub behind it.
///
/// Scrollable because a report is a `Column` that expects to live inside the profile's own scroll
/// view, and a 3000px-tall test viewport is still shorter than a full records page.
Widget _reportApp(FakeInsightsApi api, Widget report) => ProviderScope(
  overrides: [
    translationsProvider.overrideWithValue(translations),
    insightsApiProvider.overrideWithValue(api),
  ],
  child: MaterialApp(
    theme: buildChordiaTheme(),
    home: Scaffold(body: SingleChildScrollView(child: report)),
  ),
);

class _ReportProbe extends ConsumerWidget {
  const _ReportProbe();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(wrappedReportProvider(ref.watch(insightsQueryProvider(null))));
    return const SizedBox.shrink();
  }
}

Widget _card(GlobalKey key, {required WrappedCardData data}) => MaterialApp(
  theme: buildChordiaTheme(),
  home: Scaffold(
    // `FittedBox` scales the painted card into the test viewport. The card still LAYS OUT at its
    // own pixel size, which is what the capture reads.
    body: Center(
      child: FittedBox(
        child: WrappedCard(data: data, boundaryKey: key),
      ),
    ),
  ),
);

WrappedCardData _cardData() => _dataFrom(_report());

/// The same mapping [buildWrappedCardData] performs, minus the cover fetches — those need an
/// `ArtCache` with a directory on disk, and what is being asserted here is the card, not the cache.
WrappedCardData _dataFrom(WrappedReport report) {
  final t = translations.call;
  return WrappedCardData(
    heading: t(InsightsKeys.rotationHeading),
    subheading: rotationPeriodTitle(report.period, t),
    handle: '@me',
    heroValue: '${(report.totalMsPlayed / 60000).round()}',
    heroLabel: t(InsightsKeys.rotationMinutesListened),
    statLine: t(InsightsKeys.rotationStatLine, {
      'artists': report.uniqueArtists,
      'tracks': report.uniqueTracks,
    }),
    topArtistsLabel: t(InsightsKeys.rotationTopArtists),
    topArtists: [
      for (final item in report.topArtists) WrappedCardEntry(name: item.name),
    ],
    topTracksLabel: t(InsightsKeys.rotationTopTracks),
    topTracks: [
      for (final item in report.topTracks) WrappedCardEntry(name: item.name),
    ],
    topGenre: report.topGenres.isEmpty ? null : report.topGenres.first.name,
    topGenreLabel: report.topGenres.isEmpty
        ? null
        : t(InsightsKeys.rotationTopGenre),
    footer: t(CommonKeys.appName),
  );
}

/// The width and height a PNG declares in its IHDR chunk, which starts at byte 16.
Size _pngSize(Uint8List png) {
  final data = ByteData.sublistView(png);
  return Size(data.getUint32(16).toDouble(), data.getUint32(20).toDouble());
}

TopItem _item(String name) =>
    TopItem(id: name, msPlayed: 60000, name: name, plays: 1);

WrappedReport _report() => WrappedReport(
  decades: const [],
  fingerprint: const FingerprintReport(
    you: Fingerprint(
      concentration: 0.5,
      consistency: 0.5,
      discovery: 0.5,
      replay: 0.5,
      variance: 0.5,
    ),
  ),
  genreTrend: const GenreTrend(buckets: [], genres: []),
  period: Period.month,
  timezone: 'UTC',
  topAlbums: const [],
  topArtists: [_item('Artist A'), _item('Artist B')],
  topGenres: const [],
  topTracks: [_item('Track A')],
  totalMsPlayed: 120000,
  totalMsPlayedCompared: const Compared(current: 120000, previous: 60000),
  totalPlays: 2,
  totalPlaysCompared: const Compared(current: 2, previous: 1),
  undatedReleaseShare: 0,
  uniqueAlbums: 1,
  uniqueAlbumsCompared: const Compared(current: 1, previous: 1),
  uniqueArtists: 2,
  uniqueArtistsCompared: const Compared(current: 2, previous: 1),
  uniqueTracks: 1,
  uniqueTracksCompared: const Compared(current: 1, previous: 1),
  userId: 'me-id',
  windowEnd: 0,
  windowStart: 0,
);

/// An [InsightsApi] with no Hub behind it, recording the questions it was asked.
class FakeInsightsApi implements InsightsApi {
  final wrappedCalls = <InsightsQuery>[];
  final chartCalls = <InsightsQuery>[];

  /// Every offset [topChart] was asked for, in order. `null` is "the first page", which is what
  /// the Hub's own default means.
  final topChartOffsets = <int?>[];
  final milestoneCalls = <int>[];
  final entityStatsCalls = <(String, String)>[];

  /// How many entities the ranked chart holds, across every page.
  int chartTotal = 0;

  /// Active days in the records window. Zero renders the "nothing yet" card instead of a report.
  int recordsActiveDays = 0;

  /// Thrown by the NEXT chart page, for the revert test.
  Object? chartFailure;
  Object? milestoneFailure;

  @override
  Future<WrappedReport> wrapped(InsightsQuery query) async {
    wrappedCalls.add(query);
    return _report();
  }

  @override
  Future<ListeningCharts> charts(InsightsQuery query) async {
    chartCalls.add(query);
    return ListeningCharts(
      clock: List.filled(24, 0),
      clockGrid: ClockGrid(cells: List.filled(168, 0), timezone: 'UTC'),
      granularity: BucketGranularity.day,
      overTime: const [],
      period: query.period,
      timezone: 'UTC',
      weekday: List.filled(7, 0),
      windowEnd: 0,
      windowStart: 0,
    );
  }

  @override
  Future<ListeningRecords> records(InsightsQuery query) async =>
      ListeningRecords(
        activeDays: recordsActiveDays,
        avgPlaysPerDay: 0,
        avgPlaysPerDayCompared: const Compared(current: 0, previous: 0),
        biggestDayCompared: const Compared(current: 0, previous: 0),
        milestones: const [],
        period: query.period,
        timezone: 'UTC',
        topSessions: const [],
        windowEnd: 0,
        windowStart: 0,
      );

  @override
  Future<DiscoveryStats> discovery(InsightsQuery query) async => DiscoveryStats(
    albumsNew: 0,
    albumsPlayed: 0,
    albumsPlayedCompared: const Compared(current: 0, previous: 0),
    artistsNew: 0,
    artistsPlayed: 0,
    artistsPlayedCompared: const Compared(current: 0, previous: 0),
    period: query.period,
    repeatRate: 0,
    topNewArtists: const [],
    tracksNew: 0,
    tracksPlayed: 0,
    tracksPlayedCompared: const Compared(current: 0, previous: 0),
    windowEnd: 0,
    windowStart: 0,
  );

  @override
  Future<RankMovers> movers(InsightsQuery query, EntityKind kind) async =>
      RankMovers(
        climbers: const [],
        fallers: const [],
        kind: kind,
        newcomers: const [],
        period: query.period,
      );

  @override
  Future<OnThisDay> onThisDay(InsightsQuery query) async =>
      const OnThisDay(timezone: 'UTC', years: []);

  @override
  Future<ChartPage> topChart(
    InsightsQuery query,
    EntityKind kind, {
    int? offset,
    int? limit,
  }) async {
    topChartOffsets.add(offset);
    if (chartFailure != null) throw chartFailure!;
    final start = offset ?? 0;
    final size = limit ?? chartPageSize;
    final rows = (chartTotal - start).clamp(0, size);
    return ChartPage(
      entries: [
        for (var i = 0; i < rows; i++)
          ChartEntry(
            id: 'e${start + i}',
            msPlayed: 60000,
            name: 'Entry ${start + i + 1}',
            plays: 1,
            rank: start + i + 1,
          ),
      ],
      kind: kind,
      offset: start,
      period: query.period,
      total: chartTotal,
      windowEnd: 0,
      windowStart: 0,
    );
  }

  @override
  Future<HistoryPage> history(HistoryCursor cursor, {int? limit}) async =>
      const HistoryPage(entries: []);

  @override
  Future<List<RecentPlay>> recentPlays(String? handle) async => const [];

  @override
  Future<Compatibility> compatibility(String handle) async => Compatibility(
    displayName: handle,
    handle: handle,
    score: 0,
    sharedArtists: const [],
    userId: '$handle-id',
  );

  @override
  Future<List<FriendScrobble>> friendsActivity({int? limit}) async => const [];

  @override
  Future<Milestone> milestone(InsightsQuery query, int n) async {
    milestoneCalls.add(n);
    if (milestoneFailure != null) throw milestoneFailure!;
    return Milestone(
      artist: 'An Artist',
      ordinal: n,
      playedAt: 0,
      title: 'Play $n',
    );
  }

  @override
  Future<EntityStats> entityStats(
    EntityKind kind,
    String id, {
    Period? period,
    String? tz,
  }) async {
    entityStatsCalls.add((kind.wire, id));
    return EntityStats(
      granularity: BucketGranularity.day,
      id: id,
      kind: kind,
      period: period ?? Period.month,
      totalMsPlayed: 60000,
      totalPlays: 1,
      trend: const [],
      windowEnd: 0,
      windowStart: 0,
      firstPlayed: 0,
    );
  }
}
