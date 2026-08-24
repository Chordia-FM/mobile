import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../i18n/keys.g.dart';
import '../../../i18n/translations_provider.dart';
import '../data/insights_providers.dart';
import '../format.dart';
import '../share_grid.dart';
import '../widgets/insights_charts.dart';
import '../widgets/insights_primitives.dart';
import '../widgets/top_entity_card.dart';
import '../wrapped_share.dart';

/// A day in milliseconds, for reading a window's length off its own bounds.
const _dayMs = 86400000;

/// How long the window the Hub actually resolved is, which is what the chart-form gates key off.
/// The requested period is not the same thing: "this month" on the second of the month is two days.
int _windowDays(WrappedReport report) =>
    (report.windowEnd - report.windowStart) ~/ _dayMs;

/// The Overview tab: the window's headline numbers, the top three lists, and recent plays.
///
/// The share button appears only when the window has plays in it — a card announcing zero minutes
/// listened is not something anybody wants to post.
class OverviewReport extends ConsumerWidget {
  const OverviewReport({required this.handle, super.key, this.shareHandle});

  /// Whose report, or null for the signed-in listener's own.
  final String? handle;

  /// The handle to stamp on a shared card, which also switches the share button on.
  ///
  /// Whoever the report is ABOUT, not whoever is reading it — a card off a friend's profile is
  /// labelled with the friend, so it cannot publish their listening under the reader's name.
  /// Passed in rather than resolved here so this report needs nothing from the social graph.
  final String? shareHandle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final query = ref.watch(insightsQueryProvider(handle));
    final report = ref.watch(wrappedReportProvider(query));

    return ReportBody<WrappedReport>(
      value: report,
      onRetry: () => ref.invalidate(wrappedReportProvider(query)),
      builder: (context, value) => value.totalPlays == 0
          ? ReportEmpty(
              title: t(InsightsKeys.emptyOverviewTitle),
              body: t(InsightsKeys.emptyOverviewBody),
            )
          : _Overview(report: value, handle: handle, shareHandle: shareHandle),
    );
  }
}

class _Overview extends ConsumerWidget {
  const _Overview({
    required this.report,
    required this.handle,
    required this.shareHandle,
  });

  final WrappedReport report;
  final String? handle;
  final String? shareHandle;

  /// The cover collage, or nothing when the list cannot fill a square.
  ///
  /// Below four covers the card's own artwork already says everything the grid would, and a ragged
  /// last row reads as broken rather than as a collage.
  Widget? _shareGrid(List<TopItem> items, EntityKind kind) => items.length < 4
      ? null
      : ShareGridButton(
          kind: kind,
          items: items,
          handle: shareHandle ?? '',
          period: report.period,
          windowStart: report.windowStart,
          windowEnd: report.windowEnd,
        );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final showDelta = comparable(report);
    final recent = ref.watch(recentPlaysProvider(handle)).value ?? const [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (shareHandle case final stamp?)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: OutlinedButton.icon(
              onPressed: () =>
                  shareWrappedCard(context, ref, report, handle: stamp),
              icon: const Icon(Icons.ios_share_rounded),
              label: Text(t(InsightsKeys.rotationShareButton)),
            ),
          ),
        // The window has a predecessor but nothing was in it, so every metric would carry a "New"
        // chip that says the same thing five times. One line says it once.
        if (!showDelta && report.period != Period.overall)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Text(
              t(InsightsKeys.overviewFirstWindow),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        const SizedBox(height: 16),
        StatGrid(
          tiles: [
            StatTile(
              label: t(InsightsKeys.statsPlays),
              value: '${report.totalPlays}',
              compared: report.totalPlaysCompared,
              showDelta: showDelta,
            ),
            StatTile(
              label: t(InsightsKeys.statsTimeListened),
              value: msToTime(report.totalMsPlayed, t),
              compared: report.totalMsPlayedCompared,
              showDelta: showDelta,
            ),
            StatTile(
              label: t(InsightsKeys.statsUniqueArtists),
              value: '${report.uniqueArtists}',
              compared: report.uniqueArtistsCompared,
              showDelta: showDelta,
            ),
            StatTile(
              label: t(InsightsKeys.statsUniqueTracks),
              value: '${report.uniqueTracks}',
              compared: report.uniqueTracksCompared,
              showDelta: showDelta,
            ),
          ],
        ),
        const SizedBox(height: 24),
        // Hero cards, not three ranked lists: the #1 leads with its artwork and the runners-up sit
        // under it. Same data, but it is the hierarchy that makes the Overview read as a report.
        TopEntityCard(
          title: t(InsightsKeys.topCardArtist),
          items: report.topArtists,
          kind: EntityKind.artist,
          action: _shareGrid(report.topArtists, EntityKind.artist),
        ),
        TopEntityCard(
          title: t(InsightsKeys.topCardAlbum),
          items: report.topAlbums,
          kind: EntityKind.album,
          action: _shareGrid(report.topAlbums, EntityKind.album),
        ),
        TopEntityCard(
          title: t(InsightsKeys.topCardTrack),
          items: report.topTracks,
          kind: EntityKind.track,
        ),
        // Genre mix needs enough buckets to read as a flow rather than as a couple of columns;
        // over a day or two the series is too short to show drift, and the top-genre list below
        // says it better.
        if (_windowDays(report) >= 7)
          ReportPanel(
            title: t(InsightsKeys.panelsGenreFlow),
            child: GenreFlow(
              trend: report.genreTrend,
              granularity: report.period == Period.overall
                  ? BucketGranularity.month
                  : BucketGranularity.day,
              windowStart: report.windowStart,
              windowEnd: report.windowEnd,
            ),
          ),
        ReportPanel(
          title: t(InsightsKeys.panelsFingerprint),
          child: FingerprintRadar(
            you: report.fingerprint.you,
            average: report.fingerprint.globalAverage,
            // The legend contrasts this listener against the hub average, so on somebody else's
            // profile the primary series has to be named as theirs rather than as "You".
            youLabel: handle == null ? null : '@$handle',
          ),
        ),
        ReportPanel(
          title: t(InsightsKeys.panelsMusicRatio),
          child: MusicRatioRings(
            ariaLabel: t(InsightsKeys.ratioAriaLabel, {
              'tracks': report.uniqueTracks,
              'albums': report.uniqueAlbums,
              'artists': report.uniqueArtists,
            }),
            items: [
              RatioItem(
                label: t(InsightsKeys.discoveryKindsTrack),
                value: report.uniqueTracks,
                compared: report.uniqueTracksCompared,
                showDelta: showDelta,
              ),
              RatioItem(
                label: t(InsightsKeys.discoveryKindsAlbum),
                value: report.uniqueAlbums,
                compared: report.uniqueAlbumsCompared,
                showDelta: showDelta,
              ),
              RatioItem(
                label: t(InsightsKeys.discoveryKindsArtist),
                value: report.uniqueArtists,
                compared: report.uniqueArtistsCompared,
                showDelta: showDelta,
              ),
            ],
          ),
        ),
        // The one ranked list on this page that IS panelled, because the web panels it too
        // (`ListenerReport.tsx:542`) — there it is a chip cloud rather than a list of rows, and a
        // chip cloud has no edges of its own to sit on.
        if (report.topGenres.isNotEmpty)
          ReportPanel(
            title: t(InsightsKeys.topGenres),
            child: TopList.genres(items: report.topGenres, limit: 8),
          ),
        if (report.decades.any((bucket) => bucket.plays > 0))
          ReportPanel(
            title: t(InsightsKeys.panelsDecades),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                BarChart(
                  bars: [
                    for (final bucket in report.decades)
                      BarDatum(
                        t(InsightsKeys.decadesLabel, {'decade': bucket.decade}),
                        bucket.plays,
                      ),
                  ],
                ),
                // Without this line the bars imply a fully dated catalog. A fifth of a collection
                // with no release date is a normal state, and saying so is what stops the decade
                // shape being read as the whole story.
                if (report.undatedReleaseShare >= 0.005)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Text(
                      t(InsightsKeys.decadesUndated, {
                        'pct': NumberFormat.decimalPercentPattern(
                          locale: ref.watch(translationsProvider).locale,
                          decimalDigits: 0,
                        ).format(report.undatedReleaseShare),
                      }),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        if (recent.isNotEmpty) ...[
          ReportHeading(title: t(InsightsKeys.recentlyPlayed)),
          for (final play in recent.take(10))
            PlayRow(
              key: ValueKey(play.eventId),
              title: play.title,
              artist: play.artist,
              playedAt: play.playedAt,
              imageUrl: play.imageUrl,
              trackId: play.trackId,
              artistId: play.artistId,
            ),
        ],
        const SizedBox(height: 32),
      ],
    );
  }
}
