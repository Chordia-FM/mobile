import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import 'data/insights_providers.dart';
import 'format.dart';
import 'widgets/insights_primitives.dart';

/// How one artist, album or track sits in **the reader's own** listening.
///
/// The web has this as three routes under `/app/{artists,albums,tracks}/…/stats`, all rendering one
/// parameterised view (`components/insights/EntityStatsView.tsx`); this is the same page, reached
/// from a chart row. It is deliberately about the caller and nobody else — `/v1/insights/entity`
/// takes no `user`, because "how do I play this" is a question only the asker's history answers.
///
/// The layout follows the web's contract: the identity and its period-independent anchors sit
/// **above** the period pills, and everything below them is scoped by the selected window, so no
/// two numbers on screen ever describe different questions.
class EntityStatsScreen extends ConsumerWidget {
  const EntityStatsScreen({
    required this.kind,
    required this.id,
    super.key,
    this.name,
  });

  final EntityKind kind;
  final String id;

  /// What to call it. The stats endpoint answers with numbers, not a name, so the row that linked
  /// here supplies one — a deep link that arrives without it gets the kind instead of a blank bar.
  final String? name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final eyebrow = t(switch (kind) {
      EntityKind.artist => InsightsKeys.entityEyebrowArtist,
      EntityKind.album => InsightsKeys.entityEyebrowAlbum,
      EntityKind.track => InsightsKeys.entityEyebrowTrack,
    });
    final request = EntityStatsRequest(
      kind: kind,
      id: id,
      period: ref.watch(insightsPeriodProvider),
      // The reader's own zone, unlike every report that can be about somebody else: these figures
      // are always about them, so there is no other listener's midnight to respect.
      timezone: ref.watch(insightsTimezoneProvider),
    );
    final stats = ref.watch(entityStatsProvider(request));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          name ?? eyebrow,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(
              eyebrow,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const PeriodSelector(),
          ReportBody<EntityStats>(
            value: stats,
            onRetry: () => ref.invalidate(entityStatsProvider(request)),
            builder: (context, value) => _Stats(stats: value, kind: kind),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _Stats extends ConsumerWidget {
  const _Stats({required this.stats, required this.kind});

  final EntityStats stats;
  final EntityKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final locale = ref.watch(translationsProvider).locale;
    final date = DateFormat.yMMMd(locale);

    // Never played is not the same as "not played in this window", and the two get different copy:
    // one is an invitation, the other is a window that is simply too narrow. `first_played` is
    // all-time, so it is what tells them apart.
    if (stats.firstPlayed == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ReportEmpty(
            title: t(InsightsKeys.entityNeverTitle),
            body: t(switch (kind) {
              EntityKind.artist => InsightsKeys.entityNeverArtist,
              EntityKind.album => InsightsKeys.entityNeverAlbum,
              EntityKind.track => InsightsKeys.entityNeverTrack,
            }),
          ),
          if (stats.globalPlays case final global?)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                t(InsightsKeys.entityNeverHub, {'count': global}),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        StatGrid(
          tiles: [
            StatTile(
              label: t(InsightsKeys.statsPlays),
              value: t(InsightsKeys.statsPlaysValue, {
                'count': stats.totalPlays,
              }),
              showDelta: false,
            ),
            StatTile(
              label: t(InsightsKeys.statsTime),
              value: msToTime(stats.totalMsPlayed, t),
              showDelta: false,
            ),
            // Rank only exists when they played it inside the window: outside it the Hub sends no
            // rank at all, and printing a zero there would invent a position.
            if (stats.rank case final rank?)
              StatTile(
                label: t(
                  switch (kind) {
                    EntityKind.artist => InsightsKeys.entityTilesRankOfArtist,
                    EntityKind.album => InsightsKeys.entityTilesRankOfAlbum,
                    EntityKind.track => InsightsKeys.entityTilesRankOfTrack,
                  },
                  {'total': stats.rankTotal ?? 0},
                ),
                value: t(InsightsKeys.entityTilesRankValue, {'rank': rank}),
                showDelta: false,
              ),
            // Everyone's plays, not the reader's — labelled as such, because an unlabelled number
            // beside four personal ones reads as another personal one.
            if (stats.globalPlays case final global?)
              StatTile(
                label: t(InsightsKeys.entityScopeGlobal),
                value: t(InsightsKeys.entityAlltime, {'count': global}),
                showDelta: false,
              ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Text(
            [
              t(InsightsKeys.entitySince, {
                'date': date.format(
                  DateTime.fromMillisecondsSinceEpoch(stats.firstPlayed!),
                ),
              }),
              if (stats.lastPlayed case final last?)
                relativePlayTime(last, t, locale: locale),
            ].join(' · '),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        // A window the entity has plays in, but not these ones. Saying so beats an empty chart that
        // looks like a load failure.
        if (stats.totalPlays == 0)
          ReportEmpty(
            title: t(InsightsKeys.entityQuietTitle),
            body: t(InsightsKeys.entityQuietCta),
          )
        else
          // `EntityStatsView.tsx:527` — the same `Panel` the dashboard's activity chart sits in.
          ReportPanel(
            title: t(InsightsKeys.panelsActivity),
            child: BarChart(bars: _trendBars(stats, locale)),
          ),
      ],
    );
  }

  /// The play trend, in whatever buckets the Hub chose for the window.
  ///
  /// The tail, not the head: a year of daily buckets is 365 rows, and the question a reader has in
  /// front of this chart is "how have I been playing it lately".
  List<BarDatum> _trendBars(EntityStats stats, String locale) {
    final buckets = stats.trend.length > 30
        ? stats.trend.sublist(stats.trend.length - 30)
        : stats.trend;
    final label = stats.granularity == BucketGranularity.month
        ? DateFormat.yMMM(locale)
        : DateFormat.MMMd(locale);
    return [
      for (final bucket in buckets)
        BarDatum(
          label.format(DateTime.fromMillisecondsSinceEpoch(bucket.start)),
          bucket.plays,
        ),
    ];
  }
}

/// Opens the entity stats page over whatever raised it.
///
/// A plain `MaterialPageRoute` rather than a `go_router` path, because this page is reached from a
/// chart that can be sitting in ANY of the four tabs — a profile opened from Search puts its charts
/// under `/search`, and `insightsRoutes()` is spread only under `/you`. Pushing onto the branch's
/// own navigator keeps the tab's back stack, which is the whole point of the relative-route rule,
/// without needing the route table to exist four times.
Future<void> showEntityStats(
  BuildContext context, {
  required EntityKind kind,
  required String id,
  String? name,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => EntityStatsScreen(kind: kind, id: id, name: name),
  ),
);
