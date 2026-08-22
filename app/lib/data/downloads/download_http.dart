import 'dart:async';
import 'dart:io';

import 'package:chordia_api/chordia_api.dart';
import 'package:chordia_net/chordia_net.dart';
import 'package:flutter/foundation.dart';

import 'download_request.dart';

/// One response from a library server's stream endpoint, as the download loop needs it.
///
/// The status is handed back rather than turned into an exception because two of the interesting
/// answers are not failures: `304` means "your partial bytes are still valid" and `416` means
/// "your partial is longer than the file now is". Both are decisions for the loop, not errors.
@immutable
class DownloadResponse {
  const DownloadResponse({
    required this.status,
    required this.stream,
    required this.release,
    this.totalBytes,
    this.etag,
    this.contentType,
  });

  final int status;

  /// The body. Empty for a `304`, which carries none.
  final Stream<List<int>> stream;

  /// Closes the connection.
  ///
  /// Always called, on every path — completion, failure and cancellation alike. A download the
  /// user cancels mid-flight abandons the subscription rather than draining it, and without this
  /// the socket would stay open until the idle timeout for every cancelled track.
  final Future<void> Function() release;

  /// Size of the whole file (from `Content-Range` on a partial response, or `Content-Length` on a
  /// full one), not of this body. Null when the server did not say.
  final int? totalBytes;

  final String? etag;
  final String? contentType;
}

/// The outbound leg of a download.
///
/// A function, so the whole queue can be exercised against bytes from a list. Everything real that
/// implements it goes through [pinnedDownloadFetch] and therefore through the pinned client.
typedef DownloadFetch =
    Future<DownloadResponse> Function(
      DownloadRequest request, {
      int from,
      String? ifNoneMatch,
    });

/// Fetches download bytes over the pinned connection.
///
/// This is why Chordia does not use a platform download manager. `background_downloader` and its
/// peers hand the request to the OS, whose HTTP stack performs TLS somewhere no Dart certificate
/// callback can reach — the same platform fact that forces audio playback through a loopback
/// proxy. A library on a self-signed certificate is simply not fetchable that way, and pinning
/// only *some* of the audio path would be worse than not pinning it: one code path that is always
/// pinned is worth more than OS-managed backgrounding of a path that quietly is not.
DownloadFetch pinnedDownloadFetch({
  required GrantManager grants,
  required PinnedHttpClientFactory factory,
}) {
  return (request, {int from = 0, String? ifNoneMatch}) async {
    final grant = await grants.forLibrary(request.libraryId);

    // Built only to compose the URL — the byte leg opens its own connection below, so nothing is
    // kept alive by this client.
    final urls = LibraryClient(grant: grant, factory: factory);
    final Uri url;
    try {
      url = urls.streamUrl(request.trackRef, request.profile);
    } finally {
      urls.close();
    }

    final http = factory.pinnedTo(grant.fingerprint);
    var handedOff = false;
    try {
      final outbound = await http.getUrl(url);
      outbound.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer ${grant.token}',
      );
      // Never a suffix range. The library's parser understands only `bytes=start-` and
      // `bytes=start-end`; anything else falls through to a 200 with the whole body, which would
      // turn a resume into a re-download without ever reporting an error.
      if (from > 0) {
        outbound.headers.set(HttpHeaders.rangeHeader, ByteRange(from).header);
      }
      if (ifNoneMatch != null) {
        outbound.headers.set(HttpHeaders.ifNoneMatchHeader, ifNoneMatch);
      }

      final response = await outbound.close();
      handedOff = true;
      return DownloadResponse(
        status: response.statusCode,
        stream: response,
        release: () async => http.close(force: true),
        totalBytes:
            _totalFromContentRange(
              response.headers.value(HttpHeaders.contentRangeHeader),
            ) ??
            (response.contentLength < 0 ? null : response.contentLength),
        etag: response.headers.value(HttpHeaders.etagHeader),
        contentType: response.headers.contentType?.mimeType,
      );
    } on Object catch (error) {
      // A pin mismatch surfaces as an opaque handshake failure, because the callback that rejected
      // the certificate cannot throw through the TLS layer. The factory recorded the real reason.
      final mismatch = factory.takeLastMismatch();
      throw ApiException(
        status: 0,
        title: mismatch != null
            ? 'This server presented an unexpected certificate.'
            : 'Could not reach the library server.',
        method: 'GET',
        path: url.path,
        detail: (mismatch ?? error).toString(),
        cause: mismatch ?? error,
      );
    } finally {
      if (!handedOff) http.close(force: true);
    }
  };
}

/// `bytes 100-199/4096` -> 4096.
int? _totalFromContentRange(String? header) {
  if (header == null) return null;
  final slash = header.lastIndexOf('/');
  if (slash < 0) return null;
  final total = header.substring(slash + 1).trim();
  return total == '*' ? null : int.tryParse(total);
}
