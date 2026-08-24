import 'dart:async';

import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../data/art/art_cache.dart';
import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import '../catalog/widgets/list_row.dart';
import '../../widgets/cover_art.dart';
import '../libraries/libraries_home_screen.dart';
import '../nav/nav_drawer.dart';
import 'catalog_browse_screen.dart';
import 'data/library_providers.dart';
import 'data/pins.dart';
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
      appBar: AppBar(
        // A tab root: the web's top bar puts the drawer's hamburger at exactly this spot, and
        // [NavMenuButton] falls back to the ordinary back button on a pushed screen.
        leading: const NavMenuButton(),
        title: Text(t(CommonKeys.navLibrary)),
      ),
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
              icon: PhosphorIcons.playlist(),
              label: t(LibraryKeys.sidebarPlaylists),
              trailing: _countOf(playlists, (rows) => rows.length),
              onTap: () => _push(context, const PlaylistsScreen()),
            ),
            _Entry(
              icon: PhosphorIcons.sparkle(),
              label: t(PlaylistsKeys.smartKindLabel),
              trailing: _countOf(smart, (rows) => rows.length),
              onTap: () => _push(context, const SmartPlaylistsScreen()),
            ),
            _Entry(
              icon: PhosphorIcons.heart(),
              label: t(LibraryKeys.likedTitle),
              onTap: () => _push(context, const LikedScreen()),
            ),
            _Entry(
              icon: PhosphorIcons.downloadSimple(),
              label: t(LibraryKeys.downloadsNavLabel),
              trailing: _countOf(downloads, (rows) => rows.length),
              onTap: () => _push(context, const DownloadsScreen()),
            ),
            _Entry(
              icon: PhosphorIcons.microphoneStage(),
              label: t(LibraryKeys.artistsTitle),
              onTap: () => _push(context, const ArtistsScreen()),
            ),
            _Entry(
              icon: PhosphorIcons.disc(),
              // Not "Albums": the Hub has no flat album browse, and this endpoint answers with at
              // most fifty. Naming the row for what it actually shows keeps the promise honest.
              label: t(DiscoveryKeys.shelfRecentlyAdded),
              onTap: () => _push(context, const RecentAlbumsScreen()),
            ),
            _Entry(
              icon: PhosphorIcons.folders(),
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
    return ListRow(
      leading: Icon(icon, size: 20, color: theme.colorScheme.primary),
      title: Text(label),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [if (trailing != null) Text(trailing!), listRowChevron],
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
            itemBuilder: (context, index) =>
                _PinTile(pin: rows[index], index: index, count: rows.length),
          ),
        ),
        const Divider(height: 24),
      ],
    );
  }
}

class _PinTile extends ConsumerWidget {
  const _PinTile({required this.pin, required this.index, required this.count});

  final PinnedItem pin;

  /// Where this pin sits on the shelf, and how long the shelf is — the two facts the reorder
  /// actions need. The Hub has no "move one pin" call, so a move is expressed as the whole shelf
  /// in a new order and the arithmetic has to happen where the positions are known.
  final int index;
  final int count;

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
        // The shelf's only editing surface. The web client reorders it by dragging in the sidebar
        // and unpins from each entity's own menu; neither gesture exists on a phone, so without
        // this a listener could fill the shelf and never change it again.
        onLongPress: () => unawaited(_edit(context, ref)),
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
                PinKind.album => PhosphorIconsFill.disc,
                PinKind.artist => PhosphorIconsFill.microphoneStage,
                PinKind.playlist => PhosphorIconsFill.playlist,
                PinKind.radio => PhosphorIconsFill.radio,
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

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final t = ref.read(translationsProvider).call;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListRow(
              title: Text(pin.name),
              subtitle: Text(t(LibraryKeys.sidebarPinned)),
            ),
            const Divider(height: 1),
            ListRow(
              leading: const Icon(PhosphorIconsRegular.arrowUp, size: 20),
              title: Text(t(CommonKeys.actionsMoveUp)),
              enabled: index > 0,
              onTap: () {
                Navigator.of(sheetContext).pop();
                unawaited(movePin(context, ref, from: index, to: index - 1));
              },
            ),
            ListRow(
              leading: const Icon(PhosphorIconsRegular.arrowDown, size: 20),
              title: Text(t(CommonKeys.actionsMoveDown)),
              enabled: index < count - 1,
              onTap: () {
                Navigator.of(sheetContext).pop();
                unawaited(movePin(context, ref, from: index, to: index + 1));
              },
            ),
            ListRow(
              leading: const Icon(PhosphorIconsFill.pushPin, size: 20),
              title: Text(t(CommonKeys.actionsUnpin)),
              onTap: () {
                Navigator.of(sheetContext).pop();
                unawaited(togglePin(context, ref, kind: pin.kind, id: pin.id));
              },
            ),
          ],
        ),
      ),
    );
  }
}
