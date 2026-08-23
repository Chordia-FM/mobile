import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../i18n/keys.g.dart';
import '../../../i18n/translations_provider.dart';
import '../data/insights_providers.dart';
import '../format.dart';
import '../widgets/insights_primitives.dart';
import '../wrapped_share.dart';

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
  /// Null on somebody else's profile: their listening is theirs to publish. Passed in rather than
  /// resolved here so this report needs nothing from the social graph.
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
        ReportHeading(title: t(InsightsKeys.topArtists)),
        TopList(items: report.topArtists, kind: EntityKind.artist, limit: 10),
        ReportHeading(title: t(InsightsKeys.topAlbums)),
        TopList(items: report.topAlbums, kind: EntityKind.album, limit: 10),
        ReportHeading(title: t(InsightsKeys.topTracks)),
        TopList(items: report.topTracks, kind: EntityKind.track, limit: 10),
        if (report.topGenres.isNotEmpty) ...[
          ReportHeading(title: t(InsightsKeys.topGenres)),
          // No `kind`: genres are not catalog entities, so they carry neither artwork nor a stats
          // page, and a row with an empty cover slot looks like a broken image every time.
          TopList(items: report.topGenres, limit: 8),
        ],
        if (report.decades.any((bucket) => bucket.plays > 0)) ...[
          ReportHeading(title: t(InsightsKeys.panelsDecades)),
          BarChart(
            bars: [
              for (final bucket in report.decades)
                BarDatum(
                  t(InsightsKeys.decadesLabel, {'decade': bucket.decade}),
                  bucket.plays,
                ),
            ],
          ),
        ],
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
            ),
        ],
        const SizedBox(height: 32),
      ],
    );
  }
}
