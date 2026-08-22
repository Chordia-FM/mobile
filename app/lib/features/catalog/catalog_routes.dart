import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

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
    ],
  ),
  GoRoute(
    path: 'albums/:albumId',
    builder: (context, state) =>
        AlbumScreen(albumId: state.pathParameters['albumId']!),
  ),
  GoRoute(
    path: 'tracks/:trackId',
    builder: (context, state) =>
        TrackScreen(trackId: state.pathParameters['trackId']!),
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

  void goToGenres() => _pushInTab('genres');

  void goToGenre(String slug) =>
      _pushInTab('genres/${Uri.encodeComponent(slug)}');

  void goToLabels() => _pushInTab('labels');

  void goToLabel(String labelId) => _pushInTab('labels/$labelId');

  void _pushInTab(String suffix) {
    final segments = GoRouterState.of(this).uri.pathSegments;
    // No segment at all can only happen at "/", which the router redirects away from before any
    // catalog screen exists to push from — but a crash there would be a poor trade for a guard.
    if (segments.isEmpty) return;
    GoRouter.of(this).push('/${segments.first}/$suffix');
  }
}
