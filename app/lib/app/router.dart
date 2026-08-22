import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/auth_routes.dart';
import '../features/auth/forgot_password_screen.dart';
import '../features/auth/register_screen.dart';
import '../features/auth/resolving_screen.dart';
import '../features/auth/sign_in_screen.dart';
import '../features/auth/two_factor_screen.dart';
import '../features/home/home_screen.dart';
import '../features/library/library_screen.dart';
import '../features/search/search_screen.dart';
import '../features/you/you_screen.dart';
import 'providers.dart';
import 'shell.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

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
      return onGate ? '/home' : null;
    },
    routes: [
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
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home',
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/search',
                builder: (context, state) => const SearchScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/library',
                builder: (context, state) => const LibraryScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/you',
                builder: (context, state) => const YouScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

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
