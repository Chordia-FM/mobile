import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/art/art_cache.dart';
import '../../../i18n/keys.g.dart';
import '../../../i18n/translations_provider.dart';
import '../../../widgets/cover_art.dart';
import '../catalog_routes.dart';

/// One artist as a list row: round portrait, name, and how much of them there is.
///
/// Round art is not decoration — it is the one signal that separates an artist from an album at a
/// glance, and it has to be the same signal on every screen that lists both.
class ArtistRow extends ConsumerWidget {
  const ArtistRow({required this.artist, super.key, this.subtitle});

  final BrowseArtist artist;

  /// Overrides the default "N albums" line — an alias chip says what the relation is instead.
  final String? subtitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
    leading: CoverArt(
      sha256: artHashOf(artist.imageUrl),
      size: 48,
      shape: BoxShape.circle,
      fallbackIcon: Icons.person_rounded,
      semanticLabel: artist.name,
    ),
    title: Text(artist.name, maxLines: 1, overflow: TextOverflow.ellipsis),
    subtitle: Text(
      subtitle ??
          ref.t(CatalogKeys.artistCardAlbumCount, {'count': artist.albumCount}),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
    onTap: () => context.goToArtist(artist.id),
  );
}

/// One artist as a tile, for the grids on a genre page and the "fans also like" shelf.
class ArtistTile extends StatelessWidget {
  const ArtistTile({
    required this.artistId,
    required this.name,
    super.key,
    this.imageUrl,
    this.caption,
    this.width,
  });

  final String artistId;
  final String name;
  final String? imageUrl;

  /// A second line under the name — the kind of relation, on the aliases shelf.
  final String? caption;

  final double? width;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: width,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.goToArtist(artistId),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) => CoverArt(
                    sha256: artHashOf(imageUrl),
                    size: constraints.maxWidth,
                    shape: BoxShape.circle,
                    fallbackIcon: Icons.person_rounded,
                    semanticLabel: name,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                name,
                maxLines: 1,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (caption != null)
                Text(
                  caption!,
                  maxLines: 1,
                  textAlign: TextAlign.center,
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

/// A horizontally scrolling row of artist tiles.
class ArtistShelf extends StatelessWidget {
  const ArtistShelf({required this.artists, super.key});

  final List<BrowseArtist> artists;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 180,
    child: ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      itemCount: artists.length,
      itemBuilder: (context, index) => ArtistTile(
        artistId: artists[index].id,
        name: artists[index].name,
        imageUrl: artists[index].imageUrl,
        width: 130,
      ),
    ),
  );
}
