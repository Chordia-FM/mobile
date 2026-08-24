import 'package:chordia_sync/chordia_sync.dart'
    show
        AlbumContext,
        ArtistContext,
        LibraryContext,
        LikedContext,
        PlayContext,
        PlaylistContext,
        RadioContext,
        SearchContext,
        SmartPlaylistContext,
        StationKind;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../catalog/catalog_routes.dart';
import '../catalog/widgets/entity_menu.dart';
import '../library/liked_screen.dart';
import '../library/library_detail_screen.dart';
import '../library/playlist_detail_screen.dart';
import '../library/smart_playlist_screen.dart';

/// "Playing from …" as somewhere you can actually go.
///
/// It was dead text: the player named the album, the playlist or the station a queue came from and
/// nothing happened when you touched it, so from the player there was no way back to what you were
/// listening to. The web deep-links all eight kinds; this resolves the same eight.

/// The mini bar's context, which is the only one the player can navigate from.
///
/// The full player, the queue sheet and every menu they raise are ROOT-navigator routes: there is
/// no `GoRouterState` above one, so `context.goToAlbum(...)` cannot work there, and a screen pushed
/// from one would cover the tab bar. The mini bar is mounted whenever there is something playing
/// and it sits under the shell's route, which knows which tab is showing.
final playerNavHostKey = GlobalKey();

/// Where a play context leads.
@immutable
sealed class PlayContextDestination {
  const PlayContextDestination();

  /// Stable name for what this resolves to, independent of ids — what a test asserts on.
  String get kind;
}

/// A catalog route, relative to whichever tab is showing (see [pushInCurrentTab]).
class CatalogRouteDestination extends PlayContextDestination {
  const CatalogRouteDestination(this.kind, this.path);

  @override
  final String kind;

  /// Tab-relative, e.g. `albums/abc` — the same form `CatalogNavigation` pushes.
  final String path;
}

/// A collection that is a screen rather than a route: it takes plain constructor arguments and is
/// pushed, exactly as the Library tab pushes it.
class ScreenDestination extends PlayContextDestination {
  const ScreenDestination(this.kind, this.screen);

  @override
  final String kind;

  final WidgetBuilder screen;
}

/// A tab of the shell, for the one context that is a place rather than a thing.
class TabDestination extends PlayContextDestination {
  const TabDestination(this.kind, this.location);

  @override
  final String kind;

  final String location;
}

/// Resolves the "Playing from" line to a destination — total over every [PlayContext].
///
/// A station resolves to its SEED, because this client has no station page of its own: the honest
/// destination for "Artist Radio" is the artist, and for a track station the track. That is a real
/// place; a route that does not exist would be a link into an error screen.
PlayContextDestination playContextDestination(PlayContext context) =>
    switch (context) {
      AlbumContext(:final id) => CatalogRouteDestination('album', 'albums/$id'),
      ArtistContext(:final id) => CatalogRouteDestination(
        'artist',
        'artists/$id',
      ),
      RadioContext(:final id, :final stationKind) => switch (stationKind) {
        StationKind.track => CatalogRouteDestination('radio', 'tracks/$id'),
        StationKind.album => CatalogRouteDestination('radio', 'albums/$id'),
        StationKind.genre => CatalogRouteDestination(
          'radio',
          'genres/${Uri.encodeComponent(id)}',
        ),
        StationKind.playlist => ScreenDestination(
          'radio',
          (_) => PlaylistDetailScreen(playlistId: id),
        ),
        // Null means artist; see `RadioContext.stationKind`.
        StationKind.artist ||
        null => CatalogRouteDestination('radio', 'artists/$id'),
      },
      PlaylistContext(:final id) => ScreenDestination(
        'playlist',
        (_) => PlaylistDetailScreen(playlistId: id),
      ),
      SmartPlaylistContext(:final id) => ScreenDestination(
        'smart',
        (_) => SmartPlaylistScreen(playlistId: id),
      ),
      LibraryContext(:final id) => ScreenDestination(
        'library',
        (_) => LibraryDetailScreen(libraryId: id, owned: false),
      ),
      LikedContext() => const ScreenDestination('liked', _likedScreen),
      SearchContext() => const TabDestination('search', '/search'),
    };

Widget _likedScreen(BuildContext context) => const LikedScreen();

/// Leaves the player for [context]'s source.
///
/// Dismisses the full player and anything raised over it first: the destination is a page, and a
/// page opened behind a full-screen player is a page nobody sees.
void openPlayContext(BuildContext context, PlayContext playContext) =>
    leavePlayer(context, (tab) {
      switch (playContextDestination(playContext)) {
        case CatalogRouteDestination(:final path):
          pushInCurrentTab(tab, path);
        case ScreenDestination(:final screen):
          Navigator.of(tab).push(MaterialPageRoute<void>(builder: screen));
        case TabDestination(:final location):
          GoRouter.of(tab).go(location);
      }
    });

/// Dismisses the player's routes, then runs [go] against a context that can navigate.
void leavePlayer(BuildContext context, void Function(BuildContext tab) go) {
  final host = playerNavHostKey.currentContext;
  if (context.mounted) {
    // The root stack is [shell, full player, sheets…]; the branch stacks live below the shell and
    // are untouched, so this returns to exactly the tab and page the listener left.
    Navigator.of(
      context,
      rootNavigator: true,
    ).popUntil((route) => route.isFirst);
  }
  final tab = host ?? context;
  if (tab.mounted) go(tab);
}

/// How a menu opened from the player navigates.
class PlayerMenuNav implements MenuNav {
  const PlayerMenuNav(this.context);

  final BuildContext context;

  @override
  void goToArtist(String artistId) =>
      leavePlayer(context, (tab) => tab.goToArtist(artistId));

  @override
  void goToArtistDiscography(String artistId) =>
      leavePlayer(context, (tab) => tab.goToArtistDiscography(artistId));

  @override
  void goToAlbum(String albumId) =>
      leavePlayer(context, (tab) => tab.goToAlbum(albumId));

  @override
  void goToTrack(String trackId) =>
      leavePlayer(context, (tab) => tab.goToTrack(trackId));

  @override
  void goToGenre(String slug) =>
      leavePlayer(context, (tab) => tab.goToGenre(slug));

  @override
  void goToLabel(String labelId) =>
      leavePlayer(context, (tab) => tab.goToLabel(labelId));

  @override
  void openScreen(WidgetBuilder screen) => leavePlayer(
    context,
    (tab) => Navigator.of(tab).push(MaterialPageRoute<void>(builder: screen)),
  );
}

/// The menu of the collection a queue was started from, so "Playing from Discover Weekly" is a
/// long press as well as a link — the same actions its row anywhere else offers.
///
/// Null for the two kinds that are a place rather than a thing: a search and the liked songs have
/// no id to act on, and the liked songs' only action is to open them, which the tap already does.
EntityMenuBuilder? playContextMenu(
  PlayContext playContext,
) => switch (playContext) {
  AlbumContext(:final id, :final name) => (page, ref) => albumMenu(
    page,
    ref,
    AlbumLike(id: id, title: name),
    nav: PlayerMenuNav(page),
  ),
  ArtistContext(:final id, :final name) => (page, ref) => artistMenu(
    page,
    ref,
    ArtistLike(id: id, name: name),
    nav: PlayerMenuNav(page),
  ),
  PlaylistContext(:final id, :final name) => (page, ref) => playlistMenu(
    page,
    ref,
    PlaylistLike(id: id, name: name),
    nav: PlayerMenuNav(page),
  ),
  SmartPlaylistContext(:final id, :final name) =>
    (page, ref) => smartPlaylistMenu(
      page,
      ref,
      PlaylistLike(id: id, name: name),
      nav: PlayerMenuNav(page),
    ),
  LibraryContext(:final id, :final name) => (page, ref) => libraryMenu(
    page,
    ref,
    libraryId: id,
    name: name,
    nav: PlayerMenuNav(page),
  ),
  // A station is its seed's menu — around an artist that is the daily mix's own set of actions.
  // A track seed has none: a station carries no track row to act on, only the seed's id.
  RadioContext(:final id, :final name, :final stationKind) =>
    switch (stationKind) {
      StationKind.album => (page, ref) => albumMenu(
        page,
        ref,
        AlbumLike(id: id, title: name),
        nav: PlayerMenuNav(page),
      ),
      StationKind.genre => (page, ref) => genreMenu(
        page,
        ref,
        slug: id,
        name: name,
        nav: PlayerMenuNav(page),
      ),
      StationKind.playlist => (page, ref) => playlistMenu(
        page,
        ref,
        PlaylistLike(id: id, name: name),
        nav: PlayerMenuNav(page),
      ),
      StationKind.track => null,
      StationKind.artist || null => (page, ref) => mixMenu(
        page,
        ref,
        MixLike(seedArtistId: id, title: name),
        nav: PlayerMenuNav(page),
      ),
    },
  LikedContext() || SearchContext() => null,
};
