import '../hub.dart';
import '../json.dart';
import '../models.g.dart';
import 'decode.dart';

/// Listening statistics: charts, records, history and Wrapped.
///
/// Three arguments recur.
///
/// * `user` is a **handle**, and asking about someone else is subject to their scrobble privacy;
///   omitted, every call reports on the caller.
/// * `tz` is an IANA zone name. The Hub buckets by *local* calendar day, so the same events produce
///   a different "on this day" or clock grid depending on it — it is part of the question, not a
///   display detail.
/// * `fromMs`/`toMs` are epoch **milliseconds** and replace `period` with an explicit half-open
///   window. They come as a pair (one alone is rejected), cover only the caller's own data, and are
///   a Deep Analytics feature. Named for their unit because the wire spells them `from`/`to`, which
///   says nothing about what a bare integer there would mean.
extension InsightsEndpoints on HubClient {
  /// The local-calendar activity series and the listening-clock grid.
  Future<ListeningCharts> listeningCharts({
    String? user,
    Period? period,
    String? tz,
    int? fromMs,
    int? toMs,
  }) => get(
    '/v1/insights/charts',
    (json) => ListeningCharts.fromJson(asObject(json)),
    query: {
      'user': user,
      'period': period?.wire,
      'tz': tz,
      'from': fromMs,
      'to': toMs,
    },
  );

  /// Taste overlap with another listener.
  Future<Compatibility> compatibility(String handle) => get(
    '/v1/insights/compatibility/${seg(handle)}',
    (json) => Compatibility.fromJson(asObject(json)),
  );

  /// How much of the window was new music versus repeats.
  Future<DiscoveryStats> discoveryStats({
    String? user,
    Period? period,
    String? tz,
  }) => get(
    '/v1/insights/discovery',
    (json) => DiscoveryStats.fromJson(asObject(json)),
    query: {'user': user, 'period': period?.wire, 'tz': tz},
  );

  /// The caller's own lightweight numbers for one catalog entity — what the card on an artist or
  /// album page shows.
  Future<EntityStats> entityStats({
    required EntityKind kind,
    required String id,
    Period? period,
    String? tz,
  }) => get(
    '/v1/insights/entity',
    (json) => EntityStats.fromJson(asObject(json)),
    query: {'kind': kind.wire, 'id': id, 'period': period?.wire, 'tz': tz},
  );

  /// The heavier clock and top-list scans for one entity. Split from [entityStats] on purpose, so
  /// the inline card never waits on this.
  Future<EntityBreakdown> entityBreakdown({
    required EntityKind kind,
    required String id,
    Period? period,
    String? tz,
  }) => get(
    '/v1/insights/entity/breakdown',
    (json) => EntityBreakdown.fromJson(asObject(json)),
    query: {'kind': kind.wire, 'id': id, 'period': period?.wire, 'tz': tz},
  );

  /// Recent plays across the caller's friends, honouring each one's scrobble privacy.
  Future<List<FriendScrobble>> friendsActivity({int? limit}) => get(
    '/v1/insights/friends-activity',
    (json) => listOf(json, FriendScrobble.fromJson),
    query: {'limit': limit},
  );

  /// One page of the full scrobble history.
  ///
  /// Keyset paging, not offset: pass the last row's timestamp and id back as [beforeMs]/[beforeId].
  /// Both are needed because plays inside the same millisecond are common enough to lose rows.
  Future<HistoryPage> listeningHistory({
    String? user,
    int? beforeMs,
    String? beforeId,
    int? limit,
  }) => get(
    '/v1/insights/history',
    (json) => HistoryPage.fromJson(asObject(json)),
    query: {
      'user': user,
      'before_ms': beforeMs,
      'before_id': beforeId,
      'limit': limit,
    },
  );

  /// The caller's liked songs in numbers.
  Future<LikedStats> likedStats({String? tz}) => get(
    '/v1/insights/liked',
    (json) => LikedStats.fromJson(asObject(json)),
    query: {'tz': tz},
  );

  /// The nth play of a listener's history — the "your 10,000th song" card.
  Future<Milestone> milestone({required int n, String? user}) => get(
    '/v1/insights/milestone',
    (json) => Milestone.fromJson(asObject(json)),
    query: {'n': n, 'user': user},
  );

  /// Who climbed and who fell, comparing this window's chart against the one before it.
  Future<RankMovers> rankMovers({
    required EntityKind kind,
    String? user,
    Period? period,
    String? tz,
  }) => get(
    '/v1/insights/movers',
    (json) => RankMovers.fromJson(asObject(json)),
    query: {'kind': kind.wire, 'user': user, 'period': period?.wire, 'tz': tz},
  );

  /// Plays from earlier years on today's local date.
  Future<OnThisDay> onThisDay({String? user, Period? period, String? tz}) =>
      get(
        '/v1/insights/on-this-day',
        (json) => OnThisDay.fromJson(asObject(json)),
        query: {'user': user, 'period': period?.wire, 'tz': tz},
      );

  Future<List<RecentPlay>> recentPlays({String? user}) => get(
    '/v1/insights/recent',
    (json) => listOf(json, RecentPlay.fromJson),
    query: {'user': user},
  );

  /// Streaks, sessions, day records and milestones.
  Future<ListeningRecords> listeningRecords({
    String? user,
    Period? period,
    String? tz,
    int? fromMs,
    int? toMs,
  }) => get(
    '/v1/insights/records',
    (json) => ListeningRecords.fromJson(asObject(json)),
    query: {
      'user': user,
      'period': period?.wire,
      'tz': tz,
      'from': fromMs,
      'to': toMs,
    },
  );

  /// A page of the listener's *full* ranked chart for one kind — every artist, album or track they
  /// played in the window, not a top five.
  Future<ChartPage> topChart({
    required EntityKind kind,
    String? user,
    Period? period,
    String? tz,
    int? offset,
    int? limit,
    int? fromMs,
    int? toMs,
  }) => get(
    '/v1/insights/top',
    (json) => ChartPage.fromJson(asObject(json)),
    query: {
      'kind': kind.wire,
      'user': user,
      'period': period?.wire,
      'tz': tz,
      'offset': offset,
      'limit': limit,
      'from': fromMs,
      'to': toMs,
    },
  );

  /// The whole Wrapped report for a window.
  Future<WrappedReport> wrapped({
    String? user,
    Period? period,
    String? tz,
    int? fromMs,
    int? toMs,
  }) => get(
    '/v1/insights/wrapped',
    (json) => WrappedReport.fromJson(asObject(json)),
    query: {
      'user': user,
      'period': period?.wire,
      'tz': tz,
      'from': fromMs,
      'to': toMs,
    },
  );
}
