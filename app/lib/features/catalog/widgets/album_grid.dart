import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/art/art_cache.dart';
import '../../../i18n/keys.g.dart';
import '../../../i18n/translations_provider.dart';
import '../../../widgets/cover_art.dart';
import '../catalog_routes.dart';
import '../format.dart';

/// A lazy grid of albums.
///
/// A sliver, not a widget with its own scroll view: every screen that shows albums shows something
/// else above them, and nesting a second scrollable would either need a fixed height or build every
/// tile at once. As a sliver the grid shares the page's viewport and only builds what is visible.
class SliverAlbumGrid extends StatelessWidget {
  const SliverAlbumGrid({
    required this.albums,
    super.key,
    this.showArtist = false,
  });

  final List<BrowseAlbum> albums;

  /// Shows "artist · year" instead of the year alone — for a label or genre page, where the artist
  /// is the fact that identifies the record.
  final bool showArtist;

  @override
  Widget build(BuildContext context) => SliverPadding(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    sliver: SliverGrid.builder(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        // A tile per ~180 logical pixels: two columns on a phone, four on a tablet, without a
        // breakpoint anywhere.
        maxCrossAxisExtent: 200,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 0.72,
      ),
      itemCount: albums.length,
      itemBuilder: (context, index) =>
          AlbumCard(album: albums[index], showArtist: showArtist),
    ),
  );
}

/// One album tile: cover, title, and the line that identifies the release.
class AlbumCard extends ConsumerWidget {
  const AlbumCard({
    required this.album,
    super.key,
    this.showArtist = false,
    this.width,
  });

  final BrowseAlbum album;
  final bool showArtist;

  /// Set on a horizontally-scrolling shelf, where the tile has no grid cell to fill.
  final double? width;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final subtitle = showArtist
        ? ref.t(CatalogKeys.albumCardArtistYearJoin, {
            'artist': album.artist,
            'year': album.year,
          })
        : (album.year?.toString() ?? '');

    return SizedBox(
      width: width,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.goToAlbum(album.id),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // The cover is measured, not fixed: `LayoutBuilder` lets one card fill a grid cell on
              // a tablet and a 150px shelf slot on a phone without two sets of numbers.
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) => CoverArt(
                    sha256: artHashOf(album.coverUrl),
                    size: constraints.maxWidth,
                    semanticLabel: album.title,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                album.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (subtitle.isNotEmpty)
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A horizontally scrolling row of album cards — the discography shelves on an artist page.
class AlbumShelf extends StatelessWidget {
  const AlbumShelf({required this.albums, super.key, this.leading});

  final List<BrowseAlbum> albums;

  /// A card that goes first and is not an album — the artist page's Radio entry, for instance.
  final Widget? leading;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 210,
    child: ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      itemCount: albums.length + (leading == null ? 0 : 1),
      itemBuilder: (context, index) {
        if (leading != null && index == 0) {
          return SizedBox(width: 150, child: leading);
        }
        final album = albums[index - (leading == null ? 0 : 1)];
        return AlbumCard(album: album, width: 150);
      },
    ),
  );
}

/// The runtime line under a collection's title: "12 songs · 48 min".
String collectionSummary(WidgetRef ref, List<BrowseTrack> tracks) {
  final t = ref.t;
  return joinFacts([
    t(CatalogKeys.albumSongCount, {'count': tracks.length}),
    formatRuntime(
      ref.read(translationsProvider),
      totalDurationMs(tracks.map((track) => track.durationMs)),
    ),
  ]);
}
