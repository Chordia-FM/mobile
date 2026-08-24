import 'dart:async';

import 'package:chordia_api/chordia_api.dart';
import 'package:chordia_sync/chordia_sync.dart' as sync show StationKind;
import 'package:chordia_sync/chordia_sync.dart'
    show
        AlbumContext,
        ArtistContext,
        LibraryContext,
        PlayContext,
        PlaylistContext,
        RadioContext,
        SmartPlaylistContext,
        StationCursor;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart' show activeHubProvider, hubClientProvider;
import '../../../i18n/keys.g.dart';
import '../../../i18n/translations_provider.dart';
import '../../downloads/downloads_api.dart';
import '../../downloads/widgets/download_controls.dart';
import '../../insights/entity_stats_screen.dart' show showEntityStats;
import '../../library/data/library_providers.dart' show pinsProvider;
import '../../library/liked_screen.dart';
import '../../library/library_detail_screen.dart';
import '../../library/playlist_detail_screen.dart';
import '../../library/smart_playlist_screen.dart';
import '../../manager/manager_routes.dart' show ManagerNavigation;
import '../../playlists/add_to_playlist_sheet.dart';
import '../catalog_routes.dart';
import '../data/catalog_api.dart';
import '../data/catalog_providers.dart';
import '../data/playback.dart';
import 'entity_menu.dart';

/// One menu definition per entity kind — the twelve the web client has, against the one mobile had.
///
/// Every builder here returns a description; nothing in this file draws anything. Actions are wired
/// only where the endpoint behind them exists in this client: pins, stations, playlists, downloads
/// and likes all do, and each was already on the wire with nothing calling it.

// ── where a menu goes ──────────────────────────────────────────────────────────────────────────

/// How a menu leaves for somewhere else.
///
/// An interface because the answer differs by WHERE the menu was opened: a menu raised from a
/// catalog page pushes into that page's tab, while one raised from the player has to dismiss the
/// player first — it is a root-navigator route, and `GoRouterState` does not exist above one.
abstract interface class MenuNav {
  void goToArtist(String artistId);
  void goToArtistDiscography(String artistId);
  void goToAlbum(String albumId);
  void goToTrack(String trackId);
  void goToGenre(String slug);
  void goToLabel(String labelId);

  /// For the collections that are screens rather than routes — playlists, the liked songs, a
  /// library. They take plain constructor arguments and are pushed, exactly as the Library tab
  /// pushes them.
  void openScreen(WidgetBuilder screen);
}

/// The Manager destinations, which only a menu raised inside a tab can reach.
///
/// Separate from [MenuNav] rather than another pair of methods on it, because the two navs are not
/// equally able: `managerRoutes()` is spread under each tab's root and addressed relative to the
/// tab in the current location, while a menu raised from the player sits on a root-navigator route
/// that has no `GoRouterState` above it. A nav that cannot honour these simply does not implement
/// them, and the rows are absent rather than throwing when tapped.
abstract interface class DiscoverNav {
  void goToDiscoverArtist(String artistMbid);
  void goToReleaseGroup(String releaseGroupMbid);

  /// A name search in Discover, for the entities that have no MusicBrainz id to go straight to.
  void goToDiscoverSearch(String term);
}

/// The default: navigate from the page the menu was opened over.
class PageMenuNav implements MenuNav, DiscoverNav {
  const PageMenuNav(this.page);

  final BuildContext page;

  @override
  void goToArtist(String artistId) {
    if (page.mounted) page.goToArtist(artistId);
  }

  @override
  void goToArtistDiscography(String artistId) {
    if (page.mounted) page.goToArtistDiscography(artistId);
  }

  @override
  void goToAlbum(String albumId) {
    if (page.mounted) page.goToAlbum(albumId);
  }

  @override
  void goToTrack(String trackId) {
    if (page.mounted) page.goToTrack(trackId);
  }

  @override
  void goToGenre(String slug) {
    if (page.mounted) page.goToGenre(slug);
  }

  @override
  void goToLabel(String labelId) {
    if (page.mounted) page.goToLabel(labelId);
  }

  @override
  void goToDiscoverArtist(String artistMbid) {
    if (page.mounted) page.goToDiscoverArtist(artistMbid);
  }

  @override
  void goToReleaseGroup(String releaseGroupMbid) {
    if (page.mounted) page.goToReleaseGroup(releaseGroupMbid);
  }

  @override
  void goToDiscoverSearch(String term) {
    if (page.mounted) page.goToDiscoverSearch(term);
  }

  @override
  void openScreen(WidgetBuilder screen) {
    if (page.mounted) {
      Navigator.of(page).push(MaterialPageRoute<void>(builder: screen));
    }
  }
}

// ── the rows a menu is built from ──────────────────────────────────────────────────────────────

/// Everything an action needs that outlives the sheet it was tapped in.
///
/// Read once, in the builder, rather than through `ref` inside each closure: the sheet's `WidgetRef`
/// dies with the pop, and every one of these actions runs after it.
class MenuHost {
  MenuHost(this.page, WidgetRef ref, MenuNav? nav)
    : t = ref.t,
      nav = nav ?? PageMenuNav(page),
      messenger = ScaffoldMessenger.maybeOf(page),
      player = ref.read(catalogPlayerActionsProvider),
      liked = ref.read(likedTrackIdsProvider.notifier),
      hidden = ref.read(hiddenTrackIdsProvider.notifier),
      // The CONTAINER, not the queue itself: building the download manager pulls in the database,
      // the storage budget and a foreground service, and a menu that merely offers Download must
      // not stand all of that up to draw a row.
      _container = ProviderScope.containerOf(page, listen: false),
      frontend = ref.read(activeHubProvider)?.frontendUrl,
      api = _apiOrNull(ref),
      _invalidatePins = (() => ref.invalidate(pinsProvider));

  final BuildContext page;
  final String Function(String, [Map<String, Object?>]) t;
  final MenuNav nav;
  final ScaffoldMessengerState? messenger;
  final CatalogPlayerActions? player;
  final LikedTracksController liked;
  final HiddenTracksController hidden;

  /// Where this hub's public web client lives, for the share sheet. Null when the hub never said.
  final Uri? frontend;

  /// Null only when no hub is selected, which is not a state a signed-in session reaches — but a
  /// menu that throws while opening would be a worse answer than one missing its Hub-backed rows.
  final CatalogApi? api;

  final void Function() _invalidatePins;
  final ProviderContainer _container;

  /// Resolved on use rather than in the constructor, for the reason the constructor gives: the
  /// download manager is expensive to stand up, and most menus never reach this row.
  DownloadsApi get downloads => _container.read(downloadsApiProvider);

  void snack(String message) {
    final messenger = this.messenger;
    if (messenger == null || !messenger.mounted) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Replaces the queue with [tracks], attributing the session to [context].
  void play(List<BrowseTrack> tracks, PlayContext context) {
    if (tracks.isEmpty) return;
    player?.playQueue(tracks.map(toPlayerTrack).toList(), context: context);
  }

  void enqueueAll(List<BrowseTrack> tracks) {
    final player = this.player;
    if (player == null) return;
    for (final track in tracks) {
      player.enqueue(toPlayerTrack(track));
    }
    if (tracks.isNotEmpty) {
      snack(t(PlayerKeys.queueAddedAlbum, {'count': tracks.length}));
    }
  }

  /// Loads a collection's tracks, saying so rather than failing silently when it cannot.
  Future<List<BrowseTrack>> load(
    Future<List<BrowseTrack>> Function() fetch,
  ) async {
    try {
      return await fetch();
    } on Object {
      snack(t(ErrorsKeys.failedToLoad));
      return const [];
    }
  }

  /// Builds a station around any seed and plays it.
  ///
  /// The station's own cursor travels in the context, so the queue can ask for the next page when
  /// it runs dry rather than ending the listening session at track thirty.
  Future<void> startStation(StationKind kind, String seed) async {
    final player = this.player;
    final api = this.api;
    if (player == null || api == null) return;
    try {
      final station = await api.station(kind, seed);
      if (station.tracks.isEmpty) {
        snack(t(DiscoveryKeys.stationEmpty));
        return;
      }
      player
        ..setShuffle(false)
        ..playQueue(
          station.tracks.map(toPlayerTrack).toList(),
          context: RadioContext(
            id: station.seedId,
            name: station.seedName,
            stationKind: _queueStationKind(kind),
            stationCursor: StationCursor(station.nextCursor),
          ),
        );
    } on Object {
      snack(t(ErrorsKeys.discoveryRadioFailed));
    }
  }

  Future<void> togglePin(
    PinKind kind,
    String id, {
    required bool pinned,
  }) async {
    final api = this.api;
    if (api == null) return;
    try {
      await (pinned ? api.removePin(kind, id) : api.addPin(kind, id));
      _invalidatePins();
    } on Object {
      snack(t(ErrorsKeys.changeFailed));
    }
  }

  Future<void> share({required String path, required String title}) async {
    if (!page.mounted) return;
    await shareCatalogPath(
      page,
      frontend: frontend,
      path: path,
      title: title,
      errorMessage: t(ErrorsKeys.generic),
    );
  }

  /// Queues a whole collection for offline playback.
  Future<void> save(List<BrowseTrack> tracks) async {
    final messenger = this.messenger;
    if (tracks.isEmpty || messenger == null) return;
    await saveDownloadsVia(messenger, downloads, t, tracks);
  }

  void addToPlaylist(List<String> trackIds, String label) {
    if (!page.mounted || trackIds.isEmpty) return;
    unawaited(showAddToPlaylistSheet(page, trackIds: trackIds, label: label));
  }
}

CatalogApi? _apiOrNull(WidgetRef ref) {
  try {
    return ref.read(catalogApiProvider);
  } on Object {
    return null;
  }
}

bool _isPinned(WidgetRef ref, PinKind kind, String id) =>
    ref.watch(pinsProvider).value?.any((p) => p.kind == kind && p.id == id) ??
    false;

MenuAction _pinAction(
  MenuHost host, {
  required bool pinned,
  required PinKind kind,
  required String id,
}) => MenuAction(
  id: 'pin',
  label: host.t(pinned ? CommonKeys.actionsUnpin : CommonKeys.actionsPin),
  icon: pinned ? Icons.push_pin : Icons.push_pin_outlined,
  onSelect: () => host.togglePin(kind, id, pinned: pinned),
);

MenuAction _radioAction(MenuHost host, StationKind kind, String seed) =>
    MenuAction(
      id: 'radio',
      label: host.t(DiscoveryKeys.stationStart),
      icon: Icons.radio_rounded,
      enabled: host.player != null && host.api != null,
      onSelect: () => host.startStation(kind, seed),
    );

MenuAction _shareAction(
  MenuHost host, {
  required String path,
  required String title,
}) => MenuAction(
  id: 'share',
  label: host.t(CommonKeys.actionsShare),
  icon: Icons.ios_share_rounded,
  onSelect: () => host.share(path: path, title: title),
);

/// "Open in Discover" — this entity in the Manager, with its owned/missing state.
///
/// A MusicBrainz id is the destination worth having: the artist's or release group's own Manager
/// page, everything they released set against what is owned. [term] is the web's FALLBACK
/// (`lib/menus/actions.tsx` navigates to `/app/manager/discover?q=…`) and the only route a TRACK
/// has, since no track carries an MBID on the wire — without it the row would be missing from
/// exactly the rows most likely to want looking up.
///
/// Passed by the track menu alone, and that is deliberate while the phone's Discover cannot be
/// SEEDED: `manager?q=` picks the Discover tab, but `widgets/discover_view.dart` owns the search
/// field and takes no initial value, so a name search currently arrives with an empty box. For a
/// track that is still better than no row at all; for an album or artist whose MBID enrichment
/// merely has not run, it would be strictly worse than the precise destination they usually have.
/// The term is the fallback the web spells out at `lib/menus/actions.tsx:84`: without it the row
/// "would simply be missing on exactly the entities most likely to need looking up" — an album whose
/// MusicBrainz enrichment has not run yet is precisely the one somebody wants to go and find.
///
/// Null when the nav cannot reach the Manager — the player's sits on a root-navigator route with no
/// `GoRouterState` above it — or when there is neither an id nor a name to look anything up by.
MenuAction? _discoverAction(
  MenuHost host, {
  String? term,
  String? artistMbid,
  String? albumMbid,
}) {
  // Bound by pattern rather than tested with `is`: the row's callback is a closure, and a
  // promotion does not survive into one.
  if (host.nav case final DiscoverNav nav) {
    // An empty string is what an un-enriched row carries, and it is not an id.
    final release = (albumMbid?.isEmpty ?? true) ? null : albumMbid;
    final artist = (artistMbid?.isEmpty ?? true) ? null : artistMbid;
    final search = term?.trim() ?? '';
    if (release == null && artist == null && search.isEmpty) return null;

    return MenuAction(
      id: 'open-in-discover',
      label: host.t(ManagerKeys.discoverOpenIn),
      icon: Icons.travel_explore_rounded,
      onSelect: () {
        if (release != null) {
          nav.goToReleaseGroup(release);
        } else if (artist != null) {
          nav.goToDiscoverArtist(artist);
        } else {
          nav.goToDiscoverSearch(search);
        }
      },
    );
  }
  return null;
}

/// How this artist, album or track sits in the reader's own listening.
///
/// Pushed on the page the menu was opened over rather than through [MenuNav], because that is what
/// `showEntityStats` already does and it is the same page a chart row pushes from.
MenuAction _statsAction(
  MenuHost host, {
  required EntityKind kind,
  required String id,
  required String name,
}) => MenuAction(
  id: 'stats',
  label: host.t(InsightsKeys.entityTitle),
  icon: Icons.show_chart_rounded,
  onSelect: () async {
    if (!host.page.mounted) return;
    await showEntityStats(host.page, kind: kind, id: id, name: name);
  },
);

/// Correcting what the catalog says about this entity.
///
/// Gated on the host, exactly as the web gates it: the correction form is a surface the page owns,
/// and a row that offers to report a wrong title and then opens nothing is worse than no row. It is
/// deliberately NOT owner-gated — what the form lets you DO with a correction depends on what you
/// own, and that is the form's decision, not the menu's.
MenuAction _reportAction(MenuHost host, VoidCallback onReport) => MenuAction(
  id: 'report',
  label: host.t(CatalogKeys.reportAction),
  icon: Icons.flag_outlined,
  onSelect: onReport,
);

/// The queue's `StationKind`, which is a separate type from the API's — `chordia_sync` cannot
/// depend on `chordia_api`. Matched on the wire value, which is the definition of both.
sync.StationKind? _queueStationKind(StationKind kind) =>
    sync.StationKind.tryParse(kind.wire);

// ── 1. a track ─────────────────────────────────────────────────────────────────────────────────

/// A track's actions, from its ⋮ button or a long press on its row.
///
/// Kept as a named opener because half the app calls it: the row, the track page, the liked list,
/// a playlist and the downloads screen all raise the same sheet, and every one of them means "this
/// song's menu".
/// Every option [trackMenu] takes is forwarded, so a list that can reorder or correct a row does
/// not have to reach for `showEntityMenu` to say so — that is how a playlist row ended up with the
/// reordering in a Material popup and the rest of the menu behind a "More" tap.
Future<void> showTrackMenu(
  BuildContext context,
  WidgetRef ref,
  BrowseTrack track, {
  VoidCallback? onPlay,
  VoidCallback? onRemove,
  VoidCallback? onMoveUp,
  VoidCallback? onMoveDown,
  VoidCallback? onReport,
  String? removeLabel,
}) => showEntityMenu(
  context,
  (page, sheetRef) => trackMenu(
    page,
    sheetRef,
    track,
    onPlay: onPlay,
    onRemove: onRemove,
    onMoveUp: onMoveUp,
    onMoveDown: onMoveDown,
    onReport: onReport,
    removeLabel: removeLabel,
  ),
);

/// A song, wherever one is listed.
///
/// [onPlay] is supplied by lists that know what "play this row" means for them (the whole album
/// from here, not the one track). [onMoveUp] / [onMoveDown] give a playlist editor reordering
/// without drag, [onRemove] the row's removal and [onReport] the metadata-correction form — all
/// absent unless the host can honour them.
EntityMenu trackMenu(
  BuildContext page,
  WidgetRef ref,
  BrowseTrack track, {
  MenuNav? nav,
  VoidCallback? onPlay,
  VoidCallback? onRemove,
  VoidCallback? onMoveUp,
  VoidCallback? onMoveDown,
  VoidCallback? onReport,
  String? removeLabel,
}) {
  final host = MenuHost(page, ref, nav);
  final t = host.t;
  final liked = ref.watch(likedTrackIdsProvider).value?.contains(track.id);
  final hidden = ref.watch(hiddenTrackIdsProvider).value?.contains(track.id);

  return EntityMenu(
    target: MenuTarget(
      kind: MenuTargetKind.track,
      id: track.id,
      title: track.title,
      subtitle: track.artist,
      imageUrl: track.coverUrl,
    ),
    sections: [
      MenuSection(
        id: 'play',
        items: [
          if (onPlay != null)
            MenuAction(
              id: 'play',
              label: t(CommonKeys.actionsPlay),
              icon: Icons.play_arrow_rounded,
              onSelect: onPlay,
            ),
          MenuAction(
            id: 'play-next',
            label: t(PlayerKeys.queuePlayNext),
            icon: Icons.playlist_play_rounded,
            enabled: host.player != null,
            onSelect: () => host.player?.playNext(toPlayerTrack(track)),
          ),
          MenuAction(
            id: 'queue',
            label: t(PlayerKeys.queueAdd),
            icon: Icons.queue_music_rounded,
            enabled: host.player != null,
            onSelect: () => host.player?.enqueue(toPlayerTrack(track)),
          ),
          _radioAction(host, StationKind.track, track.id),
        ],
      ),
      MenuSection(
        id: 'collect',
        items: [
          _likeAction(host, track.id, liked: liked),
          _hideAction(host, track.id, hidden: hidden),
          MenuAction(
            id: 'add-to-playlist',
            label: t(PlaylistsKeys.addToPlaylist),
            icon: Icons.playlist_add_rounded,
            onSelect: () => host.addToPlaylist([track.id], track.title),
          ),
          MenuAction.custom(
            id: 'download',
            builder: (context, close) =>
                DownloadMenuTile(tracks: [track], onDone: close),
          ),
        ],
      ),
      MenuSection(
        id: 'reorder',
        items: [
          if (onMoveUp != null)
            MenuAction(
              id: 'move-up',
              label: t(CommonKeys.actionsMoveUp),
              icon: Icons.arrow_upward_rounded,
              onSelect: onMoveUp,
            ),
          if (onMoveDown != null)
            MenuAction(
              id: 'move-down',
              label: t(CommonKeys.actionsMoveDown),
              icon: Icons.arrow_downward_rounded,
              onSelect: onMoveDown,
            ),
        ],
      ),
      MenuSection(
        id: 'navigate',
        items: [
          if (track.albumId case final albumId?)
            MenuAction(
              id: 'go-to-album',
              label: t(CommonKeys.actionsGoToAlbum),
              icon: Icons.album_outlined,
              onSelect: () => host.nav.goToAlbum(albumId),
            ),
          if (track.artistId case final artistId?)
            MenuAction(
              id: 'go-to-artist',
              label: t(CommonKeys.actionsGoToArtist),
              icon: Icons.person_outline_rounded,
              onSelect: () => host.nav.goToArtist(artistId),
            ),
          _shareAction(host, path: '/tracks/${track.id}', title: track.title),
          // Name search only, and unconditionally so — a track has no MBID of its own to aim at.
          ?_discoverAction(host, term: '${track.artist} ${track.title}'.trim()),
        ],
      ),
      MenuSection(
        id: 'report',
        items: [if (onReport != null) _reportAction(host, onReport)],
      ),
      MenuSection(
        id: 'danger',
        items: [
          if (onRemove != null)
            MenuAction(
              id: 'remove',
              label: removeLabel ?? t(PlaylistsKeys.removeFromPlaylist),
              icon: Icons.delete_outline_rounded,
              destructive: true,
              onSelect: onRemove,
            ),
        ],
      ),
    ],
  );
}

MenuAction _likeAction(
  MenuHost host,
  String trackId, {
  required bool? liked,
}) => MenuAction(
  id: 'like',
  label: host.t(
    liked ?? false ? LibraryKeys.likedRemove : LibraryKeys.likedSave,
  ),
  icon: liked ?? false ? Icons.favorite_rounded : Icons.favorite_border_rounded,
  // Until the liked set has loaded there is no state to flip, and a heart that reports the
  // wrong state is worse than one that is briefly unavailable.
  enabled: liked != null,
  onSelect: () async {
    try {
      await host.liked.toggle(trackId);
    } on Object {
      host.snack(host.t(ErrorsKeys.changeFailed));
    }
  },
);

/// Which tracks the listener has hidden.
///
/// One set for the whole app, for the same reason the liked set is one: a hidden track is dimmed
/// wherever it is listed and skipped when a list is played, so every row asks the same question and
/// asking the Hub per row would be a request per track. Not auto-disposed — it outlives any screen.
///
/// Read through [HubClient] rather than `CatalogApi`: hiding is a `/v1/me` concern and the catalog
/// interface does not carry it.
final hiddenTrackIdsProvider =
    AsyncNotifierProvider<HiddenTracksController, Set<String>>(
      HiddenTracksController.new,
    );

class HiddenTracksController extends AsyncNotifier<Set<String>> {
  @override
  Future<Set<String>> build() async {
    final hub = ref.watch(hubClientProvider);
    if (hub == null) return const {};
    return (await hub.hiddenTracks()).toSet();
  }

  bool isHidden(String trackId) => state.value?.contains(trackId) ?? false;

  /// Flips one track's hidden state, showing the new state before the Hub has confirmed it.
  ///
  /// Reverts on failure and rethrows, like the liked set: a row that stays dimmed after a failed
  /// write is a lie the next launch quietly corrects.
  Future<void> toggle(String trackId) async {
    final before = state.value;
    final hub = ref.read(hubClientProvider);
    if (before == null || hub == null) return;

    final hidden = before.contains(trackId);
    final after = {...before};
    if (hidden) {
      after.remove(trackId);
    } else {
      after.add(trackId);
    }
    state = AsyncData(after);

    try {
      await (hidden ? hub.unhideTrack(trackId) : hub.hideTrack(trackId));
    } on Object {
      state = AsyncData(before);
      rethrow;
    }
  }
}

MenuAction _hideAction(
  MenuHost host,
  String trackId, {
  required bool? hidden,
}) => MenuAction(
  id: 'hide',
  label: host.t(
    hidden ?? false ? LibraryKeys.hiddenUnhide : LibraryKeys.hiddenHide,
  ),
  icon: hidden ?? false
      ? Icons.visibility_off_rounded
      : Icons.visibility_off_outlined,
  // Same rule as the heart: until the hidden set has loaded there is no state to flip.
  enabled: hidden != null && host.api != null,
  onSelect: () async {
    try {
      await host.hidden.toggle(trackId);
    } on Object {
      host.snack(host.t(ErrorsKeys.changeFailed));
    }
  },
);

// ── 2. an album card ───────────────────────────────────────────────────────────────────────────

/// An album with only what a card carries.
@immutable
class AlbumLike {
  const AlbumLike({
    required this.id,
    required this.title,
    this.artist,
    this.artistId,
    this.coverUrl,
    this.mbid,
  });

  final String id;
  final String title;
  final String? artist;
  final String? artistId;
  final String? coverUrl;

  /// MusicBrainz release-group id, for "Open in Discover". `BrowseAlbum.mbid` has carried it all
  /// along; a card that builds one of these from a browse row should pass it through, or the menu
  /// silently drops the only precise route into the Manager.
  final String? mbid;
}

/// The menu of an album CARD. A card has no track list, so Play and Add to queue fetch one.
EntityMenu albumMenu(
  BuildContext page,
  WidgetRef ref,
  AlbumLike album, {
  MenuNav? nav,
}) {
  final host = MenuHost(page, ref, nav);
  final t = host.t;
  final pinned = _isPinned(ref, PinKind.album, album.id);
  final api = host.api;

  Future<List<BrowseTrack>> tracks() => api == null
      ? Future.value(const [])
      : host.load(() => api.albumTracks(album.id));

  return EntityMenu(
    target: MenuTarget(
      kind: MenuTargetKind.album,
      id: album.id,
      title: album.title,
      subtitle: album.artist,
      imageUrl: album.coverUrl,
    ),
    sections: [
      MenuSection(
        id: 'play',
        items: [
          MenuAction(
            id: 'play',
            label: t(CommonKeys.actionsPlay),
            icon: Icons.play_arrow_rounded,
            enabled: host.player != null && api != null,
            onSelect: () async => host.play(
              await tracks(),
              AlbumContext(id: album.id, name: album.title),
            ),
          ),
          MenuAction(
            id: 'queue',
            label: t(PlayerKeys.queueAdd),
            icon: Icons.queue_music_rounded,
            enabled: host.player != null && api != null,
            onSelect: () async => host.enqueueAll(await tracks()),
          ),
          _radioAction(host, StationKind.album, album.id),
        ],
      ),
      MenuSection(
        id: 'collect',
        items: [
          _pinAction(host, pinned: pinned, kind: PinKind.album, id: album.id),
          MenuAction(
            id: 'add-to-playlist',
            label: t(PlaylistsKeys.addToPlaylist),
            icon: Icons.playlist_add_rounded,
            enabled: api != null,
            onSelect: () async => host.addToPlaylist([
              for (final track in await tracks()) track.id,
            ], album.title),
          ),
        ],
      ),
      MenuSection(
        id: 'navigate',
        items: [
          MenuAction(
            id: 'open',
            label: t(CommonKeys.actionsOpen),
            icon: Icons.album_outlined,
            onSelect: () => host.nav.goToAlbum(album.id),
          ),
          if (album.artistId case final artistId?)
            MenuAction(
              id: 'go-to-artist',
              label: t(CommonKeys.actionsGoToArtist),
              icon: Icons.person_outline_rounded,
              onSelect: () => host.nav.goToArtist(artistId),
            ),
          _shareAction(host, path: '/albums/${album.id}', title: album.title),
          ?_discoverAction(
            host,
            albumMbid: album.mbid,
            term: '${album.artist ?? ''} ${album.title}'.trim(),
          ),
        ],
      ),
    ],
  );
}

// ── 3. an album page ───────────────────────────────────────────────────────────────────────────

/// The album PAGE's menu: it holds the release, so it can offer the whole set without fetching.
EntityMenu albumDetailMenu(
  BuildContext page,
  WidgetRef ref,
  AlbumDetail album, {
  MenuNav? nav,
  VoidCallback? onReport,
}) {
  final host = MenuHost(page, ref, nav);
  final t = host.t;
  final pinned = _isPinned(ref, PinKind.album, album.id);
  final playContext = AlbumContext(id: album.id, name: album.title);

  return EntityMenu(
    target: MenuTarget(
      kind: MenuTargetKind.album,
      id: album.id,
      title: album.title,
      subtitle: album.artist,
      imageUrl: album.coverUrl,
    ),
    sections: [
      MenuSection(
        id: 'play',
        items: [
          MenuAction(
            id: 'play',
            label: t(CommonKeys.actionsPlay),
            icon: Icons.play_arrow_rounded,
            enabled: host.player != null && album.tracks.isNotEmpty,
            onSelect: () => host.play(album.tracks, playContext),
          ),
          MenuAction(
            id: 'queue',
            label: t(PlayerKeys.queueAdd),
            icon: Icons.queue_music_rounded,
            enabled: host.player != null && album.tracks.isNotEmpty,
            onSelect: () => host.enqueueAll(album.tracks),
          ),
          _radioAction(host, StationKind.album, album.id),
          if (album.artistId case final artistId?)
            MenuAction(
              id: 'artist-radio',
              label: t(CatalogKeys.albumGoToRadio),
              icon: Icons.radio_outlined,
              enabled: host.player != null && host.api != null,
              onSelect: () => host.startStation(StationKind.artist, artistId),
            ),
        ],
      ),
      MenuSection(
        id: 'collect',
        items: [
          _pinAction(host, pinned: pinned, kind: PinKind.album, id: album.id),
          MenuAction(
            id: 'add-to-playlist',
            label: t(PlaylistsKeys.addToPlaylist),
            icon: Icons.playlist_add_rounded,
            enabled: album.tracks.isNotEmpty,
            onSelect: () => host.addToPlaylist([
              for (final track in album.tracks) track.id,
            ], album.title),
          ),
          if (album.tracks.isNotEmpty)
            MenuAction.custom(
              id: 'download',
              builder: (context, close) => DownloadMenuTile(
                tracks: album.tracks,
                label: t(LibraryKeys.downloadsActionDownloadAlbum),
                onDone: close,
              ),
            ),
        ],
      ),
      MenuSection(
        id: 'navigate',
        items: [
          if (album.artistId case final artistId?)
            MenuAction(
              id: 'go-to-artist',
              label: t(CommonKeys.actionsGoToArtist),
              icon: Icons.person_outline_rounded,
              onSelect: () => host.nav.goToArtist(artistId),
            ),
          _statsAction(
            host,
            kind: EntityKind.album,
            id: album.id,
            name: album.title,
          ),
          _shareAction(host, path: '/albums/${album.id}', title: album.title),
          ?_discoverAction(
            host,
            albumMbid: album.mbid,
            term: '${album.artist} ${album.title}'.trim(),
          ),
        ],
      ),
      MenuSection(
        id: 'report',
        items: [if (onReport != null) _reportAction(host, onReport)],
      ),
    ],
  );
}

// ── 4. an artist card ──────────────────────────────────────────────────────────────────────────

@immutable
class ArtistLike {
  const ArtistLike({
    required this.id,
    required this.name,
    this.imageUrl,
    this.mbid,
  });

  final String id;
  final String name;
  final String? imageUrl;

  /// MusicBrainz artist id, for "Open in Discover" — same trap as [AlbumLike.mbid]: pass it if the
  /// row you built this from has one.
  final String? mbid;
}

/// The menu of an artist CARD or row: what can be offered without their page loaded.
EntityMenu artistMenu(
  BuildContext page,
  WidgetRef ref,
  ArtistLike artist, {
  MenuNav? nav,
}) {
  final host = MenuHost(page, ref, nav);
  final t = host.t;
  final pinned = _isPinned(ref, PinKind.artist, artist.id);
  final api = host.api;

  Future<List<BrowseTrack>> tracks() async => api == null
      ? const []
      : host.load(() async => (await api.artist(artist.id)).topTracks);

  return EntityMenu(
    target: MenuTarget(
      kind: MenuTargetKind.artist,
      id: artist.id,
      title: artist.name,
      imageUrl: artist.imageUrl,
      round: true,
    ),
    sections: [
      MenuSection(
        id: 'play',
        items: [
          MenuAction(
            id: 'play',
            label: t(CommonKeys.actionsPlay),
            icon: Icons.play_arrow_rounded,
            enabled: host.player != null && api != null,
            onSelect: () async => host.play(
              await tracks(),
              ArtistContext(id: artist.id, name: artist.name),
            ),
          ),
          MenuAction(
            id: 'queue',
            label: t(PlayerKeys.queueAdd),
            icon: Icons.queue_music_rounded,
            enabled: host.player != null && api != null,
            onSelect: () async => host.enqueueAll(await tracks()),
          ),
          _radioAction(host, StationKind.artist, artist.id),
        ],
      ),
      MenuSection(
        id: 'collect',
        items: [
          _pinAction(host, pinned: pinned, kind: PinKind.artist, id: artist.id),
        ],
      ),
      MenuSection(
        id: 'navigate',
        items: [
          MenuAction(
            id: 'open',
            label: t(CommonKeys.actionsOpen),
            icon: Icons.person_outline_rounded,
            onSelect: () => host.nav.goToArtist(artist.id),
          ),
          _shareAction(host, path: '/artists/${artist.id}', title: artist.name),
          ?_discoverAction(host, artistMbid: artist.mbid, term: artist.name),
        ],
      ),
    ],
  );
}

// ── 5. an artist page ──────────────────────────────────────────────────────────────────────────

EntityMenu artistDetailMenu(
  BuildContext page,
  WidgetRef ref,
  ArtistDetail artist, {
  MenuNav? nav,
  VoidCallback? onReport,
}) {
  final host = MenuHost(page, ref, nav);
  final t = host.t;
  final pinned = _isPinned(ref, PinKind.artist, artist.id);
  final playContext = ArtistContext(id: artist.id, name: artist.name);

  return EntityMenu(
    target: MenuTarget(
      kind: MenuTargetKind.artist,
      id: artist.id,
      title: artist.name,
      imageUrl: artist.imageUrl,
      round: true,
    ),
    sections: [
      MenuSection(
        id: 'play',
        items: [
          MenuAction(
            id: 'play',
            label: t(CommonKeys.actionsPlay),
            icon: Icons.play_arrow_rounded,
            enabled: host.player != null && artist.topTracks.isNotEmpty,
            onSelect: () => host.play(artist.topTracks, playContext),
          ),
          MenuAction(
            id: 'queue',
            label: t(PlayerKeys.queueAdd),
            icon: Icons.queue_music_rounded,
            enabled: host.player != null && artist.topTracks.isNotEmpty,
            onSelect: () => host.enqueueAll(artist.topTracks),
          ),
          _radioAction(host, StationKind.artist, artist.id),
        ],
      ),
      MenuSection(
        id: 'collect',
        items: [
          _pinAction(host, pinned: pinned, kind: PinKind.artist, id: artist.id),
        ],
      ),
      MenuSection(
        id: 'navigate',
        items: [
          MenuAction(
            id: 'discography',
            label: t(CatalogKeys.artistDiscography),
            icon: Icons.library_music_outlined,
            onSelect: () => host.nav.goToArtistDiscography(artist.id),
          ),
          _statsAction(
            host,
            kind: EntityKind.artist,
            id: artist.id,
            name: artist.name,
          ),
          _shareAction(host, path: '/artists/${artist.id}', title: artist.name),
          ?_discoverAction(host, artistMbid: artist.mbid, term: artist.name),
        ],
      ),
      MenuSection(
        id: 'report',
        items: [if (onReport != null) _reportAction(host, onReport)],
      ),
    ],
  );
}

// ── 6. a playlist ──────────────────────────────────────────────────────────────────────────────

@immutable
class PlaylistLike {
  const PlaylistLike({
    required this.id,
    required this.name,
    this.coverUrl,
    this.tracks,
  });

  final String id;
  final String name;
  final String? coverUrl;

  /// A loaded page passes its rows so Play, Queue and Download skip a round trip; a card omits them
  /// and the actions fetch on demand.
  final List<BrowseTrack>? tracks;
}

/// A playlist's actions — ONE definition for the card, the library row and the playlist page's ⋮.
///
/// The callbacks carry the surfaces only a host can open: the edit sheets and the two destructive
/// confirmations all need a context that outlives this menu, and the page is the only caller that
/// knows whether the reader owns the playlist or merely collaborates on it. A card passes none of
/// them and loses nothing it could have honoured; the page passes them all and stops being a second
/// menu that disagrees with the first.
EntityMenu playlistMenu(
  BuildContext page,
  WidgetRef ref,
  PlaylistLike playlist, {
  MenuNav? nav,

  /// Owner only: the name/description/visibility sheet.
  VoidCallback? onEditDetails,

  /// Owner only: the cover picker.
  VoidCallback? onEditCover,

  /// Owner or collaborator: who else can edit this.
  VoidCallback? onCollaborators,

  /// Editors only: enter the page's drag-reorder mode. Move up/down on a row works without it.
  VoidCallback? onReorder,

  /// Owner only, destructive.
  VoidCallback? onDelete,

  /// Collaborator only: leave a playlist somebody else owns.
  VoidCallback? onLeave,

  /// Opens this playlist's listening figures.
  ///
  /// A slot rather than a row this file builds itself, and the reason is the contract: a playlist
  /// is not an [EntityKind], so `/v1/insights/entity` — which is what [_statsAction] opens — cannot
  /// answer for one. Playlist figures come from `/v1/playlists/{id}/stats`, a different shape with
  /// its own me/everyone scope, and the surface that renders them is the host's. Absent until a
  /// host passes this, exactly as the web has it: a menu row must never navigate somewhere broken.
  VoidCallback? onStats,
}) {
  final host = MenuHost(page, ref, nav);
  final t = host.t;
  final pinned = _isPinned(ref, PinKind.playlist, playlist.id);
  final api = host.api;
  final known = playlist.tracks;
  final playContext = PlaylistContext(id: playlist.id, name: playlist.name);

  Future<List<BrowseTrack>> tracks() async =>
      known ??
      (api == null
          ? const []
          : host.load(() async => (await api.playlist(playlist.id)).tracks));

  return EntityMenu(
    target: MenuTarget(
      kind: MenuTargetKind.playlist,
      id: playlist.id,
      title: playlist.name,
      imageUrl: playlist.coverUrl,
    ),
    sections: [
      MenuSection(
        id: 'owner',
        items: [
          if (onEditDetails != null)
            MenuAction(
              id: 'edit-details',
              label: t(PlaylistsKeys.editTitle),
              icon: Icons.edit_outlined,
              onSelect: onEditDetails,
            ),
          if (onEditCover != null)
            MenuAction(
              id: 'edit-cover',
              label: t(PlaylistsKeys.editChoosePhoto),
              icon: Icons.image_outlined,
              onSelect: onEditCover,
            ),
          if (onCollaborators != null)
            MenuAction(
              id: 'collaborators',
              label: t(PlaylistsKeys.collaboratorsManage),
              icon: Icons.group_outlined,
              onSelect: onCollaborators,
            ),
          if (onReorder != null)
            MenuAction(
              id: 'reorder',
              label: t(PlaylistsKeys.reorderStart),
              icon: Icons.swap_vert_rounded,
              onSelect: onReorder,
            ),
        ],
      ),
      MenuSection(
        id: 'play',
        items: [
          MenuAction(
            id: 'play',
            label: t(CommonKeys.actionsPlay),
            icon: Icons.play_arrow_rounded,
            enabled: host.player != null && known?.isEmpty != true,
            onSelect: () async => host.play(await tracks(), playContext),
          ),
          MenuAction(
            id: 'queue',
            label: t(PlayerKeys.queueAdd),
            icon: Icons.queue_music_rounded,
            enabled: host.player != null && known?.isEmpty != true,
            onSelect: () async => host.enqueueAll(await tracks()),
          ),
          _radioAction(host, StationKind.playlist, playlist.id),
        ],
      ),
      MenuSection(
        id: 'collect',
        items: [
          _pinAction(
            host,
            pinned: pinned,
            kind: PinKind.playlist,
            id: playlist.id,
          ),
          if (known != null && known.isNotEmpty)
            MenuAction.custom(
              id: 'download',
              builder: (context, close) => DownloadMenuTile(
                tracks: known,
                label: t(LibraryKeys.downloadsActionDownloadPlaylist),
                onDone: close,
              ),
            )
          else
            MenuAction(
              id: 'download',
              label: t(LibraryKeys.downloadsActionDownloadPlaylist),
              icon: Icons.download_for_offline_outlined,
              enabled: api != null,
              onSelect: () async => host.save(await tracks()),
            ),
        ],
      ),
      MenuSection(
        id: 'navigate',
        items: [
          MenuAction(
            id: 'open',
            label: t(CommonKeys.actionsOpen),
            icon: Icons.queue_music_rounded,
            onSelect: () => host.nav.openScreen(
              (_) => PlaylistDetailScreen(playlistId: playlist.id),
            ),
          ),
          _shareAction(
            host,
            path: '/playlists/${playlist.id}',
            title: playlist.name,
          ),
          if (onStats != null)
            MenuAction(
              id: 'stats',
              label: t(InsightsKeys.entityTitle),
              icon: Icons.show_chart_rounded,
              onSelect: onStats,
            ),
        ],
      ),
      MenuSection(
        id: 'danger',
        items: [
          if (onDelete != null)
            MenuAction(
              id: 'delete',
              label: t(PlaylistsKeys.deleteTitle),
              icon: Icons.delete_outline_rounded,
              destructive: true,
              onSelect: onDelete,
            ),
          // Not the owner: leaving is the only way out, and offering "Delete" to somebody who
          // cannot delete is worse than not offering it.
          if (onLeave != null)
            MenuAction(
              id: 'leave',
              label: t(PlaylistsKeys.leaveTitle),
              icon: Icons.logout_rounded,
              destructive: true,
              onSelect: onLeave,
            ),
        ],
      ),
    ],
  );
}

// ── 7. a smart playlist ────────────────────────────────────────────────────────────────────────

/// At parity with a regular playlist, minus manual ordering — the order is the rules' answer.
///
/// What it adds is the pair only it has: a snapshot that can be rebuilt on demand, and a rule set
/// that can be edited. Both arrive as callbacks for the reason the playlist's do — only the host
/// knows whether the sheet they open is the reader's to open.
EntityMenu smartPlaylistMenu(
  BuildContext page,
  WidgetRef ref,
  PlaylistLike playlist, {
  MenuNav? nav,

  /// Owner only: the rules-and-details sheet.
  VoidCallback? onEdit,

  /// Owner only: rebuild the snapshot now.
  VoidCallback? onRefresh,

  /// Owner only, destructive.
  VoidCallback? onDelete,

  /// This playlist's listening figures — see [playlistMenu]'s `onStats` for why it is a slot.
  VoidCallback? onStats,
}) {
  final host = MenuHost(page, ref, nav);
  final t = host.t;
  final pinned = _isPinned(ref, PinKind.playlist, playlist.id);
  final api = host.api;
  final known = playlist.tracks;
  final playContext = SmartPlaylistContext(
    id: playlist.id,
    name: playlist.name,
  );

  Future<List<BrowseTrack>> tracks() async =>
      known ??
      (api == null
          ? const []
          : host.load(
              () async => (await api.smartPlaylist(playlist.id)).tracks,
            ));

  return EntityMenu(
    target: MenuTarget(
      // `playlist`, not a kind of its own: the header names and pictures the thing, and for that
      // purpose a smart playlist is a playlist.
      kind: MenuTargetKind.playlist,
      id: playlist.id,
      title: playlist.name,
      imageUrl: playlist.coverUrl,
    ),
    sections: [
      MenuSection(
        id: 'owner',
        items: [
          if (onEdit != null)
            MenuAction(
              id: 'edit',
              label: t(PlaylistsKeys.smartEditTitle),
              icon: Icons.edit_outlined,
              onSelect: onEdit,
            ),
          if (onRefresh != null)
            MenuAction(
              id: 'refresh',
              label: t(PlaylistsKeys.smartRefreshAction),
              icon: Icons.refresh_rounded,
              onSelect: onRefresh,
            ),
        ],
      ),
      MenuSection(
        id: 'play',
        items: [
          MenuAction(
            id: 'play',
            label: t(CommonKeys.actionsPlay),
            icon: Icons.play_arrow_rounded,
            enabled: host.player != null && known?.isEmpty != true,
            onSelect: () async => host.play(await tracks(), playContext),
          ),
          MenuAction(
            id: 'queue',
            label: t(PlayerKeys.queueAdd),
            icon: Icons.queue_music_rounded,
            enabled: host.player != null && known?.isEmpty != true,
            onSelect: () async => host.enqueueAll(await tracks()),
          ),
          _radioAction(host, StationKind.playlist, playlist.id),
        ],
      ),
      MenuSection(
        id: 'collect',
        items: [
          // Pinned as a `playlist`: there is no smart pin kind, and the pin only has to reach a
          // page both kinds have.
          _pinAction(
            host,
            pinned: pinned,
            kind: PinKind.playlist,
            id: playlist.id,
          ),
          // A snapshot is a track list like any other, so it downloads like one — the same two
          // shapes the regular playlist uses: the loaded page's rows go straight to the download
          // tile, and a card fetches them first.
          if (known != null && known.isNotEmpty)
            MenuAction.custom(
              id: 'download',
              builder: (context, close) => DownloadMenuTile(
                tracks: known,
                label: t(LibraryKeys.downloadsActionDownloadPlaylist),
                onDone: close,
              ),
            )
          else
            MenuAction(
              id: 'download',
              label: t(LibraryKeys.downloadsActionDownloadPlaylist),
              icon: Icons.download_for_offline_outlined,
              enabled: api != null && known?.isEmpty != true,
              onSelect: () async => host.save(await tracks()),
            ),
        ],
      ),
      MenuSection(
        id: 'navigate',
        items: [
          MenuAction(
            id: 'open',
            label: t(CommonKeys.actionsOpen),
            icon: Icons.auto_awesome_rounded,
            onSelect: () => host.nav.openScreen(
              (_) => SmartPlaylistScreen(playlistId: playlist.id),
            ),
          ),
          _shareAction(
            host,
            path: '/smart/${playlist.id}',
            title: playlist.name,
          ),
          if (onStats != null)
            MenuAction(
              id: 'stats',
              label: t(InsightsKeys.entityTitle),
              icon: Icons.show_chart_rounded,
              onSelect: onStats,
            ),
        ],
      ),
      MenuSection(
        id: 'danger',
        items: [
          if (onDelete != null)
            MenuAction(
              id: 'delete',
              label: t(PlaylistsKeys.deleteTitle),
              icon: Icons.delete_outline_rounded,
              destructive: true,
              onSelect: onDelete,
            ),
        ],
      ),
    ],
  );
}

// ── 8. a genre ─────────────────────────────────────────────────────────────────────────────────

EntityMenu genreMenu(
  BuildContext page,
  WidgetRef ref, {
  required String slug,
  required String name,
  List<BrowseTrack>? tracks,
  MenuNav? nav,
}) {
  final host = MenuHost(page, ref, nav);
  final t = host.t;
  final rows = tracks ?? const <BrowseTrack>[];

  return EntityMenu(
    target: MenuTarget(kind: MenuTargetKind.genre, id: slug, title: name),
    sections: [
      MenuSection(
        id: 'play',
        items: [
          if (rows.isNotEmpty)
            MenuAction(
              id: 'play',
              label: t(CommonKeys.actionsPlay),
              icon: Icons.play_arrow_rounded,
              enabled: host.player != null,
              // The same context the genre page itself plays with: a genre is not one of the
              // queue's own kinds, and inventing one would write a slug into the append-only
              // listening-events table under a kind that means something else.
              onSelect: () =>
                  host.play(rows, LibraryContext(id: slug, name: name)),
            ),
          // A genre station is seeded by the SLUG, not an id.
          _radioAction(host, StationKind.genre, slug),
        ],
      ),
      MenuSection(
        id: 'navigate',
        items: [
          MenuAction(
            id: 'open',
            label: t(CommonKeys.actionsOpen),
            icon: Icons.category_rounded,
            onSelect: () => host.nav.goToGenre(slug),
          ),
          _shareAction(host, path: '/genres/$slug', title: name),
        ],
      ),
    ],
  );
}

// ── 9. a record label ──────────────────────────────────────────────────────────────────────────

EntityMenu labelMenu(
  BuildContext page,
  WidgetRef ref, {
  required String labelId,
  required String name,
  String? logoUrl,
  MenuNav? nav,
}) {
  final host = MenuHost(page, ref, nav);
  final t = host.t;

  return EntityMenu(
    target: MenuTarget(
      kind: MenuTargetKind.label,
      id: labelId,
      title: name,
      imageUrl: logoUrl,
    ),
    sections: [
      MenuSection(
        id: 'navigate',
        items: [
          MenuAction(
            id: 'open',
            label: t(CommonKeys.actionsOpen),
            icon: Icons.business_rounded,
            onSelect: () => host.nav.goToLabel(labelId),
          ),
          _shareAction(host, path: '/labels/$labelId', title: name),
        ],
      ),
    ],
  );
}

// ── 10. a daily mix / station ──────────────────────────────────────────────────────────────────

@immutable
class MixLike {
  const MixLike({
    required this.seedArtistId,
    required this.title,
    this.subtitle,
    this.imageUrl,
  });

  final String seedArtistId;
  final String title;
  final String? subtitle;
  final String? imageUrl;
}

/// A daily mix. It plays through its seed artist's station, which is what generated it.
EntityMenu mixMenu(
  BuildContext page,
  WidgetRef ref,
  MixLike mix, {
  MenuNav? nav,
}) {
  final host = MenuHost(page, ref, nav);
  final t = host.t;
  final api = host.api;

  return EntityMenu(
    target: MenuTarget(
      kind: MenuTargetKind.mix,
      id: mix.seedArtistId,
      title: mix.title,
      subtitle: mix.subtitle,
      imageUrl: mix.imageUrl,
    ),
    sections: [
      MenuSection(
        id: 'play',
        items: [
          MenuAction(
            id: 'play',
            label: t(CommonKeys.actionsPlay),
            icon: Icons.play_arrow_rounded,
            enabled: host.player != null && api != null,
            onSelect: () async {
              if (api == null) return;
              final detail = await host.load(
                () async => (await api.dailyMix(mix.seedArtistId)).tracks,
              );
              host.play(
                detail,
                RadioContext(
                  id: mix.seedArtistId,
                  name: mix.title,
                  stationKind: sync.StationKind.artist,
                ),
              );
            },
          ),
          _radioAction(host, StationKind.artist, mix.seedArtistId),
        ],
      ),
      MenuSection(
        id: 'navigate',
        items: [
          MenuAction(
            id: 'go-to-artist',
            label: t(CommonKeys.actionsGoToArtist),
            icon: Icons.person_outline_rounded,
            onSelect: () => host.nav.goToArtist(mix.seedArtistId),
          ),
          _shareAction(
            host,
            path: '/artists/${mix.seedArtistId}',
            title: mix.title,
          ),
        ],
      ),
    ],
  );
}

// ── 11. a library ──────────────────────────────────────────────────────────────────────────────

/// A library's actions, for its card and for the player's "playing from".
///
/// [onShare] is the grant flow — handing a friend access to this library — and is a different thing
/// from the `share` row, which copies a link to it. [onMoveUp] / [onMoveDown] are the whole reason
/// the web moved reordering in here: it used to be hover-only icon buttons, so a touch reader had
/// no route to it at all.
EntityMenu libraryMenu(
  BuildContext page,
  WidgetRef ref, {
  required String libraryId,
  required String name,
  bool owned = false,
  MenuNav? nav,
  VoidCallback? onManage,
  VoidCallback? onShare,
  VoidCallback? onMoveUp,
  VoidCallback? onMoveDown,
  VoidCallback? onRemove,
}) {
  final host = MenuHost(page, ref, nav);
  final t = host.t;

  return EntityMenu(
    target: MenuTarget(
      kind: MenuTargetKind.library,
      id: libraryId,
      title: name,
    ),
    sections: [
      MenuSection(
        id: 'navigate',
        items: [
          MenuAction(
            id: 'open',
            label: t(CommonKeys.actionsOpen),
            icon: Icons.folder_open_rounded,
            onSelect: () => host.nav.openScreen(
              (_) => LibraryDetailScreen(libraryId: libraryId, owned: owned),
            ),
          ),
          if (onManage != null)
            MenuAction(
              id: 'edit',
              label: t(CommonKeys.actionsEdit),
              icon: Icons.tune_rounded,
              onSelect: onManage,
            ),
          _shareAction(host, path: '/library/$libraryId', title: name),
        ],
      ),
      MenuSection(
        id: 'owner',
        items: [
          if (onShare != null)
            MenuAction(
              id: 'share-with-friend',
              label: t(LibraryKeys.cardShareTitle),
              icon: Icons.person_add_alt_rounded,
              onSelect: onShare,
            ),
          if (onMoveUp != null)
            MenuAction(
              id: 'move-up',
              label: t(LibraryKeys.cardMoveUp),
              icon: Icons.arrow_upward_rounded,
              onSelect: onMoveUp,
            ),
          if (onMoveDown != null)
            MenuAction(
              id: 'move-down',
              label: t(LibraryKeys.cardMoveDown),
              icon: Icons.arrow_downward_rounded,
              onSelect: onMoveDown,
            ),
        ],
      ),
      MenuSection(
        id: 'danger',
        items: [
          if (onRemove != null)
            MenuAction(
              id: 'remove',
              label: t(CommonKeys.actionsRemove),
              icon: Icons.delete_outline_rounded,
              destructive: true,
              onSelect: onRemove,
            ),
        ],
      ),
    ],
  );
}

// ── 12. the liked songs ────────────────────────────────────────────────────────────────────────

/// The one collection with no id: everything the listener has hearted.
EntityMenu likedSongsMenu(
  BuildContext page,
  WidgetRef ref, {
  required String name,
  MenuNav? nav,
}) {
  final host = MenuHost(page, ref, nav);
  final t = host.t;

  return EntityMenu(
    target: MenuTarget(kind: MenuTargetKind.playlist, id: 'liked', title: name),
    sections: [
      MenuSection(
        id: 'navigate',
        items: [
          MenuAction(
            id: 'open',
            label: t(CommonKeys.actionsOpen),
            icon: Icons.favorite_rounded,
            onSelect: () => host.nav.openScreen((_) => const LikedScreen()),
          ),
        ],
      ),
    ],
  );
}

// ── 13. a pinned station ───────────────────────────────────────────────────────────────────────

/// A radio pin: the artist station somebody kept.
///
/// The thirteenth, and the one kind the web has no menu for — its sidebar pin row offers Unpin and
/// the layout editor, because a desktop reader reaches the station itself by clicking the row and
/// everything else about it from the artist's page. The phone shows pins in exactly one place, the
/// Quick access shelf, so the station's own actions have nowhere else to live.
///
/// Pinned as [PinKind.radio] and not [PinKind.artist]: the Hub stores them as two separate pins of
/// the same seed, and unpinning the wrong kind would leave the pill sitting on the shelf.
EntityMenu radioPinMenu(
  BuildContext page,
  WidgetRef ref, {
  required String seedArtistId,
  required String name,
  String? imageUrl,
  MenuNav? nav,
}) {
  final host = MenuHost(page, ref, nav);
  final t = host.t;
  final pinned = _isPinned(ref, PinKind.radio, seedArtistId);

  return EntityMenu(
    target: MenuTarget(
      kind: MenuTargetKind.mix,
      id: seedArtistId,
      title: name,
      imageUrl: imageUrl,
      // Round, as the pill draws it: a station's artwork is its seed artist's.
      round: true,
    ),
    sections: [
      MenuSection(
        id: 'play',
        items: [_radioAction(host, StationKind.artist, seedArtistId)],
      ),
      MenuSection(
        id: 'collect',
        items: [
          _pinAction(
            host,
            pinned: pinned,
            kind: PinKind.radio,
            id: seedArtistId,
          ),
        ],
      ),
      MenuSection(
        id: 'navigate',
        items: [
          MenuAction(
            id: 'go-to-artist',
            label: t(CommonKeys.actionsGoToArtist),
            icon: Icons.person_outline_rounded,
            onSelect: () => host.nav.goToArtist(seedArtistId),
          ),
          // The artist, not the station: `shareUrlFor` resolves against the frontend's public
          // redirect stubs, and there is no stub for a station.
          _shareAction(host, path: '/artists/$seedArtistId', title: name),
        ],
      ),
    ],
  );
}
