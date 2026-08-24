import 'dart:convert';
import 'dart:io';

import '../errors.dart';
import '../hub.dart';
import '../transport.dart';

/// The Hub calls whose body is a **file**, not JSON.
///
/// [HubClient]'s own verbs all go through `JsonTransport`, which encodes what it is handed and sets
/// `Content-Type: application/json`. Two endpoints refuse that shape: `POST /v1/images` uploads an
/// avatar and `POST /v1/me/imports` uploads a listening-history export, and both key their decoder
/// off the raw bytes. So they need a socket of their own, and it belongs here rather than private
/// to one caller — `ImageEndpoints` in `user.dart` had the first copy, and while it stayed private
/// starting an import was unreachable from this client at all.
///
/// Everything the JSON path does around a request happens here too: a bearer token, one retry when
/// the token turned out to be stale mid-flight, a certificate mismatch reported as a mismatch, and
/// a problem document decoded into the [ApiException] every screen already knows how to show. The
/// one thing it does NOT carry is `Accept-Language`, which [HubClient] keeps private, so a failure
/// on one of these two routes comes back in the server's default language.
extension ByteBodyEndpoints on HubClient {
  /// POSTs [bytes] to [path] and decodes the JSON answer.
  ///
  /// [contentType] is a hint the Hub is free to disagree with — it sniffs both of these uploads —
  /// but sending what the picker said is what keeps a format the sniffer would otherwise have to
  /// guess at honest.
  Future<T> postBytes<T>(
    String path,
    T Function(Object?) decode, {
    required List<int> bytes,
    required String contentType,
    Map<String, Object?>? query,
  }) async {
    final parameters = query == null
        ? const <String, String>{}
        : queryOf(query);
    final url = baseUrl.replace(
      path: '${baseUrl.path}$path',
      queryParameters: parameters.isEmpty ? null : parameters,
    );

    try {
      final first = await sessions.freshAccessToken();
      var response = await _postBytes(url, bytes, contentType, first);
      // One retry on 401, the same shape every JSON call uses: an access token can expire between
      // the freshness check and the socket, and re-picking a file is not a reasonable thing to ask
      // of somebody for that.
      if (response.status == 401) {
        final refreshed = await sessions.forceRefresh();
        if (refreshed != null) {
          response = await _postBytes(
            url,
            bytes,
            contentType,
            refreshed.accessToken,
          );
        }
      }
      return decode(_bodyOrThrow(response, path));
    } on ApiException {
      rethrow;
    } on Object catch (e) {
      final mismatch = factory.takeLastMismatch();
      throw ApiException(
        status: 0,
        title: mismatch != null
            ? 'This server presented an unexpected certificate.'
            : 'Could not reach the server.',
        method: 'POST',
        path: path,
        detail: (mismatch ?? e).toString(),
        cause: mismatch ?? e,
      );
    }
  }

  Future<ByteBodyResponse> _postBytes(
    Uri url,
    List<int> bytes,
    String contentType,
    String? token,
  ) async {
    final client = factory.unpinned();
    try {
      final request = await client.postUrl(url);
      request.headers
        ..set(HttpHeaders.acceptHeader, 'application/json')
        ..set(HttpHeaders.contentTypeHeader, contentType);
      if (token != null) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }
      request.add(bytes);
      final response = await request.close();
      final text = await response.transform(utf8.decoder).join();
      return ByteBodyResponse(response.statusCode, response.reasonPhrase, text);
    } finally {
      client.close(force: true);
    }
  }

  /// The decoded JSON body, or the problem document raised as the exception it describes.
  Object? _bodyOrThrow(ByteBodyResponse response, String path) {
    Object? decoded;
    try {
      decoded = response.body.isEmpty ? null : jsonDecode(response.body);
    } on FormatException {
      // A body that is not JSON is a proxy's own error page. Left null so the status line is what
      // gets reported rather than a wall of HTML.
      decoded = null;
    }
    if (response.status >= 400) {
      throw ApiException.fromProblem(
        status: response.status,
        method: 'POST',
        path: path,
        body: decoded,
        fallbackTitle: response.reason,
      );
    }
    return decoded;
  }
}

/// One raw HTTP answer, before it is known whether it is a result or a problem.
class ByteBodyResponse {
  const ByteBodyResponse(this.status, this.reason, this.body);

  final int status;
  final String reason;
  final String body;
}
