import 'dart:async';

import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../data/art/art_cache.dart';
import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import '../../widgets/cover_art.dart';
import 'catalog_routes.dart';
import 'data/catalog_providers.dart';
import 'data/playback.dart';
import 'format.dart';
import 'widgets/artist_links.dart';
import 'widgets/catalog_state.dart';
import 'widgets/entity_menu.dart';
import 'widgets/section.dart';
import 'widgets/track_row.dart';

/// One song on its own page: what it is, and what the listener has done with it.
///
/// Reached from a context menu and from the player. The stats half is a second, slower read — the
/// details above it render as soon as the track does rather than waiting on a rollup scan.
class TrackScreen extends ConsumerWidget {
  const TrackScreen({required this.trackId, super.key});

  final String trackId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = ref.watch(trackDetailProvider(trackId));
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            icon: Icon(PhosphorIcons.shareNetwork()),
            tooltip: ref.t(CommonKeys.actionsShare),
            onPressed: () => unawaited(
              shareCatalogLink(
                context,
                ref,
                path: '/tracks/$trackId',
                title: track.value?.title ?? '',
              ),
            ),
          ),
        ],
      ),
      body: CatalogBody<BrowseTrack>(
        value: track,
        errorTitle: ref.t(ErrorsKeys.catalogTrackLoadFailed),
        onRetry: () => ref.invalidate(trackDetailProvider(trackId)),
        skeleton: const CatalogDetailSkeleton(),
        builder: (context, value) => _TrackView(track: value),
      ),
    );
  }
}

class _TrackView extends ConsumerWidget {
  const _TrackView({required this.track});

  final BrowseTrack track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final theme = Theme.of(context);
    final hasPlayer = ref.watch(catalogPlayerActionsProvider) != null;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Center(
          child: CoverArt(
            sha256: artHashOf(track.coverUrl),
            size: 220,
            semanticLabel: track.title,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                track.title,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            TrackBadges(track: track),
          ],
        ),
        const SizedBox(height: 8),
        Center(
          // The Hub already assembled the credit line; the per-artist array is what turns it into
          // one link each, including featured artists.
          child: ArtistLinks(
            artists: track.artists,
            fallbackName: track.artist,
            fallbackId: track.artistId,
            style: theme.textTheme.bodyMedium,
            linkStyle: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 8),
        CollectionActions(
          // A single track from its own page is a queue of one, with no collection to attribute it
          // to — anything else would credit a listen to a source the listener never opened.
          onPlay: hasPlayer
              ? () => playCollection(ref, tracks: [track], playContext: null)
              : null,
          onShuffle: null,
          trailing: [
            IconButton(
              icon: Icon(PhosphorIcons.dotsThree(PhosphorIconsStyle.bold)),
              tooltip: t(CommonKeys.actionsMore),
              onPressed: () => unawaited(showTrackMenu(context, ref, track)),
            ),
          ],
        ),
        SectionHeader(title: t(CatalogKeys.trackDetails)),
        _DetailRow(
          label: t(CatalogKeys.trackLength),
          value: formatTrackLength(track.durationMs),
        ),
        if (track.album != null)
          _DetailRow(
            label: t(CatalogKeys.trackColumnAlbum),
            value: track.album!,
            onTap: track.albumId == null
                ? null
                : () => context.goToAlbum(track.albumId!),
          ),
        if (track.trackNo != null)
          _DetailRow(
            label: t(CatalogKeys.trackNumber),
            value: track.discNo == null
                ? '${track.trackNo}'
                : joinFacts([
                    t(CatalogKeys.albumDisc, {'n': track.discNo}),
                    '${track.trackNo}',
                  ]),
          ),
        if ((track.plays ?? 0) > 0)
          _DetailRow(
            label: t(CatalogKeys.trackHubPlays),
            value: t(CatalogKeys.trackPlaysNumber, {'n': track.plays}),
          ),
        _TrackStats(trackId: track.id),
      ],
    );
  }
}

/// The viewer's own numbers, once the rollup scan lands.
///
/// Silent about a track nobody has played: an empty stats block on a catalog — which is most of it
/// — says less than no block at all.
class _TrackStats extends ConsumerWidget {
  const _TrackStats({required this.trackId});

  final String trackId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final stats = ref.watch(trackStatsProvider(trackId)).value;
    if (stats == null || stats.totalPlays == 0) return const SizedBox.shrink();

    final locale = ref.read(translationsProvider).locale;
    String? date(int? epochMillis) => epochMillis == null
        ? null
        : DateFormat.yMMMd(
            locale,
          ).format(DateTime.fromMillisecondsSinceEpoch(epochMillis));

    final first = date(stats.firstPlayed);
    final last = date(stats.lastPlayed);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(title: t(InsightsKeys.statsTitle)),
        _DetailRow(
          label: t(InsightsKeys.statsPlays),
          value: t(InsightsKeys.statsPlaysValue, {'count': stats.totalPlays}),
        ),
        if (stats.rank != null && stats.rankTotal != null)
          _DetailRow(
            label: t(CatalogKeys.trackRank),
            value: t(InsightsKeys.statsRankOf, {
              'rank': stats.rank,
              'total': stats.rankTotal,
            }),
          ),
        if (first != null)
          _DetailRow(label: t(InsightsKeys.statsFirstPlayed), value: first),
        if (last != null)
          _DetailRow(label: t(InsightsKeys.statsLastPlayed), value: last),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value, this.onTap});

  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 130,
              child: Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: onTap == null
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
