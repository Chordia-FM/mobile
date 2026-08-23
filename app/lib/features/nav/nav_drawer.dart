import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/art/art_cache.dart';
import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import '../../widgets/cover_art.dart';
import '../../widgets/tokens.dart';
import '../admin/admin_routes.dart';
import '../admin/data/admin_providers.dart';
import '../catalog/catalog_routes.dart';
import '../home/data/discovery_nav.dart';
import '../library/data/library_providers.dart';
import '../manager/manager_routes.dart';
import '../player/eq_screen.dart';
import '../settings/settings_routes.dart';
import '../social/social_routes.dart';
import 'account_menu.dart';

/// The phone's full navigation, ported from the web's `src/components/app/MobileNavDrawer.tsx`.
///
/// The web hosts `<Sidebar variant="drawer" />` in this sheet and a block of extra destinations
/// beside it, and the phone's tab bar is only four entries *because* of that — `MobileTabBar.tsx`
/// says so: "Everything the rail carries (pins, playlists, smart playlists, libraries, and their
/// context menus) lives in that drawer."
///
/// So it lives here too, in [_SidebarBlock]. It was left out once on the grounds that the Library
/// tab already holds the same things, which is true and is not the same claim: reaching a named
/// playlist from Home cost a tab switch, a list and three taps, where the web costs a hamburger and
/// a name. The one divergence from the web's layout is the ORDER — the web puts the sidebar above
/// its destination list and this puts it below, so the rows people already know stay where they
/// have always been.
///
/// One deliberate omission: the web's **keyboard shortcuts** entry. It opens a modal listing chords
/// a phone has no way to type, and this client has no keybind layer at all to open.
class NavDrawer extends ConsumerWidget {
  const NavDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    // "Not known yet" and "not an admin" both mean "show nothing", and they have to look identical:
    // an admin row that appears a beat late has already been offered to an ordinary listener.
    final admin = ref.watch(isAdminProvider).value == true;

    return Drawer(
      semanticLabel: t(CommonKeys.navMenu),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            // The web puts a close button exactly where the hamburger that opened the drawer was,
            // so the control the listener just pressed is the one that dismisses it. The avatar
            // opposite it is the web's top-bar `UserMenu`, which this client has no top bar of its
            // own to carry — see [NavAccountButton].
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: t(CommonKeys.navCloseMenu),
                    onPressed: () => _close(context),
                  ),
                  const Spacer(),
                  const NavAccountButton(),
                ],
              ),
            ),
            NavDrawerRow(
              icon: Icons.speed_outlined,
              label: t(ManagerKeys.nav),
              onSelected: (context) => context.goToManager(),
            ),
            const Divider(indent: 16, endIndent: 16),
            NavDrawerRow(
              icon: Icons.people_outline,
              label: t(CommonKeys.navFriends),
              onSelected: (context) => context.goToFriends(),
            ),
            NavDrawerRow(
              icon: Icons.folder_copy_outlined,
              label: t(CommonKeys.navAllLibraries),
              onSelected: (context) => _pushInTab(context, 'libraries'),
            ),
            NavDrawerRow(
              icon: Icons.music_note_outlined,
              label: t(CatalogKeys.genresTitle),
              onSelected: (context) => context.goToGenres(),
            ),
            NavDrawerRow(
              icon: Icons.label_outline,
              label: t(CatalogKeys.labelsTitle),
              onSelected: (context) => context.goToLabels(),
            ),
            NavDrawerRow(
              icon: Icons.equalizer,
              label: t(SettingsKeys.equalizerTitle),
              // Not a route on this client: the equalizer opens over everything, the way the full
              // player does, so it is reachable from whatever is playing rather than from one tab.
              onSelected: openEqualizer,
            ),
            NavDrawerRow(
              icon: Icons.settings_outlined,
              label: t(CommonKeys.navSettings),
              onSelected: (context) => context.goToSettings(),
            ),
            if (admin)
              NavDrawerRow(
                icon: Icons.shield_outlined,
                label: t(AdminKeys.title),
                onSelected: (context) => context.goToAdmin(),
              ),
            const _SidebarBlock(),
          ],
        ),
      ),
    );
  }
}

/// The web's `<Sidebar variant="drawer" />`: the listener's own things, one tap from every page.
///
/// Everything here is READ, never blocking: each list paints when it arrives and is simply absent
/// until then. A drawer that waits for five requests before it can be used is a drawer nobody opens
/// twice, and none of these sections mean anything as a spinner.
class _SidebarBlock extends ConsumerWidget {
  const _SidebarBlock();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final pins = ref.watch(pinsProvider).value ?? const <PinnedItem>[];
    final smart = ref.watch(smartPlaylistsProvider).value ?? const [];
    final playlists = ref.watch(playlistsProvider).value ?? const <Playlist>[];
    final libraries = ref.watch(myLibrariesProvider).value ?? const [];
    final shared = ref.watch(sharedLibrariesProvider).value ?? const [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(indent: 16, endIndent: 16),
        // The web's system rows. Search is one too, but on this client it is a tab.
        NavDrawerRow(
          icon: Icons.favorite_outline,
          label: t(LibraryKeys.likedSongs),
          onSelected: (context) => _pushInTab(context, 'liked'),
        ),
        NavDrawerRow(
          icon: Icons.download_outlined,
          label: t(LibraryKeys.downloadsNavLabel),
          onSelected: (context) => _pushInTab(context, 'downloads'),
        ),
        if (pins.isNotEmpty) ...[
          _SidebarHeading(label: t(LibraryKeys.sidebarPinned)),
          for (final pin in pins)
            NavDrawerEntityRow(
              name: pin.name,
              imageUrl: pin.imageUrl,
              round: pin.kind == PinKind.artist || pin.kind == PinKind.radio,
              fallbackIcon: switch (pin.kind) {
                PinKind.album => Icons.album_rounded,
                PinKind.artist => Icons.person_rounded,
                PinKind.playlist => Icons.queue_music_rounded,
                PinKind.radio => Icons.radio_rounded,
              },
              onSelected: (context) => switch (pin.kind) {
                PinKind.album => context.goToAlbum(pin.id),
                PinKind.artist => context.goToArtist(pin.id),
                PinKind.playlist => context.goToPlaylist(pin.id),
                PinKind.radio => context.goToArtistRadio(pin.id),
              },
            ),
        ],
        if (smart.isNotEmpty || playlists.isNotEmpty) ...[
          _SidebarHeading(label: t(LibraryKeys.sidebarPlaylists)),
          // Smart first, then hand-built — the web's order. A smart playlist wears the same
          // artwork and the same row as a hand-built one there, because it IS a playlist, one that
          // maintains itself.
          for (final playlist in smart)
            NavDrawerEntityRow(
              name: playlist.name,
              imageUrl: playlist.coverUrl,
              fallbackIcon: Icons.auto_awesome_rounded,
              onSelected: (context) =>
                  _pushInTab(context, 'smart/${playlist.id}'),
            ),
          for (final playlist in playlists)
            NavDrawerEntityRow(
              name: playlist.name,
              imageUrl: playlist.coverUrl,
              fallbackIcon: Icons.queue_music_rounded,
              onSelected: (context) => context.goToPlaylist(playlist.id),
            ),
        ],
        if (libraries.isNotEmpty) ...[
          _SidebarHeading(label: t(LibraryKeys.sidebarYourLibrary)),
          for (final library in libraries)
            _LibraryRow(library: library, owned: true),
        ],
        // Under its own heading rather than mixed in above: these are somebody else's, and the
        // distinction decides what you can do with them. Omitted entirely when nobody has shared
        // anything, so an account that has never been granted access never sees a section asking
        // about it.
        if (shared.isNotEmpty) ...[
          _SidebarHeading(label: t(LibraryKeys.sidebarSharedWithYou)),
          for (final library in shared)
            _LibraryRow(library: library, owned: false),
        ],
      ],
    );
  }
}

/// A library row: the web sends it to the library's MUSIC, with managing one level in from there.
class _LibraryRow extends StatelessWidget {
  const _LibraryRow({required this.library, required this.owned});

  final LibrarySummary library;
  final bool owned;

  @override
  Widget build(BuildContext context) => NavDrawerRow(
    icon: Icons.dns_outlined,
    label: library.name,
    // `owned` rides in `extra` rather than being re-derived: the row that linked here already
    // knows, and the screen would otherwise have to ask the directory again to draw its first
    // frame. See `nav_routes.dart`.
    onSelected: (context) =>
        _pushInTab(context, 'library/${library.id}', extra: owned),
  );
}

/// A section label inside the sidebar block — the web's `text-xs uppercase tracking-wide`.
class _SidebarHeading extends StatelessWidget {
  const _SidebarHeading({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
    child: Text(
      label.toUpperCase(),
      style: ChordiaType.xs.copyWith(
        fontWeight: ChordiaType.semibold,
        letterSpacing: 0.8,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

/// One destination in [NavDrawer].
///
/// Dismisses the drawer before navigating, for the reason the web's version does: a drawer left
/// standing sits over the page the listener just asked for.
@visibleForTesting
class NavDrawerRow extends StatelessWidget {
  const NavDrawerRow({
    required this.icon,
    required this.label,
    required this.onSelected,
    super.key,
  });

  final IconData icon;
  final String label;
  final void Function(BuildContext context) onSelected;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon),
    title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    onTap: () {
      _close(context);
      onSelected(context);
    },
  );
}

/// One of the listener's own things in [NavDrawer]: artwork and a name.
///
/// Its own widget rather than a [NavDrawerRow] with a picture, so the drawer's list of DESTINATIONS
/// and its list of CONTENT stay separable — a test can assert the first is exactly the web's without
/// the second, which is somebody's own library, walking into the assertion.
@visibleForTesting
class NavDrawerEntityRow extends StatelessWidget {
  const NavDrawerEntityRow({
    required this.name,
    required this.onSelected,
    super.key,
    this.imageUrl,
    this.round = false,
    this.fallbackIcon = Icons.album_rounded,
  });

  final String name;
  final String? imageUrl;

  /// Circular artwork for the kinds that stand for a person or a station.
  final bool round;
  final IconData fallbackIcon;
  final void Function(BuildContext context) onSelected;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: CoverArt(
      sha256: artHashOf(imageUrl),
      // The web's sidebar rows are `size-9`.
      size: 36,
      shape: round ? BoxShape.circle : BoxShape.rectangle,
      fallbackIcon: fallbackIcon,
      fallbackInitial: round ? name : null,
      semanticLabel: name,
    ),
    title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
    onTap: () {
      _close(context);
      onSelected(context);
    },
  );
}

void _close(BuildContext context) => Scaffold.maybeOf(context)?.closeDrawer();

/// Pushes onto the CURRENT tab's stack, which is what every navigation extension in this app does:
/// the first path segment is the tab, and a destination that ignored it would either miss the route
/// table or throw the listener into a different tab mid-flow.
void _pushInTab(BuildContext context, String suffix, {Object? extra}) {
  final segments = GoRouterState.of(context).uri.pathSegments;
  if (segments.isEmpty) return;
  GoRouter.of(context).push('/${segments.first}/$suffix', extra: extra);
}

/// Hands the shell's drawer to anything under it, so a screen with an `AppBar` of its own can open
/// the same drawer the shell owns.
///
/// An `InheritedWidget` rather than a global key: the shell can be built more than once (a test
/// pumps one, a hot restart makes another), and a `GlobalKey` shared between two of them is a
/// framework error rather than a bug you get to see.
class NavDrawerScope extends InheritedWidget {
  const NavDrawerScope({required this.open, required super.child, super.key});

  /// Opens the shell's navigation drawer.
  final VoidCallback open;

  static VoidCallback? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<NavDrawerScope>()?.open;

  @override
  bool updateShouldNotify(NavDrawerScope oldWidget) => open != oldWidget.open;
}

/// The hamburger the web puts at the left of its top bar, as an `AppBar` leading.
///
/// Safe to drop into any screen's `AppBar` unconditionally: on a pushed screen there is something
/// to go back to, so it is the back button the framework would have supplied anyway; only at a tab
/// root does it become the menu.
class NavMenuButton extends ConsumerWidget {
  const NavMenuButton({super.key, this.alwaysMenu = false});

  /// Never fall back to a back button. Set by the shell's own bar, which sits outside every tab's
  /// navigator: what it can pop is not what the listener is looking at.
  final bool alwaysMenu;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!alwaysMenu && Navigator.of(context).canPop()) {
      return const BackButton();
    }
    final open = NavDrawerScope.maybeOf(context);
    if (open == null) return const SizedBox.shrink();
    return IconButton(
      icon: const Icon(Icons.menu),
      tooltip: ref.t(CommonKeys.navOpenMenu),
      onPressed: open,
    );
  }
}
