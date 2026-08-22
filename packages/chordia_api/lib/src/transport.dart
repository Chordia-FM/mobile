import 'dart:convert';
import 'dart:io';

import 'package:chordia_net/chordia_net.dart';

import 'errors.dart';

/// One JSON request/response exchange, over a caller-supplied [HttpClient].
///
/// The client is supplied rather than created here because which one is correct depends on who is
/// being called: the Hub is a public host validated normally, while a library server is pinned to
/// the fingerprint its directory entry advertises. Keeping construction outside means this file
/// cannot accidentally open an unpinned connection to a library.
class JsonTransport {
  JsonTransport({
    required this.client,
    required this.factory,
    this.timeout = const Duration(seconds: 30),
  });

  final HttpClient client;

  /// Consulted after a handshake failure to report which certificate was rejected.
  final PinnedHttpClientFactory factory;
  final Duration timeout;

  Future<Object?> send({
    required String method,
    required Uri url,
    Map<String, String> headers = const {},
    Object? body,
  }) async {
    try {
      final request = await client.openUrl(method, url).timeout(timeout);

      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      headers.forEach(request.headers.set);
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.add(utf8.encode(jsonEncode(body)));
      }

      final response = await request.close().timeout(timeout);
      final text = response.statusCode == HttpStatus.noContent
          ? ''
          : await response.transform(utf8.decoder).join();

      final decoded = text.isEmpty ? null : _tryDecode(text);

      if (response.statusCode >= 400) {
        throw ApiException.fromProblem(
          status: response.statusCode,
          method: method,
          path: url.path,
          body: decoded,
          fallbackTitle: response.reasonPhrase,
        );
      }
      return decoded;
    } on ApiException {
      rethrow;
    } on Object catch (e) {
      // A pin mismatch surfaces as an opaque handshake failure, because a callback cannot throw
      // through the TLS layer. The factory recorded the real reason on the way past.
      final mismatch = factory.takeLastMismatch();
      throw ApiException(
        status: 0,
        title: mismatch != null
            ? 'This server presented an unexpected certificate.'
            : 'Could not reach the server.',
        method: method,
        path: url.path,
        detail: (mismatch ?? e).toString(),
        cause: mismatch ?? e,
      );
    }
  }

  static Object? _tryDecode(String text) {
    try {
      return jsonDecode(text);
    } on FormatException {
      // A proxy error page or a truncated body. Surfaced as a null payload, which the caller's
      // decoder rejects with a shape error naming the field it wanted.
      return null;
    }
  }

  void close() => client.close(force: true);
}

/// Builds a query string, dropping absent values so a caller can pass optionals straight through.
Map<String, String> queryOf(Map<String, Object?> params) => {
  for (final e in params.entries)
    if (e.value != null) e.key: '${e.value}',
};
