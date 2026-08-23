import 'package:chordia_api/chordia_api.dart';
import 'package:chordia_db/chordia_db.dart';
import 'package:chordia_sync/chordia_sync.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../libraries/data/libraries_api.dart';
import '../../libraries/data/libraries_providers.dart';
import '../../playlists/data/playlists_providers.dart';
import 'library_api.dart';

// The database and its DAOs live in `app/lib/app/providers.dart`, opened once in `bootstrap`.
// This feature deliberately declares neither: a second connection to the same file would have its
// own drift stream set, so a download finishing on one would never redraw a screen watching the
// other — and the two would look identical while doing it.

/// Everything downloaded, most recent first, kept live so a removal on this screen — or a
/// download finishing in the background — redraws without a manual refresh.
final downloadedTracksProvider = StreamProvider<List<DownloadedTrack>>(
  (ref) => ref.watch(downloadsDaoProvider).watchAll(),
);

/// How the library hands work to the parts of the app it does not own.
///
/// Playing a track needs the queue and the audio engine; opening an album or an artist needs the
/// catalog screens. Both arrive in later milestones, and neither belongs to this feature — so the
/// library states what it needs and the app supplies it. Until it is supplied the affordances
/// that would use it render disabled, which is the truthful state: the screen is finished, the
/// destination is not.
abstract interface class LibraryHandoff {
  /// Starts a queue of [tracks] at [startIndex]. [context] is the "Playing from …" back-link.
  Future<void> playTracks(
    List<BrowseTrack> tracks, {
    int startIndex,
    bool shuffle,
    PlayContext? context,
  });

  void openAlbum(BuildContext context, String albumId);

  void openArtist(BuildContext context, String artistId);

  /// A generated station, seeded by whatever [PinKind.radio] pinned.
  void openRadio(BuildContext context, String stationId);
}

/// Null until the playback and catalog milestones override it.
final libraryHandoffProvider = Provider<LibraryHandoff?>((ref) => null);

/// The Hub-backed playlist calls, or null while there is no signed-in hub.
final playlistApiProvider = Provider<PlaylistApi?>((ref) {
  final hub = ref.watch(hubClientProvider);
  return hub == null ? null : HubPlaylistApi(hub);
});

/// The Hub-backed pin calls, or null while there is no signed-in hub.
final pinsApiProvider = Provider<PinsApi?>((ref) {
  final hub = ref.watch(hubClientProvider);
  return hub == null ? null : HubPinsApi(hub);
});

final likedApiProvider = Provider<LikedApi?>((ref) {
  final hub = ref.watch(hubClientProvider);
  return hub == null ? null : HubLikedApi(hub);
});

/// Runs [call] against the active Hub, or fails loudly when there is none.
///
/// A screen inside the shell can only be reached while signed in, so a null client here is a
/// wiring mistake rather than a state to render — and an error is how it gets noticed.
Future<T> _viaHub<T>(Ref ref, Future<T> Function(HubClient hub) call) {
  final hub = ref.watch(hubClientProvider);
  if (hub == null) {
    throw StateError('no active hub — the library tab is behind the auth gate');
  }
  return call(hub);
}

final playlistsProvider = FutureProvider<List<Playlist>>(
  (ref) => _viaHub(ref, (hub) => hub.playlists()),
);

final smartPlaylistsProvider = FutureProvider<List<SmartPlaylist>>(
  (ref) => _viaHub(ref, (hub) => hub.smartPlaylists()),
);

/// One smart playlist's materialised snapshot. Auto-disposed: the rules resolve server-side on a
/// schedule, so a snapshot held from a previous visit is stale by construction.
///
/// Read through [smartPlaylistsApiProvider] rather than the hub directly, so the screen that shows
/// it and the menu that edits and deletes it are all driven by one fake in a test.
final smartPlaylistProvider = FutureProvider.autoDispose
    .family<SmartPlaylistDetail, String>((ref, id) async {
      final api = ref.watch(smartPlaylistsApiProvider);
      if (api == null) {
        throw StateError(
          'no active hub — the library tab is behind the auth gate',
        );
      }
      return api.detail(id);
    });

/// The pinned shelf, read through [pinsApiProvider] so a test can drive the shelf and its edits
/// through one fake rather than through a transport.
final pinsProvider = FutureProvider<List<PinnedItem>>((ref) async {
  final api = ref.watch(pinsApiProvider);
  if (api == null) {
    throw StateError('no active hub — the library tab is behind the auth gate');
  }
  return api.pins();
});

/// Everything about a library server goes through [librariesApiProvider] rather than the hub
/// client: one fake then drives the whole surface — the list, one library's page, its shares and
/// whether its server is answering — which is what makes "tapping this opens that" testable.
Future<T> _viaLibraries<T>(Ref ref, Future<T> Function(LibrariesApi api) call) {
  final api = ref.watch(librariesApiProvider);
  if (api == null) {
    throw StateError('no active hub — the library tab is behind the auth gate');
  }
  return call(api);
}

final myLibrariesProvider = FutureProvider<List<LibrarySummary>>(
  (ref) => _viaLibraries(ref, (api) => api.mine()),
);

final sharedLibrariesProvider = FutureProvider<List<LibrarySummary>>(
  (ref) => _viaLibraries(ref, (api) => api.sharedWithMe()),
);

/// Where a library server is reachable and whether it answered its last heartbeat.
///
/// Keyed by server id rather than library id because one paired machine can host several
/// libraries, and resolving it once per library would ask the same question four times.
final serverStatusProvider = FutureProvider.family<ResolvedServer, String>(
  (ref, serverId) => _viaLibraries(ref, (api) => api.resolveServer(serverId)),
);

final libraryDetailProvider = FutureProvider.family<LibrarySummary, String>(
  (ref, libraryId) => _viaLibraries(ref, (api) => api.detail(libraryId)),
);

/// Who the owner has given access to. Only the owner may ask, so this is not read on a library
/// that is merely shared with the viewer.
final librarySharesProvider = FutureProvider.family<List<LibraryShare>, String>(
  (ref, libraryId) => _viaLibraries(ref, (api) => api.shares(libraryId)),
);

/// Artists across every accessible library, or inside one when an id is given.
final catalogArtistsProvider =
    FutureProvider.family<List<BrowseArtist>, String?>(
      (ref, libraryId) =>
          _viaHub(ref, (hub) => hub.artists(libraryId: libraryId)),
    );

/// Albums that most recently appeared in the caller's libraries.
///
/// The Hub has no flat "every album" browse — this endpoint is capped at 50 server-side — so this
/// is deliberately presented as "recently added" rather than as a complete albums list.
final recentAlbumsProvider = FutureProvider<List<BrowseAlbum>>(
  (ref) => _viaHub(ref, (hub) => hub.recentlyAdded(limit: 50)),
);
