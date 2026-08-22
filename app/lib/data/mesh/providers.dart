/// The mesh, wired into the app.
library;

import 'dart:async';

// The whole surface, not a `show`: `myNowPlaying` is an extension method, and a show clause
// hides extensions along with everything else it does not name.
import 'package:chordia_api/chordia_api.dart';
import 'package:chordia_sync/chordia_sync.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../app/providers.dart';
import '../../features/catalog/data/catalog_providers.dart' as catalog;
import '../../features/home/data/home_feed.dart' as home;
import '../../features/library/data/library_providers.dart' as lib;
import '../../i18n/keys.g.dart';
import 'mesh_connection.dart';
import 'mesh_playback.dart';
import 'mirror.dart';
import 'realtime_bus.dart';
import 'realtime_socket.dart';

/// This app process's mesh identity.
///
/// Minted per launch and deliberately NOT persisted: the mesh's unit is a client instance — a
/// browser tab on the web, this process here — because that is what owns an engine and therefore
/// what playback can move to. A relaunched app is a new engine. The stable per-install identity is
/// [deviceIdProvider], which is what the picker uses to tell "this phone" from "some other phone".
final playerSyncTabIdProvider = Provider<String>((ref) => const Uuid().v4());

/// What the other devices call this one.
///
/// The same string the now-playing report carries, and that is load-bearing rather than tidy: the
/// picker falls back to the Hub's last-known report when a device's socket has dropped, and two
/// different names for one phone would read as two phones.
final meshDeviceLabelProvider = Provider<String>(
  (ref) => ref.watch(translationsProvider)(PlayerKeys.devicesMobileApp),
);

/// This device's membership of the mesh.
///
/// Built without a link and without handlers; [meshConnectionProvider] attaches the pipe and
/// [meshPlaybackProvider] installs the player. Until both exist this is a mesh of one, which is
/// exactly the state a signed-out app should be in.
final playerSyncControllerProvider = Provider<PlayerSyncController>((ref) {
  final controller = PlayerSyncController(
    tabId: ref.watch(playerSyncTabIdProvider),
    deviceLabel: ref.watch(meshDeviceLabelProvider),
    deviceId: ref.watch(deviceIdProvider),
  );
  ref.onDispose(() => unawaited(controller.dispose()));
  return controller;
});

/// Binds the mesh to this device's engine, queue and media session.
final meshPlaybackProvider = Provider<MeshPlayback>((ref) {
  final playback = MeshPlayback(
    controller: ref.watch(playerSyncControllerProvider),
    handler: ref.watch(audioHandlerProvider),
    queue: ref.watch(queueControllerProvider),
    engine: ref.watch(playbackEngineProvider),
  )..start();
  ref.onDispose(() => unawaited(playback.dispose()));
  return playback;
});

/// Where the socket's view-refresh pushes land.
final realtimeEventBusProvider = Provider<RealtimeEventBus>((ref) {
  final bus = RealtimeEventBus();
  ref.onDispose(() => unawaited(bus.dispose()));
  return bus;
});

/// Opens the realtime socket. Overridden in tests with a scripted pipe.
final realtimeSocketOpenerProvider = Provider<RealtimeSocketOpener>(
  (ref) => ioRealtimeSocketOpener(ref.watch(httpClientFactoryProvider)),
);

/// The live connection to the Hub's realtime socket, or null when there is nothing to connect to.
///
/// Rebuilt when the hub or the session changes, which is what makes a hub switch move this device
/// onto the other Hub's mesh rather than leaving it talking to the previous one.
final meshConnectionProvider = Provider<MeshConnection?>((ref) {
  final hub = ref.watch(activeHubProvider);
  final sessions = ref.watch(sessionManagerProvider);
  final signedIn = ref.watch(authControllerProvider).isSignedIn;
  if (hub == null || sessions == null || !signedIn) return null;

  // Read, not watched: the binding installs itself on the controller and does not need this
  // provider to rebuild when the player changes underneath it.
  ref.read(meshPlaybackProvider);

  final connection = MeshConnection(
    controller: ref.watch(playerSyncControllerProvider),
    bus: ref.watch(realtimeEventBusProvider),
    baseUrl: hub.url,
    // Goes through the session manager rather than holding a token: asking inside its refresh skew
    // is what rotates the credential, and a rotation is what tells the connection to reopen.
    accessToken: sessions.freshAccessToken,
    open: ref.watch(realtimeSocketOpenerProvider),
  );
  unawaited(connection.start());
  ref.onDispose(() => unawaited(connection.stop()));
  return connection;
});

/// The mesh's shared view, as a value the UI can watch.
final meshStateProvider = StreamProvider<PlayerSyncState>((ref) {
  // Building the connection here rather than in the shell keeps the mesh alive for as long as
  // anything is watching it, and closes the socket when nothing is.
  ref.watch(meshConnectionProvider);
  final controller = ref.watch(playerSyncControllerProvider);
  // `states` deliberately does not replay its current value, so it is seeded by hand — a picker
  // that stayed empty until the next heartbeat would read as broken. Seeded AFTER subscribing, so
  // a change landing in between is not the one that goes missing.
  final seeded = StreamController<PlayerSyncState>();
  final subscription = controller.states.listen(seeded.add);
  seeded.add(controller.state);
  ref.onDispose(() {
    unawaited(subscription.cancel());
    unawaited(seeded.close());
  });
  return seeded.stream;
});

/// What another device is playing, when one is.
final mirrorStateProvider = Provider<MirrorState>((ref) {
  final controller = ref.watch(playerSyncControllerProvider);
  final mesh = ref.watch(meshStateProvider).value;
  return mesh == null
      ? MirrorState.idle
      : MirrorState.of(mesh, controller.tabId);
});

/// Every transport action, routed to whichever device is playing.
final meshTransportProvider = Provider<MeshTransport>(
  (ref) => MeshTransport(
    controller: ref.watch(playerSyncControllerProvider),
    local: ref.watch(playerActionsProvider),
  ),
);

/// The Hub's last-known now-playing entry, for the picker's offline fallback.
///
/// Not redundant with the live mesh. A phone drops its socket the moment the OS freezes it — which
/// is precisely when somebody is listening with the screen off and looking at another device —
/// while the Hub's entry stands for about twelve minutes. Listing it, plainly marked out of reach,
/// beats a picker that has silently forgotten the device playing the music.
final remoteNowPlayingProvider = FutureProvider.autoDispose<DeviceNowPlaying?>((
  ref,
) async {
  final hub = ref.watch(hubClientProvider);
  if (hub == null) return null;
  return hub.myNowPlaying();
});

/// Which providers a server push should invalidate.
///
/// Deliberately a small explicit table rather than a blanket refresh: a `catalog` push arrives
/// every twenty seconds for as long as an enrichment worker has a backlog, and "refetch
/// everything" at that rate is how a phone's battery disappears. Anything not named here is a kind
/// this client has no screen for yet, and dropping it costs nothing.
void _invalidateFor(Ref ref, String key) {
  switch (key) {
    case 'liked':
      ref.invalidate(catalog.likedTrackIdsProvider);
    case 'playlists':
      ref
        ..invalidate(lib.playlistsProvider)
        ..invalidate(lib.smartPlaylistsProvider)
        ..invalidate(catalog.playlistsProvider);
    case 'catalog':
      ref
        ..invalidate(home.homeFeedProvider)
        ..invalidate(lib.recentAlbumsProvider)
        ..invalidate(lib.catalogArtistsProvider);
    case 'plays':
      ref.invalidate(catalog.trackStatsProvider);
    case 'billing':
      ref.invalidate(userSettingsProvider);
    default:
      // `playlist:<id>` and anything newer. The playlist lists are the only thing this client
      // renders from a playlist push today, and refreshing them is both correct and cheap.
      if (key.startsWith('playlist:')) {
        ref
          ..invalidate(lib.playlistsProvider)
          ..invalidate(catalog.playlistsProvider);
      }
  }
}

/// Keeps open screens in step with the Hub.
///
/// Watched once, by the app shell: it has no value of its own and exists only for the subscription
/// it holds. Reaching down into the feature providers from here is the deliberate direction — the
/// alternative is every feature growing its own socket listener, and then nobody can say what a
/// `catalog` push actually refetches.
final meshRefreshProvider = Provider<void>((ref) {
  final subscription = ref
      .watch(realtimeEventBusProvider)
      .keys
      .listen((key) => _invalidateFor(ref, key));
  ref.onDispose(subscription.cancel);
  // The bus is fed by the connection, so watching it here is what keeps the socket open for as
  // long as the shell is mounted.
  ref.watch(meshConnectionProvider);
});
