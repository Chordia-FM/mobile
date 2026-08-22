import 'package:go_router/go_router.dart';

import 'libraries_home_screen.dart';
import 'library_manage_screen.dart';
import 'overrides_screen.dart';
import 'pairing_wizard_screen.dart';

/// Managing the library servers this account can reach.
///
/// Relative paths, spread under a tab root, so the tab keeps its own back stack — the same reason
/// the catalog routes are declared this way.
List<RouteBase> librariesRoutes() => [
  GoRoute(
    path: 'libraries',
    builder: (context, state) => const LibrariesHomeScreen(),
    routes: [
      GoRoute(
        path: 'pair',
        builder: (context, state) => const PairingWizardScreen(),
      ),
      GoRoute(
        path: ':libraryId',
        builder: (context, state) => LibraryManageScreen(
          libraryId: state.pathParameters['libraryId']!,
          // Whether this account owns the library decides which controls the screen offers, and
          // the list that linked here already knows. Passed as a flag rather than re-derived so
          // the screen does not have to ask the directory again to draw its first frame; a deep
          // link with no extra falls back to the safer of the two.
          owned: (state.extra as bool?) ?? false,
        ),
        routes: [
          GoRoute(
            path: 'overrides',
            builder: (context, state) =>
                OverridesScreen(libraryId: state.pathParameters['libraryId']!),
          ),
        ],
      ),
    ],
  ),
];
