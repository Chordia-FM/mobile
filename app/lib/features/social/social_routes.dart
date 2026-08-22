import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'friends_screen.dart';
import 'profile_screen.dart';

/// The social screens, as sub-routes of a tab's root.
///
/// RELATIVE paths, for the reason the catalog's routes are: each tab in the shell keeps its own
/// navigation stack, so a profile opened from Search has to live under `/search` and the same
/// profile opened from You under `/you`. An absolute path would put these screens in exactly one
/// tab and collapse the other three to their roots whenever anybody opened a profile.
///
/// `u/:handle` mirrors the web client's `/app/u/{handle}`, so a link copied on one client is a
/// route this one already knows how to open.
///
/// WIRING: spread this into the `routes:` of each branch's root `GoRoute` in `app/router.dart`:
///
/// ```dart
/// GoRoute(path: '/you', builder: ..., routes: [...socialRoutes(), ...insightsRoutes()])
/// ```
List<RouteBase> socialRoutes() => [
  GoRoute(path: 'friends', builder: (context, state) => const FriendsScreen()),
  GoRoute(
    path: 'u/:handle',
    builder: (context, state) =>
        ProfileScreen(handle: state.pathParameters['handle']!),
  ),
];

/// Opening a social screen from anywhere, without the caller knowing which tab it is in.
extension SocialNavigation on BuildContext {
  void goToFriends() => _pushInTab('friends');

  void goToProfile(String handle) =>
      _pushInTab('u/${Uri.encodeComponent(handle)}');

  void _pushInTab(String suffix) {
    // The destination is built from the CURRENT location's first segment, because that segment is
    // the tab: pushing `/friends` from the You tab would miss the route table entirely.
    final segments = GoRouterState.of(this).uri.pathSegments;
    if (segments.isEmpty) return;
    GoRouter.of(this).push('/${segments.first}/$suffix');
  }
}
