import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/home/home_screen.dart';
import '../features/library/library_screen.dart';
import '../features/search/search_screen.dart';
import '../features/you/you_screen.dart';
import 'shell.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

/// The app's routes.
///
/// A `StatefulShellRoute` gives each tab its own navigation stack, so switching tabs and coming
/// back lands where you left — the behaviour people expect from a music app, where you browse an
/// artist, jump to search, and return.
GoRouter buildRouter() => GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: '/home',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => AppShell(shell: shell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/home',
              builder: (context, state) => const HomeScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/search',
              builder: (context, state) => const SearchScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/library',
              builder: (context, state) => const LibraryScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/you',
              builder: (context, state) => const YouScreen(),
            ),
          ],
        ),
      ],
    ),
  ],
);
