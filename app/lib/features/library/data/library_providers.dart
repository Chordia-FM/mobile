import 'package:chordia_api/chordia_api.dart';
import 'package:chordia_db/open.dart';
import 'package:chordia_sync/chordia_sync.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import 'library_api.dart';

/// The on-device database.
///
/// Declared here because the Library tab is the first screen that needs it; it belongs in
/// `app/lib/app/providers.dart` beside the other app-wide seams as soon as a second feature reads
/// it, and moving it there is a cut-and-paste with no call-site changes.
final chordiaDatabaseProvider = Provider<ChordiaDatabase>((ref) {
  final database = openChordiaDatabase();
  ref.onDispose(database.close);
  return database;
});

/// The index of audio held on this device.
final downloadsDaoProvider = Provider<DownloadsDao>(
  (ref) => ref.watch(chordiaDatabaseProvider).downloadsDao,
);

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
final smartPlaylistProvider = FutureProvider.autoDispose
    .family<SmartPlaylistDetail, String>(
      (ref, id) => _viaHub(ref, (hub) => hub.smartPlaylist(id)),
    );

final pinsProvider = FutureProvider<List<PinnedItem>>(
  (ref) => _viaHub(ref, (hub) => hub.pins()),
);

final myLibrariesProvider = FutureProvider<List<LibrarySummary>>(
  (ref) => _viaHub(ref, (hub) => hub.libraries()),
);

final sharedLibrariesProvider = FutureProvider<List<LibrarySummary>>(
  (ref) => _viaHub(ref, (hub) => hub.librariesSharedWithMe()),
);

/// Where a library server is reachable and whether it answered its last heartbeat.
///
/// Keyed by server id rather than library id because one paired machine can host several
/// libraries, and resolving it once per library would ask the same question four times.
final serverStatusProvider = FutureProvider.family<ResolvedServer, String>(
  (ref, serverId) => _viaHub(ref, (hub) => hub.resolveServer(serverId)),
);

final libraryDetailProvider = FutureProvider.family<LibrarySummary, String>(
  (ref, libraryId) => _viaHub(ref, (hub) => hub.libraryDetail(libraryId)),
);

/// Who the owner has given access to. Only the owner may ask, so this is not read on a library
/// that is merely shared with the viewer.
final librarySharesProvider = FutureProvider.family<List<LibraryShare>, String>(
  (ref, libraryId) => _viaHub(ref, (hub) => hub.libraryShares(libraryId)),
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
