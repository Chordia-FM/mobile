import 'dart:convert';

import 'package:chordia_api/chordia_api.dart';

import 'secret_store.dart';

/// Sessions kept in the platform keystore, one record per hub.
///
/// **Only the refresh token is written down.** It is the long-lived credential — the one thing
/// that can mint new access tokens for as long as the server honours it — so it belongs in the
/// keystore and nowhere else. The access token is short-lived and is re-derived from the refresh
/// token on the first request after launch, so persisting it would add a second copy of a
/// credential to disk and buy one saved round trip an hour.
///
/// That is why [read] hands back a session whose access token is empty and already expired:
/// `SessionManager` sees a session that needs refreshing, refreshes once, and the app is signed in
/// — which is exactly the path a token that expired while the app was closed takes anyway.
class SecureSessionStore implements SessionStore {
  const SecureSessionStore(this._secrets);

  /// Per-hub, because signing out of one hub must not disturb another — and because two hubs hold
  /// two unrelated accounts whose tokens must never be confusable.
  static const keyPrefix = 'chordia_auth::';

  static String keyFor(String hubId) => '$keyPrefix$hubId';

  final SecretStore _secrets;

  @override
  Future<Session?> read(String hubId) async {
    final raw = await _secrets.read(keyFor(hubId));
    if (raw == null) return null;
    final refresh = _refreshTokenOf(raw);
    if (refresh == null) {
      // A record written by an incompatible build, or a truncated write. Treat it as no session
      // rather than as a corrupt one: the user signs in again, which always works.
      await _secrets.delete(keyFor(hubId));
      return null;
    }
    return Session(accessToken: '', refreshToken: refresh, expiresAt: 0);
  }

  @override
  Future<void> write(String hubId, Session session) => _secrets.write(
    keyFor(hubId),
    jsonEncode({'refresh_token': session.refreshToken}),
  );

  @override
  Future<void> clear(String hubId) => _secrets.delete(keyFor(hubId));

  static String? _refreshTokenOf(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final token = decoded['refresh_token'];
      return token is String && token.isNotEmpty ? token : null;
    } on FormatException {
      return null;
    }
  }
}
