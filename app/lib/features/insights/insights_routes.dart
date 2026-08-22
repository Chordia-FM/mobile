import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'insights_screen.dart';

/// The viewer's own listening report, as a sub-route of a tab's root.
///
/// RELATIVE, for the reason the catalog's and settings' routes are: each tab in the shell keeps its
/// own navigation stack, so Insights opened from the You tab has to live under `/you`. An absolute
/// path would put it in exactly one tab and collapse the others to their roots.
///
/// Somebody else's report is not a route of its own — it is a tab on their profile, which is
/// `u/:handle` in `features/social/social_routes.dart`, the same shape the web client uses.
///
/// WIRING: spread this into the `routes:` of a branch's root `GoRoute` in `app/router.dart`:
///
/// ```dart
/// GoRoute(path: '/you', builder: ..., routes: [...socialRoutes(), ...insightsRoutes()])
/// ```
List<RouteBase> insightsRoutes() => [
  GoRoute(
    path: 'insights',
    builder: (context, state) => const InsightsScreen(),
  ),
];

/// Opening Insights from anywhere, without the caller knowing which tab it is in.
extension InsightsNavigation on BuildContext {
  void goToInsights() {
    final segments = GoRouterState.of(this).uri.pathSegments;
    if (segments.isEmpty) return;
    GoRouter.of(this).push('/${segments.first}/insights');
  }
}
