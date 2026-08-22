import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'settings_screen.dart';

/// Settings, as a sub-route of a tab's root.
///
/// RELATIVE, for the same reason the catalog's routes are: each tab in the shell keeps its own
/// navigation stack, so Settings opened from the You tab has to live under `/you`. An absolute
/// path would put it in exactly one tab and collapse the others to their roots whenever anybody
/// opened it.
///
/// Only the index is a route. The eight pages under it are pushed onto the tab's navigator with
/// plain constructor arguments (see `openSettingsScreen`), which is how every other stack in this
/// app is built — and means wiring Settings up is one line rather than nine.
///
/// WIRING: spread this into the `routes:` of a branch's root `GoRoute` in `app/router.dart`:
///
/// ```dart
/// GoRoute(path: '/you', builder: ..., routes: settingsRoutes())
/// ```
List<RouteBase> settingsRoutes() => [
  GoRoute(
    path: 'settings',
    builder: (context, state) => const SettingsScreen(),
  ),
];

/// Opening Settings from anywhere, without the caller knowing which tab it is in.
extension SettingsNavigation on BuildContext {
  void goToSettings() {
    // The destination is built from the CURRENT location's first segment, because that segment is
    // the tab: pushing `/settings` from the You tab would miss the route table entirely.
    final segments = GoRouterState.of(this).uri.pathSegments;
    if (segments.isEmpty) return;
    GoRouter.of(this).push('/${segments.first}/settings');
  }
}
