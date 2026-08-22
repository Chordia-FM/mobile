import 'package:chordia_api/chordia_api.dart';
import 'package:chordia_mobile/app/theme.dart';
import 'package:chordia_mobile/features/insights/data/insights_api.dart';
import 'package:chordia_mobile/features/insights/data/insights_providers.dart';
import 'package:chordia_mobile/features/insights/format.dart';
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
        activeDays: 0,
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
  }) async => ChartPage(
    entries: const [],
    kind: kind,
    offset: offset ?? 0,
    period: query.period,
    total: 0,
    windowEnd: 0,
    windowStart: 0,
  );

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
}
