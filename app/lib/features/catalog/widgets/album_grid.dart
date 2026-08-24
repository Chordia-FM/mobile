import 'dart:math' as math;

import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/art/art_cache.dart';
import '../../../i18n/keys.g.dart';
import '../../../i18n/translations_provider.dart';
import '../../../widgets/cover_art.dart';
import '../../../widgets/surface.dart';
import '../../../widgets/tokens.dart';
import '../catalog_routes.dart';
import '../format.dart';
import 'entity_menu.dart';
import 'section.dart';

/// One shelf card, edge to edge — the web's `w-40` (`components/catalog/DiscographyRow.tsx`).
const catalogCardWidth = 160.0;

/// The inset every card carries — the web's `p-3`. The cover is the card width minus twice this,
/// which is what makes a shelf card and a grid tile read as the same object at two sizes.
const catalogCardInset = 12.0;

/// The gap between two cards — the web's `gap-3`.
const catalogCardGap = 12.0;

/// A shelf's height: inset, a square cover, the `mb-3` under it, a title line, a caption line, and
/// the inset again. Derived rather than guessed, so changing the card width moves it correctly.
const catalogShelfHeight =
    catalogCardInset * 2 +
    (catalogCardWidth - catalogCardInset * 2) +
    12 +
    20 +
    16;

/// Cards a shelf shows before "See all" takes over — the web's `DISCOGRAPHY_PREVIEW`.
const catalogShelfPreview = 10;

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
    // The page gutter, exactly as `AlbumGrid.tsx` inherits it from the route's `px-4`.
    padding: const EdgeInsets.symmetric(horizontal: catalogGutter),
    sliver: SliverGrid.builder(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        // Two columns on a phone, more on a tablet, without a breakpoint anywhere — the web's
        // `grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 xl:grid-cols-6`.
        maxCrossAxisExtent: 200,
        mainAxisSpacing: catalogCardGap,
        crossAxisSpacing: catalogCardGap,
        childAspectRatio: 0.74,
      ),
      itemCount: albums.length,
      itemBuilder: (context, index) =>
          AlbumCard(album: albums[index], showArtist: showArtist),
    ),
  );
}

/// One album tile: square cover, title, and the line that identifies the release.
///
/// Two lines under the art, never more, and square art always — round is reserved for artists, and
/// it is the one signal that separates a person from a record at a glance
/// (`components/catalog/AlbumGrid.tsx` vs `ArtistGrid.tsx`).
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
    final subtitle = showArtist
        ? ref.t(CatalogKeys.albumCardArtistYearJoin, {
            'artist': album.artist,
            'year': album.year,
          })
        : (album.year?.toString() ?? '');

    return EntityMenuGesture(
      menu: (page, sheetRef) => albumMenu(
        page,
        sheetRef,
        AlbumLike(
          id: album.id,
          title: album.title,
          artist: album.artist,
          artistId: album.artistId,
          coverUrl: album.coverUrl,
        ),
      ),
      child: CatalogCard(
        width: width,
        onTap: () => context.goToAlbum(album.id),
        title: album.title,
        caption: subtitle,
        art: CoverArtSlot(
          sha256: artHashOf(album.coverUrl),
          semanticLabel: album.title,
        ),
      ),
    );
  }
}

/// The card body shared by every catalog card — art, one bold line, one muted line.
///
/// The web's shelf and grid cards are the same markup at two widths
/// (`DiscographyRow.tsx` sets `w-40 shrink-0 md:w-auto` on the same card `AlbumGrid.tsx` renders in
/// a grid track), so this is one widget that a shelf sizes and a grid cell measures.
class CatalogCard extends StatelessWidget {
  const CatalogCard({
    required this.art,
    required this.title,
    required this.onTap,
    super.key,
    this.caption,
    this.width,
    this.centred = false,
  });

  final Widget art;
  final String title;

  /// The second line: a year, a release type, a track count, a relation. Empty renders nothing —
  /// a blank line under a title is a layout bug, not a caption.
  final String? caption;

  /// Nullable, and still `required`: a followed artist the Hub could not resolve to a catalog page
  /// has genuinely nowhere to go, and a card that fills under a thumb and then does nothing is
  /// worse than one that admits it is inert. [PressFill] with no callback is not interactive.
  final VoidCallback? onTap;

  final double? width;

  /// Artist cards centre their text under the round portrait (`ArtistGrid.tsx`'s `text-center`);
  /// album cards do not.
  final bool centred;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final subtitle = caption;
    return SizedBox(
      width: width,
      // `rounded-xl`, and a fill rather than a ripple: the web's cards are
      // `rounded-xl p-3 transition-none hover:bg-accent/40`, and the `transition-none` is
      // deliberate — see [PressFill].
      child: PressFill(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(catalogCardInset),
          child: Column(
            crossAxisAlignment: centred
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Expanded(child: art),
              // The web's `mb-3` under the art.
              const SizedBox(height: 12),
              Text(
                title,
                maxLines: 1,
                textAlign: centred ? TextAlign.center : TextAlign.start,
                overflow: TextOverflow.ellipsis,
                // `truncate font-semibold text-sm`. Material's `bodyMedium` is 16px at w400 and
                // was a size too big here, which is what made every grid on the phone read as a
                // Material list rather than as this app's browse grid.
                style: ChordiaType.sm.copyWith(
                  fontWeight: ChordiaType.semibold,
                  color: scheme.onSurface,
                ),
              ),
              if (subtitle != null && subtitle.isNotEmpty)
                Text(
                  subtitle,
                  maxLines: 1,
                  textAlign: centred ? TextAlign.center : TextAlign.start,
                  overflow: TextOverflow.ellipsis,
                  // `truncate text-muted-foreground text-xs`.
                  style: ChordiaType.xs.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A card's artwork slot: square, measured from whatever space the card has.
///
/// Sized from the SHORTER of the two axes. A grid tile whose row is taller than its column is wide
/// would otherwise hand the cover a width it cannot be tall enough for, and the art would spill
/// past its own clip.
class CoverArtSlot extends StatelessWidget {
  const CoverArtSlot({
    required this.sha256,
    super.key,
    this.semanticLabel,
    this.circular = false,
    this.fallbackIcon = Icons.music_note_rounded,
    this.fallbackInitial,
  });

  final String? sha256;
  final String? semanticLabel;

  /// Round for artists, square for everything else.
  final bool circular;

  final IconData fallbackIcon;

  /// A name whose initial stands in when there is no portrait — see [CoverArt.fallbackInitial].
  final String? fallbackInitial;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final side = math.min(constraints.maxWidth, constraints.maxHeight);
      return Align(
        alignment: Alignment.topCenter,
        // `shadow-lg` on the cover itself (AlbumGrid.tsx:63, ArtistGrid.tsx:56). On this palette a
        // dark cover on a dark card has no edge without it, which is a large part of why the
        // phone's grids read flat next to the desktop's.
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: circular ? BoxShape.circle : BoxShape.rectangle,
            borderRadius: circular ? null : ChordiaRadius.mdAll,
            boxShadow: chordiaCoverShadow,
          ),
          child: CoverArt(
            sha256: sha256,
            size: side,
            shape: circular ? BoxShape.circle : BoxShape.rectangle,
            fallbackIcon: fallbackIcon,
            fallbackInitial: fallbackInitial,
            semanticLabel: semanticLabel,
          ),
        ),
      );
    },
  );
}

/// A horizontally scrolling row of album cards — the discography shelves on an artist page.
///
/// The web's `CardShelf` (`components/catalog/CardShelf.tsx`): below `md` it is a horizontal snap
/// shelf whose first and last cards line up with the page gutter, capped at `DISCOGRAPHY_PREVIEW`
/// cards with the section's "See all" carrying the rest.
class AlbumShelf extends StatelessWidget {
  const AlbumShelf({required this.albums, super.key, this.leading, this.limit});

  final List<BrowseAlbum> albums;

  /// A card that goes first and is not an album — the artist page's Live collection entry, for
  /// instance. It takes the first slot, so it counts against [limit].
  final Widget? leading;

  /// How many album cards the shelf shows; null shows all of them. Optional for the same reason
  /// the web's `DiscographyRow.limit` is: a preview beside a "See all" caps, a rail that IS the
  /// whole list does not.
  final int? limit;

  @override
  Widget build(BuildContext context) {
    final lead = leading;
    final cap = limit;
    final shown = cap == null
        ? albums
        : albums.take(lead == null ? cap : cap - 1).toList(growable: false);
    return CatalogShelf(
      itemCount: shown.length + (lead == null ? 0 : 1),
      itemBuilder: (context, index) {
        if (lead != null && index == 0) {
          return SizedBox(width: catalogCardWidth, child: lead);
        }
        final album = shown[index - (lead == null ? 0 : 1)];
        return AlbumCard(album: album, width: catalogCardWidth);
      },
    );
  }
}

/// The shelf box itself: one card-high strip that bleeds to the screen edge while its first and
/// last cards still align with the page gutter.
class CatalogShelf extends StatelessWidget {
  const CatalogShelf({
    required this.itemCount,
    required this.itemBuilder,
    super.key,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: catalogShelfHeight,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      // The page gutter — the web's `-mx-4 … px-4`, which lets the strip bleed to the screen edge
      // while the first and last CARDS still start on the gutter (their covers sit one card inset
      // further in, exactly as they do in the grid).
      padding: const EdgeInsets.symmetric(horizontal: catalogGutter),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: itemCount,
      separatorBuilder: (context, index) =>
          const SizedBox(width: catalogCardGap),
      itemBuilder: itemBuilder,
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
