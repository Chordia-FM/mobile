import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../i18n/keys.g.dart';
import '../../../i18n/translations_provider.dart';
import '../../../widgets/tokens.dart';
import '../../catalog/widgets/list_row.dart';
import '../data/insights_providers.dart';
import '../format.dart';
import '../widgets/insights_primitives.dart';

/// The Discovery tab: how much of the window was new, what the newcomers were, and who moved.
class DiscoveryReport extends ConsumerStatefulWidget {
  const DiscoveryReport({required this.handle, super.key, this.own = false});

  final String? handle;

  /// Whether the report is about the reader, which is what the catalogs' `person` select needs.
  final bool own;

  @override
  ConsumerState<DiscoveryReport> createState() => _DiscoveryReportState();
}

class _DiscoveryReportState extends ConsumerState<DiscoveryReport> {
  EntityKind _kind = EntityKind.artist;

  @override
  Widget build(BuildContext context) {
    final t = ref.t;
    final query = ref.watch(insightsQueryProvider(widget.handle));
    final stats = ref.watch(discoveryStatsProvider(query));

    return ReportBody<DiscoveryStats>(
      value: stats,
      onRetry: () => ref.invalidate(discoveryStatsProvider(query)),
      builder: (context, value) => value.tracksPlayed == 0
          ? ReportEmpty(
              title: t(InsightsKeys.discoveryEmptyTitle),
              body: t(
                InsightsKeys.discoveryEmptyBody,
                personArg(own: widget.own),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _NewVsFamiliar(stats: value),
                const SizedBox(height: 8),
                StatGrid(
                  tiles: [
                    StatTile(
                      label: t(InsightsKeys.discoveryTilesNewArtists),
                      value: '${value.artistsNew}',
                      compared: value.artistsPlayedCompared,
                      showDelta: value.period != Period.overall,
                    ),
                    StatTile(
                      label: t(InsightsKeys.discoveryTilesNewAlbums),
                      value: '${value.albumsNew}',
                      compared: value.albumsPlayedCompared,
                      showDelta: value.period != Period.overall,
                    ),
                    StatTile(
                      label: t(InsightsKeys.discoveryTilesNewTracks),
                      value: '${value.tracksNew}',
                      compared: value.tracksPlayedCompared,
                      showDelta: value.period != Period.overall,
                    ),
                    StatTile(
                      label: t(InsightsKeys.discoveryTilesOfPlayed, {
                        'count': value.artistsPlayed,
                      }),
                      value: '${value.artistsPlayed}',
                    ),
                  ],
                ),
                if (value.topNewArtists.isNotEmpty) ...[
                  ReportHeading(title: t(InsightsKeys.discoveryTopNewArtists)),
                  TopList(
                    items: value.topNewArtists,
                    kind: EntityKind.artist,
                    limit: 10,
                  ),
                ],
                ReportHeading(title: t(InsightsKeys.discoveryMoversTitle)),
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
                _Movers(
                  request: ChartRequest(query: query, kind: _kind),
                ),
                const SizedBox(height: 32),
              ],
            ),
    );
  }
}

/// The share of this window's plays that were first listens.
class _NewVsFamiliar extends ConsumerWidget {
  const _NewVsFamiliar({required this.stats});

  final DiscoveryStats stats;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final theme = Theme.of(context);
    final fresh = 1 - stats.repeatRate;
    final freshPercent = '${(fresh * 100).round()}%';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t(InsightsKeys.discoveryMixTitle),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                freshPercent,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  t(InsightsKeys.discoveryMixHeadline),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Semantics(
            label: t(InsightsKeys.discoveryMixMeterAriaLabel),
            child: ClipRRect(
              // `rounded-full`, like every other bar on the web (`DownloadStatsPanel.tsx:139`).
              borderRadius: ChordiaRadius.pill,
              child: LinearProgressIndicator(value: fresh, minHeight: 10),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${t(InsightsKeys.discoveryMixNew, {'pct': freshPercent})} · '
            '${t(InsightsKeys.discoveryMixRepeats, {'pct': '${(stats.repeatRate * 100).round()}%'})}',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Who climbed, who fell, and who arrived, against the window before this one.
class _Movers extends ConsumerWidget {
  const _Movers({required this.request});

  final ChartRequest request;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    // "All time" has no window before it, so there is nothing movement could be measured against.
    if (request.query.period == Period.overall) {
      return ReportEmpty(title: t(InsightsKeys.discoveryMoversNeedsWindow));
    }
    final movers = ref.watch(rankMoversProvider(request));

    return ReportBody<RankMovers>(
      value: movers,
      onRetry: () => ref.invalidate(rankMoversProvider(request)),
      builder: (context, value) {
        if (value.climbers.isEmpty &&
            value.fallers.isEmpty &&
            value.newcomers.isEmpty) {
          return ReportEmpty(title: t(InsightsKeys.discoveryMoversNone));
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _MoveGroup(
              title: t(InsightsKeys.discoveryMoversClimbers),
              moves: value.climbers,
              climbing: true,
            ),
            _MoveGroup(
              title: t(InsightsKeys.discoveryMoversFallers),
              moves: value.fallers,
              climbing: false,
            ),
            if (value.newcomers.isNotEmpty) ...[
              ReportHeading(title: t(InsightsKeys.discoveryMoversNewcomers)),
              for (final entry in value.newcomers)
                ListRow(
                  leading: SizedBox(
                    width: 32,
                    child: Text(
                      '${entry.rank}',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  title: Text(
                    entry.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(t(InsightsKeys.discoveryMoversNew)),
                ),
            ],
          ],
        );
      },
    );
  }
}

class _MoveGroup extends ConsumerWidget {
  const _MoveGroup({
    required this.title,
    required this.moves,
    required this.climbing,
  });

  final String title;
  final List<RankMove> moves;
  final bool climbing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (moves.isEmpty) return const SizedBox.shrink();
    final t = ref.t;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ReportHeading(title: title),
        for (final move in moves)
          ListRow(
            leading: Icon(
              climbing
                  ? Icons.trending_up_rounded
                  : Icons.trending_down_rounded,
              color: climbing
                  ? theme.colorScheme.primary
                  : theme.colorScheme.error,
            ),
            title: Text(
              move.item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              [
                if (move.delta case final delta?)
                  t(
                    climbing
                        ? InsightsKeys.discoveryMoversClimbedBy
                        : InsightsKeys.discoveryMoversFellBy,
                    {'count': delta.abs()},
                  ),
                if (move.item.prevRank case final previous?)
                  t(InsightsKeys.discoveryMoversWasRank, {'rank': previous}),
              ].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Text(
              '#${move.item.rank}',
              style: theme.textTheme.labelLarge,
            ),
          ),
      ],
    );
  }
}
