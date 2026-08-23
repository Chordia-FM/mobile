import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'admin_screen.dart';
import 'admin_user_detail_screen.dart';

/// The admin screens, as sub-routes of a tab's root.
///
/// RELATIVE, exactly like the catalog's and the Manager's: each tab in the shell keeps its own
/// navigation stack, so Admin opened from the You tab has to live under `/you`.
///
/// The routes exist for every signed-in account — [AdminScreen] does the gating, and it does it
/// from the Hub's own answer rather than from whether a route was registered. A router that only
/// knows admin paths for admins would send a demoted account to a 404 instead of to "you don't
/// have access", and would leak the shape of the section through its own routing table.
///
/// WIRING: spread this into the `routes:` of a branch's root `GoRoute` in `app/router.dart`:
///
/// ```dart
/// GoRoute(path: '/you', builder: ..., routes: [...settingsRoutes(), ...adminRoutes()])
/// ```
List<RouteBase> adminRoutes() => [
  GoRoute(
    path: 'admin',
    builder: (context, state) => const AdminScreen(),
    routes: [
      GoRoute(
        path: 'users/:userId',
        builder: (context, state) =>
            AdminUserDetailScreen(userId: state.pathParameters['userId']!),
      ),
    ],
  ),
];

/// Opening an admin screen from anywhere, without the caller knowing which tab it is in.
extension AdminNavigation on BuildContext {
  void goToAdmin() => _pushInTab('admin');

  void goToAdminUser(String userId) => _pushInTab('admin/users/$userId');

  void _pushInTab(String suffix) {
    final segments = GoRouterState.of(this).uri.pathSegments;
    if (segments.isEmpty) return;
    GoRouter.of(this).push('/${segments.first}/$suffix');
  }
}
