import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:chordia_api/chordia_api.dart';
import 'package:chordia_mobile/data/art/art_cache.dart';
import 'package:flutter_test/flutter_test.dart';

const aHash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const bHash =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const cHash =
    'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';

Uint8List bytes(int n) => Uint8List.fromList(List.filled(n, 7));

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('chordia_art');
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  ArtCache build({
    required ArtFetcher fetch,
    int maxBytes = ArtCache.defaultMaxBytes,
  }) =>
      ArtCache(directory: Future.value(temp), fetch: fetch, maxBytes: maxBytes);

  group('width snapping', () {
    test('every requested width lands on a width the Hub derives', () async {
      // Off the ladder the Hub ignores `?w=` and serves the ORIGINAL, which from a fanart.tv
      // source can be several megabytes. This is the guard that keeps a phone off that path.
      final asked = <int>[];
      final cache = build(
        fetch: (sha, width) async {
          asked.add(width);
          return bytes(4);
        },
      );

      for (var w = 1; w <= 1200; w += 7) {
        await cache.file(aHash, width: w);
      }

      expect(asked, isNotEmpty);
      expect(
        asked.toSet().difference(imageWidthLadder.toSet()),
        isEmpty,
        reason: 'nothing was requested at an underived width',
      );
    });

    test('two sizes that snap the same way share one download', () async {
      var calls = 0;
      final cache = build(
        fetch: (sha, width) async {
          calls++;
          return bytes(4);
        },
      );

      await cache.file(aHash, width: 100); // -> 128
      await cache.file(aHash, width: 120); // -> 128

      expect(calls, 1);
    });
  });

  group('single flight', () {
    test('concurrent requests for one cover download once', () async {
      // A track list and its header asking for the same album art in one frame is the normal case.
      var calls = 0;
      final gate = Completer<void>();
      final cache = build(
        fetch: (sha, width) async {
          calls++;
          await gate.future;
          return bytes(8);
        },
      );

      final all = List.generate(6, (_) => cache.file(aHash, width: 128));
      await Future<void>.delayed(Duration.zero);
      gate.complete();
      final files = await Future.wait(all);

      expect(calls, 1);
      expect(files.map((f) => f?.path).toSet(), hasLength(1));
    });
  });

  group('a hash the Hub has no image for', () {
    test('is remembered, so a scroll does not re-ask', () async {
      var calls = 0;
      final cache = build(
        fetch: (sha, width) async {
          calls++;
          throw const ArtMissingException(aHash);
        },
      );

      expect(await cache.file(aHash, width: 128), isNull);
      expect(await cache.file(aHash, width: 128), isNull);
      expect(await cache.file(aHash, width: 512), isNull);

      expect(calls, 1, reason: 'absent at one width is absent at every width');
    });
  });

  group('failures', () {
    test('leave no partial file behind', () async {
      final cache = build(
        fetch: (sha, width) async => throw const ApiException(
          status: 0,
          title: 'offline',
          method: 'GET',
          path: '/v1/images/x',
        ),
      );

      expect(await cache.file(aHash, width: 128), isNull);

      final leftovers = await temp.list().where((e) => e is File).toList();
      expect(leftovers, isEmpty, reason: 'a torn write is not left readable');
    });

    test('are retried, unlike a 404', () async {
      var calls = 0;
      final cache = build(
        fetch: (sha, width) async {
          calls++;
          if (calls == 1) {
            throw const ApiException(
              status: 0,
              title: 'offline',
              method: 'GET',
              path: '/x',
            );
          }
          return bytes(4);
        },
      );

      expect(await cache.file(aHash, width: 128), isNull);
      expect(await cache.file(aHash, width: 128), isNotNull);
      expect(calls, 2);
    });
  });

  group('path safety', () {
    test(
      'a hash that is not a content address never reaches the filesystem',
      () async {
        // These arrive from the network; a `..` in one would escape the cache directory.
        var calls = 0;
        final cache = build(
          fetch: (sha, width) async {
            calls++;
            return bytes(4);
          },
        );

        for (final bad in [
          '../../etc/passwd',
          '',
          'ABC',
          'g' * 64,
          '$aHash/x',
        ]) {
          expect(await cache.file(bad, width: 128), isNull);
        }
        expect(calls, 0);
      },
    );
  });

  group('eviction', () {
    test('drops least-recently-used first and honours the cap', () async {
      final cache = build(
        maxBytes: 250,
        fetch: (sha, width) async => bytes(100),
      );

      await cache.file(aHash, width: 128);
      await cache.file(bHash, width: 128);
      // Touching A makes B the oldest.
      await cache.file(aHash, width: 128);
      await cache.file(cHash, width: 128);

      expect(await cache.totalBytes(), lessThanOrEqualTo(250));

      final names = await temp
          .list()
          .where((e) => e is File)
          .map((e) => e.uri.pathSegments.last)
          .toList();
      expect(
        names.where((n) => n.startsWith(bHash)),
        isEmpty,
        reason: 'B was the least recently used',
      );
      expect(names.where((n) => n.startsWith(cHash)), isNotEmpty);
    });

    test('an image bigger than the whole cap is still kept', () async {
      // Otherwise it deletes itself the instant it lands and re-downloads forever.
      final cache = build(
        maxBytes: 10,
        fetch: (sha, width) async => bytes(500),
      );

      final file = await cache.file(aHash, width: 128);

      expect(file, isNotNull);
      expect(await file!.exists(), isTrue);
    });
  });

  group('clear', () {
    test('empties the directory and forgets absent hashes', () async {
      var calls = 0;
      final cache = build(
        fetch: (sha, width) async {
          calls++;
          if (sha == bHash) throw const ArtMissingException(bHash);
          return bytes(4);
        },
      );

      await cache.file(aHash, width: 128);
      await cache.file(bHash, width: 128);
      final before = calls;

      await cache.clear();

      expect(await cache.totalBytes(), 0);
      // Enrichment catching up later is exactly why someone clears artwork.
      await cache.file(bHash, width: 128);
      expect(calls, before + 1);
    });
  });
}
