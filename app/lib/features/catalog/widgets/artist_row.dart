import 'dart:async';

import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../data/art/art_cache.dart';
import '../../../i18n/keys.g.dart';
import '../../../i18n/translations_provider.dart';
import '../../../widgets/cover_art.dart';
import '../catalog_routes.dart';
import 'album_grid.dart';
import 'entity_menu.dart';
import 'list_row.dart';

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
  Widget build(BuildContext context, WidgetRef ref) => ListRow(
    // The catalog row, not a `ListTile`: this sits directly above a `TrackRow` on a search-results
    // screen, and Material's 72px two-line height beside the web's row is the mismatch in one view.
    leading: CoverArt(
      sha256: artHashOf(artist.imageUrl),
      size: 40,
      shape: BoxShape.circle,
      // The artist glyph, not the account glyph: `MicrophoneStageIcon` is what the web means by
      // "artist" (`lib/menus/actions.tsx` goToArtist), and `UserIcon` there is only ever the
      // signed-in person (`layout/UserMenu.tsx`).
      fallbackIcon: PhosphorIconsFill.microphoneStage,
      fallbackInitial: artist.name,
      semanticLabel: artist.name,
    ),
    title: Text(artist.name),
    subtitle: Text(
      subtitle ??
          ref.t(CatalogKeys.artistCardAlbumCount, {'count': artist.albumCount}),
    ),
    onTap: () => context.goToArtist(artist.id),
    onLongPress: () => unawaited(
      showEntityMenu(
        context,
        (page, sheetRef) =>
            artistMenu(page, sheetRef, artistMenuTarget(artist)),
      ),
    ),
  );
}

/// The artist an [ArtistRow] or [ArtistTile] acts on, in the shape the menu takes.
ArtistLike artistMenuTarget(BrowseArtist artist) =>
    ArtistLike(id: artist.id, name: artist.name, imageUrl: artist.imageUrl);

/// One artist as a card, for the grids on a genre page and the "fans also like" shelf.
///
/// The same card body as an album's ([CatalogCard]) with two differences the web keeps too
/// (`components/catalog/ArtistShelf.tsx`): the portrait is round, and the two lines under it are
/// centred.
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

  /// The second line under the name — an album count on the similarity shelf, the kind of relation
  /// on the aliases shelf.
  final String? caption;

  final double? width;

  @override
  Widget build(BuildContext context) => EntityMenuGesture(
    menu: (page, ref) => artistMenu(
      page,
      ref,
      ArtistLike(id: artistId, name: name, imageUrl: imageUrl),
    ),
    child: CatalogCard(
      width: width,
      centred: true,
      onTap: () => context.goToArtist(artistId),
      title: name,
      caption: caption,
      art: CoverArtSlot(
        sha256: artHashOf(imageUrl),
        circular: true,
        fallbackIcon: PhosphorIconsFill.microphoneStage,
        fallbackInitial: name,
        semanticLabel: name,
      ),
    ),
  );
}

/// A horizontally scrolling row of artist cards.
///
/// Same box, same card width and same cap as the album shelves — the web hands all of them to one
/// `CardShelf`, so a page of shelves reads as one rhythm rather than four.
class ArtistShelf extends ConsumerWidget {
  const ArtistShelf({required this.artists, super.key, this.limit});

  final List<BrowseArtist> artists;

  /// How many cards the shelf shows; null shows all of them.
  final int? limit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cap = limit;
    final shown = cap == null
        ? artists
        : artists.take(cap).toList(growable: false);
    return CatalogShelf(
      itemCount: shown.length,
      itemBuilder: (context, index) => ArtistTile(
        artistId: shown[index].id,
        name: shown[index].name,
        imageUrl: shown[index].imageUrl,
        caption: ref.t(CatalogKeys.artistCardAlbumCount, {
          'count': shown[index].albumCount,
        }),
        width: catalogCardWidth,
      ),
    );
  }
}
