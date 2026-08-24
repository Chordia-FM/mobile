import 'dart:async';

import 'package:chordia_api/chordia_api.dart';
import 'package:chordia_sync/chordia_sync.dart'
    show ArtistContext, PlayContext, RadioContext, StationCursor;
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
/// and reached the same way — every radio pin and every "start a station from this" action lands
/// here. A "Made for you" card does NOT: that is a daily mix, and it has its own destination in
/// [DailyMixScreen] below.
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

/// One daily mix, opened as a destination of its own.
///
/// The mobile counterpart of the web's `/app/daily-mix/{mixId}` route, which renders the same
/// `StationView` this screen's body is — and, like it, is a genuinely different destination from
/// `/app/radio/{kind}/{seedId}`. The Hub draws a mix inward and a radio outward, so sending the
/// "Made for you" card at the radio generator (which this client used to do) answered with a
/// different track list under a different title.
class DailyMixScreen extends ConsumerWidget {
  const DailyMixScreen({required this.mixId, super.key});

  /// The mix's seed artist id, which is the mix's own stable identity Hub-side.
  final String mixId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(),
    body: CatalogBody<DailyMixDetail>(
      value: ref.watch(dailyMixProvider(mixId)),
      errorTitle: ref.t(ErrorsKeys.discoveryDailyMixFailed),
      onRetry: () => ref.invalidate(dailyMixProvider(mixId)),
      skeleton: const CatalogDetailSkeleton(),
      builder: (context, value) => _MixView(mix: value),
    ),
  );
}

class _StationView extends ConsumerWidget {
  const _StationView({required this.station});

  final Station station;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Composed here, not taken from the server: the Hub builds `title` in English. `seedName` is
    // what it hands back so the title can be said in the listener's language, and the server's
    // stays the fallback for a Hub too old to send one.
    final heading = station.seedName.isEmpty
        ? station.title
        : ref.t(stationTitleKey(station.kind), {'name': station.seedName});

    return _StationBody(
      label: ref.t(stationLabelKey(station.kind)),
      heading: heading,
      subtitle: station.subtitle,
      imageUrl: station.imageUrl,
      tracks: station.tracks,
      // The station's own cursor travels in the context, so the queue can ask for the next page
      // when it runs dry rather than ending the listening session at track thirty.
      playContext: RadioContext(
        id: station.seedId,
        name: heading,
        stationKind: sync.StationKind.tryParse(station.kind.wire),
        stationCursor: StationCursor(station.nextCursor),
      ),
      trailing: [_PinStation(station: station)],
    );
  }
}

class _MixView extends ConsumerWidget {
  const _MixView({required this.mix});

  final DailyMixDetail mix;

  @override
  Widget build(BuildContext context, WidgetRef ref) => _StationBody(
    label: ref.t(DiscoveryKeys.dailyMixLabel),
    // The Hub composes a mix's title around the seed artist's name rather than around a kind noun,
    // so unlike a station's there is nothing here to recompose in the listener's language.
    heading: mix.title,
    subtitle: mix.subtitle,
    imageUrl: mix.imageUrl,
    tracks: mix.tracks,
    // An artist context, not a radio one: a mix is finite and has no cursor to continue from, and
    // the web's `StationView` resolves a `DailyMixDetail` to `{kind: "artist"}` for exactly that
    // reason — "Playing from" then leads back to the artist the mix was woven around.
    playContext: ArtistContext(id: mix.seedArtistId, name: mix.title),
  );
}

/// The shape both destinations share: cover, kicker, title, action row, track list.
///
/// One body rather than two, because the web has one (`components/discovery/StationView.tsx` takes
/// `DailyMixDetail | Station`). The two shapes agree on everything drawn here and differ only in
/// how the seed is named and whether the queue can continue, which is all the caller resolves.
class _StationBody extends ConsumerWidget {
  const _StationBody({
    required this.label,
    required this.heading,
    required this.subtitle,
    required this.imageUrl,
    required this.tracks,
    required this.playContext,
    this.trailing = const [],
  });

  final String label;
  final String heading;
  final String subtitle;
  final String? imageUrl;
  final List<BrowseTrack> tracks;
  final PlayContext playContext;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canPlay =
        tracks.isNotEmpty && ref.watch(catalogPlayerActionsProvider) != null;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: _StationHeader(
            label: label,
            heading: heading,
            subtitle: subtitle,
            imageUrl: imageUrl,
            trackCount: tracks.length,
          ),
        ),
        SliverToBoxAdapter(
          child: CollectionActions(
            onPlay: canPlay
                ? () => playCollection(
                    ref,
                    tracks: tracks,
                    playContext: playContext,
                  )
                : null,
            onShuffle: canPlay
                ? () => playCollection(
                    ref,
                    tracks: tracks,
                    playContext: playContext,
                    shuffle: true,
                  )
                : null,
            trailing: trailing,
          ),
        ),
        if (tracks.isEmpty)
          SliverToBoxAdapter(
            child: CatalogEmpty(message: ref.t(DiscoveryKeys.stationEmpty)),
          )
        else
          SliverTrackList(tracks: tracks, playContext: playContext),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }
}

class _StationHeader extends ConsumerWidget {
  const _StationHeader({
    required this.label,
    required this.heading,
    required this.subtitle,
    required this.imageUrl,
    required this.trackCount,
  });

  final String label;
  final String heading;
  final String subtitle;
  final String? imageUrl;
  final int trackCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        children: [
          CoverArt(
            sha256: artHashOf(imageUrl),
            size: 220,
            fallbackIcon: Icons.radio_rounded,
            semanticLabel: heading,
          ),
          const SizedBox(height: 16),
          Text(
            label.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            heading,
            textAlign: TextAlign.center,
            // `display-title break-words font-bold text-3xl sm:text-4xl` (StationView.tsx:85),
            // which on a phone-width column is `text-3xl` — the `displayMedium` slot.
            style: theme.textTheme.displayMedium,
          ),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            t(CatalogKeys.songCount, {'count': trackCount}),
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
