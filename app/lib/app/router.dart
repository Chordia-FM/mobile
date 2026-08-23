import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/admin/admin_routes.dart';
import '../features/auth/auth_routes.dart';
import '../features/auth/forgot_password_screen.dart';
import '../features/auth/register_screen.dart';
import '../features/auth/resolving_screen.dart';
import '../features/auth/sign_in_screen.dart';
import '../features/auth/two_factor_screen.dart';
import '../data/playback/playback_errors.dart';
import '../features/catalog/catalog_routes.dart';
import '../features/home/data/discovery_nav.dart';
import '../features/home/home_screen.dart';
import '../features/libraries/libraries_routes.dart';
import '../features/library/library_screen.dart';
import '../features/manager/manager_routes.dart';
import '../features/nav/insights_tab.dart';
import '../features/nav/nav_routes.dart';
import '../features/nav/nav_tabs.dart';
import '../features/playlists/playlists_routes.dart';
import '../features/search/search_screen.dart';
import '../features/settings/settings_routes.dart';
import '../features/social/social_routes.dart';
import 'providers.dart';
import 'shell.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

/// The screens every tab can reach.
///
/// Spread into all four branches rather than into the one tab that "owns" each screen, because
/// the links between them do not respect that ownership: the Home feed links to profiles and
/// playlists, an album links to its artist, a station links to its tracks. A screen registered
/// under one branch only is reachable from one tab only — and pushing it from any other lands on
/// GoRouter's error page, which is exactly what every "Made for you" card used to do.
///
/// The nav drawer is the second reason the list is this complete: every entry in it pushes onto the
/// CURRENT tab, so Friends, All libraries, Genres, Labels, Settings, the Manager and Admin have to
/// resolve from all four. That is also what keeps the removal of the old "You" tab from orphaning
/// anything — the screens it used to hold hang off every tab now, rather than off it.
List<RouteBase> _sharedRoutes() => [
  ...catalogRoutes(),
  ...socialRoutes(),
  ...discoveryRoutes(),
  ...librariesRoutes(),
  ...playlistsRoutes(),
  ...settingsRoutes(),
  ...managerRoutes(),
  ...adminRoutes(),
  ...insightsTabRoutes(),
  ...navRoutes(),
];

/// The app's routes.
///
/// A `StatefulShellRoute` gives each tab its own navigation stack, so switching tabs and coming
/// back lands where you left — the behaviour people expect from a music app, where you browse an
/// artist, jump to search, and return.
///
/// The auth screens sit outside that shell: they have no tabs, no player, and no business keeping
/// a navigation stack across a sign-out.
GoRouter buildRouter() {
  final refresh = _AuthRefresh();
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: AuthRoutes.splash,
    refreshListenable: refresh,
    redirect: (context, state) {
      // The container comes from the context rather than being passed in, because `ChordiaApp`
      // builds this router with no arguments — rebuilding a `GoRouter` throws away every
      // navigation stack, so it is built once and cannot be handed a `Ref` that changes.
      final container = ProviderScope.containerOf(context, listen: false);
      refresh.attach(container);

      final auth = container.read(authControllerProvider);
      final location = state.matchedLocation;

      final onGate =
          AuthRoutes.isAuthScreen(location) || location == AuthRoutes.splash;

      // "Still reading the keystore" is not "signed out". Sending somebody to a sign-in form here
      // is what makes an app look like it forgot them between launches.
      //
      // Somebody already standing on an auth screen stays there: adding a server re-resolves the
      // session, and bouncing them through the splash would remount the form and throw away the
      // email they had just typed.
      if (auth.isResolving) return onGate ? null : AuthRoutes.splash;
      if (!auth.isSignedIn) {
        return AuthRoutes.isAuthScreen(location) ? null : AuthRoutes.signIn;
      }
      if (onGate) return NavTab.home.path;
      // A link somebody shared speaks the web client's URL vocabulary, not this one's. Translating
      // it here rather than registering a second route table means every screen stays reachable by
      // one path and the App Link picks up whatever gets added later for free.
      return webLocationToTabLocation(state.uri);
    },
    routes: [
      // The bare root, which nothing inside the app links to and the platform can still hand us:
      // an App Link to the site's origin, or a restored route from before a location was set.
      // Without it a signed-in listener arriving at `/` falls through the redirect above — `/` is
      // neither an auth screen nor the splash, so it is left alone — and lands on the error page.
      GoRoute(path: '/', redirect: (context, state) => AuthRoutes.splash),
      GoRoute(
        path: AuthRoutes.splash,
        builder: (context, state) => const ResolvingScreen(),
      ),
      GoRoute(
        path: AuthRoutes.signIn,
        builder: (context, state) => const SignInScreen(),
        routes: [
          GoRoute(
            path: 'two-factor',
            // The challenge token travels in `extra`, which does not survive a restore or a deep
            // link. Landing here without one means there is no challenge to answer, so the only
            // honest destination is the start of the flow.
            redirect: (context, state) =>
                state.extra is String ? null : AuthRoutes.signIn,
            builder: (context, state) =>
                TwoFactorScreen(mfaToken: state.extra! as String),
          ),
        ],
      ),
      GoRoute(
        path: AuthRoutes.register,
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: AuthRoutes.forgotPassword,
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      StatefulShellRoute.indexedStack(
        // The failure reporter wraps the shell rather than the player, so a track that dies
        // while the listener is browsing an artist still says so. It draws nothing until
        // something fails.
        builder: (context, state, shell) =>
            PlaybackErrorReporter(child: AppShell(shell: shell)),
        // One branch per [NavTab], in [NavTab]'s order: the shell indexes straight into it.
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: NavTab.home.path,
                builder: (context, state) => const HomeScreen(),
                // The shared screens hang off every tab that can reach them rather than living in
                // one place, so each tab keeps its own back stack: opening an album from Search
                // and switching to Library must not drop you into Search's history on the way
                // back.
                routes: _sharedRoutes(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: NavTab.search.path,
                builder: (context, state) => const SearchScreen(),
                routes: _sharedRoutes(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: NavTab.library.path,
                builder: (context, state) => const LibraryScreen(),
                routes: _sharedRoutes(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                // The web's `/app/insights` redirects to `/app/u/{handle}`: your own report IS your
                // own profile, banner and all. This lands there directly — see
                // `features/nav/insights_tab.dart`. There is no separate stats screen, and no "You"
                // tab: neither exists on the web, and inventing them is what made this app's
                // navigation somebody's idea rather than the product's.
                path: NavTab.insights.path,
                builder: (context, state) => const OwnProfileScreen(),
                routes: _sharedRoutes(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

/// The web client's shareable path shapes, minus the `/app/…` ones this handles wholesale.
///
/// `shareUrl()` in the web client drops the `/app` prefix from every copied link — "the prefix is an
/// internal routing detail and it is the noisiest part of the URL" — and serves the short form from
/// redirect stubs under `src/routes/_authed/{artists,albums,playlists,genres,labels,tracks,smart}/`,
/// plus `u/` for a profile. So `chordia.dev/albums/{id}` is the form people actually paste.
///
/// None of these collide with a tab root ([NavTab.path]), which is what makes the translation below
/// unambiguous. `library` is deliberately absent for that reason: it is this client's Library TAB
/// and the web's server directory, two different pages wearing one word.
const _webShortLinkSections = {
  'albums',
  'artists',
  'genres',
  'labels',
  'playlists',
  'smart',
  'tracks',
  'u',
};

/// The handful of web paths whose destination here is a TAB rather than a screen inside one.
const _webTabAliases = <String, String>{
  // `/app` itself.
  '': '/home',
  'search': '/search',
  'insights': '/insights',
  // The web's Library tab is the server directory it labels `nav.allLibraries`; this client spells
  // that `libraries` and gives the word "Library" to its collections hub instead.
  'library': '/home/libraries',
};

/// Translates a link written in the web client's URL vocabulary into this client's, or null when
/// the location is already one of ours.
///
/// Every shareable Chordia destination is a `/app/…` path or one of the short forms above, while
/// every path here is prefixed by the tab it is being read in — so the two clients share no URL
/// vocabulary at all, and an App Link with no translation opens the app onto GoRouter's error page.
/// That is strictly worse than having no App Link, which at least opens the browser onto the page.
///
/// The Home tab receives everything that is not a tab of its own. It is the tab a cold launch is
/// already standing in, so a shared link never throws away a stack the listener was reading.
@visibleForTesting
String? webLocationToTabLocation(Uri uri) {
  final segments = uri.pathSegments;
  if (segments.isEmpty) return null;

  final List<String> rest;
  if (segments.first == 'app') {
    rest = segments.sublist(1);
  } else if (_webShortLinkSections.contains(segments.first)) {
    rest = segments;
  } else {
    return null;
  }

  if (rest.length <= 1) {
    final alias = _webTabAliases[rest.isEmpty ? '' : rest.first];
    if (alias != null) return _withQuery(alias, uri);
  }
  return _withQuery('${NavTab.home.path}/${rest.join('/')}', uri);
}

/// Carries a link's query string across the rewrite. Nothing in the route table reads one today,
/// and dropping it silently is the sort of thing that is only noticed once something does.
String _withQuery(String path, Uri uri) =>
    uri.hasQuery ? '$path?${uri.query}' : path;

/// Re-runs the router's redirect when sign-in state changes.
///
/// [attach] is idempotent and called from the redirect because that is the first place a
/// `ProviderContainer` is in reach. It has to be wired before the app finishes reading the
/// keystore, which it is: the first redirect runs while that read is still in flight.
class _AuthRefresh extends ChangeNotifier {
  ProviderSubscription<AuthState>? _subscription;

  void attach(ProviderContainer container) {
    _subscription ??= container.listen<AuthState>(
      authControllerProvider,
      (_, _) => notifyListeners(),
    );
  }

  @override
  void dispose() {
    _subscription?.close();
    super.dispose();
  }
}
