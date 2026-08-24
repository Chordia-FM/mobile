import 'dart:async';

import 'package:flutter/material.dart';

import '../../../data/art/art_cache.dart';
import '../../../widgets/cover_art.dart';
import '../../catalog/widgets/entity_menu.dart';
import '../../catalog/widgets/list_row.dart';

/// One search result that is not a track or an artist — those have rows of their own in the catalog
/// feature, and a result list has to look like the lists it links into.
///
/// [ListRow] rather than a `ListTile` for the reason `ArtistRow` gives in the same words: these sit
/// directly under a `TrackRow` and above an `ArtistRow` in ONE scroll, and Material's 72px two-line
/// height beside the web's row is the mismatch showing up in a single view. Same 40px leading slot
/// as those two, for the same reason.
class ResultRow extends StatelessWidget {
  const ResultRow({
    required this.title,
    required this.onTap,
    super.key,
    this.imageUrl,
    this.subtitle,
    this.fallbackIcon = Icons.album_rounded,
    this.menu,
  });

  final String title;
  final String? subtitle;

  /// The Hub image reference as the DTO carries it; the hash is taken out here.
  final String? imageUrl;
  final IconData fallbackIcon;
  final VoidCallback? onTap;

  /// What a long press on this result offers.
  ///
  /// Supplied by the caller rather than derived here: a result row is kindless by design — one row
  /// draws albums, playlists, labels and genres — and the group that built it is the only thing
  /// that knows which. The web's search results carry their menus (`routes/…/search.tsx` wraps its
  /// label cards, and its albums come through `AlbumGrid`, which wraps every card), so a row
  /// without one is a result that can only be opened.
  final EntityMenuBuilder? menu;

  @override
  Widget build(BuildContext context) {
    final second = subtitle;
    final rowMenu = menu;
    return ListRow(
      leading: CoverArt(
        sha256: artHashOf(imageUrl),
        size: 40,
        fallbackIcon: fallbackIcon,
        semanticLabel: title,
      ),
      title: Text(title),
      subtitle: second == null ? null : Text(second),
      onTap: onTap,
      onLongPress: rowMenu == null
          ? null
          : () => unawaited(showEntityMenu(context, rowMenu)),
    );
  }
}
