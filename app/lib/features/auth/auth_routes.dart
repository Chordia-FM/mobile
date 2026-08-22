/// The auth screens' paths.
///
/// Constants rather than literals because three places have to agree on them: the route table, the
/// buttons that navigate between the screens, and the router's redirect — which decides whether a
/// location is one a signed-out person is allowed to be at.
abstract final class AuthRoutes {
  static const signIn = '/sign-in';

  /// Nested under [signIn] so the redirect's "is this an auth screen" test stays a prefix match.
  static const twoFactor = '/sign-in/two-factor';

  static const register = '/register';
  static const forgotPassword = '/forgot-password';

  /// Shown while the keystore is still being read, so nobody is bounced to a sign-in form for a
  /// session the app simply has not finished loading yet.
  static const splash = '/splash';

  /// Every location a signed-out person may stay at.
  static const all = [signIn, register, forgotPassword];

  static bool isAuthScreen(String location) =>
      all.any((route) => location == route || location.startsWith('$route/'));
}
