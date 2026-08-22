import 'package:chordia_api/chordia_api.dart';
import 'package:chordia_sync/chordia_sync.dart' show LibraryContext;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import 'data/catalog_providers.dart';
import 'format.dart';
import 'widgets/album_grid.dart';
import 'widgets/artist_row.dart';
import 'widgets/catalog_state.dart';
import 'widgets/section.dart';
import 'widgets/track_list.dart';

/// One genre: its artists, albums and songs, most-played first — the shape a listener expects from
/// a tag page.
class GenreScreen extends ConsumerWidget {
  const GenreScreen({required this.slug, super.key});

  final String slug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final genre = ref.watch(genreDetailProvider(slug));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          titleCaseGenre(genre.value?.name ?? slug),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: CatalogBody<GenreDetail>(
        value: genre,
        errorTitle: t(ErrorsKeys.catalogGenreLoadFailed),
        onRetry: () => ref.invalidate(genreDetailProvider(slug)),
        skeleton: const CatalogGridSkeleton(),
        builder: (context, value) => _GenreView(genre: value),
      ),
    );
  }
}

class _GenreView extends ConsumerWidget {
  const _GenreView({required this.genre});

  final GenreDetail genre;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final theme = Theme.of(context);
    final artists = genre.topArtists ?? const <BrowseArtist>[];
    final albums = genre.topAlbums ?? const <BrowseAlbum>[];
    final tracks = genre.topTracks ?? const <BrowseTrack>[];
    final variants = genre.variants ?? const <String>[];
    final name = titleCaseGenre(genre.name);

    // A genre is not one of the queue's own context kinds, and inventing one would write a slug
    // into the append-only listening-events table under a kind that means something else. The
    // library context is the honest answer: these tracks came from a browse, and its id is the
    // slug that produced them.
    final playContext = LibraryContext(id: genre.slug, name: name);

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t(CatalogKeys.genresEyebrow),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    letterSpacing: 0.8,
                  ),
                ),
                Text(
                  name,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  t(CatalogKeys.genresCounts, {
                    'albums': genre.albumCount,
                    'artists': genre.artistCount,
                    'albumsFormatted': genre.albumCount,
                    'artistsFormatted': genre.artistCount,
                  }),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                // Say what was merged: these tags arrive from MusicBrainz as free text, so one
                // genre comes under several spellings and folding them silently looks like loss.
                if (variants.length > 1) ...[
                  const SizedBox(height: 4),
                  Text(
                    t(CatalogKeys.genresVariants, {
                      'list': variants.join(', '),
                    }),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),

        if (artists.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: SectionHeader(title: t(CatalogKeys.genresTopArtists)),
          ),
          SliverToBoxAdapter(child: ArtistShelf(artists: artists)),
        ],

        if (tracks.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: SectionHeader(title: t(CatalogKeys.genresTopTracks)),
          ),
          SliverTrackList(tracks: tracks, playContext: playContext),
        ],

        if (albums.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: SectionHeader(title: t(CatalogKeys.genresTopAlbums)),
          ),
          SliverAlbumGrid(albums: albums, showArtist: true),
        ],

        if (artists.isEmpty && tracks.isEmpty && albums.isEmpty)
          SliverToBoxAdapter(
            child: CatalogEmpty(message: t(CatalogKeys.genresNotFound)),
          ),

        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }
}
