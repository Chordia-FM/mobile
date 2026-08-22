import 'dart:async';

import 'package:chordia_api/chordia_api.dart';
import 'package:chordia_sync/chordia_sync.dart' show AlbumContext;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/art/art_cache.dart';
import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import '../../widgets/cover_art.dart';
import '../downloads/widgets/download_controls.dart';
import 'data/catalog_providers.dart';
import 'data/playback.dart';
import 'format.dart';
import 'widgets/artist_links.dart';
import 'widgets/catalog_state.dart';
import 'widgets/entity_links.dart';
import 'widgets/entity_menu.dart';
import 'widgets/section.dart';
import 'widgets/track_list.dart';

/// One release: what it is, who made it, and its running order.
class AlbumScreen extends ConsumerWidget {
  const AlbumScreen({required this.albumId, super.key});

  final String albumId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final album = ref.watch(albumDetailProvider(albumId));
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            icon: const Icon(Icons.ios_share_rounded),
            tooltip: ref.t(CommonKeys.actionsShare),
            onPressed: () => unawaited(
              shareCatalogLink(
                context,
                ref,
                path: '/albums/$albumId',
                title: album.value?.title ?? '',
              ),
            ),
          ),
        ],
      ),
      body: CatalogBody<AlbumDetail>(
        value: album,
        errorTitle: ref.t(ErrorsKeys.catalogAlbumLoadFailed),
        onRetry: () => ref.invalidate(albumDetailProvider(albumId)),
        skeleton: const CatalogDetailSkeleton(),
        builder: (context, value) => _AlbumView(album: value),
      ),
    );
  }
}

class _AlbumView extends ConsumerWidget {
  const _AlbumView({required this.album});

  final AlbumDetail album;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final playContext = AlbumContext(id: album.id, name: album.title);
    final canPlay =
        album.tracks.isNotEmpty &&
        ref.watch(catalogPlayerActionsProvider) != null;

    // Only worth a line per row when the album is not simply forty tracks by its own artist.
    final showArtists = album.tracks.any(
      (track) => track.artist != album.artist,
    );

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _AlbumHeader(album: album)),
        SliverToBoxAdapter(
          child: CollectionActions(
            onPlay: canPlay
                ? () => playCollection(
                    ref,
                    tracks: album.tracks,
                    playContext: playContext,
                  )
                : null,
            onShuffle: canPlay
                ? () => playCollection(
                    ref,
                    tracks: album.tracks,
                    playContext: playContext,
                    shuffle: true,
                  )
                : null,
            trailing: [
              if (canPlay)
                IconButton(
                  onPressed: () => saveDownloads(context, ref, album.tracks),
                  icon: const Icon(Icons.download_rounded),
                  tooltip: ref.t(LibraryKeys.downloadsActionDownload),
                ),
            ],
          ),
        ),
        if (album.tracks.isEmpty)
          SliverToBoxAdapter(
            child: CatalogEmpty(message: t(CatalogKeys.albumNoTracks)),
          )
        else
          SliverTrackList(
            tracks: album.tracks,
            playContext: playContext,
            numbered: true,
            groupByDisc: true,
            showArtists: showArtists,
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }
}

class _AlbumHeader extends ConsumerWidget {
  const _AlbumHeader({required this.album});

  final AlbumDetail album;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final theme = Theme.of(context);
    final types = [
      if (album.albumType != null) album.albumType!,
      ...?album.secondaryTypes,
    ];
    final genres = album.genres ?? const <String>[];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          CoverArt(
            sha256: artHashOf(album.coverUrl),
            size: 220,
            semanticLabel: album.title,
          ),
          const SizedBox(height: 16),
          if (types.isNotEmpty)
            Text(
              t(CatalogKeys.albumTypesJoin, {'types': types.join(' · ')}),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                letterSpacing: 0.8,
              ),
            ),
          const SizedBox(height: 4),
          Text(
            album.title,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          // The Hub assembles the credited-artist line; this renders the credit as a link rather
          // than splitting that assembled string, which would break on "feat." and on any name
          // containing the separator.
          ArtistLinks(
            artists: null,
            fallbackName: album.artist,
            fallbackId: album.artistId,
            style: theme.textTheme.bodyMedium,
            linkStyle: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            joinFacts([
              yearOf(album.releaseDate) ?? album.year?.toString(),
              t(CatalogKeys.albumSongCount, {'count': album.tracks.length}),
              formatRuntime(
                ref.read(translationsProvider),
                totalDurationMs(album.tracks.map((track) => track.durationMs)),
              ),
              if ((album.plays ?? 0) > 0)
                t(PlayerKeys.plays, {'count': album.plays}),
            ]),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (genres.isNotEmpty) ...[
            const SizedBox(height: 10),
            GenreChips(genres: genres),
          ],
          if (album.label != null) ...[
            const SizedBox(height: 8),
            LabelLink(name: album.label!, labelId: album.labelId),
          ],
        ],
      ),
    );
  }
}
