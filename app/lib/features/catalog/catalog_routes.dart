import 'package:chordia_api/chordia_api.dart' show EntityKind;
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../insights/entity_stats_screen.dart';
import 'album_screen.dart';
import 'artist_discography_screen.dart';
import 'artist_screen.dart';
import 'genre_screen.dart';
import 'genres_screen.dart';
import 'label_screen.dart';
import 'labels_screen.dart';
import 'track_screen.dart';

/// The catalog screens, as sub-routes of a tab's root.
///
/// RELATIVE paths, and that is the whole design. Each tab in the shell keeps its own navigation
/// stack, so an artist opened from Search has to live under `/search` and an artist opened from
/// Home under `/home` — the same screens, reachable from every tab, each stack remembering where it
/// was. Absolute paths would put the catalog in exactly one tab and collapse the other three back
/// to their roots the moment anyone opened an album.
///
/// WIRING: spread this into the `routes:` of each branch's root `GoRoute` in `app/router.dart`:
///
/// ```dart
/// GoRoute(path: '/home', builder: ..., routes: catalogRoutes())
/// ```
List<RouteBase> catalogRoutes() => [
  GoRoute(
    path: 'artists/:artistId',
    builder: (context, state) =>
        ArtistScreen(artistId: state.pathParameters['artistId']!),
    routes: [
      GoRoute(
        path: 'discography',
        builder: (context, state) => ArtistDiscographyScreen(
          artistId: state.pathParameters['artistId']!,
        ),
      ),
      _stats(EntityKind.artist, 'artistId'),
    ],
  ),
  GoRoute(
    path: 'albums/:albumId',
    builder: (context, state) =>
        AlbumScreen(albumId: state.pathParameters['albumId']!),
    routes: [_stats(EntityKind.album, 'albumId')],
  ),
  GoRoute(
    path: 'tracks/:trackId',
    builder: (context, state) =>
        TrackScreen(trackId: state.pathParameters['trackId']!),
    routes: [_stats(EntityKind.track, 'trackId')],
  ),
  GoRoute(
    path: 'genres',
    builder: (context, state) => const GenresScreen(),
    routes: [
      GoRoute(
        path: ':slug',
        builder: (context, state) =>
            GenreScreen(slug: state.pathParameters['slug']!),
      ),
    ],
  ),
  GoRoute(
    path: 'labels',
    builder: (context, state) => const LabelsScreen(),
    routes: [
      GoRoute(
        path: ':labelId',
        builder: (context, state) =>
            LabelScreen(labelId: state.pathParameters['labelId']!),
      ),
    ],
  ),
];

/// `{entity}/{id}/stats` — one entity's listening figures, at the web's own path.
///
/// The screen has existed for a while and had exactly one way in: a row inside Insights > Charts.
/// The web reaches it from the album and artist context menus and from the "On this day" rail, and
/// those menus live in `features/catalog/widgets/entity_actions.dart` — so this registers the
/// destination and a shared `/app/albums/{id}/stats` link now lands on it, while the menu entries
/// are still owed.
GoRoute _stats(EntityKind kind, String parameter) => GoRoute(
  path: 'stats',
  builder: (context, state) =>
      EntityStatsScreen(kind: kind, id: state.pathParameters[parameter]!),
);

/// Opening one catalog entity from another, without either knowing which tab it is in.
///
/// The destination is built from the CURRENT location's first segment, because that segment is the
/// tab: pushing `/artists/x` from the search tab would either miss the route table or, worse, jump
/// the user to a different tab mid-flow. Reading it back is what keeps every one of these screens
/// tab-agnostic.
extension CatalogNavigation on BuildContext {
  void goToArtist(String artistId) => _pushInTab('artists/$artistId');

  void goToArtistDiscography(String artistId) =>
      _pushInTab('artists/$artistId/discography');

  void goToAlbum(String albumId) => _pushInTab('albums/$albumId');

  void goToTrack(String trackId) => _pushInTab('tracks/$trackId');

  /// One entity's listening figures. [kind] decides the path, exactly as it decides the web's.
  void goToEntityStats(EntityKind kind, String id) =>
      _pushInTab('${kind.wire}s/$id/stats');

  void goToGenres() => _pushInTab('genres');

  void goToGenre(String slug) =>
      _pushInTab('genres/${Uri.encodeComponent(slug)}');

  void goToLabels() => _pushInTab('labels');

  void goToLabel(String labelId) => _pushInTab('labels/$labelId');

  void _pushInTab(String suffix) => pushInCurrentTab(this, suffix);
}

/// Pushes a tab-relative catalog path into whichever tab is showing.
///
/// Public because the player navigates too, and it holds a path rather than a call: "Playing from"
/// resolves a play context to a route, and one function has to be able to push whatever came back.
void pushInCurrentTab(BuildContext context, String suffix) {
  final segments = GoRouterState.of(context).uri.pathSegments;
  // No segment at all can only happen at "/", which the router redirects away from before any
  // catalog screen exists to push from — but a crash there would be a poor trade for a guard.
  if (segments.isEmpty) return;
  GoRouter.of(context).push('/${segments.first}/$suffix');
}
