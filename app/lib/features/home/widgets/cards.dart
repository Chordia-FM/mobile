import 'package:flutter/material.dart';

import '../../../data/art/art_cache.dart';
import '../../../widgets/cover_art.dart';
import '../../../widgets/surface.dart';
import '../../../widgets/tokens.dart';
import '../../catalog/widgets/album_grid.dart';
import 'rail.dart';

/// One card on a home shelf: artwork over a name and, usually, a second line.
///
/// Now literally the catalog's [CatalogCard] rather than a copy built "to its proportions" — a mix
/// card and an album card sit two shelves apart on the same page, and the copy had already drifted
/// (6px of inset against 12, 8px under the cover against 12). The web has one card for both
/// (`components/discovery/cards.tsx` renders the same `RAIL_CARD` block `AlbumGrid.tsx` does), so
/// one card here is the same decision, not a shortcut.
class EntityCard extends StatelessWidget {
  const EntityCard({
    required this.title,
    required this.onTap,
    super.key,
    this.imageUrl,
    this.subtitle,
    this.shape = BoxShape.rectangle,
    this.width = shelfCardWidth,
    this.fallbackIcon = Icons.album_rounded,
  });

  /// The Hub image reference, exactly as the DTO carries it; the hash is taken out here.
  final String? imageUrl;
  final String title;
  final String? subtitle;

  /// Circular for the kinds that stand for a person or a station.
  final BoxShape shape;
  final double width;
  final IconData fallbackIcon;

  /// Null only where there is genuinely nowhere to go, so no tap is ever swallowed.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final round = shape == BoxShape.circle;
    return CatalogCard(
      width: width,
      centred: round,
      onTap: onTap,
      title: title,
      caption: subtitle,
      art: CoverArtSlot(
        sha256: artHashOf(imageUrl),
        circular: round,
        fallbackIcon: fallbackIcon,
        // A round card stands for a person or a station, so an imageless one gets the monogram
        // rather than a glyph — `ArtistGrid.tsx:59` passes `fallbackInitial={a.name}` for exactly
        // this case.
        fallbackInitial: round ? title : null,
        semanticLabel: title,
      ),
    );
  }
}

/// A pinned entity as a compact pill: small artwork and a name, no second line.
///
/// The phone has no sidebar, so this shelf is where pins live. Pills rather than cards because a
/// row people scan for a name they already know should cost as little height as it can.
///
/// Shaped like the web's sidebar pin rows: `rounded-full`, a `--pane-raised` fill, an
/// accent-tinted hairline, and the same instant fill on press that every other row here uses.
class PinPill extends StatelessWidget {
  const PinPill({
    required this.name,
    required this.onTap,
    super.key,
    this.imageUrl,
    this.round = false,
  });

  final String name;
  final String? imageUrl;

  /// Circular artwork for the kinds that stand for a person or a station.
  final bool round;
  final VoidCallback onTap;

  /// The pill plus its shelf padding; comfortably past the 44px touch floor
  /// ([ChordiaControl.sm]).
  static const shelfHeight = 68.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: PressFill(
        onTap: onTap,
        borderRadius: ChordiaRadius.pill,
        child: Container(
          constraints: const BoxConstraints(
            maxWidth: 220,
            minHeight: ChordiaControl.sm,
          ),
          padding: const EdgeInsets.fromLTRB(6, 6, 16, 6),
          decoration: BoxDecoration(
            color: scheme.surfaceContainer,
            borderRadius: ChordiaRadius.pill,
            border: Border.all(color: scheme.line),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CoverArt(
                sha256: artHashOf(imageUrl),
                size: 44,
                shape: round ? BoxShape.circle : BoxShape.rectangle,
                fallbackInitial: round ? name : null,
                semanticLabel: name,
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  // `font-semibold text-sm`, the same line a card title uses.
                  style: ChordiaType.sm.copyWith(
                    fontWeight: ChordiaType.semibold,
                    color: scheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A friend and what they are playing right now.
///
/// The avatar is the artwork, not the album cover: the shelf answers "who is listening", and the
/// track is the line underneath because that is the part that changes every three minutes. The web
/// makes the same call in `FriendsListeningRail.tsx:102`, where the card's cover is
/// `rounded-full` on the friend's avatar.
class FriendCard extends StatelessWidget {
  const FriendCard({
    required this.displayName,
    required this.line,
    required this.onTap,
    super.key,
    this.avatarUrl,
  });

  final String displayName;

  /// The track, composed as one line by the caller so this widget holds no formatting.
  final String line;
  final String? avatarUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => CatalogCard(
    width: shelfCardWidth,
    centred: true,
    onTap: onTap,
    title: displayName,
    caption: line,
    art: CoverArtSlot(
      sha256: artHashOf(avatarUrl),
      circular: true,
      fallbackIcon: Icons.person_rounded,
      fallbackInitial: displayName,
      semanticLabel: displayName,
    ),
  );
}
