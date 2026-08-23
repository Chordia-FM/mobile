import 'package:flutter/material.dart';

import '../../../widgets/states.dart';
import '../../../widgets/tokens.dart';
import '../../catalog/widgets/album_grid.dart';
import '../../catalog/widgets/section.dart';

/// The height of a card shelf, and the width of one card on it.
///
/// Aliases for the catalog's own numbers rather than a second pair, because home shows an
/// `AlbumShelf` beside its own shelves: two shelves of different heights stacked on one page is the
/// sort of half-millimetre wrongness nobody can name and everybody sees. The web has exactly one
/// rail too (`components/discovery/rail.tsx`), used by home and by the catalog alike.
const shelfHeight = catalogShelfHeight;
const shelfCardWidth = catalogCardWidth;

/// The shelf's outer padding — the page gutter, so the first card starts where the heading does.
const shelfInset = catalogGutter;

/// One home shelf: a heading over a horizontally scrolling row.
///
/// The web's `RailSection` (`rail.tsx:104`) is precisely this: a `RailHeader` and a `Rail`, and
/// nothing else, so every rail on the page shares one rhythm.
class RailSection extends StatelessWidget {
  const RailSection({
    required this.title,
    required this.child,
    super.key,
    this.onSeeAll,
  });

  final String title;
  final Widget child;

  /// The route to the full list, where the rail has one — `RailHeader`'s `seeAllTo`.
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SectionHeader(title: title, onSeeAll: onSeeAll),
      child,
    ],
  );
}

/// A shelf built from a list — the rails with no ready-made shelf of their own.
///
/// Delegates to [CatalogShelf] so the gutter, the `gap-3` between cards and the scroll physics are
/// the catalog's, not a second set. `ListView.builder` underneath, so a rail of a hundred albums
/// builds the three or four cards a thumb can actually see.
class RailShelf extends StatelessWidget {
  const RailShelf({
    required this.height,
    required this.itemCount,
    required this.itemBuilder,
    super.key,
  });

  /// Kept so a shelf of pills can be shorter than a shelf of cards.
  final double height;

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: CatalogShelf(itemCount: itemCount, itemBuilder: itemBuilder),
  );
}

/// Home's shape before its first data arrives.
///
/// Three shelves in outline rather than a spinner: the page that follows has this shape, so nothing
/// jumps when the real rails replace it. The silhouette is the CARD's — cover, title bar, caption
/// bar, at the card's own inset — which is what the web's `RailSkeleton` does; a row of bare
/// squares would be the shape of nothing in the app.
class HomeSkeleton extends StatelessWidget {
  const HomeSkeleton({super.key, this.rails = 3});

  final int rails;

  static const _coverSide = catalogCardWidth - catalogCardInset * 2;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (var rail = 0; rail < rails; rail++) ...[
        // The heading's own box: `space-y-10` above, `mb-4` below, a `text-xl` bar in between.
        const Padding(
          padding: EdgeInsets.fromLTRB(catalogGutter, 40, catalogGutter, 16),
          child: ShimmerBox(width: 150, height: 20),
        ),
        SizedBox(
          height: shelfHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: catalogGutter),
            separatorBuilder: (context, index) =>
                const SizedBox(width: catalogCardGap),
            // Enough to run off the right edge of any phone.
            itemCount: 4,
            itemBuilder: (context, index) => const SizedBox(
              width: catalogCardWidth,
              child: Padding(
                padding: EdgeInsets.all(catalogCardInset),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ShimmerBox(
                      width: _coverSide,
                      height: _coverSide,
                      borderRadius: ChordiaRadius.mdAll,
                    ),
                    SizedBox(height: 12),
                    ShimmerBox(width: 104, height: 12),
                    SizedBox(height: 6),
                    ShimmerBox(width: 64, height: 10),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    ],
  );
}
