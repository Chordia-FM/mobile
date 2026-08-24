import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';

import '../../../data/art/art_cache.dart';
import '../../../widgets/cover_art.dart';
import '../../../widgets/surface.dart';
import '../../../widgets/tokens.dart';
import '../../catalog/catalog_routes.dart';
import '../../catalog/widgets/album_grid.dart';
import '../../catalog/widgets/entity_menu.dart';
import '../data/discovery_nav.dart';
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
    this.menu,
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

  /// This card's long-press menu.
  ///
  /// A parameter rather than something the card derives, because the card is deliberately kindless
  /// — it draws a title over artwork for six different sorts of thing — and only the shelf knows
  /// which of them this one is. The web attaches a menu to every card it renders
  /// (`components/discovery/cards.tsx` wraps all four kinds in `EntityContextMenu`), so a card
  /// without one is a card that answers less than the same card on the desktop.
  final EntityMenuBuilder? menu;

  @override
  Widget build(BuildContext context) {
    final round = shape == BoxShape.circle;
    final card = CatalogCard(
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

    return menu == null ? card : EntityMenuGesture(menu: menu!, child: card);
  }
}

/// One "Jump back in" entry: an album, an artist or a playlist the listener has played.
///
/// A widget rather than an [EntityCard] built at each call site, because the shelf and the "See
/// all" page show the same entry and the kind→shape→destination mapping is the whole content of
/// the card. The web keeps it in one place too (`components/discovery/cards.tsx` `RecentCard`).
class RecentCard extends StatelessWidget {
  const RecentCard({required this.item, super.key});

  final RecentItem item;

  @override
  Widget build(BuildContext context) => EntityCard(
    imageUrl: item.imageUrl,
    title: item.name,
    subtitle: item.subtitle,
    // Round is the one signal that separates a person from a record at a glance.
    shape: item.kind == RecentKind.artist
        ? BoxShape.circle
        : BoxShape.rectangle,
    fallbackIcon: switch (item.kind) {
      RecentKind.artist => Icons.person_rounded,
      RecentKind.playlist => Icons.queue_music_rounded,
      RecentKind.album => Icons.album_rounded,
    },
    onTap: () => switch (item.kind) {
      RecentKind.album => context.goToAlbum(item.id),
      RecentKind.artist => context.goToArtist(item.id),
      RecentKind.playlist => context.goToPlaylist(item.id),
    },
    // The kind picks the menu exactly as it picks the destination. `RecentItem.mbid` exists for
    // this: its doc says it is carried "so a menu on a 'Jump back in' card can link straight into
    // the Manager instead of falling back to a name search", and until now nothing read it.
    menu: switch (item.kind) {
      RecentKind.album => (page, ref) => albumMenu(
        page,
        ref,
        AlbumLike(
          id: item.id,
          title: item.name,
          artist: item.subtitle,
          coverUrl: item.imageUrl,
          mbid: item.mbid,
        ),
      ),
      RecentKind.artist => (page, ref) => artistMenu(
        page,
        ref,
        ArtistLike(
          id: item.id,
          name: item.name,
          imageUrl: item.imageUrl,
          mbid: item.mbid,
        ),
      ),
      RecentKind.playlist => (page, ref) => playlistMenu(
        page,
        ref,
        PlaylistLike(id: item.id, name: item.name, coverUrl: item.imageUrl),
      ),
    },
  );
}

/// One "Made for you" mix.
///
/// It opens the MIX, not the artist radio its seed would generate. Those are two Hub endpoints
/// answering with two track lists under two titles — the Hub's own words are that a mix "draws
/// inward (the seed plus artists the caller already plays)" while radio draws outward and never
/// ends — and this card pointing at the second one is what made the shelf's headline row lie.
class MixCard extends StatelessWidget {
  const MixCard({required this.mix, super.key});

  final DailyMix mix;

  @override
  Widget build(BuildContext context) => EntityCard(
    imageUrl: mix.imageUrl,
    title: mix.title,
    subtitle: mix.subtitle,
    fallbackIcon: Icons.radio_rounded,
    onTap: () => context.goToDailyMix(mix.seedArtistId),
    menu: (page, ref) => mixMenu(
      page,
      ref,
      MixLike(
        seedArtistId: mix.seedArtistId,
        title: mix.title,
        subtitle: mix.subtitle,
        imageUrl: mix.imageUrl,
      ),
    ),
  );
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
    this.menu,
  });

  final String name;
  final String? imageUrl;

  /// Circular artwork for the kinds that stand for a person or a station.
  final bool round;
  final VoidCallback onTap;

  /// This pin's long-press menu, from the shelf that knows which kind of thing it is — the web's
  /// sidebar pins carry one (`components/app/Sidebar.tsx`), and unpinning is otherwise unreachable
  /// from the only place the phone shows pins at all.
  final EntityMenuBuilder? menu;

  /// The pill plus its shelf padding; comfortably past the 44px touch floor
  /// ([ChordiaControl.sm]).
  static const shelfHeight = 68.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pill = Padding(
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

    return menu == null ? pill : EntityMenuGesture(menu: menu!, child: pill);
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
