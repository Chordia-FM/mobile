import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import '../admin/admin_routes.dart';
import '../admin/data/admin_providers.dart';
import '../catalog/catalog_routes.dart';
import '../manager/manager_routes.dart';
import '../player/eq_screen.dart';
import '../settings/settings_routes.dart';
import '../social/social_routes.dart';

/// The phone's full navigation, ported from the web's `src/components/app/MobileNavDrawer.tsx`.
///
/// The web hosts `<Sidebar variant="drawer" />` at the top of this sheet and a block of extra
/// destinations below a rule. Everything in that sidebar block — pins, playlists, smart playlists,
/// liked, downloads, libraries — is already the Library tab on this client, so the only sidebar row
/// with nowhere else to live is the Manager, which sits above the rule where the web puts it.
/// Below the rule is the web's list, in the web's order, with the web's labels.
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
            // so the control the listener just pressed is the one that dismisses it.
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: t(CommonKeys.navCloseMenu),
                  onPressed: () => _close(context),
                ),
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
          ],
        ),
      ),
    );
  }
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

void _close(BuildContext context) => Scaffold.maybeOf(context)?.closeDrawer();

/// Pushes onto the CURRENT tab's stack, which is what every navigation extension in this app does:
/// the first path segment is the tab, and a destination that ignored it would either miss the route
/// table or throw the listener into a different tab mid-flow.
void _pushInTab(BuildContext context, String suffix) {
  final segments = GoRouterState.of(context).uri.pathSegments;
  if (segments.isEmpty) return;
  GoRouter.of(context).push('/${segments.first}/$suffix');
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
