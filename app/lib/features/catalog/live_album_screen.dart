import 'package:chordia_api/chordia_api.dart';
import 'package:chordia_sync/chordia_sync.dart' show ArtistContext;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart' show hubClientProvider;
import '../../data/art/art_cache.dart';
import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import '../../widgets/cover_art.dart';
import '../../widgets/tokens.dart';
import 'data/playback.dart';
import 'widgets/album_grid.dart';
import 'widgets/catalog_state.dart';
import 'widgets/section.dart';
import 'widgets/track_list.dart';

/// The icon that stands for live material everywhere it appears — the card, the header, the cover
/// fallback. The web draws Phosphor's microphone-on-a-stand; this is the nearest Material has.
const _liveIcon = Icons.mic_external_on_rounded;

/// Riverpod 3 retries an errored provider on its own; switched off for the reason
/// `data/catalog_providers.dart` switches it off — the screen already draws a Retry button, and a
/// background retry both contradicts it and leaves a pending timer behind in widget tests.
Duration? _noAutoRetry(int attempt, Object error) => null;

/// One artist's live material, gathered by the Hub.
///
/// Read straight off the client rather than through `CatalogApi`: this is the only screen that
/// calls it, and widening that interface would add a stub to every fake implementing it. A test
/// overrides THIS provider instead, which is the same seam one screen further in.
///
/// Auto-disposed: the collection is assembled per read from whatever the listener's libraries
/// currently hold, so a copy kept from an earlier visit is stale the moment a library rescans.
final liveAlbumProvider = FutureProvider.autoDispose.family<LiveAlbum, String>((
  ref,
  artistId,
) {
  final hub = ref.watch(hubClientProvider);
  if (hub == null) {
    throw StateError('No hub session to read a collection from.');
  }
  return hub.artistLiveAlbum(artistId);
}, retry: _noAutoRetry);

/// An artist's live recordings as one collection.
///
/// The web's `/app/artists/{id}/live` (`routes/_authed/app/artists/$artistId/live.tsx`), which
/// renders it through the same `StationView` a daily mix uses. There is no album row behind this:
/// the Hub builds it fresh from the artist's live-version releases PLUS the live tracks scattered
/// through ordinary records as bonus material, which is exactly the thing a listener cannot
/// assemble by browsing — the second half is invisible from the discography.
class ArtistLiveScreen extends ConsumerWidget {
  const ArtistLiveScreen({required this.artistId, super.key});

  final String artistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(),
    body: CatalogBody<LiveAlbum>(
      value: ref.watch(liveAlbumProvider(artistId)),
      errorTitle: ref.t(ErrorsKeys.catalogArtistLoadFailed),
      onRetry: () => ref.invalidate(liveAlbumProvider(artistId)),
      skeleton: const CatalogDetailSkeleton(),
      builder: (context, value) => _LiveView(live: value),
    ),
  );
}

/// Opens the live collection over whatever raised it.
///
/// A plain `MaterialPageRoute`, for the reason `showEntityStats` gives: an artist page can be
/// sitting in any of the four tabs, and pushing onto the branch's own navigator keeps that tab's
/// back stack without the route table having to exist four times over. The screen is also what a
/// `artists/:artistId/live` route should build, so a shared web link and this card land on the
/// same page.
Future<void> showArtistLiveCollection(BuildContext context, String artistId) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ArtistLiveScreen(artistId: artistId),
      ),
    );

class _LiveView extends ConsumerWidget {
  const _LiveView({required this.live});

  final LiveAlbum live;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    // Composed here rather than taken from the server, exactly as the station screen composes a
    // station's: the Hub has no way to say "{name} · Live" in the listener's language.
    final heading = t(CatalogKeys.artistLiveAlbumTitle, {
      'name': live.artistName,
    });
    // An artist context, not a radio one. The collection is finite and has no cursor to continue
    // from, so "Playing from" leads back to the artist it was gathered for — the same resolution
    // the web's `StationView` makes for a `DailyMixDetail`.
    final playContext = ArtistContext(id: live.artistId, name: heading);
    final canPlay =
        live.tracks.isNotEmpty &&
        ref.watch(catalogPlayerActionsProvider) != null;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: _LiveHeader(live: live, heading: heading),
        ),
        SliverToBoxAdapter(
          child: CollectionActions(
            onPlay: canPlay
                ? () => playCollection(
                    ref,
                    tracks: live.tracks,
                    playContext: playContext,
                  )
                : null,
            onShuffle: canPlay
                ? () => playCollection(
                    ref,
                    tracks: live.tracks,
                    playContext: playContext,
                    shuffle: true,
                  )
                : null,
          ),
        ),
        SliverTrackList(tracks: live.tracks, playContext: playContext),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }
}

class _LiveHeader extends ConsumerWidget {
  const _LiveHeader({required this.live, required this.heading});

  final LiveAlbum live;
  final String heading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(catalogGutter, 8, catalogGutter, 0),
      child: Column(
        children: [
          CoverArt(
            sha256: artHashOf(live.imageUrl),
            size: 220,
            fallbackIcon: _liveIcon,
            semanticLabel: heading,
          ),
          const SizedBox(height: 16),
          Text(
            t(CatalogKeys.artistLiveAlbumLabel).toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            heading,
            textAlign: TextAlign.center,
            // The web renders the synthesized Live album through `StationView`
            // (`artists/$artistId/live.tsx:30`), so its title is that page's H1:
            // `display-title font-bold text-3xl` at phone width.
            style: theme.textTheme.displayMedium,
          ),
          const SizedBox(height: 8),
          // "From N albums" — the fact that explains what this is, since no such album exists.
          Text(
            t(CatalogKeys.artistLiveAlbumSubtitle, {
              'count': live.sourceAlbumCount,
            }),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            t(CatalogKeys.songCount, {'count': live.tracks.length}),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// The card that leads the artist page's Live shelf.
///
/// Not an album card, because there is no album: the web draws a gradient tile with a microphone on
/// it rather than borrowing a cover, so nothing implies a release that could be opened, downloaded
/// or credited (`ArtistView.tsx:574-593`). It takes the first slot of the shelf and the shelf shows
/// even when the artist has no live RELEASES at all — scattered live bonus tracks are most of what
/// this collection is for.
class ArtistLiveCard extends ConsumerWidget {
  const ArtistLiveCard({required this.artistId, super.key});

  final String artistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    return CatalogCard(
      width: catalogCardWidth,
      onTap: () => showArtistLiveCollection(context, artistId),
      title: t(CatalogKeys.artistLiveAlbumCard),
      caption: t(CatalogKeys.artistLiveAlbumLabel),
      art: const _LiveArt(),
    );
  }
}

/// The gradient square that stands in for a cover.
///
/// `bg-gradient-to-br from-primary/70 to-primary/25` with the mark at a third of the tile, over the
/// same `shadow-lg` and `rounded-md` every real cover carries — the point is that it sits in a row
/// of album cards without looking like a different kind of object.
class _LiveArt extends StatelessWidget {
  const _LiveArt();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = constraints.maxWidth;
        return Align(
          alignment: Alignment.topCenter,
          child: Container(
            width: side,
            height: side,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: ChordiaRadius.mdAll,
              boxShadow: chordiaCoverShadow,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  scheme.primary.withValues(alpha: 0.7),
                  scheme.primary.withValues(alpha: 0.25),
                ],
              ),
            ),
            child: Icon(_liveIcon, size: side / 3, color: scheme.onPrimary),
          ),
        );
      },
    );
  }
}
