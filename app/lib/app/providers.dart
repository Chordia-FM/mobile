import 'dart:async';
import 'dart:io';

import 'package:chordia_api/chordia_api.dart';
import 'package:chordia_net/chordia_net.dart';
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
import '../data/secret_store.dart';
import '../data/session_store.dart';
import '../i18n/translations_provider.dart';

/// `appConfigProvider` and `translationsProvider` were declared alongside the catalogs; they are
/// re-exported so a screen needs one import for "the app's providers" rather than two.
export '../i18n/translations_provider.dart'
    show appConfigProvider, translationsProvider;

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

/// Adds, removes and switches hubs, keeping the stored registry and the in-memory one in step.
class HubsController extends AsyncNotifier<HubRegistrySnapshot> {
  @override
  Future<HubRegistrySnapshot> build() => ref.watch(hubRegistryProvider).list();

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
