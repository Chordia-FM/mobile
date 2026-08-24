import 'package:chordia_api/chordia_api.dart';
import 'package:chordia_sync/chordia_sync.dart' show AlbumContext;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/art/art_cache.dart';
import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import '../../widgets/cover_art.dart';
import '../../widgets/tokens.dart';
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
          // The ⋮ is the whole action set — play, queue, radio, pin, playlist, download, share —
          // and it only appears once the release is loaded, because every one of those acts on it.
          if (album.value case final loaded?)
            EntityMenuButton(
              menu: (page, sheetRef) => albumDetailMenu(page, sheetRef, loaded),
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
        SliverToBoxAdapter(child: AlbumHeader(album: album)),
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
                RingIconButton(
                  icon: Icons.download_rounded,
                  tooltip: ref.t(LibraryKeys.downloadsActionDownload),
                  onPressed: () => saveDownloads(context, ref, album.tracks),
                ),
            ],
          ),
        ),
        // The web's `space-y-6` between the action row and the running order.
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
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

/// The album hero.
///
/// Ported from the web's below-`sm` album header (`components/catalog/AlbumView.tsx`): a blurred
/// bloom of the cover behind it, then the cover itself, the release types, the title, ONE meta line
/// that starts with the credited artist as a link and carries the date, song count, runtime and
/// plays after it, and finally genres and label together on the last line.
///
/// Left-aligned, and stacked rather than centred, because that is the layout the web renders on a
/// phone — cover above metadata, everything reading from the same left edge as the track list under
/// it.
class AlbumHeader extends ConsumerWidget {
  const AlbumHeader({required this.album, super.key});

  final AlbumDetail album;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final theme = Theme.of(context);
    // The web's meta line is `text-sm text-muted-foreground`.
    final muted = ChordiaType.sm.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final types = [
      if (album.albumType != null) album.albumType!,
      ...?album.secondaryTypes,
    ];
    final genres = album.genres ?? const <String>[];
    // Everything after the credited artist on the web's single meta line.
    final facts = joinFacts([
      releaseDateLabel(ref, album),
      t(CatalogKeys.albumSongCount, {'count': album.tracks.length}),
      formatRuntime(
        ref.read(translationsProvider),
        totalDurationMs(album.tracks.map((track) => track.durationMs)),
      ),
      if ((album.plays ?? 0) > 0) t(PlayerKeys.plays, {'count': album.plays}),
    ]);

    return HeroSurface(
      // Sized to its content, not to a fixed band: an album has no banner art to fill one, and a
      // `min-h` would only pad the cover down from the top.
      background: HeroWash(sha256: artHashOf(album.coverUrl)),
      // `px-4 pt-6 pb-6`.
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          catalogGutter,
          24,
          catalogGutter,
          24,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CoverArt(
              // `w-48`.
              sha256: artHashOf(album.coverUrl),
              size: 192,
              semanticLabel: album.title,
            ),
            // The web's `gap-6` between the cover and the metadata column.
            const SizedBox(height: 24),
            if (types.isNotEmpty)
              Text(
                t(CatalogKeys.albumTypesJoin, {'types': types.join(' · ')}),
                // `text-xs uppercase tracking-wide` — the web upper-cases in CSS, which cannot be
                // done to a translated string without breaking languages that have no case.
                style: ChordiaType.xs.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  letterSpacing: 0.8,
                ),
              ),
            Text(
              album.title,
              // `display-title font-bold text-4xl` — the serif, at the size `displayLarge`
              // already carries. It reached for `headlineLarge` and then re-sized it to 36, which
              // is `displayLarge`'s size in the sans: the same number, the wrong face.
              style: theme.textTheme.displayLarge,
            ),
            const SizedBox(height: 8),
            // ONE line: the credited artist, then the facts. `Wrap` rather than a single rich span
            // because the artist half is its own widget — the Hub assembles the credited-artist
            // line and `ArtistLinks` renders the credits as links rather than splitting that
            // assembled string, which would break on "feat." and on any name containing a comma.
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ArtistLinks(
                  artists: null,
                  fallbackName: album.artist,
                  fallbackId: album.artistId,
                  style: muted,
                  linkStyle: ChordiaType.sm.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontWeight: ChordiaType.medium,
                  ),
                ),
                if (facts.isNotEmpty) Text(' · $facts', style: muted),
              ],
            ),
            // Genres and label share the last line, as they do on the web, because they answer the
            // same question about a release and neither earns a row of its own.
            if (genres.isNotEmpty || album.label != null) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (genres.isNotEmpty) GenreChips(genres: genres),
                  if (album.label != null)
                    LabelLink(name: album.label!, labelId: album.labelId),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The release date, in full when the Hub knows the day and as a bare year otherwise.
///
/// Mirrors `AlbumView.tsx`'s `releaseDateLabel`: a Postgres `date` arrives as `YYYY-MM-DD` and is
/// split into its parts rather than parsed, because reading it as an instant interprets it as UTC
/// and can shift the day — and the year with it — across a time zone.
String? releaseDateLabel(WidgetRef ref, AlbumDetail album) {
  final raw = album.releaseDate;
  if (raw != null) {
    final parts = raw.split('-');
    if (parts.length == 3) {
      final year = int.tryParse(parts[0]);
      final month = int.tryParse(parts[1]);
      final day = int.tryParse(parts[2]);
      if (year != null && month != null && day != null) {
        return ref.t(CatalogKeys.albumReleaseDate, {
          'date': DateTime(year, month, day),
        });
      }
    }
    final year = yearOf(raw);
    if (year != null) return year;
  }
  return album.year?.toString();
}
