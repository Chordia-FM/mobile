import 'package:flutter/material.dart';

import '../../i18n/keys.g.dart';

/// The phone's primary navigation, ported one-for-one from the web client's
/// `src/components/app/MobileTabBar.tsx`.
///
/// Four destinations, in the web's order, with the web's labels: Home, Search, Library, Insights.
/// There is no "You" tab and no "More" entry — the web has neither. Everything that is *about you*
/// is the Insights tab (which is your profile, see `insights_tab.dart`), and everything the desktop
/// rail carries lives in the drawer behind the menu button (`nav_drawer.dart`).
///
/// The order here IS the branch order in `app/router.dart`: `StatefulNavigationShell.currentIndex`
/// indexes straight into [values].
enum NavTab {
  home(
    path: '/home',
    labelKey: CommonKeys.navHome,
    icon: Icons.home_outlined,
    selectedIcon: Icons.home,
    rootHasAppBar: false,
  ),
  search(
    path: '/search',
    labelKey: CommonKeys.navSearch,
    icon: Icons.search_outlined,
    selectedIcon: Icons.search,
    rootHasAppBar: false,
  ),
  library(
    path: '/library',
    labelKey: CommonKeys.navLibrary,
    icon: Icons.library_music_outlined,
    selectedIcon: Icons.library_music,
    rootHasAppBar: true,
  ),

  /// The web's `ChartLineUpIcon` entry. It points at `/app/insights`, which redirects to the
  /// signed-in listener's own profile; this one lands there directly.
  insights(
    path: '/insights',
    labelKey: CommonKeys.navInsights,
    icon: Icons.insights_outlined,
    selectedIcon: Icons.insights,
    rootHasAppBar: true,
  );

  const NavTab({
    required this.path,
    required this.labelKey,
    required this.icon,
    required this.selectedIcon,
    required this.rootHasAppBar,
  });

  /// The branch's root location. Absolute, because it is a tab; everything under it is relative so
  /// the tab keeps its own stack.
  final String path;

  final String labelKey;
  final IconData icon;
  final IconData selectedIcon;

  /// Whether this tab's root screen draws an `AppBar` of its own.
  ///
  /// The web has ONE top bar for the whole app and pages carry no bar, so the hamburger has one
  /// home. This app's screens each own their chrome and two of the four roots draw a bar, so the
  /// shell supplies the menu row only for the roots that do not — stacking a shell bar on top of a
  /// screen's own bar is two bars saying one thing. The roots that do draw one put
  /// [NavMenuButton] in its leading slot instead, which is the same place: top-left.
  final bool rootHasAppBar;
}
