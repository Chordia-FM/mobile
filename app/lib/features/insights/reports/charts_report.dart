import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../i18n/keys.g.dart';
import '../../../i18n/translations_provider.dart';
import '../../social/data/social_messages.dart';
import '../data/insights_providers.dart';
import '../entity_stats_screen.dart';
import '../format.dart';
import '../widgets/insights_charts.dart';
import '../widgets/insights_primitives.dart';

/// A day's worth of milliseconds, for reading a window's length off its bounds.
const _dayMs = 86400000;

/// The Charts tab: when the listening happened, and the full ranked chart behind the top five.
class ChartsReport extends ConsumerStatefulWidget {
  const ChartsReport({required this.handle, super.key, this.own = false});

  final String? handle;

  /// Whether the report is about the reader, which is what the catalogs' `person` select needs.
  final bool own;

  @override
  ConsumerState<ChartsReport> createState() => _ChartsReportState();
}

class _ChartsReportState extends ConsumerState<ChartsReport> {
  EntityKind _kind = EntityKind.artist;

  @override
  Widget build(BuildContext context) {
    final t = ref.t;
    final query = ref.watch(insightsQueryProvider(widget.handle));
    final charts = ref.watch(listeningChartsProvider(query));

    return ReportBody<ListeningCharts>(
      value: charts,
      onRetry: () => ref.invalidate(listeningChartsProvider(query)),
      builder: (context, value) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Activity(charts: value),
          ReportHeading(title: t(InsightsKeys.panelsListeningClock)),
          BarChart(bars: _clockBars(value, ref)),
          // A window shorter than a fortnight spans one or two weekdays, so seven bars would be
          // five empty ones and a claim about a pattern that cannot exist yet.
          if (_windowDays(value) >= 14) ...[
            ReportHeading(title: t(InsightsKeys.panelsByWeekday)),
            BarChart(
              bars: [
                for (final (day, plays) in value.weekday.indexed)
                  BarDatum(weekdayLabel(day, t), plays),
              ],
            ),
          ],
          // Below about three weeks each (weekday, hour) cell holds at most a couple of samples —
          // noise, not a pattern — so the 7x24 grid only appears once the window can feed it. The
          // clock and weekday bars above always show, so nothing vanishes on a short period; the
          // grid is their cross, not a replacement for either.
          if (_windowDays(value) >= 21) ...[
            ReportHeading(title: t(InsightsKeys.panelsClockHeatmap)),
            ClockGridHeatmap(grid: value.clockGrid),
          ],
          ReportHeading(
            title: t(switch (_kind) {
              EntityKind.artist => InsightsKeys.topArtists,
              EntityKind.album => InsightsKeys.topAlbums,
              EntityKind.track => InsightsKeys.topTracks,
            }),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<EntityKind>(
              segments: [
                ButtonSegment(
                  value: EntityKind.artist,
                  label: Text(t(InsightsKeys.discoveryKindsArtist)),
                ),
                ButtonSegment(
                  value: EntityKind.album,
                  label: Text(t(InsightsKeys.discoveryKindsAlbum)),
                ),
                ButtonSegment(
                  value: EntityKind.track,
                  label: Text(t(InsightsKeys.discoveryKindsTrack)),
                ),
              ],
              selected: {_kind},
              onSelectionChanged: (selection) =>
                  setState(() => _kind = selection.first),
            ),
          ),
          _FullChart(
            request: ChartRequest(query: query, kind: _kind),
            own: widget.own,
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  int _windowDays(ListeningCharts charts) =>
      (charts.windowEnd - charts.windowStart) ~/ _dayMs;

  /// One bar per local hour, labelled in the reader's own clock convention.
  ///
  /// `DateFormat.j` is the localisation here — it is what turns hour 13 into "1 PM" or "13:00" —
  /// so there is no catalog string to keep in step with it. The date the hours are hung on is
  /// arbitrary and never shown.
  List<BarDatum> _clockBars(ListeningCharts charts, WidgetRef ref) {
    final clock = DateFormat.j(ref.watch(translationsProvider).locale);
    return [
      for (final (hour, plays) in charts.clock.indexed)
        BarDatum(clock.format(DateTime(2000, 1, 1, hour)), plays),
    ];
  }
}

/// Plays over the window, in whatever buckets the Hub chose.
class _Activity extends ConsumerWidget {
  const _Activity({required this.charts});

  final ListeningCharts charts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    if (charts.overTime.every((bucket) => bucket.plays == 0)) {
      return ReportEmpty(title: t(InsightsKeys.chartNoActivityPeriod));
    }
    // One over-time view, never two of the same data. Bar rows while individual days still read as
    // a trend; past about twenty weeks a calendar, because a year of daily cells shows streaks and
    // seasonality that 365 stacked rows cannot — and the truncation those rows needed was answering
    // a question nobody asked, since "the last 30 days" is a different report from "this year".
    final windowDays = (charts.windowEnd - charts.windowStart) ~/ _dayMs;
    if (charts.granularity == BucketGranularity.day && windowDays >= 140) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ReportHeading(title: t(InsightsKeys.panelsActivity)),
          CalendarHeatmap(
            buckets: charts.overTime,
            windowStart: charts.windowStart,
            windowEnd: charts.windowEnd,
          ),
        ],
      );
    }
    final buckets = charts.overTime.length > 30
        ? charts.overTime.sublist(charts.overTime.length - 30)
        : charts.overTime;
    final locale = ref.watch(translationsProvider).locale;
    final label = charts.granularity == BucketGranularity.month
        ? DateFormat.yMMM(locale)
        : DateFormat.MMMd(locale);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ReportHeading(title: t(InsightsKeys.panelsActivity)),
        BarChart(
          bars: [
            for (final bucket in buckets)
              BarDatum(
                label.format(DateTime.fromMillisecondsSinceEpoch(bucket.start)),
                bucket.plays,
              ),
          ],
        ),
      ],
    );
  }
}

/// The listener's full ranked chart, one page at a time.
///
/// The Hub's `offset` is what makes rank 26 reachable at all. It was a parameter this screen never
/// passed, so the chart stopped dead at 25 rows while the line above it went on claiming "1-25 of
/// 412" — the count was right and the list was a lie.
class _FullChart extends ConsumerWidget {
  const _FullChart({required this.request, required this.own});

  final ChartRequest request;
  final bool own;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final feed = ref.watch(topChartProvider(request));

    return ReportBody<ChartFeed>(
      value: feed,
      onRetry: () => ref.invalidate(topChartProvider(request)),
      builder: (context, value) => value.entries.isEmpty
          ? ReportEmpty(
              title: t(InsightsKeys.chartsEmptyTitle),
              body: t(InsightsKeys.chartsEmptyBody, personArg(own: own)),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text(
                    // Counted from the rows in hand, not from the page that just landed: every
                    // page loaded so far is still on screen, so "1-50 of 412" is the honest line
                    // after a second page.
                    t(InsightsKeys.chartsShowing, {
                      'from': 1,
                      'to': value.entries.length,
                      'total': value.total,
                    }),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                for (final entry in value.entries)
                  _ChartRow(entry: entry, kind: value.kind),
                if (value.nextOffset != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Center(
                      child: OutlinedButton(
                        onPressed: value.loadingMore
                            ? null
                            : () => _loadMore(context, ref),
                        child: Text(
                          t(
                            value.loadingMore
                                ? CommonKeys.statesLoading
                                : CommonKeys.actionsSeeMore,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Future<void> _loadMore(BuildContext context, WidgetRef ref) async {
    final t = ref.read(translationsProvider).call;
    try {
      await ref.read(topChartProvider(request).notifier).loadMore();
    } on Object catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(describeSocialError(error, t))));
    }
  }
}

class _ChartRow extends ConsumerWidget {
  const _ChartRow({required this.entry, required this.kind});

  final ChartEntry entry;
  final EntityKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: SizedBox(
        width: 32,
        child: Text(
          '${entry.rank}',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
      title: Text(entry.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          ?entry.subtitle,
          t(InsightsKeys.topPlaysCount, {'count': entry.plays}),
          msToTime(entry.msPlayed, t),
        ].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      // Drilling from "what did I play" into "how do I play it" is the whole point of the entity
      // page, and a ranked row is where that question is asked — on anybody's chart. This used to
      // be gated on the chart being the reader's own, on the grounds that `/v1/insights/entity`
      // reports on the caller; that left row 87 of a friend's chart with nowhere to go at all,
      // which is worse. The web links every row for the same reason, and the page it opens is
      // written throughout in the second person ("of N artists you played"), so it cannot be
      // mistaken for a report about the profile it was opened from.
      onTap: () =>
          showEntityStats(context, kind: kind, id: entry.id, name: entry.name),
      trailing: _RankMove(rank: entry.rank, previous: entry.prevRank),
    );
  }
}

class _RankMove extends ConsumerWidget {
  const _RankMove({required this.rank, required this.previous});

  final int rank;
  final int? previous;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final theme = Theme.of(context);
    // No previous rank is not a fall from infinity — it means the entry was not in the last
    // window's chart at all, which is a different fact and gets different copy.
    if (previous == null) {
      return Text(
        t(InsightsKeys.chartsNew),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.primary,
        ),
      );
    }
    final delta = previous! - rank;
    if (delta == 0) {
      return Text(
        t(InsightsKeys.chartsHeld),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }
    final up = delta > 0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
          size: 14,
          color: up ? theme.colorScheme.primary : theme.colorScheme.error,
        ),
        Text(
          '${delta.abs()}',
          semanticsLabel: t(
            up ? InsightsKeys.chartsUp : InsightsKeys.chartsDown,
            {'count': delta.abs()},
          ),
          style: theme.textTheme.labelSmall,
        ),
      ],
    );
  }
}
