import 'dart:io';

import 'package:chordia_net/chordia_net.dart';

import 'grants.dart';
import 'json.dart';
import 'models.g.dart';
import 'transport.dart';

/// Talks to one library server, on the credential and the pin a [Grant] carries.
///
/// A new client is cheap and is built per grant rather than held, because the endpoint and the
/// fingerprint both come from the directory and can change when an operator moves or re-issues.
class LibraryClient {
  LibraryClient({required this.grant, required PinnedHttpClientFactory factory})
    : _factory = factory,
      _transport = JsonTransport(
        client: factory.pinnedTo(grant.fingerprint),
        factory: factory,
      );

  final Grant grant;
  final PinnedHttpClientFactory _factory;
  final JsonTransport _transport;

  PinnedHttpClientFactory get factory => _factory;

  Uri _url(String path, [Map<String, Object?>? query]) {
    final base = grant.endpoint;
    final q = query == null ? const <String, String>{} : queryOf(query);
    return base.replace(
      path: '${base.path}$path',
      queryParameters: q.isEmpty ? null : q,
    );
  }

  Map<String, String> get _auth => {
    HttpHeaders.authorizationHeader: 'Bearer ${grant.token}',
  };

  Future<List<LibrarySummary>> libraries() async {
    final json = await _transport.send(
      method: 'GET',
      url: _url('/v1/libraries'),
      headers: _auth,
    );
    return asList(
      json,
    ).map((e) => LibrarySummary.fromJson(asObject(e))).toList();
  }

  Future<List<Track>> tracks(
    String libraryId, {
    int limit = 200,
    int offset = 0,
  }) async {
    final json = await _transport.send(
      method: 'GET',
      url: _url('/v1/libraries/$libraryId/tracks', {
        'limit': limit,
        'offset': offset,
      }),
      headers: _auth,
    );
    return asList(json).map((e) => Track.fromJson(asObject(e))).toList();
  }

  Future<Track> track(String trackRef) async {
    final json = await _transport.send(
      method: 'GET',
      url: _url('/v1/tracks/$trackRef'),
      headers: _auth,
    );
    return Track.fromJson(asObject(json));
  }

  /// Resolves whether this library holds a copy of a track described by fingerprint.
  ///
  /// Unauthenticated on the server, but still sent over the pinned client — the answer names what
  /// somebody owns.
  Future<MatchResult> match(MatchQuery query) async {
    final json = await _transport.send(
      method: 'GET',
      url: _url('/v1/tracks/match', {
        'content_hash': query.contentHash,
        'acoustid': query.acoustid,
        'recording_mbid': query.recordingMbid,
        'artist_norm': query.artistNorm,
        'title_norm': query.titleNorm,
        'duration_ms': query.durationMs,
      }),
      headers: _auth,
    );
    return MatchResult.fromJson(asObject(json));
  }

  /// Where the audio lives.
  ///
  /// Nothing hands this URL to a platform player: the bytes are fetched here, over the pinned
  /// connection, and served to the player from a loopback proxy. ExoPlayer and AVPlayer do TLS in
  /// the platform stack, which no Dart certificate callback can reach, so a pinned self-signed
  /// library is unplayable any other way.
  Uri streamUrl(String trackRef, QualityProfile profile) =>
      _url('/v1/stream/$trackRef', {'profile': profile.wire});

  void close() => _transport.close();
}

/// A byte range to request, already in a form the library server understands.
///
/// Its parser accepts only `bytes=start-` and `bytes=start-end`. A suffix range (`bytes=-500`,
/// which ExoPlayer emits while probing a file's tail) falls through to a **200 with the whole
/// body** — silently turning a small probe into a full download. Every outbound range is
/// normalised here so that cannot happen.
class ByteRange {
  const ByteRange(this.start, [this.endInclusive]);

  final int start;
  final int? endInclusive;

  /// Rewrites a suffix range into an absolute one, given the known total size.
  static ByteRange fromSuffix(int lastNBytes, {required int totalBytes}) {
    final start = (totalBytes - lastNBytes).clamp(0, totalBytes);
    return ByteRange(start, totalBytes - 1);
  }

  String get header =>
      endInclusive == null ? 'bytes=$start-' : 'bytes=$start-$endInclusive';

  @override
  String toString() => header;
}
