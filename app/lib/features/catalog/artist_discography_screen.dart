import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import 'data/catalog_providers.dart';
import 'widgets/album_grid.dart';
import 'widgets/catalog_state.dart';

/// Which slice of an artist's releases the grid is showing.
enum DiscographyFilter {
  all(CatalogKeys.artistDiscographyAllFilterAll),
  albums(CatalogKeys.artistDiscographyAllFilterAlbums),
  singlesAndEps(CatalogKeys.artistDiscographyAllFilterSinglesEps),
  featuring(CatalogKeys.artistDiscographyAllFilterFeaturing);

  const DiscographyFilter(this.labelKey);

  final String labelKey;

  bool matches(BrowseAlbum album) {
    final appearsOn = album.appearsOn ?? false;
    final singleOrEp = album.albumType == 'Single' || album.albumType == 'EP';
    return switch (this) {
      DiscographyFilter.all => true,
      // "Albums" means the artist's OWN full-lengths — a guest verse on someone else's record is
      // not one, which is exactly what the separate Featuring filter is for.
      DiscographyFilter.albums => !appearsOn && !singleOrEp,
      DiscographyFilter.singlesAndEps => !appearsOn && singleOrEp,
      DiscographyFilter.featuring => appearsOn,
    };
  }
}

/// Every release an artist appears on, filterable — the page the artist screen's "See all" opens.
class ArtistDiscographyScreen extends ConsumerStatefulWidget {
  const ArtistDiscographyScreen({required this.artistId, super.key});

  final String artistId;

  @override
  ConsumerState<ArtistDiscographyScreen> createState() =>
      _ArtistDiscographyScreenState();
}

class _ArtistDiscographyScreenState
    extends ConsumerState<ArtistDiscographyScreen> {
  DiscographyFilter _filter = DiscographyFilter.all;

  @override
  Widget build(BuildContext context) {
    final t = ref.t;
    final artist = ref.watch(artistDetailProvider(widget.artistId));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          artist.value?.name ?? t(CatalogKeys.artistDiscography),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: CatalogBody<ArtistDetail>(
        value: artist,
        errorTitle: t(ErrorsKeys.catalogArtistLoadFailed),
        onRetry: () => ref.invalidate(artistDetailProvider(widget.artistId)),
        skeleton: const CatalogGridSkeleton(),
        builder: (context, value) {
          final albums = value.albums.where(_filter.matches).toList();
          // Newest first, and by full release date where the Hub knows it — `year` alone puts a
          // January single and a December album in an arbitrary order.
          albums.sort((a, b) => _sortKey(b).compareTo(_sortKey(a)));
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      for (final filter in DiscographyFilter.values)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(t(filter.labelKey)),
                            selected: _filter == filter,
                            onSelected: (_) => setState(() => _filter = filter),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (albums.isEmpty)
                SliverToBoxAdapter(
                  child: CatalogEmpty(
                    message: t(CatalogKeys.artistDiscographyAllEmpty),
                  ),
                )
              else
                SliverAlbumGrid(albums: albums, showArtist: true),
              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ],
          );
        },
      ),
    );
  }
}

/// A sortable date key: the full release date when known, else the year, else nothing.
String _sortKey(BrowseAlbum album) =>
    album.releaseDate ?? (album.year == null ? '' : '${album.year}');
