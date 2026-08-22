import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';

/// Who a report is about, over what window, bucketed in which zone.
///
/// One value rather than three loose arguments because it is also the **cache key**: two reads with
/// the same handle, period and zone are the same question, and letting them differ by argument
/// order would fetch the same window twice.
@immutable
class InsightsQuery {
  const InsightsQuery({this.handle, this.period = Period.month, this.timezone});

  /// The listener's handle, or null for the caller's own report.
  final String? handle;

  final Period period;

  /// IANA zone to bucket by, or null to let the Hub resolve it.
  ///
  /// Null when viewing somebody else, and that is load-bearing: a listening clock or a weekday
  /// split describes when *they* listen, so bucketing their plays against the viewer's midnight
  /// would describe nobody's day. The Hub then uses that listener's own setting, and every response
  /// carries the zone it was computed in.
  final String? timezone;

  InsightsQuery withPeriod(Period next) =>
      InsightsQuery(handle: handle, period: next, timezone: timezone);

  @override
  bool operator ==(Object other) =>
      other is InsightsQuery &&
      other.handle == handle &&
      other.period == period &&
      other.timezone == timezone;

  @override
  int get hashCode => Object.hash(handle, period, timezone);

  @override
  String toString() =>
      'InsightsQuery(handle: $handle, period: ${period.wire}, tz: $timezone)';
}

/// One page of a listener's history, addressed by the keyset cursor of the page before it.
@immutable
class HistoryCursor {
  const HistoryCursor({this.handle, this.beforeMs, this.beforeId});

  final String? handle;

  /// Both halves of the cursor, or neither: plays inside the same millisecond are common enough
  /// that a timestamp alone loses rows, and the Hub rejects one without the other.
  final int? beforeMs;
  final String? beforeId;

  @override
  bool operator ==(Object other) =>
      other is HistoryCursor &&
      other.handle == handle &&
      other.beforeMs == beforeMs &&
      other.beforeId == beforeId;

  @override
  int get hashCode => Object.hash(handle, beforeMs, beforeId);
}

/// Everything the insights screens ask the Hub for.
///
/// Narrow on purpose — one method per call these screens actually make, so a fake is a few lines
/// rather than the whole insights tag. It exists because `HubClient`'s calls are extension methods,
/// which dispatch statically and can therefore never be intercepted by a subclass.
abstract interface class InsightsApi {
  Future<WrappedReport> wrapped(InsightsQuery query);

  Future<ListeningCharts> charts(InsightsQuery query);

  Future<ListeningRecords> records(InsightsQuery query);

  Future<DiscoveryStats> discovery(InsightsQuery query);

  Future<RankMovers> movers(InsightsQuery query, EntityKind kind);

  Future<OnThisDay> onThisDay(InsightsQuery query);

  Future<ChartPage> topChart(
    InsightsQuery query,
    EntityKind kind, {
    int? offset,
    int? limit,
  });

  Future<HistoryPage> history(HistoryCursor cursor, {int? limit});

  Future<List<RecentPlay>> recentPlays(String? handle);

  Future<Compatibility> compatibility(String handle);

  Future<List<FriendScrobble>> friendsActivity({int? limit});
}

/// [InsightsApi] over the real Hub.
class HubInsightsApi implements InsightsApi {
  const HubInsightsApi(this._hub);

  final HubClient _hub;

  @override
  Future<WrappedReport> wrapped(InsightsQuery query) => _hub.wrapped(
    user: query.handle,
    period: query.period,
    tz: query.timezone,
  );

  @override
  Future<ListeningCharts> charts(InsightsQuery query) => _hub.listeningCharts(
    user: query.handle,
    period: query.period,
    tz: query.timezone,
  );

  @override
  Future<ListeningRecords> records(InsightsQuery query) =>
      _hub.listeningRecords(
        user: query.handle,
        period: query.period,
        tz: query.timezone,
      );

  @override
  Future<DiscoveryStats> discovery(InsightsQuery query) => _hub.discoveryStats(
    user: query.handle,
    period: query.period,
    tz: query.timezone,
  );

  @override
  Future<RankMovers> movers(InsightsQuery query, EntityKind kind) =>
      _hub.rankMovers(
        kind: kind,
        user: query.handle,
        period: query.period,
        tz: query.timezone,
      );

  @override
  Future<OnThisDay> onThisDay(InsightsQuery query) => _hub.onThisDay(
    user: query.handle,
    period: query.period,
    tz: query.timezone,
  );

  @override
  Future<ChartPage> topChart(
    InsightsQuery query,
    EntityKind kind, {
    int? offset,
    int? limit,
  }) => _hub.topChart(
    kind: kind,
    user: query.handle,
    period: query.period,
    tz: query.timezone,
    offset: offset,
    limit: limit,
  );

  @override
  Future<HistoryPage> history(HistoryCursor cursor, {int? limit}) =>
      _hub.listeningHistory(
        user: cursor.handle,
        beforeMs: cursor.beforeMs,
        beforeId: cursor.beforeId,
        limit: limit,
      );

  @override
  Future<List<RecentPlay>> recentPlays(String? handle) =>
      _hub.recentPlays(user: handle);

  @override
  Future<Compatibility> compatibility(String handle) =>
      _hub.compatibility(handle);

  @override
  Future<List<FriendScrobble>> friendsActivity({int? limit}) =>
      _hub.friendsActivity(limit: limit);
}

/// Thrown when an insights screen is somehow reached with no hub selected.
class InsightsUnavailableException implements Exception {
  const InsightsUnavailableException();

  @override
  String toString() => 'No hub is selected, so listening stats cannot be read.';
}

/// The insights call surface for the active hub. Overridden with a fake in tests.
final insightsApiProvider = Provider<InsightsApi>((ref) {
  final hub = ref.watch(hubClientProvider);
  if (hub == null) throw const InsightsUnavailableException();
  return HubInsightsApi(hub);
});
