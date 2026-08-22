import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/foundation.dart';

import 'hub_transport.dart';

/// What `POST /v1/auth/login` answered.
///
/// The endpoint returns one of two shapes under the same 200, so the caller has to look before it
/// decodes. Modelled as a union rather than a nullable field so no screen can forget the second
/// branch: a `switch` that omits one does not compile.
@immutable
sealed class LoginOutcome {
  const LoginOutcome();
}

/// Credentials were enough. There is a session to adopt.
@immutable
final class LoginAuthenticated extends LoginOutcome {
  const LoginAuthenticated(this.response);

  final AuthResponse response;
}

/// The account has a second factor. [mfaToken] is the short-lived challenge to redeem at
/// `POST /v1/auth/2fa/verify` together with a TOTP or recovery code.
@immutable
final class LoginMfaRequired extends LoginOutcome {
  const LoginMfaRequired(this.mfaToken);

  final String mfaToken;
}

/// Reads the login union.
///
/// Kept as a free function, isolated from everything else here, because `chordia_api` is expected
/// to grow a typed `LoginOutcome` of its own. When it does, this file deletes these three
/// declarations and re-exports the package's — no call site changes.
LoginOutcome readLoginOutcome(Object? json) {
  final map = jsonObject(json);
  if (map['mfa_required'] != true) {
    return LoginAuthenticated(AuthResponse.fromJson(map));
  }
  final token = map['mfa_token'];
  if (token is! String || token.isEmpty) {
    throw JsonShapeException('an mfa_token', token);
  }
  return LoginMfaRequired(token);
}

/// Every credential exchange with one Hub.
///
/// The repository owns adopting a session as well as obtaining one: a caller that got an
/// [AuthResponse] and forgot to store it would leave the app holding tokens it never used, so
/// there is no path here that returns tokens without persisting them.
class AuthRepository {
  const AuthRepository({required this.hub, required this.sessions});

  final HubClient hub;
  final SessionManager sessions;

  Future<LoginOutcome> login({
    required String email,
    required String password,
    bool remember = true,
  }) async {
    final outcome = await hub.post<LoginOutcome>(
      '/v1/auth/login',
      readLoginOutcome,
      body: LoginRequest(
        email: email,
        password: password,
        remember: remember,
      ).toJson(),
      authenticated: false,
    );
    if (outcome is LoginAuthenticated) await adopt(outcome.response);
    return outcome;
  }

  Future<AuthResponse> verifyMfa({
    required String mfaToken,
    required String code,
  }) => _authenticating(
    '/v1/auth/2fa/verify',
    MfaVerifyBody(code: code, mfaToken: mfaToken).toJson(),
  );

  Future<AuthResponse> register({
    required String email,
    required String handle,
    required String displayName,
    required String password,
  }) => _authenticating(
    '/v1/auth/register',
    RegisterRequest(
      displayName: displayName,
      email: email,
      handle: handle,
      password: password,
    ).toJson(),
  );

  /// Redeems the one-time code the browser handed back. See `BrowserHandoff`.
  Future<AuthResponse> exchangeDesktopCode({
    required String code,
    required String verifier,
  }) => _authenticating(
    '/v1/auth/desktop/exchange',
    DesktopExchangeRequest(code: code, verifier: verifier).toJson(),
  );

  /// Asks for a reset email. Always succeeds as far as the client can tell — the Hub does not
  /// reveal whether an account exists, and neither does this screen.
  Future<void> requestPasswordReset(String email) => hub.post<void>(
    '/v1/auth/password-reset/request',
    (_) {},
    body: EmailBody(email: email).toJson(),
    authenticated: false,
  );

  /// Revokes the session server-side, then drops it locally.
  ///
  /// The local half runs even when the network call fails. A user who taps sign out on a plane
  /// must end up signed out; the server-side token expires on its own schedule regardless.
  Future<void> signOut() async {
    final refreshToken = sessions.current?.refreshToken;
    if (refreshToken != null && refreshToken.isNotEmpty) {
      try {
        await hub.post<void>(
          '/v1/auth/logout',
          (_) {},
          body: RefreshRequest(refreshToken: refreshToken).toJson(),
          // The refresh token in the body is the credential; a bearer here would make the call
          // wait on a refresh of the very session being thrown away.
          authenticated: false,
        );
      } on ApiException {
        // Already revoked, expired, or unreachable. All three mean the same thing locally.
      }
    }
    await sessions.signOut();
  }

  /// Stores the tokens from an [AuthResponse] as the live session.
  Future<void> adopt(AuthResponse response) => sessions.adopt(
    Session(
      accessToken: response.tokens.accessToken,
      refreshToken: response.tokens.refreshToken,
      expiresAt: response.tokens.accessExpiresAt,
    ),
  );

  Future<AuthResponse> _authenticating(
    String path,
    Map<String, Object?> body,
  ) async {
    final response = await hub.post<AuthResponse>(
      path,
      (json) => AuthResponse.fromJson(jsonObject(json)),
      body: body,
      authenticated: false,
    );
    await adopt(response);
    return response;
  }
}
