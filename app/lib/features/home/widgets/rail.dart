import 'package:flutter/material.dart';

import '../../catalog/widgets/catalog_state.dart';
import '../../catalog/widgets/section.dart';

/// The height of a card shelf, and the width of one card on it.
///
/// Both are `AlbumShelf`'s numbers (`features/catalog/widgets/album_grid.dart`), because home shows
/// that shelf beside its own: two shelves of different heights stacked on one page is the sort of
/// half-millimetre wrongness nobody can name and everybody sees.
const shelfHeight = 210.0;
const shelfCardWidth = 150.0;

/// The shelf's outer padding. The cards carry 6 of their own, so the first card lines up with the
/// heading at 16 and the gap between two cards comes to 12.
const shelfInset = 10.0;

/// One home shelf: a heading over a horizontally scrolling row.
class RailSection extends StatelessWidget {
  const RailSection({required this.title, required this.child, super.key});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SectionHeader(title: title),
      child,
    ],
  );
}

/// A shelf built from a list — the rails with no ready-made shelf of their own.
///
/// `ListView.builder`, so a rail of a hundred albums builds the three or four cards a thumb can
/// actually see.
class RailShelf extends StatelessWidget {
  const RailShelf({
    required this.height,
    required this.itemCount,
    required this.itemBuilder,
    super.key,
  });

  final double height;
  final int itemCount;
  final NullableIndexedWidgetBuilder itemBuilder;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: shelfInset),
      itemCount: itemCount,
      itemBuilder: itemBuilder,
    ),
  );
}

/// Home's shape before its first data arrives.
///
/// Three shelves in outline rather than a spinner: the page that follows has this shape, so
/// nothing jumps when the real rails replace it.
class HomeSkeleton extends StatelessWidget {
  const HomeSkeleton({super.key, this.rails = 3});

  final int rails;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (var rail = 0; rail < rails; rail++) ...[
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 24, 8, 12),
          child: SkeletonBox(width: 150, height: 20),
        ),
        SizedBox(
          height: shelfHeight,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: shelfInset),
            // Enough to run off the right edge of any phone.
            itemCount: 4,
            itemBuilder: (context, index) => const Padding(
              padding: EdgeInsets.all(6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(
                    width: shelfCardWidth,
                    height: shelfCardWidth,
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                  ),
                  SizedBox(height: 10),
                  SkeletonBox(width: 120, height: 12),
                  SizedBox(height: 6),
                  SkeletonBox(width: 80, height: 10),
                ],
              ),
            ),
          ),
        ),
      ],
    ],
  );
}
