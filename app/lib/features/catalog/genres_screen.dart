import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/art/art_cache.dart';
import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import '../../widgets/cover_art.dart';
import '../../widgets/tokens.dart';
import 'catalog_routes.dart';
import 'data/catalog_providers.dart';
import 'format.dart';
import 'widgets/catalog_state.dart';
import 'widgets/entity_menu.dart';

/// Browse by genre.
///
/// Tiles lead with the cover of each genre's most-played album, because a genre is only
/// recognisable through the records in it — a grid of text chips reads as a tag dump.
class GenresScreen extends ConsumerWidget {
  const GenresScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final genres = ref.watch(genresProvider);

    return Scaffold(
      appBar: AppBar(title: Text(t(CatalogKeys.genresTitle))),
      body: CatalogBody<List<GenreSummary>>(
        value: genres,
        errorTitle: t(ErrorsKeys.catalogGenresLoadFailed),
        onRetry: () => ref.invalidate(genresProvider),
        skeleton: const CatalogGridSkeleton(),
        builder: (context, value) => value.isEmpty
            ? CatalogEmpty(message: t(CatalogKeys.genresEmpty))
            : GridView.builder(
                padding: const EdgeInsets.all(12),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 200,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 0.78,
                ),
                itemCount: value.length,
                itemBuilder: (context, index) =>
                    _GenreCard(genre: value[index]),
              ),
      ),
    );
  }
}

class _GenreCard extends ConsumerWidget {
  const _GenreCard({required this.genre});

  final GenreSummary genre;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final name = titleCaseGenre(genre.name);
    return EntityMenuGesture(
      // The title-cased name, not the catalog's lower-cased one: the sheet's header has to say
      // what the tile under the finger says, and `useGenreMenu` on the web is handed
      // `titleCaseGenre(g.name)` for exactly that reason.
      menu: (page, sheetRef) =>
          genreMenu(page, sheetRef, slug: genre.slug, name: name),
      child: InkWell(
        borderRadius: ChordiaRadius.lgAll,
        onTap: () => context.goToGenre(genre.slug),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) => CoverArt(
                    sha256: artHashOf(genre.imageUrl),
                    size: constraints.maxWidth,
                    semanticLabel: name,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                ref.t(CatalogKeys.genresCounts, {
                  'albums': genre.albumCount,
                  'artists': genre.artistCount,
                  'albumsFormatted': genre.albumCount,
                  'artistsFormatted': genre.artistCount,
                }),
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
