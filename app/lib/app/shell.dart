import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/nav/mobile_tab_bar.dart';
import '../features/nav/nav_drawer.dart';
import '../features/nav/nav_tabs.dart';
import '../features/player/mini_player.dart';

/// The persistent frame: tab bar at the bottom, mini-player docked above it, tab content above
/// that. The player survives tab switches because it lives in the shell, not in any branch.
///
/// The tabs are the web's four ([NavTab]), and the menu behind [NavDrawer] is the web's drawer.
/// Together they are the whole of `MobileTabBar.tsx` + `MobileNavDrawer.tsx` + the top bar's
/// hamburger, which is the only navigation model this product has.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({required this.shell, super.key});

  final StatefulNavigationShell shell;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  final _scaffold = GlobalKey<ScaffoldState>();

  /// A method rather than a closure built in `build`, so the callback handed to [NavDrawerScope] is
  /// the same object every frame and the scope does not notify every descendant on each paint.
  void _openDrawer() => _scaffold.currentState?.openDrawer();

  @override
  Widget build(BuildContext context) {
    final tab = NavTab.values[widget.shell.currentIndex];
    // A tab root is a one-segment location: `/home`, not `/home/albums/x`. Anything deeper is a
    // screen the tab pushed, and those bring their own bar with a back button.
    final atRoot = GoRouterState.of(context).uri.pathSegments.length == 1;

    return NavDrawerScope(
      open: _openDrawer,
      child: Scaffold(
        key: _scaffold,
        drawer: const NavDrawer(),
        // The menu row the web keeps in its top bar, supplied only where the tab's root screen has
        // no bar of its own to put [NavMenuButton] in. See [NavTab.rootHasAppBar].
        appBar: tab.rootHasAppBar || !atRoot
            ? null
            : AppBar(
                toolbarHeight: 48,
                leading: const NavMenuButton(alwaysMenu: true),
                backgroundColor: Colors.transparent,
                scrolledUnderElevation: 0,
              ),
        body: widget.shell,
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const MiniPlayer(),
            MobileTabBar(
              currentIndex: widget.shell.currentIndex,
              onSelected: (index) => widget.shell.goBranch(
                index,
                // Tapping the tab you are already on pops that tab back to its root.
                initialLocation: index == widget.shell.currentIndex,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
