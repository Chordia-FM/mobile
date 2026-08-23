import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// The destinations discovery links to that the catalog does not own.
///
/// Same rule as `CatalogNavigation` in `features/catalog/catalog_routes.dart`, and deliberately the
/// same shape: the path is built from the CURRENT location's first segment, because that segment is
/// the tab. A playlist opened from Search has to live under `/search` and one opened from Home
/// under `/home`, or opening it throws the user into another tab and loses the stack they were in.
extension DiscoveryNavigation on BuildContext {
  void goToPlaylist(String playlistId) => _pushInTab('playlists/$playlistId');

  /// An artist-seeded station. The seed kind travels in the path because the Hub builds a station
  /// from any entity, and only the kind says how to read the id.
  void goToArtistRadio(String seedArtistId) =>
      _pushInTab('radio/artist/$seedArtistId');

  void goToProfile(String handle) =>
      _pushInTab('u/${Uri.encodeComponent(handle)}');

  void _pushInTab(String suffix) {
    final segments = GoRouterState.of(this).uri.pathSegments;
    // Only "/" has no segments, and the router redirects away from it before any of these screens
    // exists to push from.
    if (segments.isEmpty) return;
    GoRouter.of(this).push('/${segments.first}/$suffix');
  }
}
