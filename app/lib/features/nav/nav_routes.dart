import 'package:go_router/go_router.dart';

import '../library/downloads_screen.dart';
import '../library/liked_screen.dart';
import '../library/library_detail_screen.dart';
import '../library/smart_playlist_screen.dart';

/// The collections the nav drawer reaches that had no route of their own.
///
/// They existed as screens and were pushed imperatively from the Library tab, which is fine from
/// inside that tab and impossible from the drawer: the drawer is built by the SHELL's `Scaffold`,
/// above every branch navigator, so a `Navigator.push` from it would raise the screen over the tab
/// bar and the player rather than into the tab the listener is standing in. A route is what the
/// drawer can push, so these are the drawer's half of the web sidebar made addressable.
///
/// Relative paths, spread under every tab root, for the reason the catalog's are: the drawer opens
/// over whichever tab is showing and pushes onto that tab's own stack.
///
/// The paths are the web's, minus its `/app` prefix — `liked`, `downloads`, `smart/{id}`,
/// `library/{id}` — so a link copied from the web client resolves here too (see the App Link
/// rewrite in `app/router.dart`).
List<RouteBase> navRoutes() => [
  GoRoute(path: 'liked', builder: (context, state) => const LikedScreen()),
  GoRoute(
    path: 'downloads',
    builder: (context, state) => const DownloadsScreen(),
  ),
  GoRoute(
    path: 'smart/:smartId',
    builder: (context, state) =>
        SmartPlaylistScreen(playlistId: state.pathParameters['smartId']!),
  ),
  GoRoute(
    // The library's MUSIC, which is what a library row means everywhere else in this app and on the
    // web ("the web client's library card links to `/app/library/{id}` — its artists — with editing
    // one level in from there"). The plural `libraries/{id}` is the management screen; that split
    // is the web's, not an accident of naming.
    path: 'library/:libraryId',
    builder: (context, state) => LibraryDetailScreen(
      libraryId: state.pathParameters['libraryId']!,
      // Whether this account owns it decides which controls the screen offers, and the row that
      // linked here already knows. A deep link carries no extra and falls back to the safer of the
      // two, exactly as `librariesRoutes()` does.
      owned: (state.extra as bool?) ?? false,
    ),
  ),
];
