import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../i18n/keys.g.dart';
import '../../../i18n/translations_provider.dart';
import '../../../widgets/tokens.dart';
import '../../catalog/catalog_routes.dart';
import '../../catalog/widgets/catalog_state.dart';
import '../../home/data/discovery_nav.dart';
import '../../home/widgets/cards.dart';
import '../../home/widgets/rail.dart';
import '../../library/widgets/collection_header.dart';
import 'profile_reads.dart';

/// How many rows the Hub puts on a profile shelf (`PROFILE_SHELF_LIMIT` in the backend's
/// `users.rs`). A shelf that comes back full is the only signal that there are more.
const _shelfLimit = 12;

/// A shelf heading with the See-all affordance beside it.
///
/// Its own widget rather than the catalog's [SectionHeader] because "See all" here expands the
/// shelf **in place** — there is no playlists page to link to, and the followers/following lists
/// are tabs on this same profile.
class _ShelfHeader extends ConsumerWidget {
  const _ShelfHeader({required this.title, this.onSeeAll});

  final String title;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 8, 4),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        if (onSeeAll != null)
          TextButton(
            onPressed: onSeeAll,
            child: Text(ref.t(SocialKeys.profileShelvesSeeAll)),
          ),
      ],
    ),
  );
}

/// The public-playlists shelf.
///
/// "See all" expands IN PLACE via the full-list endpoint, exactly as the web does: there is no
/// dedicated playlists page to send anyone to. The first twelve rows already arrived with the
/// profile, so nothing is fetched until it is pressed.
///
/// The web gates See-all on how many cards its widest desktop grid reveals, because rows past that
/// are unreachable there. A phone has no grid — the shelf scrolls to everything it holds — so the
/// honest gate here is the one the web shares: are there more than the shelf was given.
class PlaylistShelf extends ConsumerStatefulWidget {
  const PlaylistShelf({
    required this.handle,
    required this.shelf,
    required this.total,
    super.key,
  });

  final String handle;
  final List<Playlist> shelf;
  final int total;

  @override
  ConsumerState<PlaylistShelf> createState() => _PlaylistShelfState();
}

class _PlaylistShelfState extends ConsumerState<PlaylistShelf> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final t = ref.t;
    final full = _expanded
        ? ref.watch(allUserPlaylistsProvider(widget.handle)).value
        : null;
    final items = full ?? widget.shelf;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ShelfHeader(
          title: t(SocialKeys.profileShelvesPlaylists),
          onSeeAll: !_expanded && widget.total > widget.shelf.length
              ? () => setState(() => _expanded = true)
              : null,
        ),
        if (items.isEmpty)
          CatalogEmpty(message: t(SocialKeys.profileShelvesNoPlaylists))
        else
          RailShelf(
            height: shelfHeight,
            itemCount: items.length,
            itemBuilder: (context, index) {
              final playlist = items[index];
              return SizedBox(
                width: shelfCardWidth,
                child: InkWell(
                  borderRadius: ChordiaRadius.lgAll,
                  onTap: () => context.goToPlaylist(playlist.id),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // A playlist with no cover of its own is a mosaic of what is in it, the
                        // same fallback the library's own rows use.
                        MosaicCover(
                          coverUrl: playlist.coverUrl,
                          autoCoverUrls: playlist.autoCoverUrls,
                          size: shelfCardWidth - 12,
                          semanticLabel: playlist.name,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          playlist.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          t(CatalogKeys.trackCount, {
                            'count': playlist.trackCount,
                          }),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

/// The followed-artists shelf, same expand-in-place shape as [PlaylistShelf].
///
/// It sits under the **Following** tab rather than in a section of its own, because following is
/// one question — who does this person follow — and answering half of it in a tab and the other
/// half further down the page made them look like different things.
class ArtistShelf extends ConsumerStatefulWidget {
  const ArtistShelf({required this.handle, required this.shelf, super.key});

  final String handle;
  final List<ProfileArtist> shelf;

  @override
  ConsumerState<ArtistShelf> createState() => _ArtistShelfState();
}

class _ArtistShelfState extends ConsumerState<ArtistShelf> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final t = ref.t;
    final full = _expanded
        ? ref.watch(allFollowedArtistsProvider(widget.handle)).value
        : null;
    final items = full ?? widget.shelf;
    // The DTO carries no followed-artist total, so a shelf that came back at the Hub's limit IS
    // the truncation signal.
    final truncated = widget.shelf.length >= _shelfLimit;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ShelfHeader(
          title: t(SocialKeys.profileShelvesFollowedArtists),
          onSeeAll: !_expanded && truncated
              ? () => setState(() => _expanded = true)
              : null,
        ),
        if (items.isEmpty)
          CatalogEmpty(message: t(SocialKeys.profileShelvesNoArtists))
        else
          RailShelf(
            height: shelfHeight,
            itemCount: items.length,
            itemBuilder: (context, index) {
              final artist = items[index];
              return EntityCard(
                title: artist.name,
                imageUrl: artist.imageUrl,
                shape: BoxShape.circle,
                fallbackIcon: PhosphorIcons.user(),
                // Followed artists are MBID-identified and need not exist in this Hub's catalog.
                // Only one the Hub resolved an `artist_id` for — in a library this VIEWER can
                // reach — has a page to open; the rest are plain, non-interactive cards.
                onTap: artist.artistId == null
                    ? null
                    : () => context.goToArtist(artist.artistId!),
              );
            },
          ),
      ],
    );
  }
}
