import 'package:meta/meta.dart';

import '../hub.dart';
import '../json.dart';
import '../models.g.dart';
import 'decode.dart';

/// What `POST /v1/auth/login` answered.
///
/// The Hub serialises this as an **untagged** union: either the ordinary [AuthResponse], or a
/// challenge `{ mfa_required: true, mfa_token }` with no tokens in it at all. The OpenAPI document
/// declares only the first shape, so a client that trusts the schema decodes a 2FA challenge as a
/// malformed [AuthResponse] and reports a parse error where the user should have been asked for a
/// code. Sealing it here forces every call site to handle the branch the spec forgot.
@immutable
sealed class LoginOutcome {
  const LoginOutcome();

  /// The challenge carries no `tokens` key, which is what separates the two shapes on the wire.
  /// `mfa_required` is probed rather than the absence of `tokens`, so a future field cannot make a
  /// challenge look like a success.
  static LoginOutcome fromJson(Object? json) {
    final body = asObject(json);
    if (body['mfa_required'] == true) {
      return LoginNeedsMfa(asString(body['mfa_token']));
    }
    return LoginSucceeded(AuthResponse.fromJson(body));
  }
}

/// Signed in: tokens and profile in hand.
@immutable
class LoginSucceeded extends LoginOutcome {
  const LoginSucceeded(this.auth);

  final AuthResponse auth;
}

/// The password was right, but the account has 2FA on.
///
/// [mfaToken] is a short-lived challenge id, not a session token — it authorises exactly one call
/// to [AuthEndpoints.verifyMfa] and nothing else, so it must never be stored as a session.
@immutable
class LoginNeedsMfa extends LoginOutcome {
  const LoginNeedsMfa(this.mfaToken);

  final String mfaToken;
}

/// The start of TOTP enrollment.
///
/// Hand-written because the Hub's response struct is local to its auth handler rather than declared
/// in `contracts`, so the OpenAPI document describes this 200 as having no body at all and the
/// generator emits nothing for it.
@immutable
class TotpSetup {
  const TotpSetup({
    required this.secret,
    required this.otpauthUrl,
    required this.qrSvg,
  });

  factory TotpSetup.fromJson(Map<String, Object?> json) => TotpSetup(
    secret: asString(json['secret']),
    otpauthUrl: asString(json['otpauth_url']),
    qrSvg: asString(json['qr_svg']),
  );

  /// Base32, for someone typing it into an authenticator by hand.
  final String secret;

  /// The `otpauth://` URI the QR encodes.
  final String otpauthUrl;

  /// The QR as inline SVG markup — not an image URL, so it renders offline.
  final String qrSvg;
}

/// Signing in, signing out, and everything that proves who the caller is.
///
/// The calls that establish a session pass `authenticated: false`: they run before there is a token
/// to send, and asking the session manager for one would trigger a pointless refresh (or, mid
/// sign-out, resurrect a session that is being torn down).
extension AuthEndpoints on HubClient {
  /// Exchanges credentials for a session, or for a 2FA challenge — see [LoginOutcome].
  Future<LoginOutcome> login(LoginRequest request) => post(
    '/v1/auth/login',
    LoginOutcome.fromJson,
    body: request.toJson(),
    authenticated: false,
  );

  Future<AuthResponse> register(RegisterRequest request) => post(
    '/v1/auth/register',
    (json) => AuthResponse.fromJson(asObject(json)),
    body: request.toJson(),
    authenticated: false,
  );

  /// Rotates a refresh token for a fresh pair.
  ///
  /// `SessionManager` normally owns this — refresh tokens are single-use, so two callers racing to
  /// spend one kills the session. Use this directly only where no session manager exists yet.
  Future<TokenPair> refreshTokens(RefreshRequest request) => post(
    '/v1/auth/refresh',
    (json) => TokenPair.fromJson(asObject(json)),
    body: request.toJson(),
    authenticated: false,
  );

  /// Revokes one refresh token server-side. A no-op on a token the Hub has already forgotten, so
  /// the client can always clear its own state afterwards.
  Future<void> logout(RefreshRequest request) => post<void>(
    '/v1/auth/logout',
    discard,
    body: request.toJson(),
    authenticated: false,
  );

  /// Signs every device out, including this one.
  Future<void> logoutEverywhere() => post<void>('/v1/auth/logout-all', discard);

  Future<List<SessionInfo>> authSessions() =>
      get('/v1/auth/sessions', (json) => listOf(json, SessionInfo.fromJson));

  Future<void> revokeAuthSession(String sessionId) =>
      delete('/v1/auth/sessions/$sessionId');

  /// Begins TOTP enrollment: the Hub stores a pending secret and hands back what to display.
  /// Nothing is active until [enableTotp] confirms a code from it.
  Future<TotpSetup> beginTotpSetup() =>
      post('/v1/auth/2fa/setup', (json) => TotpSetup.fromJson(asObject(json)));

  /// Confirms enrollment and turns 2FA on. Returns the recovery codes, which the Hub shows **once**
  /// — they are hashed on its side and cannot be re-read.
  Future<List<String>> enableTotp(CodeBody code) => post(
    '/v1/auth/2fa/enable',
    (json) => stringsOf(asObject(json)['recovery_codes']),
    body: code.toJson(),
  );

  Future<void> disableTotp(CodeBody code) =>
      post<void>('/v1/auth/2fa/disable', discard, body: code.toJson());

  /// Completes a login that stopped at [LoginNeedsMfa], redeeming the challenge for real tokens.
  Future<AuthResponse> verifyMfa(MfaVerifyBody body) => post(
    '/v1/auth/2fa/verify',
    (json) => AuthResponse.fromJson(asObject(json)),
    body: body.toJson(),
    authenticated: false,
  );

  Future<void> changePassword(ChangePasswordRequest request) =>
      post<void>('/v1/auth/password/change', discard, body: request.toJson());

  /// Emails a password-set link to an account that has none (Discord-only sign-ups). Those accounts
  /// are excluded from the public reset flow, so this is their only route to a password.
  Future<void> requestPasswordSet() =>
      post<void>('/v1/auth/password/set-request', discard);

  /// Always succeeds, whether or not the address has an account — the response must not reveal
  /// which.
  Future<void> requestPasswordReset(EmailBody email) => post<void>(
    '/v1/auth/password-reset/request',
    discard,
    body: email.toJson(),
    authenticated: false,
  );

  /// Sets a new password from an emailed token, revoking every existing session.
  Future<void> confirmPasswordReset(ResetConfirm request) => post<void>(
    '/v1/auth/password-reset/confirm',
    discard,
    body: request.toJson(),
    authenticated: false,
  );

  Future<void> requestEmailVerification() =>
      post<void>('/v1/auth/verify-email/request', discard);

  Future<void> confirmEmailVerification(TokenBody token) => post<void>(
    '/v1/auth/verify-email/confirm',
    discard,
    body: token.toJson(),
    authenticated: false,
  );

  /// Starts a change of the login address. The change only lands once the new inbox confirms it.
  Future<void> requestEmailChange(EmailBody email) => post<void>(
    '/v1/auth/email-change/request',
    discard,
    body: email.toJson(),
  );

  Future<void> confirmEmailChange(TokenBody token) => post<void>(
    '/v1/auth/email-change/confirm',
    discard,
    body: token.toJson(),
    authenticated: false,
  );

  /// Lends the desktop app the session this client already holds, as a one-time code.
  Future<DesktopAuthorizeResponse> authorizeDesktop(
    DesktopAuthorizeRequest request,
  ) => post(
    '/v1/auth/desktop/authorize',
    (json) => DesktopAuthorizeResponse.fromJson(asObject(json)),
    body: request.toJson(),
  );

  /// Trades that one-time code (plus the PKCE verifier) for a session of its own.
  Future<AuthResponse> exchangeDesktopCode(DesktopExchangeRequest request) =>
      post(
        '/v1/auth/desktop/exchange',
        (json) => AuthResponse.fromJson(asObject(json)),
        body: request.toJson(),
        authenticated: false,
      );
}
