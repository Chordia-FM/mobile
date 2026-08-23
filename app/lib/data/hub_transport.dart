import 'package:chordia_api/chordia_api.dart';
import 'package:chordia_net/chordia_net.dart';

/// Reads a JSON object, failing at the value that surprised us.
///
/// The generated models' own coercions are library-private, and every decode in this layer wants
/// the same one line, so it lives here rather than being spelled out at each call site.
Map<String, Object?> jsonObject(Object? value) => value is Map
    ? value.cast<String, Object?>()
    : throw JsonShapeException('an object', value);

/// Runs [body] against a Hub client that carries no session at all.
///
/// Two calls need this and both would be wrong with an ordinary client. Probing an address asks
/// "is this a Chordia Hub" before any account here exists to authenticate with. And refreshing
/// carries its credential in the body, so a client that tried to attach a bearer token would have
/// to ask the very `SessionManager` that is waiting on the answer — a cycle, and one that would
/// deadlock the first request after launch.
Future<T> withBareHubClient<T>(
  Uri baseUrl,
  PinnedHttpClientFactory factory,
  Future<T> Function(HubClient hub) body,
) async {
  final client = HubClient(
    baseUrl: baseUrl,
    sessions: SessionManager(
      hubId: 'anonymous',
      store: MemorySessionStore(),
      refresher: (_) => throw StateError('an anonymous client cannot refresh'),
    ),
    factory: factory,
  );
  try {
    return await body(client);
  } finally {
    client.close();
  }
}

/// Trades a refresh token for a fresh pair. This is `SessionManager.refresher`.
///
/// Refresh tokens rotate and are single-use, which `SessionManager` already serialises; this
/// function's only job is the round trip. A thrown [ApiException] is how it says the token is
/// gone for good, which is the signal that ends the session.
Future<Session> refreshSession({
  required Uri baseUrl,
  required PinnedHttpClientFactory factory,
  required String refreshToken,
}) => withBareHubClient(baseUrl, factory, (hub) async {
  final pair = await hub.post<TokenPair>(
    '/v1/auth/refresh',
    (json) => TokenPair.fromJson(jsonObject(json)),
    body: RefreshRequest(refreshToken: refreshToken).toJson(),
    authenticated: false,
  );
  return Session(
    accessToken: pair.accessToken,
    refreshToken: pair.refreshToken,
    expiresAt: pair.accessExpiresAt,
  );
});
