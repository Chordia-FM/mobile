// just_audio marks StreamAudioSource experimental, but it is the only sanctioned way to supply
// bytes the plugin did not fetch itself, and the whole pinned-TLS design depends on doing exactly
// that. The annotation is a stability warning, not a discouragement; pinning the just_audio version
// is how that risk is managed.
// ignore_for_file: experimental_member_use

import 'dart:async';
import 'dart:io';

import 'package:chordia_api/chordia_api.dart';
import 'package:chordia_net/chordia_net.dart';
import 'package:just_audio/just_audio.dart';
import 'package:meta/meta.dart';

import 'engine.dart';
import 'stream_cache.dart';

/// Fetches audio bytes for the player.
///
/// Everything about this class follows from one platform fact: **ExoPlayer and AVPlayer perform
/// TLS inside the platform stack, where Dart's certificate callback cannot reach.** Chordia pins
/// library servers to the SHA-256 fingerprint the Hub directory advertises, so handing a native
/// player an `https://` URL for a self-signed library is not a shortcut we declined to take — it
/// simply cannot work. (just_audio issue #442 has tracked this for years and is unlikely to close.)
///
/// So the bytes are fetched here, in Dart, over the pinned client, and served to the player through
/// just_audio's loopback proxy. Three further things fall out of that and are worth keeping:
///
/// * **Capability tokens live five minutes**, which is shorter than plenty of tracks. Because every
///   outbound request asks the grant cache for a token, expiry stops being an event anything has to
///   handle — no watching the clock, no swapping the player's URL mid-track.
/// * **Downloads and partial caches resolve here too**, so offline playback is the same code path
///   rather than a parallel one.
/// * **Ranges are normalised on the way out.** The library server's parser understands only
///   `bytes=start-` and `bytes=start-end`; a suffix range (`bytes=-N`, which ExoPlayer emits while
///   probing a file's tail) falls through to a 200 with the whole body, quietly turning a small
///   probe into a full download.
class ChordiaAudioSource extends StreamAudioSource {
  ChordiaAudioSource({
    required this.source,
    required this.grants,
    required this.factory,
    required this.cache,
    @visibleForTesting this.openStream,
  }) : super(tag: source.track.qid);

  final EngineSource source;
  final GrantManager grants;
  final PinnedHttpClientFactory factory;
  final StreamCache cache;

  /// Test seam standing in for the outbound HTTPS leg.
  final Future<UpstreamResponse> Function(Uri url, Map<String, String> headers)?
  openStream;

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final s = source;
    if (s is DownloadedSource) return _fromFile(File(s.filePath), start, end);
    return _fromLibrary(s as StreamedSource, start, end);
  }

  Future<StreamAudioResponse> _fromFile(File file, int? start, int? end) async {
    final length = await file.length();
    final from = start ?? 0;
    final to = end ?? length;
    return StreamAudioResponse(
      sourceLength: length,
      contentLength: to - from,
      offset: from,
      stream: file.openRead(from, to),
      contentType: _contentTypeFor(file.path),
    );
  }

  Future<StreamAudioResponse> _fromLibrary(
    StreamedSource s,
    int? start,
    int? end,
  ) async {
    final entry = await cache.entryFor(s.cacheKey);
    final from = start ?? 0;

    // Serve from disk when the whole requested span is already held. Anything partial goes
    // upstream rather than stitching, which keeps the sparse-range bookkeeping in one direction.
    final available = entry.contiguousFrom(from);
    final wanted = end == null ? null : end - from;
    if (available > 0 &&
        (wanted == null ? entry.isComplete : available >= wanted)) {
      final total = entry.totalBytes;
      final length = wanted ?? (total == null ? available : total - from);
      return StreamAudioResponse(
        sourceLength: total,
        contentLength: length,
        offset: from,
        stream: Stream.fromFuture(cache.readAt(entry, from, length)),
        contentType: entry.contentType ?? 'audio/mpeg',
      );
    }

    final grant = await grants.forLibrary(s.libraryId);
    final client = LibraryClient(grant: grant, factory: factory);
    try {
      final url = client.streamUrl(s.trackRef, s.profile);
      // Never a suffix range: see the class doc.
      final range = end == null ? ByteRange(from) : ByteRange(from, end - 1);

      final open = openStream ?? (u, h) => _open(u, h, grant);
      final response = await open(url, {
        HttpHeaders.authorizationHeader: 'Bearer ${grant.token}',
        HttpHeaders.rangeHeader: range.header,
      });

      entry
        ..totalBytes = response.totalBytes ?? entry.totalBytes
        ..contentType = response.contentType ?? entry.contentType
        ..etag = response.etag ?? entry.etag;
      await entry.persist();

      // Tee the bytes to disk as they pass through, so a replay or a seek backwards costs nothing.
      var offset = from;
      final teed = response.stream.map((chunk) {
        final at = offset;
        offset += chunk.length;
        unawaited(
          cache.writeAt(entry, at, chunk).catchError((Object _) {
            // A cache write failing must never interrupt playback; the bytes still reach the
            // player, they simply are not kept.
          }),
        );
        return chunk;
      });

      return StreamAudioResponse(
        sourceLength: response.totalBytes,
        contentLength: response.contentLength,
        offset: from,
        stream: teed,
        contentType: response.contentType ?? 'audio/mpeg',
      );
    } finally {
      client.close();
    }
  }

  Future<UpstreamResponse> _open(
    Uri url,
    Map<String, String> headers,
    Grant grant,
  ) async {
    final http = factory.pinnedTo(grant.fingerprint);
    var handedOff = false;
    try {
      final request = await http.getUrl(url);
      headers.forEach(request.headers.set);
      final response = await request.close();

      if (response.statusCode >= 400) {
        throw ApiException(
          status: response.statusCode,
          title: 'The library refused the stream request.',
          method: 'GET',
          path: url.path,
        );
      }

      final total = _totalFromContentRange(
        response.headers.value(HttpHeaders.contentRangeHeader),
      );
      final length = response.contentLength < 0 ? null : response.contentLength;
      handedOff = true;
      return UpstreamResponse(
        // The connection outlives this function — it is closed when the body is fully read, or
        // when the player abandons it mid-track by cancelling the subscription. Without both
        // paths a seek-heavy session leaks a socket per seek.
        stream: response.transform(
          StreamTransformer<List<int>, List<int>>.fromHandlers(
            handleDone: (sink) {
              sink.close();
              http.close(force: true);
            },
            handleError: (error, stack, sink) {
              sink.addError(error, stack);
              http.close(force: true);
            },
          ),
        ),
        totalBytes: total ?? length,
        contentLength: length,
        contentType: response.headers.contentType?.mimeType,
        etag: response.headers.value(HttpHeaders.etagHeader),
      );
    } finally {
      if (!handedOff) http.close(force: true);
    }
  }

  /// `bytes 100-199/4096` -> 4096.
  static int? _totalFromContentRange(String? header) {
    if (header == null) return null;
    final slash = header.lastIndexOf('/');
    if (slash < 0) return null;
    final total = header.substring(slash + 1).trim();
    return total == '*' ? null : int.tryParse(total);
  }

  static String _contentTypeFor(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.flac')) return 'audio/flac';
    if (lower.endsWith('.mp3')) return 'audio/mpeg';
    if (lower.endsWith('.m4a') || lower.endsWith('.aac')) return 'audio/mp4';
    if (lower.endsWith('.opus') || lower.endsWith('.ogg')) return 'audio/ogg';
    if (lower.endsWith('.wav')) return 'audio/wav';
    return 'audio/mpeg';
  }
}

/// What the outbound leg produced, independent of how it was fetched.
@immutable
class UpstreamResponse {
  const UpstreamResponse({
    required this.stream,
    required this.totalBytes,
    required this.contentLength,
    required this.contentType,
    required this.etag,
  });

  final Stream<List<int>> stream;

  /// Size of the whole file, from `Content-Range`. Null when the server did not say.
  final int? totalBytes;

  /// Size of this response body.
  final int? contentLength;
  final String? contentType;
  final String? etag;
}
