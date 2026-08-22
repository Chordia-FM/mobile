import 'package:flutter/material.dart';

import '../../../data/art/art_cache.dart';
import '../../../widgets/cover_art.dart';
import 'rail.dart';

/// One card on a home shelf: artwork over a name and, usually, a second line.
///
/// Built to `AlbumCard`'s proportions (`features/catalog/widgets/album_grid.dart`) — 6px of inset,
/// a cover measured from the slot rather than fixed, one bold line and one muted one — because a
/// mix card and an album card sit two shelves apart on the same page.
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
    final theme = Theme.of(context);
    final centred = shape == BoxShape.circle;
    return SizedBox(
      width: width,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: centred
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            children: [
              // Measured, not fixed: the same card fills a 150px shelf slot on a phone and a wider
              // one on a tablet without a second set of numbers.
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) => CoverArt(
                    sha256: artHashOf(imageUrl),
                    size: constraints.maxWidth,
                    shape: shape,
                    fallbackIcon: fallbackIcon,
                    semanticLabel: title,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: centred ? TextAlign.center : TextAlign.start,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: centred ? TextAlign.center : TextAlign.start,
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

/// A pinned entity as a compact pill: small artwork and a name, no second line.
///
/// The phone has no sidebar, so this shelf is where pins live. Pills rather than cards because a
/// row people scan for a name they already know should cost as little height as it can.
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

  /// The pill plus its shelf padding; comfortably past a 48dp target.
  static const shelfHeight = 68.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 220),
          padding: const EdgeInsets.fromLTRB(6, 6, 16, 6),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: theme.colorScheme.outline),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CoverArt(
                sha256: artHashOf(imageUrl),
                size: 44,
                shape: round ? BoxShape.circle : BoxShape.rectangle,
                semanticLabel: name,
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
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
/// track is the line underneath because that is the part that changes every three minutes.
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: shelfCardWidth,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) => CoverArt(
                    sha256: artHashOf(avatarUrl),
                    size: constraints.maxWidth,
                    shape: BoxShape.circle,
                    fallbackIcon: Icons.person_rounded,
                    semanticLabel: displayName,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                line,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
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
