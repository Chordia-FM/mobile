import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:chordia_api/chordia_api.dart';
import 'package:chordia_net/chordia_net.dart';
import 'package:chordia_player/src/engine/chordia_audio_source.dart';
import 'package:chordia_player/src/engine/engine.dart';
import 'package:chordia_player/src/engine/stream_cache.dart';
import 'package:chordia_sync/chordia_sync.dart';
import 'package:flutter_test/flutter_test.dart';

/// A GrantManager needs a HubClient to mint; this stands in for one that already has a grant.
class _StubGrants implements GrantManager {
  _StubGrants(this._grant);

  final Grant _grant;
  var calls = 0;

  @override
  Future<Grant> forLibrary(String libraryId) async {
    calls++;
    return _grant;
  }

  @override
  void clear() {}

  @override
  HubClient get hub => throw UnimplementedError();
}

Grant grantFor({String token = 'cap-1'}) => Grant(
  token: token,
  expiresAt: DateTime.now()
      .add(const Duration(minutes: 5))
      .millisecondsSinceEpoch,
  server: const ServerEndpoint(
    endpoint: 'https://library.example:8443',
    lastHeartbeat: 1700000000000,
    online: true,
    ownerId: 'owner',
    serverId: 'server',
    tlsFingerprint:
        '', // Empty: the stub never opens a socket, so no pin is needed.
  ),
);

PlayerTrack trackFixture() => const PlayerTrack(
  qid: 'qid-1',
  id: 'track-1',
  title: 'A Song',
  artist: 'An Artist',
  album: 'An Album',
  durationMs: 240000,
  libraryId: 'lib-1',
  trackRef: 'ref-1',
  contentHash: 'sha-1',
);

void main() {
  late Directory temp;
  late StreamCache cache;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('chordia_stream_cache');
    cache = StreamCache(directory: temp);
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  ChordiaAudioSource sourceWith({
    required List<int> body,
    required List<Map<String, String>> seenHeaders,
    required List<Uri> seenUrls,
    int? totalBytes,
    _StubGrants? grants,
  }) => ChordiaAudioSource(
    source: StreamedSource(
      track: trackFixture(),
      libraryId: 'lib-1',
      trackRef: 'ref-1',
      profile: QualityProfile.original,
    ),
    grants: grants ?? _StubGrants(grantFor()),
    factory: PinnedHttpClientFactory(),
    cache: cache,
    openStream: (url, headers) async {
      seenUrls.add(url);
      seenHeaders.add(headers);
      return UpstreamResponse(
        stream: Stream.value(body),
        totalBytes: totalBytes ?? body.length,
        contentLength: body.length,
        contentType: 'audio/flac',
        etag: '"hash"',
      );
    },
  );

  group('range normalisation', () {
    test('an open-ended request sends bytes=start-', () async {
      final headers = <Map<String, String>>[];
      final urls = <Uri>[];
      final source = sourceWith(
        body: List.filled(100, 7),
        seenHeaders: headers,
        seenUrls: urls,
      );

      await source.request(0);

      expect(headers.single[HttpHeaders.rangeHeader], 'bytes=0-');
    });

    test(
      'a bounded request converts the exclusive end to an inclusive one',
      () async {
        // just_audio asks for [start, end) but HTTP ranges are inclusive. Off by one here reads one
        // byte short of every span, which decodes as corruption rather than as an error.
        final headers = <Map<String, String>>[];
        final urls = <Uri>[];
        final source = sourceWith(
          body: List.filled(100, 7),
          seenHeaders: headers,
          seenUrls: urls,
        );

        await source.request(100, 200);

        expect(headers.single[HttpHeaders.rangeHeader], 'bytes=100-199');
      },
    );

    test('never emits a suffix range', () async {
      // `bytes=-N` falls through the library's parser to a 200 with the whole body, turning a tail
      // probe into a full download.
      final headers = <Map<String, String>>[];
      final urls = <Uri>[];
      final source = sourceWith(
        body: List.filled(10, 1),
        seenHeaders: headers,
        seenUrls: urls,
      );

      await source.request();
      await source.request(0, 10);

      for (final h in headers) {
        expect(h[HttpHeaders.rangeHeader], isNot(startsWith('bytes=-')));
      }
    });

    test('carries the capability token as a bearer header', () async {
      final headers = <Map<String, String>>[];
      final urls = <Uri>[];
      final source = sourceWith(
        body: const [1, 2, 3],
        seenHeaders: headers,
        seenUrls: urls,
        grants: _StubGrants(grantFor(token: 'cap-xyz')),
      );

      await source.request(0);

      expect(headers.single[HttpHeaders.authorizationHeader], 'Bearer cap-xyz');
    });

    test('builds the stream URL with the requested profile', () async {
      final headers = <Map<String, String>>[];
      final urls = <Uri>[];
      final source = sourceWith(
        body: const [1],
        seenHeaders: headers,
        seenUrls: urls,
      );

      await source.request(0);

      expect(urls.single.path, '/v1/stream/ref-1');
      expect(urls.single.queryParameters['profile'], 'original');
    });
  });

  group('a fresh grant per request', () {
    test('asks for a token on every request rather than holding one', () async {
      // Capability tokens live five minutes and tracks routinely run longer. Asking per request is
      // what makes expiry a non-event; the grant cache makes it cheap.
      final grants = _StubGrants(grantFor());
      final headers = <Map<String, String>>[];
      final urls = <Uri>[];
      final source = sourceWith(
        body: List.filled(10, 3),
        seenHeaders: headers,
        seenUrls: urls,
        grants: grants,
      );

      await source.request(0, 5);
      await source.request(5, 10);

      expect(grants.calls, greaterThanOrEqualTo(2));
    });
  });

  group('caching', () {
    test(
      'a fully cached span is served from disk without going upstream',
      () async {
        final body = Uint8List.fromList(List.generate(64, (i) => i));
        final headers = <Map<String, String>>[];
        final urls = <Uri>[];
        final source = sourceWith(
          body: body,
          seenHeaders: headers,
          seenUrls: urls,
        );

        // Drain the first response so the tee actually writes through to disk.
        final first = await source.request(0);
        await first.stream.toList();
        await Future<void>.delayed(const Duration(milliseconds: 50));

        final before = urls.length;
        final second = await source.request(0, 32);
        final bytes = (await second.stream.toList()).expand((c) => c).toList();

        expect(
          urls.length,
          before,
          reason: 'served from cache, no second upstream request',
        );
        expect(bytes, body.sublist(0, 32));
      },
    );

    test('a partially cached span still goes upstream', () async {
      final headers = <Map<String, String>>[];
      final urls = <Uri>[];
      final source = sourceWith(
        body: List.filled(16, 9),
        seenHeaders: headers,
        seenUrls: urls,
        totalBytes: 1000,
      );

      final first = await source.request(0, 16);
      await first.stream.toList();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await source.request(0, 500);
      expect(urls.length, 2, reason: 'the cache held only the first 16 bytes');
    });
  });

  group('downloaded sources', () {
    test('play from the file with no grant and no network', () async {
      final file = File('${temp.path}${Platform.pathSeparator}track.flac');
      await file.writeAsBytes(List.generate(50, (i) => i));

      final grants = _StubGrants(grantFor());
      final source = ChordiaAudioSource(
        source: DownloadedSource(
          track: trackFixture(),
          filePath: file.path,
          profile: QualityProfile.original,
        ),
        grants: grants,
        factory: PinnedHttpClientFactory(),
        cache: cache,
        openStream: (_, _) async =>
            throw StateError('must not reach the network'),
      );

      final response = await source.request(10, 20);
      final bytes = (await response.stream.toList()).expand((c) => c).toList();

      expect(bytes, List.generate(10, (i) => i + 10));
      expect(response.sourceLength, 50);
      expect(response.contentType, 'audio/flac');
      expect(grants.calls, 0, reason: 'a local file needs no capability token');
    });
  });

  group('StreamCacheEntry', () {
    test('coalesces adjacent and overlapping ranges', () {
      final entry =
          StreamCacheEntry(
              dataFile: File('${temp.path}/x.bin'),
              indexFile: File('${temp.path}/x.idx'),
              ranges: [],
            )
            ..record(0, 10)
            ..record(10, 10)
            ..record(5, 3);

      expect(entry.ranges.length, 1);
      expect(entry.ranges.single.start, 0);
      expect(entry.ranges.single.end, 20);
    });

    test('keeps a gap that was never fetched', () {
      // The bug this guards: treating "file exists" as "file complete" serves silence for the
      // bytes a seek skipped over.
      final entry =
          StreamCacheEntry(
              dataFile: File('${temp.path}/y.bin'),
              indexFile: File('${temp.path}/y.idx'),
              ranges: [],
            )
            ..record(0, 10)
            ..record(100, 10);

      expect(entry.ranges.length, 2);
      expect(entry.contiguousFrom(0), 10);
      expect(entry.contiguousFrom(10), 0, reason: 'the gap is not claimed');
      expect(entry.contiguousFrom(100), 10);
      expect(entry.isComplete, isFalse);
    });

    test('round-trips through its index file', () async {
      final data = File('${temp.path}/z.bin');
      final index = File('${temp.path}/z.idx');
      final entry =
          StreamCacheEntry(dataFile: data, indexFile: index, ranges: [])
            ..totalBytes = 500
            ..contentType = 'audio/flac'
            ..etag = '"abc"'
            ..record(0, 100);
      await entry.persist();

      final restored = StreamCacheEntry.fromJson(
        jsonDecode(await index.readAsString()) as Map<String, Object?>,
        dataFile: data,
        indexFile: index,
      );

      expect(restored.totalBytes, 500);
      expect(restored.contentType, 'audio/flac');
      expect(restored.etag, '"abc"');
      expect(restored.contiguousFrom(0), 100);
    });
  });

  group('StreamCache eviction', () {
    test('drops least-recently-used entries and spares pinned ones', () async {
      final small = StreamCache(directory: temp, maxBytes: 300);

      for (final key in ['a', 'b', 'c']) {
        final entry = await small.entryFor(key);
        await small.writeAt(entry, 0, List.filled(200, 1));
        // Distinct access times, so "least recently used" is well defined.
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      small.pin('a');

      await small.evictToFit();

      expect(
        await File(
          '${temp.path}/${base64Url.encode(utf8.encode('a')).replaceAll('=', '')}.bin',
        ).exists(),
        isTrue,
        reason: 'pinned entries survive even when oldest',
      );
      expect(
        await small.totalBytes(),
        lessThanOrEqualTo(300 + 200),
        reason: 'the pinned entry may push it over, nothing else may',
      );
    });
  });
}
