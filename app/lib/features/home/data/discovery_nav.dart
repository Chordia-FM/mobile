import 'package:chordia_api/chordia_api.dart' show StationKind;
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../library/playlist_detail_screen.dart';
import '../see_all_screens.dart';
import '../station_screen.dart';
import 'station.dart';

/// The destinations discovery links to that the catalog does not own.
///
/// Routes and links are declared in the same file on purpose. Every path below is built by hand
/// from a string, so the only thing standing between "the card navigates" and "the card lands on
/// GoRouter's error page" is that these two halves agree — and they cannot drift while they sit
/// next to each other. They did drift once: every "Made for you" card and every radio pin pushed
/// `radio/...` against a router that had never heard of it.
///
/// RELATIVE paths, like the catalog's: each tab in the shell keeps its own navigation stack, so a
/// station opened from Search has to live under `/search` and one opened from Home under `/home`.
///
/// WIRING: spread into the `routes:` of each branch's root `GoRoute` in `app/router.dart`.
List<RouteBase> discoveryRoutes() => [
  GoRoute(
    path: 'radio/:kind/:seedId',
    // `:kind` arrives as an arbitrary string. Validated here rather than cast, because
    // `StationKind.fromWire` falls back to `artist` for anything it does not know — right for a
    // payload from a newer server, wrong for a typo'd link, where it would send the Hub looking
    // for an artist under a genre's slug.
    redirect: (context, state) =>
        stationKindFromSegment(state.pathParameters['kind'] ?? '') == null
        ? '/home'
        : null,
    builder: (context, state) => StationScreen(
      kind: stationKindFromSegment(state.pathParameters['kind']!)!,
      seedId: state.pathParameters['seedId']!,
    ),
  ),
  GoRoute(
    // A mix is its own destination, not the station its seed would generate — see [DailyMixScreen].
    // The web spells this route the same way (`/app/daily-mix/{mixId}`), which is what lets a
    // shared link resolve here.
    path: 'daily-mix/:mixId',
    builder: (context, state) =>
        DailyMixScreen(mixId: state.pathParameters['mixId']!),
  ),
  GoRoute(
    path: 'jump-back-in',
    builder: (context, state) => const JumpBackInScreen(),
  ),
  GoRoute(
    path: 'made-for-you',
    builder: (context, state) => const MadeForYouScreen(),
  ),
  GoRoute(
    path: 'playlists/:playlistId',
    builder: (context, state) =>
        PlaylistDetailScreen(playlistId: state.pathParameters['playlistId']!),
  ),
];

/// Opening one of those destinations from anywhere, without the caller knowing which tab it is in.
///
/// Same rule as `CatalogNavigation` in `features/catalog/catalog_routes.dart`, and deliberately the
/// same shape: the path is built from the CURRENT location's first segment, because that segment is
/// the tab. A playlist opened from Search has to live under `/search` and one opened from Home
/// under `/home`, or opening it throws the user into another tab and loses the stack they were in.
extension DiscoveryNavigation on BuildContext {
  void goToPlaylist(String playlistId) => _pushInTab('playlists/$playlistId');

  /// One daily mix. The id is its seed artist's, which is the mix's stable identity Hub-side —
  /// the same parameter the web's `/app/daily-mix/$mixId` carries.
  void goToDailyMix(String mixId) => _pushInTab('daily-mix/$mixId');

  /// The full "Jump back in" list, behind the hero's "See all".
  void goToJumpBackIn() => _pushInTab('jump-back-in');

  /// The full "Made for you" list, behind that rail's "See all".
  void goToMadeForYou() => _pushInTab('made-for-you');

  /// A station seeded by any entity. The seed kind travels in the path because the Hub builds a
  /// station from any of five kinds, and only the kind says how to read the id.
  void goToStation(StationKind kind, String seed) =>
      _pushInTab('radio/${kind.wire}/${Uri.encodeComponent(seed)}');

  /// An artist-seeded station — a daily mix, a radio pin, an artist's own radio.
  void goToArtistRadio(String seedArtistId) =>
      goToStation(StationKind.artist, seedArtistId);

  void _pushInTab(String suffix) {
    final segments = GoRouterState.of(this).uri.pathSegments;
    // Only "/" has no segments, and the router redirects away from it before any of these screens
    // exists to push from.
    if (segments.isEmpty) return;
    GoRouter.of(this).push('/${segments.first}/$suffix');
  }
}
