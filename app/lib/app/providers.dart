import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:chordia_api/chordia_api.dart';
// `Hub` here is the drift row for a paired server; the app's own `Hub` in `data/hub.dart` is
// the one every screen speaks, and the registry still keeps hubs in the keystore.
import 'package:chordia_db/chordia_db.dart' hide Hub;
import 'package:chordia_net/chordia_net.dart';
import 'package:chordia_player/chordia_player.dart';
// `PlaybackState` is audio_service's here; chordia_sync's namesake describes the mesh and is not
// what any provider below publishes.
import 'package:chordia_sync/chordia_sync.dart' hide PlaybackState;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/art/art_cache.dart';
import '../data/auth_repository.dart';
import '../data/browser_handoff.dart';
import '../data/hub.dart';
import '../data/hub_probe.dart';
import '../data/hub_registry.dart';
import '../data/hub_transport.dart';
import '../data/playback/auto_browse_source.dart';
import '../data/playback/eq.dart';
import '../data/playback/notification_art.dart';
import '../data/playback/playback_service.dart';
import '../data/playback/player_state.dart';
import '../data/playback/quality.dart';
import '../data/playback/routed_grants.dart';
import '../data/playback/source_resolver.dart';
import '../data/secret_store.dart';
import '../data/session_store.dart';
import '../i18n/keys.g.dart';
import '../i18n/translations_provider.dart';

/// `appConfigProvider` and `translationsProvider` were declared alongside the catalogs; they are
/// re-exported so a screen needs one import for "the app's providers" rather than two.
export '../i18n/translations_provider.dart'
    show appConfigProvider, translationsProvider;

/// The playback vocabulary the providers below publish, re-exported for the same reason.
export '../data/playback/playback_service.dart'
    show PlaybackPreferences, PlaybackService;
export '../data/playback/player_state.dart' show PlayerActions, PlayerSnapshot;
export '../data/playback/quality.dart' show NetworkStatus, effectiveQuality;

/// The platform keystore. Overridden in tests with `MemorySecretStore`.
final secretStoreProvider = Provider<SecretStore>(
  (ref) => const KeystoreSecretStore(),
);

/// The one place Chordia opens a socket. Shared across hubs: it holds no per-host state beyond the
/// last pin mismatch, and building one per request would throw away every keep-alive connection.
final httpClientFactoryProvider = Provider<PinnedHttpClientFactory>(
  (ref) => PinnedHttpClientFactory(userAgent: 'Chordia-Mobile'),
);

/// Where the known hubs live.
///
/// **This is the seam.** `chordia_db` is growing a `hubs` table; swapping this line for
/// `DriftHubRegistry(ref.watch(databaseProvider))` moves every hub off the keystore blob without
/// touching a provider, a screen, or the router.
final hubRegistryProvider = Provider<HubRegistry>(
  (ref) => SecretsHubRegistry(ref.watch(secretStoreProvider)),
);

/// Sessions in the keystore, keyed per hub.
final sessionStoreProvider = Provider<SessionStore>(
  (ref) => SecureSessionStore(ref.watch(secretStoreProvider)),
);

/// The known hubs and which one is active.
final hubsProvider = AsyncNotifierProvider<HubsController, HubRegistrySnapshot>(
  HubsController.new,
);

/// The hub the app is pointed at, or null on a first launch.
final activeHubProvider = Provider<Hub?>(
  (ref) => ref.watch(hubsProvider).value?.active,
);

/// Resolves a typed address to a hub. Refuses cleartext unless this build allows it.
final hubProbeProvider = Provider<HubProbe>(
  (ref) => HubProbe.over(
    ref.watch(httpClientFactoryProvider),
    allowInsecureHubs: ref.watch(appConfigProvider).allowInsecureHubs,
  ),
);

/// The live session for the active hub. Null when there is no hub to have a session with.
final sessionManagerProvider = Provider<SessionManager?>((ref) {
  final hub = ref.watch(activeHubProvider);
  if (hub == null) return null;
  final factory = ref.watch(httpClientFactoryProvider);
  final manager = SessionManager(
    hubId: hub.id,
    store: ref.watch(sessionStoreProvider),
    // Not through `hubClientProvider`: that client asks this manager for a token, so wiring it
    // here would close a cycle around the first request after launch.
    refresher: (refreshToken) => refreshSession(
      baseUrl: hub.url,
      factory: factory,
      refreshToken: refreshToken,
    ),
  );
  ref.onDispose(manager.dispose);
  return manager;
});

/// The client every Hub call goes through.
final hubClientProvider = Provider<HubClient?>((ref) {
  final hub = ref.watch(activeHubProvider);
  final sessions = ref.watch(sessionManagerProvider);
  if (hub == null || sessions == null) return null;
  final client = HubClient(
    baseUrl: hub.url,
    sessions: sessions,
    factory: ref.watch(httpClientFactoryProvider),
    // Server-side problem titles come back in the language the app is showing.
    acceptLanguage: () => ref.read(translationsProvider).locale,
  );
  ref.onDispose(client.close);
  return client;
});

/// Artwork, fetched once at a width the Hub derives and then read off disk.
///
/// Deliberately not scoped to the active hub: covers are content-addressed, so the same hash is
/// the same image whichever server served it, and re-downloading a shared cover after a hub switch
/// would be waste.
final artCacheProvider = Provider<ArtCache>((ref) {
  return ArtCache(
    directory: getApplicationCacheDirectory().then(
      (base) => Directory('${base.path}${Platform.pathSeparator}art'),
    ),
    fetch: (sha256, width) async {
      final hub = ref.read(hubClientProvider);
      if (hub == null) throw const ArtMissingException('no active hub');
      try {
        return Uint8List.fromList(await hub.imageBytes(sha256, width: width));
      } on ApiException catch (e) {
        // A 404 is an answer, not a failure: this entity has no artwork, and the cache remembers
        // that so a grid of art-less albums does not re-ask on every scroll.
        if (e.isNotFound) throw ArtMissingException(sha256);
        rethrow;
      }
    },
  );
});

/// Capability tokens for library servers.
final grantManagerProvider = Provider<GrantManager?>((ref) {
  final hub = ref.watch(hubClientProvider);
  return hub == null ? null : GrantManager(hub: hub);
});

/// Credential exchanges with the active hub.
final authRepositoryProvider = Provider<AuthRepository?>((ref) {
  final hub = ref.watch(hubClientProvider);
  final sessions = ref.watch(sessionManagerProvider);
  if (hub == null || sessions == null) return null;
  return AuthRepository(hub: hub, sessions: sessions);
});

/// Deep links from the OS. Overridden in tests.
final deepLinkSourceProvider = Provider<DeepLinkSource>(
  (ref) => AppLinksDeepLinkSource(),
);

/// The browser sign-in handoff for the active hub.
final browserHandoffProvider = Provider<BrowserHandoff?>((ref) {
  final hub = ref.watch(activeHubProvider);
  final repository = ref.watch(authRepositoryProvider);
  if (hub == null || repository == null) return null;
  return BrowserHandoff(
    hubId: hub.id,
    exchange: repository.exchangeDesktopCode,
    secrets: ref.watch(secretStoreProvider),
    links: ref.watch(deepLinkSourceProvider),
    launcher: (url) => launchUrl(url, mode: LaunchMode.externalApplication),
  );
});

/// Whether the app has somebody signed in, and to what.
final authControllerProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);

// ── on-device storage ─────────────────────────────────────────────────────────────────────────

/// The drift database. Overridden in `bootstrap`, which opens it before the first frame because
/// the audio service can be started into a process that never builds a widget.
final databaseProvider = Provider<ChordiaDatabase>(
  (ref) => throw StateError('databaseProvider must be overridden in bootstrap'),
);

final downloadsDaoProvider = Provider<DownloadsDao>(
  (ref) => ref.watch(databaseProvider).downloadsDao,
);

final scrobbleQueueDaoProvider = Provider<ScrobbleQueueDao>(
  (ref) => ref.watch(databaseProvider).scrobbleQueueDao,
);

final kvDaoProvider = Provider<KvDao>(
  (ref) => ref.watch(databaseProvider).kvDao,
);

/// This install's opaque device id, minted once and kept.
///
/// One per app install, never per screen or per session: the Hub uses it only so a client can tell
/// its own now-playing report from another of the user's devices, and a fresh id each launch would
/// make one phone look like a growing crowd.
final deviceIdProvider = Provider<String>(
  (ref) => throw StateError('deviceIdProvider must be overridden in bootstrap'),
);

/// Directory the partial-stream cache writes into. Overridden in `bootstrap`: the path comes from
/// an async platform call and [StreamCache] takes a resolved directory.
final audioCacheDirectoryProvider = Provider<Directory>(
  (ref) => throw StateError(
    'audioCacheDirectoryProvider must be overridden in bootstrap',
  ),
);

// ── network class ─────────────────────────────────────────────────────────────────────────────

/// The live interface list from the platform.
///
/// Seeded with an explicit `checkConnectivity` rather than relying on the change stream to open
/// with the current state, which it does not promise to do on every platform — and a player that
/// believes it is offline until the user next walks between networks would refuse to stream at all.
final connectivityProvider = StreamProvider<List<ConnectivityResult>>((
  ref,
) async* {
  final connectivity = Connectivity();
  yield await connectivity.checkConnectivity();
  yield* connectivity.onConnectivityChanged;
});

final networkStatusProvider = Provider<NetworkStatus>((ref) {
  final results = ref.watch(connectivityProvider).value;
  return results == null ? NetworkStatus.unknown : NetworkStatus.from(results);
});

// ── listener preferences ──────────────────────────────────────────────────────────────────────

/// The signed-in listener's settings, or null when nobody is signed in.
///
/// Errors are left on the `AsyncValue` rather than swallowed — a settings screen has to be able to
/// say the fetch failed. Playback reads `valueOrNull` and falls back to [PlaybackPreferences]'
/// defaults, which is the right behaviour for a phone that is simply offline.
final userSettingsProvider = FutureProvider<UserSettings?>((ref) async {
  final hub = ref.watch(hubClientProvider);
  if (hub == null || !ref.watch(authControllerProvider).isSignedIn) return null;
  return hub.settings();
});

final playbackPreferencesProvider = Provider<PlaybackPreferences>(
  (ref) => PlaybackPreferences.from(ref.watch(userSettingsProvider).value),
);

// ── the playback stack ────────────────────────────────────────────────────────────────────────

/// Capability tokens, for a consumer that outlives any one hub session.
///
/// The engine is built once at boot and never rebuilt, so it cannot hold the per-hub
/// [GrantManager] directly; see [RoutedGrantManager].
final playbackGrantsProvider = Provider<GrantManager>(
  (ref) => RoutedGrantManager(() => ref.read(grantManagerProvider)),
);

final streamCacheProvider = Provider<StreamCache>(
  (ref) => StreamCache(directory: ref.watch(audioCacheDirectoryProvider)),
);

/// The engine, built once for the life of the process.
///
/// Nothing here disposes it: [audioHandlerProvider] owns the whole stack's teardown, and disposing
/// the engine twice is not something just_audio survives.
final playbackEngineProvider = Provider<PlaybackEngine>(
  (ref) => JustAudioEngine(
    grants: ref.watch(playbackGrantsProvider),
    factory: ref.watch(httpClientFactoryProvider),
    cache: ref.watch(streamCacheProvider),
    equalizer: ref.watch(equalizerControllerProvider),
  ),
);

/// What a car head unit can browse.
///
/// Built even when nobody is signed in: Android Auto can start this app cold, and a source that
/// refuses to exist until a session loads would show an empty app to somebody whose downloads are
/// sitting right there on the device.
final autoBrowseProvider = Provider<AutoBrowse>((ref) {
  final t = ref.watch(translationsProvider).call;
  final art = ref.watch(artCacheProvider);
  return AutoBrowse(
    sections: [
      BrowseNode(
        id: BrowseId.section(BrowseId.home),
        title: t(CommonKeys.navHome),
      ),
      BrowseNode(
        id: BrowseId.section(BrowseId.library),
        title: t(CommonKeys.navLibrary),
      ),
      BrowseNode(
        id: BrowseId.section(BrowseId.downloads),
        title: t(LibraryKeys.downloadsTitle),
      ),
    ],
    source: HubAutoBrowseSource(
      hub: () => ref.read(hubClientProvider),
      downloads: ref.watch(downloadsDaoProvider),
      artFile: (sha, width) => art.file(sha, width: width),
      labels: AutoBrowseLabels(
        home: t(CommonKeys.navHome),
        library: t(CommonKeys.navLibrary),
        downloads: t(LibraryKeys.downloadsTitle),
        playlists: t(LibraryKeys.sidebarPlaylists),
        liked: t(LibraryKeys.likedTitle),
        recentlyAdded: t(DiscoveryKeys.shelfRecentlyAdded),
      ),
    ),
  );
});

/// The Android equaliser, and the one definition of how our curve becomes a device's bands.
///
/// The same function draws the curve on the EQ screen, so the picture and the sound cannot drift
/// apart. On iOS the controller reports itself unsupported and the screen says so rather than
/// pretending a curve is reaching the audio.
final equalizerControllerProvider = Provider<AndroidEqualizerController>((ref) {
  final controller = AndroidEqualizerController(mapCurve: deviceBandGains);
  // A curve stored on the account applies to a deck the moment it is built, so a listener who set
  // one on another device hears it on the first track here rather than the second.
  ref.listen(
    userSettingsProvider,
    (_, next) => unawaited(controller.apply(next.value?.eq)),
    fireImmediately: true,
  );
  return controller;
});

/// The queue. Also disposed by the handler rather than here.
final queueControllerProvider = Provider<QueueController>(
  (ref) => QueueController(),
);

/// The durable listening pipeline.
///
/// Built once and shared across hub switches on purpose: it holds the retry backoff, and the queue
/// it drains is a table on disk that does not belong to any one session either. The Hub client is
/// read per send rather than watched, so a switch changes where the next batch goes without
/// resetting how long the last failure said to wait.
final scrobbleServiceProvider = Provider<ScrobbleService>((ref) {
  return ScrobbleService(
    queue: ref.watch(scrobbleQueueDaoProvider),
    send: (events) async {
      final hub = ref.read(hubClientProvider);
      if (hub == null) {
        // Status 0 is the transport-failure code the service treats as retryable, which is what
        // "signed out for the moment" should be: the plays stay queued.
        throw const ApiException(
          status: 0,
          title: 'No hub session to deliver scrobbles to.',
          method: 'POST',
          path: '/v1/scrobbles:batch',
        );
      }
      return hub.submitScrobbles(ScrobbleBatch(events: events));
    },
    reportNowPlayingWith: (report) async =>
        ref.read(hubClientProvider)?.reportNowPlaying(report),
    deviceId: ref.watch(deviceIdProvider),
    deviceLabel: ref.watch(translationsProvider)(PlayerKeys.devicesMobileApp),
  );
});

/// Reads a track's measured loudness from the library holding it.
final loudnessReaderProvider = Provider<LoudnessReader>((ref) {
  final grants = ref.watch(playbackGrantsProvider);
  final factory = ref.watch(httpClientFactoryProvider);
  return (track) async {
    final client = LibraryClient(
      grant: await grants.forLibrary(track.libraryId),
      factory: factory,
    );
    try {
      return (await client.track(track.trackRef)).audio;
    } finally {
      client.close();
    }
  };
});

/// The media session: the notification, the lock screen, a headset button, a car head unit.
///
/// Handed to `AudioService.init` in `bootstrap`, so it must be built exactly once. Everything it
/// watches is itself built once; the two sinks reach the app's playback service through
/// `ref.read` at call time, which is what keeps this provider from depending on it.
final Provider<ChordiaAudioHandler> audioHandlerProvider = Provider((ref) {
  final handler = ChordiaAudioHandler(
    engine: ref.watch(playbackEngineProvider),
    controller: ref.watch(queueControllerProvider),
    resolveArt: notificationArtResolver(ref.watch(artCacheProvider)),
    onScrobble: (track, msPlayed) =>
        ref.read(playbackServiceProvider).onScrobble(track, msPlayed),
    onNowPlaying: (track) =>
        ref.read(playbackServiceProvider).onTrackStarted(track),
    browse: ref.watch(autoBrowseProvider),
  );
  // Disposes the engine and the queue with it.
  ref.onDispose(handler.dispose);
  return handler;
});

/// Everything around a track that is not the audio: which bytes, how loud, and when a play becomes
/// durable. Started from `bootstrap`.
final Provider<PlaybackService> playbackServiceProvider = Provider((ref) {
  final service = PlaybackService(
    handler: ref.watch(audioHandlerProvider),
    engine: ref.watch(playbackEngineProvider),
    queue: ref.watch(queueControllerProvider),
    resolver: SourceResolver(
      downloads: (trackId) => ref.read(downloadsDaoProvider).byTrack(trackId),
      quality: () => effectiveQuality(
        chosen: ref.read(playbackPreferencesProvider).quality,
        network: ref.read(networkStatusProvider),
      ),
    ),
    recordPlay:
        (
          track, {
          required startedAt,
          required msPlayed,
          context,
          source = PlaybackSource.ownLibrary,
        }) async {
          await ref
              .read(scrobbleServiceProvider)
              .record(
                track: track,
                startedAt: startedAt,
                msPlayed: msPlayed,
                context: context,
                source: source,
              );
        },
    flush: ({bool force = false}) async {
      await ref.read(scrobbleServiceProvider).flush(force: force);
    },
    reportNowPlaying: (track) =>
        ref.read(scrobbleServiceProvider).reportNowPlaying(track),
    readLoudness: (track) => ref.read(loudnessReaderProvider)(track),
    preferences: () => ref.read(playbackPreferencesProvider),
    network: () => ref.read(networkStatusProvider),
  );
  // Regaining a connection is one of the three flush triggers, and the only one the service cannot
  // observe for itself.
  ref.listen(
    networkStatusProvider,
    (_, next) => service.onNetworkChanged(next),
  );
  ref.onDispose(service.dispose);
  return service;
});

// ── what the player UI reads ──────────────────────────────────────────────────────────────────

/// Everything the player draws except the playhead.
final playerStateProvider =
    NotifierProvider<PlayerStateNotifier, PlayerSnapshot>(
      PlayerStateNotifier.new,
    );

/// The current entry, for the many widgets that need nothing else.
final currentTrackProvider = Provider<PlayerTrack?>(
  (ref) => ref.watch(playerStateProvider.select((s) => s.current)),
);

/// The playhead, sampled at the engine's 2 Hz and on every seek.
///
/// Separate from [playerStateProvider] precisely so it can be watched alone: a widget that reads
/// this rebuilds twice a second, and only the two that draw elapsed time should be doing that.
/// Publishing it inside the snapshot would re-lay-out the whole player at the same rate, which is
/// the thing that makes a player feel cheap.
final playerPositionProvider = StreamProvider<Duration>(
  (ref) => ref
      .watch(audioHandlerProvider)
      .playbackState
      // `updatePosition` is the last sample the engine reported, not an extrapolation from it —
      // the scrubber advances in the same steps the engine actually measured.
      .map((state) => state.updatePosition)
      .distinct(),
);

final playerActionsProvider = Provider<PlayerActions>(
  (ref) => PlayerActions(
    handler: ref.watch(audioHandlerProvider),
    queue: ref.watch(queueControllerProvider),
  ),
);

/// Folds the queue and the media session into one value the UI can draw.
///
/// Two sources, because neither alone is enough: the queue knows what is loaded, in what order and
/// with which modes, and the handler knows whether it is sounding. They are combined here rather
/// than in two providers so a widget cannot render a track from one and a transport state from the
/// other frame.
class PlayerStateNotifier extends Notifier<PlayerSnapshot> {
  /// Guards against the media session's replayed current value arriving during [build], before
  /// there is a `state` to assign to.
  bool _ready = false;

  bool _playing = false;
  bool _buffering = false;

  late QueueController _queue;

  /// Rebuilt only when the queue changes, so [PlayerSnapshot]'s equality can settle the common
  /// case — a playhead tick that changed nothing — on identity alone.
  List<PlayerTrack> _entries = const [];

  @override
  PlayerSnapshot build() {
    _ready = false;
    final handler = ref.watch(audioHandlerProvider);
    _queue = ref.watch(queueControllerProvider);
    _entries = List<PlayerTrack>.unmodifiable(_queue.queue);

    final subscriptions = <StreamSubscription<Object?>>[
      _queue.events.listen((_) {
        _entries = List<PlayerTrack>.unmodifiable(_queue.queue);
        _publish();
      }),
      handler.playbackState.listen((playback) {
        _playing = playback.playing;
        _buffering =
            playback.processingState == AudioProcessingState.loading ||
            playback.processingState == AudioProcessingState.buffering;
        _publish();
      }),
    ];
    ref.onDispose(() {
      for (final subscription in subscriptions) {
        unawaited(subscription.cancel());
      }
    });

    final initial = _compute();
    _ready = true;
    return initial;
  }

  void _publish() {
    if (!_ready) return;
    final next = _compute();
    if (next != state) state = next;
  }

  PlayerSnapshot _compute() => PlayerSnapshot(
    current: _queue.current,
    queue: _entries,
    currentIndex: _queue.currentIndex,
    playing: _playing,
    buffering: _buffering,
    shuffle: _queue.shuffle,
    repeat: _queue.repeat,
    sleepTimer: _queue.sleepTimer,
    context: _queue.context,
  );
}

/// Adds, removes and switches hubs, keeping the stored registry and the in-memory one in step.
class HubsController extends AsyncNotifier<HubRegistrySnapshot> {
  @override
  Future<HubRegistrySnapshot> build() async {
    final registry = ref.watch(hubRegistryProvider);
    final snapshot = await registry.list();
    if (snapshot.hubs.isNotEmpty || !await registry.isPristine()) {
      return snapshot;
    }

    // First launch: put the build's own hub in the list so somebody who just installed the app is
    // looking at a server rather than an empty picker.
    //
    // PROBED, exactly like one somebody adds by hand. A hub record is not just an address — it
    // carries the instance's name, whether Discord sign-in is offered, and the website address the
    // browser hand-off sends people to. Seeding a bare URL produces a hub that looks present and
    // then cannot do half of what the picker implies, which is worse than an empty picker.
    final url = Uri.tryParse(ref.watch(appConfigProvider).defaultHubUrl);
    if (url == null || url.host.isEmpty) {
      return snapshot;
    }
    try {
      final probed = await ref.read(hubProbeProvider).probe(url.toString());
      return await registry.add(
        Hub.discovered(
          url: probed.url,
          info: probed.info,
          addedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    } on Object {
      // Offline on a first launch, or a hub that is simply down. Nothing is stored: a half-formed
      // record would be indistinguishable from a real one and would keep the app from ever
      // learning the rest, whereas an empty picker invites the one action that fixes it.
      return snapshot;
    }
  }

  /// Records a hub that answered a probe, and makes it active.
  Future<void> addProbed(HubProbeResult result) => add(
    Hub.discovered(
      url: result.url,
      info: result.info,
      addedAt: DateTime.now().millisecondsSinceEpoch,
    ),
  );

  Future<void> add(Hub hub) async {
    state = AsyncData(await ref.read(hubRegistryProvider).add(hub));
  }

  /// Forgets a hub, along with the credentials held for it.
  ///
  /// The registry deliberately knows nothing about sessions, so clearing them is done here — and
  /// it must happen: a refresh token for a server the user has removed is a credential nobody
  /// expects the app to still be holding.
  Future<void> remove(String id) async {
    await ref.read(sessionStoreProvider).clear(id);
    state = AsyncData(await ref.read(hubRegistryProvider).remove(id));
  }

  Future<void> setActive(String id) async {
    state = AsyncData(await ref.read(hubRegistryProvider).setActive(id));
  }
}

/// Where the app is between "no idea yet" and "signed in".
enum AuthStatus {
  /// The registry or the stored session is still being read. Distinct from [signedOut]: sending
  /// somebody to a sign-in form because a keystore read had not landed yet is the bug that makes
  /// an app look like it forgot you.
  resolving,
  signedOut,
  signedIn,
}

@immutable
class AuthState {
  const AuthState({required this.status, this.hub, this.user});

  final AuthStatus status;

  /// The hub this state is about, so a screen can name it while signed out.
  final Hub? hub;

  /// Known only when this session was established in this run of the app; a session restored from
  /// the keystore carries tokens, not a profile.
  final UserProfile? user;

  bool get isSignedIn => status == AuthStatus.signedIn;
  bool get isResolving => status == AuthStatus.resolving;
}

class AuthController extends Notifier<AuthState> {
  /// Bumped on every [build]. Async work started by one build must not write state that belongs to
  /// the next — switching hubs mid-restore would otherwise land the old hub's answer on the new
  /// hub's screen.
  int _generation = 0;

  @override
  AuthState build() {
    final hubs = ref.watch(hubsProvider);
    final hub = ref.watch(activeHubProvider);
    final sessions = ref.watch(sessionManagerProvider);
    final generation = ++_generation;

    if (hub == null || sessions == null) {
      return hubs.isLoading
          ? const AuthState(status: AuthStatus.resolving)
          : const AuthState(status: AuthStatus.signedOut);
    }

    // Fires both when the user asks and when a refresh fails terminally — a session revoked from
    // another device looks exactly like the second one, and both have to land the app on sign-in.
    final subscription = sessions.onSignedOut.listen(
      (_) => _handleSignedOut(generation),
    );
    ref.onDispose(subscription.cancel);

    unawaited(_restore(generation, sessions, hub));
    return AuthState(status: AuthStatus.resolving, hub: hub);
  }

  /// Adopts a session the user has just established. The repository has already stored it.
  void completeSignIn(AuthResponse response) {
    state = AuthState(
      status: AuthStatus.signedIn,
      hub: ref.read(activeHubProvider),
      user: response.user,
    );
  }

  Future<void> signOut() async {
    final repository = ref.read(authRepositoryProvider);
    if (repository == null) {
      state = AuthState(status: AuthStatus.signedOut, hub: state.hub);
      return;
    }
    // State moves in the `onSignedOut` handler, so a sign-out the app did not initiate and one it
    // did take exactly the same path.
    await repository.signOut();
  }

  Future<void> _restore(
    int generation,
    SessionManager sessions,
    Hub hub,
  ) async {
    await sessions.load();
    if (generation != _generation) return;
    state = AuthState(
      status: sessions.isSignedIn ? AuthStatus.signedIn : AuthStatus.signedOut,
      hub: hub,
    );
  }

  void _handleSignedOut(int generation) {
    if (generation != _generation) return;
    // A capability token outlives the session that minted it, so a cached grant would let a
    // signed-out app keep streaming for the rest of that token's five minutes.
    ref.read(grantManagerProvider)?.clear();
    state = AuthState(status: AuthStatus.signedOut, hub: state.hub);
  }
}
