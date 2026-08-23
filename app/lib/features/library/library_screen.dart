import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/art/art_cache.dart';
import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import '../../widgets/cover_art.dart';
import '../libraries/libraries_home_screen.dart';
import 'catalog_browse_screen.dart';
import 'data/library_providers.dart';
import 'downloads_screen.dart';
import 'liked_screen.dart';
import 'playlist_detail_screen.dart';
import 'playlists_screen.dart';

/// The Library tab: everything the listener has put somewhere on purpose.
///
/// Pinned things come first, because a pin is the listener saying "this one, quickly". Below that
/// the collections are entry rows rather than expanded shelves: on a phone six half-shelves fill
/// the screen without showing all of any of them, and the counts on each row already answer the
/// question a shelf would.
class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final playlists = ref.watch(playlistsProvider);
    final smart = ref.watch(smartPlaylistsProvider);
    final downloads = ref.watch(downloadedTracksProvider);
    final libraries = ref.watch(myLibrariesProvider);

    return Scaffold(
      appBar: AppBar(title: Text(t(CommonKeys.navLibrary))),
      body: RefreshIndicator(
        onRefresh: () async {
          ref
            ..invalidate(pinsProvider)
            ..invalidate(playlistsProvider)
            ..invalidate(smartPlaylistsProvider)
            ..invalidate(myLibrariesProvider)
            ..invalidate(sharedLibrariesProvider);
        },
        child: ListView(
          children: [
            const _PinnedShelf(),
            _Entry(
              icon: Icons.queue_music_rounded,
              label: t(LibraryKeys.sidebarPlaylists),
              trailing: _countOf(playlists, (rows) => rows.length),
              onTap: () => _push(context, const PlaylistsScreen()),
            ),
            _Entry(
              icon: Icons.auto_awesome_rounded,
              label: t(PlaylistsKeys.smartKindLabel),
              trailing: _countOf(smart, (rows) => rows.length),
              onTap: () => _push(context, const SmartPlaylistsScreen()),
            ),
            _Entry(
              icon: Icons.favorite_rounded,
              label: t(LibraryKeys.likedTitle),
              onTap: () => _push(context, const LikedScreen()),
            ),
            _Entry(
              icon: Icons.download_rounded,
              label: t(LibraryKeys.downloadsNavLabel),
              trailing: _countOf(downloads, (rows) => rows.length),
              onTap: () => _push(context, const DownloadsScreen()),
            ),
            _Entry(
              icon: Icons.person_rounded,
              label: t(LibraryKeys.artistsTitle),
              onTap: () => _push(context, const ArtistsScreen()),
            ),
            _Entry(
              icon: Icons.album_rounded,
              // Not "Albums": the Hub has no flat album browse, and this endpoint answers with at
              // most fifty. Naming the row for what it actually shows keeps the promise honest.
              label: t(DiscoveryKeys.shelfRecentlyAdded),
              onTap: () => _push(context, const RecentAlbumsScreen()),
            ),
            _Entry(
              icon: Icons.dns_rounded,
              label: t(LibraryKeys.listTitle),
              trailing: _countOf(libraries, (rows) => rows.length),
              onTap: () => _push(context, const LibrariesHomeScreen()),
            ),
          ],
        ),
      ),
    );
  }

  /// A count only once it is known. A zero printed while the request is still in flight reads as
  /// "you have no playlists", which is the one thing this row must not say by accident.
  static String? _countOf<T>(AsyncValue<T> value, int Function(T) count) {
    final loaded = value.value;
    return loaded == null ? null : '${count(loaded)}';
  }

  static void _push(BuildContext context, Widget screen) {
    // Pushed onto the tab's own navigator, so the Library tab keeps its stack across tab switches
    // and the system back button unwinds it. These screens take plain constructor arguments, so
    // moving them onto declarative `go_router` routes later is a one-line change per screen.
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }
}

class _Entry extends StatelessWidget {
  const _Entry({
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final String? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(icon, color: theme.colorScheme.primary),
      title: Text(label),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (trailing != null)
            Text(
              trailing!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          const Icon(Icons.chevron_right_rounded),
        ],
      ),
      onTap: onTap,
    );
  }
}

/// The pinned shelf. Absent entirely when nothing is pinned — an empty shelf with a heading
/// implies something is missing, when in fact nothing has been put there yet.
class _PinnedShelf extends ConsumerWidget {
  const _PinnedShelf();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final pins = ref.watch(pinsProvider);
    final rows = pins.value ?? const <PinnedItem>[];
    if (rows.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            t(LibraryKeys.sidebarPinned),
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        SizedBox(
          height: 156,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: rows.length,
            separatorBuilder: (context, index) => const SizedBox(width: 12),
            itemBuilder: (context, index) => _PinTile(pin: rows[index]),
          ),
        ),
        const Divider(height: 24),
      ],
    );
  }
}

class _PinTile extends ConsumerWidget {
  const _PinTile({required this.pin});

  final PinnedItem pin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final handoff = ref.watch(libraryHandoffProvider);
    // A playlist pin opens a screen this feature owns; the other three kinds live in the catalog
    // milestone, so until it lands they render without an action rather than with a dead one.
    final open = switch (pin.kind) {
      PinKind.playlist => () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PlaylistDetailScreen(playlistId: pin.id),
        ),
      ),
      PinKind.album =>
        handoff == null ? null : () => handoff.openAlbum(context, pin.id),
      PinKind.artist =>
        handoff == null ? null : () => handoff.openArtist(context, pin.id),
      PinKind.radio =>
        handoff == null ? null : () => handoff.openRadio(context, pin.id),
    };

    return SizedBox(
      width: 108,
      child: InkWell(
        onTap: open,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CoverArt(
              sha256: artHashOf(pin.imageUrl),
              size: 108,
              shape: pin.kind == PinKind.artist
                  ? BoxShape.circle
                  : BoxShape.rectangle,
              fallbackIcon: switch (pin.kind) {
                PinKind.album => Icons.album_rounded,
                PinKind.artist => Icons.person_rounded,
                PinKind.playlist => Icons.queue_music_rounded,
                PinKind.radio => Icons.radio_rounded,
              },
              semanticLabel: pin.name,
            ),
            const SizedBox(height: 6),
            Text(
              pin.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
