import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import 'insights_api.dart';

/// Riverpod 3 retries an errored provider on its own, with a backoff. Switched off here for the
/// reason the catalog switched it off: these screens show a failure with a Retry button, and a
/// silent background retry both contradicts that button and leaves a pending timer in widget tests.
Duration? _noAutoRetry(int attempt, Object error) => null;

/// The windows the period pills offer, shortest first.
///
/// Deliberately not every [Period] the contract has — the set mirrors the web client's pill row, so
/// the same person switching devices sees the same seven windows with the same labels.
const insightsPeriods = <Period>[
  Period.day,
  Period.week,
  Period.month,
  Period.quarter,
  Period.halfYear,
  Period.year,
  Period.overall,
];

/// The reporting window every insights surface reads.
///
/// App-wide rather than per screen: moving from your own charts to a friend's and back should not
/// silently re-ask a different question, and a period chosen on one tab is the one the next tab
/// should already be showing.
class InsightsPeriodController extends Notifier<Period> {
  @override
  Period build() => Period.month;

  void set(Period period) => state = period;
}

final insightsPeriodProvider =
    NotifierProvider<InsightsPeriodController, Period>(
      InsightsPeriodController.new,
    );

/// The zone the caller's own reports are bucketed in, or null to let the Hub decide.
///
/// Only an explicit setting is sent. Dart has no IANA zone name for the device — the platform gives
/// an abbreviation like "GMT+2", which the Hub cannot resolve — so guessing one would be inventing
/// the answer to a question the Hub can answer correctly from the account's own setting.
final insightsTimezoneProvider = Provider<String?>((ref) {
  final zone = ref.watch(userSettingsProvider).value?.timezone;
  return (zone == null || zone.isEmpty) ? null : zone;
});

/// The query for one listener, at the currently selected period.
///
/// [handle] is null for the caller's own report. A family so a profile screen and the viewer's own
/// insights can be on screen at once without sharing a key.
final insightsQueryProvider = Provider.autoDispose.family<InsightsQuery, String?>(
  (ref, handle) => InsightsQuery(
    handle: handle,
    period: ref.watch(insightsPeriodProvider),
    // Someone else's report is bucketed in *their* zone, which only the Hub knows.
    timezone: handle == null ? ref.watch(insightsTimezoneProvider) : null,
  ),
);

final wrappedReportProvider = FutureProvider.autoDispose
    .family<WrappedReport, InsightsQuery>(
      (ref, query) => ref.watch(insightsApiProvider).wrapped(query),
      retry: _noAutoRetry,
    );

final listeningChartsProvider = FutureProvider.autoDispose
    .family<ListeningCharts, InsightsQuery>(
      (ref, query) => ref.watch(insightsApiProvider).charts(query),
      retry: _noAutoRetry,
    );

final listeningRecordsProvider = FutureProvider.autoDispose
    .family<ListeningRecords, InsightsQuery>(
      (ref, query) => ref.watch(insightsApiProvider).records(query),
      retry: _noAutoRetry,
    );

final discoveryStatsProvider = FutureProvider.autoDispose
    .family<DiscoveryStats, InsightsQuery>(
      (ref, query) => ref.watch(insightsApiProvider).discovery(query),
      retry: _noAutoRetry,
    );

final onThisDayProvider = FutureProvider.autoDispose
    .family<OnThisDay, InsightsQuery>(
      (ref, query) => ref.watch(insightsApiProvider).onThisDay(query),
      retry: _noAutoRetry,
    );

/// A chart read that also names which kind of entity it is about.
@immutable
class ChartRequest {
  const ChartRequest({required this.query, required this.kind});

  final InsightsQuery query;
  final EntityKind kind;

  @override
  bool operator ==(Object other) =>
      other is ChartRequest && other.query == query && other.kind == kind;

  @override
  int get hashCode => Object.hash(query, kind);
}

/// How many chart rows one page holds. A phone scrolls; it does not page a table.
const chartPageSize = 25;

final topChartProvider = FutureProvider.autoDispose
    .family<ChartPage, ChartRequest>(
      (ref, request) => ref
          .watch(insightsApiProvider)
          .topChart(request.query, request.kind, limit: chartPageSize),
      retry: _noAutoRetry,
    );

final rankMoversProvider = FutureProvider.autoDispose
    .family<RankMovers, ChartRequest>(
      (ref, request) =>
          ref.watch(insightsApiProvider).movers(request.query, request.kind),
      retry: _noAutoRetry,
    );

final recentPlaysProvider = FutureProvider.autoDispose
    .family<List<RecentPlay>, String?>(
      (ref, handle) => ref.watch(insightsApiProvider).recentPlays(handle),
      retry: _noAutoRetry,
    );

final compatibilityProvider = FutureProvider.autoDispose
    .family<Compatibility, String>(
      (ref, handle) => ref.watch(insightsApiProvider).compatibility(handle),
      retry: _noAutoRetry,
    );

final friendsActivityProvider =
    FutureProvider.autoDispose<List<FriendScrobble>>(
      (ref) => ref.watch(insightsApiProvider).friendsActivity(limit: 30),
      retry: _noAutoRetry,
    );

/// How many history rows one page holds.
const historyPageSize = 50;

/// A listener's scrobble history, paged by hand.
///
/// Keyset paging, not offset: the Hub cursors on the last row's `(played_at, event_id)` pair, and
/// both halves are needed because plays inside the same millisecond are common enough to lose rows.
/// A notifier rather than a `FutureProvider` because "load more" appends to what is already on
/// screen, and a family keyed by cursor would re-render the page from the top on every tap.
class HistoryController extends AsyncNotifier<HistoryFeed> {
  HistoryController(this.handle);

  /// Whose history, or null for the caller's own.
  final String? handle;

  @override
  Future<HistoryFeed> build() async {
    final page = await ref
        .watch(insightsApiProvider)
        .history(HistoryCursor(handle: handle), limit: historyPageSize);
    return HistoryFeed(entries: page.entries, next: _cursorOf(page));
  }

  /// Appends the next page. Silently does nothing at the end of the history, which is what "no
  /// cursor" means.
  Future<void> loadMore() async {
    final current = state.value;
    final next = current?.next;
    if (current == null || next == null || current.loadingMore) return;
    state = AsyncData(current.copyWith(loadingMore: true));
    try {
      final page = await ref
          .read(insightsApiProvider)
          .history(next, limit: historyPageSize);
      state = AsyncData(
        HistoryFeed(
          entries: [...current.entries, ...page.entries],
          next: _cursorOf(page),
        ),
      );
    } on Object {
      // The rows already on screen are still true, so the failure costs the page rather than the
      // feed; the button comes back and the reader can try again.
      state = AsyncData(current.copyWith(loadingMore: false));
      rethrow;
    }
  }

  HistoryCursor? _cursorOf(HistoryPage page) {
    final ms = page.nextBeforeMs;
    final id = page.nextBeforeId;
    return ms == null || id == null
        ? null
        : HistoryCursor(handle: handle, beforeMs: ms, beforeId: id);
  }
}

@immutable
class HistoryFeed {
  const HistoryFeed({
    required this.entries,
    this.next,
    this.loadingMore = false,
  });

  final List<HistoryEntry> entries;

  /// Where the next page starts, or null at the beginning of the listener's history.
  final HistoryCursor? next;

  final bool loadingMore;

  HistoryFeed copyWith({bool? loadingMore}) => HistoryFeed(
    entries: entries,
    next: next,
    loadingMore: loadingMore ?? this.loadingMore,
  );
}

final historyControllerProvider = AsyncNotifierProvider.autoDispose
    .family<HistoryController, HistoryFeed, String?>(
      HistoryController.new,
      retry: _noAutoRetry,
    );
