import 'dart:async';

import 'package:chordia_api/chordia_api.dart';
import 'package:chordia_sync/chordia_sync.dart'
    show RadioContext, StationCursor;
import 'package:chordia_sync/chordia_sync.dart' as sync show StationKind;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/art/art_cache.dart';
import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import '../../widgets/cover_art.dart';
import '../catalog/data/playback.dart';
import '../catalog/widgets/catalog_state.dart';
import '../catalog/widgets/section.dart';
import '../catalog/widgets/track_list.dart';
import '../library/data/pins.dart';
import 'data/station.dart';

/// A generated station: a daily mix, an artist's radio, or anything else the Hub can seed from.
///
/// The mobile counterpart of the web client's `StationView` + `/app/radio/{kind}/{seedId}` route,
/// and reached the same way — every "Made for you" card and every radio pin lands here.
class StationScreen extends ConsumerWidget {
  const StationScreen({required this.kind, required this.seedId, super.key});

  final StationKind kind;

  /// The seed's id, or its slug when [kind] is [StationKind.genre].
  final String seedId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seed = (kind: kind, seed: seedId);
    return Scaffold(
      appBar: AppBar(),
      body: CatalogBody<Station>(
        value: ref.watch(stationProvider(seed)),
        errorTitle: ref.t(ErrorsKeys.discoveryStationFailed),
        onRetry: () => ref.invalidate(stationProvider(seed)),
        skeleton: const CatalogDetailSkeleton(),
        builder: (context, value) => _StationView(station: value),
      ),
    );
  }
}

class _StationView extends ConsumerWidget {
  const _StationView({required this.station});

  final Station station;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    // Composed here, not taken from the server: the Hub builds `title` in English. `seedName` is
    // what it hands back so the title can be said in the listener's language, and the server's
    // stays the fallback for a Hub too old to send one.
    final heading = station.seedName.isEmpty
        ? station.title
        : t(stationTitleKey(station.kind), {'name': station.seedName});

    // The station's own cursor travels in the context, so the queue can ask for the next page when
    // it runs dry rather than ending the listening session at track thirty.
    final playContext = RadioContext(
      id: station.seedId,
      name: heading,
      stationKind: sync.StationKind.tryParse(station.kind.wire),
      stationCursor: StationCursor(station.nextCursor),
    );

    final canPlay =
        station.tracks.isNotEmpty &&
        ref.watch(catalogPlayerActionsProvider) != null;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: _StationHeader(station: station, heading: heading),
        ),
        SliverToBoxAdapter(
          child: CollectionActions(
            onPlay: canPlay
                ? () => playCollection(
                    ref,
                    tracks: station.tracks,
                    playContext: playContext,
                  )
                : null,
            onShuffle: canPlay
                ? () => playCollection(
                    ref,
                    tracks: station.tracks,
                    playContext: playContext,
                    shuffle: true,
                  )
                : null,
            trailing: [_PinStation(station: station)],
          ),
        ),
        if (station.tracks.isEmpty)
          SliverToBoxAdapter(
            child: CatalogEmpty(message: t(DiscoveryKeys.stationEmpty)),
          )
        else
          SliverTrackList(tracks: station.tracks, playContext: playContext),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }
}

class _StationHeader extends ConsumerWidget {
  const _StationHeader({required this.station, required this.heading});

  final Station station;
  final String heading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        children: [
          CoverArt(
            sha256: artHashOf(station.imageUrl),
            size: 220,
            fallbackIcon: Icons.radio_rounded,
            semanticLabel: heading,
          ),
          const SizedBox(height: 16),
          Text(
            t(stationLabelKey(station.kind)).toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            heading,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          if (station.subtitle.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              station.subtitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            t(CatalogKeys.songCount, {'count': station.tracks.length}),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Pins the station to the Library tab's shelf.
///
/// Only an artist seed can be pinned: `PinKind.radio` resolves an artist id Hub-side, so pinning a
/// track or genre seed under the same kind would produce a pin the Hub cannot name. Same rule as
/// the web client's station page.
class _PinStation extends ConsumerWidget {
  const _PinStation({required this.station});

  final Station station;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (station.kind != StationKind.artist) return const SizedBox.shrink();
    final pinned = isPinned(ref, PinKind.radio, station.seedId);
    return IconButton(
      icon: Icon(pinned ? Icons.push_pin : Icons.push_pin_outlined),
      tooltip: ref.t(pinned ? CommonKeys.actionsUnpin : DiscoveryKeys.radioPin),
      onPressed: () => unawaited(
        togglePin(context, ref, kind: PinKind.radio, id: station.seedId),
      ),
    );
  }
}
