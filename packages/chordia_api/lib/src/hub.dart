import 'dart:io';

import 'package:chordia_net/chordia_net.dart';

import 'errors.dart';
import 'session.dart';
import 'transport.dart';

/// Talks to one Hub.
///
/// The Hub is a public host with an ordinary certificate, so this connection is validated against
/// the system trust store — unlike a library server, which is pinned. Every call carries the
/// session bearer token and the user's language, so server-side error titles come back translated.
class HubClient {
  HubClient({
    required this.baseUrl,
    required this.sessions,
    required PinnedHttpClientFactory factory,
    String Function()? acceptLanguage,
  }) : _factory = factory,
       _acceptLanguage = acceptLanguage,
       _transport = JsonTransport(client: factory.unpinned(), factory: factory);

  final Uri baseUrl;
  final SessionManager sessions;
  final PinnedHttpClientFactory _factory;
  final String Function()? _acceptLanguage;
  final JsonTransport _transport;

  PinnedHttpClientFactory get factory => _factory;

  Uri _url(String path, [Map<String, Object?>? query]) {
    final q = query == null ? const <String, String>{} : queryOf(query);
    return baseUrl.replace(
      path: '${baseUrl.path}$path',
      queryParameters: q.isEmpty ? null : q,
    );
  }

  Future<Object?> _send(
    String method,
    String path, {
    Map<String, Object?>? query,
    Object? body,
    bool authenticated = true,
  }) async {
    Future<Object?> attempt(String? token) => _transport.send(
      method: method,
      url: _url(path, query),
      headers: {
        if (token != null) HttpHeaders.authorizationHeader: 'Bearer $token',
        // A CORS-safelisted header, so it costs no preflight on the web client and behaves
        // identically here. The Hub localises problem titles from it.
        if (_acceptLanguage != null)
          HttpHeaders.acceptLanguageHeader: _acceptLanguage(),
      },
      body: body,
    );

    if (!authenticated) return attempt(null);

    try {
      return await attempt(await sessions.freshAccessToken());
    } on ApiException catch (e) {
      // Refreshing the auth endpoints themselves would recurse, and a 401 from them is the answer
      // rather than a stale token.
      if (!e.isUnauthorized || path.startsWith('/v1/auth/')) rethrow;
      final refreshed = await sessions.forceRefresh();
      if (refreshed == null) rethrow;
      return attempt(refreshed.accessToken);
    }
  }

  Future<T> get<T>(
    String path,
    T Function(Object?) decode, {
    Map<String, Object?>? query,
    bool authenticated = true,
  }) async => decode(
    await _send('GET', path, query: query, authenticated: authenticated),
  );

  Future<T> post<T>(
    String path,
    T Function(Object?) decode, {
    Object? body,
    Map<String, Object?>? query,
    bool authenticated = true,
  }) async => decode(
    await _send(
      'POST',
      path,
      body: body,
      query: query,
      authenticated: authenticated,
    ),
  );

  Future<T> put<T>(
    String path,
    T Function(Object?) decode, {
    Object? body,
    Map<String, Object?>? query,
  }) async => decode(await _send('PUT', path, body: body, query: query));

  Future<T> patch<T>(
    String path,
    T Function(Object?) decode, {
    Object? body,
    Map<String, Object?>? query,
  }) async => decode(await _send('PATCH', path, body: body, query: query));

  Future<void> delete(
    String path, {
    Map<String, Object?>? query,
    Object? body,
  }) => _send('DELETE', path, query: query, body: body);

  /// Absolute URL for a content-addressed image.
  ///
  /// The Hub honours `?w=` only on a fixed ladder; any other width is ignored and the **original**
  /// is served, which on a fanart.tv source can be several megabytes. Every caller goes through
  /// here so no screen can quietly request one.
  Uri imageUrl(String sha256, {int? width}) {
    final snapped = width == null ? null : snapImageWidth(width);
    return _url('/v1/images/$sha256', {'w': snapped});
  }

  void close() => _transport.close();
}

/// The widths the Hub actually derives.
const imageWidthLadder = [64, 96, 128, 256, 384, 512, 768, 1024];

/// Rounds up to the smallest ladder width that covers [want], capped at the largest.
int snapImageWidth(int want) {
  for (final w in imageWidthLadder) {
    if (w >= want) return w;
  }
  return imageWidthLadder.last;
}
