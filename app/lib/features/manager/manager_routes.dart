import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'artist_coverage_screen.dart';
import 'discover_artist_screen.dart';
import 'manager_screen.dart';
import 'release_group_screen.dart';

/// The Manager screens, as sub-routes of a tab's root.
///
/// RELATIVE, for the same reason the catalog's routes are: each tab in the shell keeps its own
/// navigation stack, so the Manager opened from the You tab has to live under `/you`. An absolute
/// path would pin it to exactly one tab and collapse the others to their roots whenever anybody
/// opened it.
///
/// The nesting under `manager/` is what keeps `manager/artists/:artistId` (coverage for an owned
/// artist) distinct from the catalog's own `artists/:artistId` at the tab root — the same artist,
/// two different questions.
///
/// WIRING: spread this into the `routes:` of a branch's root `GoRoute` in `app/router.dart`:
///
/// ```dart
/// GoRoute(path: '/you', builder: ..., routes: [...settingsRoutes(), ...managerRoutes()])
/// ```
List<RouteBase> managerRoutes() => [
  GoRoute(
    path: 'manager',
    // `?q=` seeds a Discover search, exactly as the web's `/app/manager/discover?q=` does. A query
    // rather than a path segment for the reason the web gives: the page IS a live search box, and
    // this fills it in rather than replacing it.
    builder: (context, state) =>
        ManagerScreen(query: state.uri.queryParameters['q']),
    routes: [
      GoRoute(
        path: 'artists/:artistId',
        builder: (context, state) =>
            ArtistCoverageScreen(artistId: state.pathParameters['artistId']!),
      ),
      GoRoute(
        path: 'discover/artists/:mbid',
        builder: (context, state) =>
            DiscoverArtistScreen(artistMbid: state.pathParameters['mbid']!),
      ),
      GoRoute(
        path: 'releases/:mbid',
        builder: (context, state) =>
            ReleaseGroupScreen(releaseGroupMbid: state.pathParameters['mbid']!),
      ),
    ],
  ),
];

/// Opening a Manager screen from anywhere, without the caller knowing which tab it is in.
extension ManagerNavigation on BuildContext {
  void goToManager() => _pushInTab('manager');

  /// What MusicBrainz says one owned artist released, against what is in the library.
  void goToArtistCoverage(String artistId) =>
      _pushInTab('manager/artists/$artistId');

  /// A name search in Discover, for the entities with no MusicBrainz id to aim at.
  ///
  /// The route an "Open in Discover" on a TRACK takes: tracks carry no MBID on the wire, so the
  /// name is all there is to look one up by.
  void goToDiscoverSearch(String term) =>
      _pushInTab('manager?q=${Uri.encodeQueryComponent(term)}');

  /// A discovered artist — not necessarily one the caller owns anything by.
  void goToDiscoverArtist(String artistMbid) =>
      _pushInTab('manager/discover/artists/${Uri.encodeComponent(artistMbid)}');

  /// Per-edition track coverage, keyed by release-group MBID.
  void goToReleaseGroup(String releaseGroupMbid) =>
      _pushInTab('manager/releases/${Uri.encodeComponent(releaseGroupMbid)}');

  void _pushInTab(String suffix) {
    // The destination is built from the CURRENT location's first segment, because that segment is
    // the tab: pushing `/manager` from the You tab would miss the route table entirely.
    final segments = GoRouterState.of(this).uri.pathSegments;
    if (segments.isEmpty) return;
    GoRouter.of(this).push('/${segments.first}/$suffix');
  }
}
