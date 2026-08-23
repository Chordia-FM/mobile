import 'dart:async';

import 'package:chordia_api/chordia_api.dart';
import 'package:chordia_mobile/features/lyrics/data/lyrics_repository.dart';
import 'package:flutter_test/flutter_test.dart';

LyricsLine line(String text, {int? at}) => LyricsLine(text: text, startMs: at);

Lyrics doc(List<LyricsLine> lines, {LyricsSyncType? sync}) => Lyrics(
  lines: lines,
  syncType: sync ?? LyricsSyncType.lineSYNCED,
  trackId: 'track-1',
);

/// A 404, as the Hub answers for a track with no lyrics.
const _missing = ApiException(
  status: 404,
  title: 'Not found',
  method: 'GET',
  path: '/v1/lyrics/track-1',
);

/// A transport failure, which says nothing about the song.
const _offline = ApiException(
  status: 0,
  title: 'Network unreachable',
  method: 'GET',
  path: '/v1/lyrics/track-1',
);

void main() {
  group('picking the line that is sounding', () {
    final starts = lyricStarts([
      line('one', at: 0),
      line('two', at: 1000),
      line('three', at: 2500),
    ]);

    test('the first line is current from the instant it starts', () {
      expect(activeLyricLine(starts, 0), 0);
      expect(activeLyricLine(starts, 1), 0);
    });

    test('a boundary belongs to the line it opens', () {
      expect(activeLyricLine(starts, 999), 0);
      expect(activeLyricLine(starts, 1000), 1);
      expect(activeLyricLine(starts, 2499), 1);
      expect(activeLyricLine(starts, 2500), 2);
    });

    test('the last line stays current to the end of the track', () {
      expect(activeLyricLine(starts, 600000), 2);
    });

    test('nothing is current before the first line', () {
      final late = lyricStarts([line('one', at: 4000)]);
      expect(activeLyricLine(late, 0), -1);
      expect(activeLyricLine(late, 3999), -1);
      expect(activeLyricLine(late, 4000), 0);
    });

    test('an empty document has no current line', () {
      expect(activeLyricLine(lyricStarts(const []), 1000), -1);
    });

    test('a line whose end has passed stays current until the next begins', () {
      // The gap between `end_ms` and the next `start_ms` is an instrumental break. Dropping the
      // highlight through it reads as the view having lost its place.
      final withGap = lyricStarts(const [
        LyricsLine(text: 'one', startMs: 0, endMs: 500),
        LyricsLine(text: 'two', startMs: 9000, endMs: 9500),
      ]);
      expect(activeLyricLine(withGap, 4000), 0);
    });

    test('the search survives an untimed line in a synced document', () {
      // Nothing in the contract forces every LINE_SYNCED line to carry a start, and one that does
      // not would make a raw lookup non-monotonic — which a binary search answers with confident
      // nonsense rather than an error.
      final mixed = lyricStarts([
        line('one', at: 0),
        line('untimed'),
        line('three', at: 2000),
      ]);
      expect(mixed, [0, 2000, 2000]);
      expect(activeLyricLine(mixed, 500), 0);
      // At 2000 both the untimed line and the timed one qualify; the timed one, being later, wins.
      // The untimed line is drawn but never highlighted, because nothing is known about when it is
      // sung.
      expect(activeLyricLine(mixed, 2000), 2);
      expect(activeLyricLine(mixed, 5000), 2);
    });

    test('a trailing untimed line is never highlighted', () {
      final trailing = lyricStarts([line('one', at: 0), line('untimed')]);
      expect(activeLyricLine(trailing, 1 << 40), 0);
    });

    test('every position agrees with a linear scan', () {
      // The binary search is an optimisation over the obvious implementation, and the obvious
      // implementation is the specification.
      final lines = [for (var i = 0; i < 97; i++) line('line $i', at: i * 137)];
      final built = lyricStarts(lines);
      for (var ms = -5; ms < 97 * 137 + 5; ms += 7) {
        var expected = -1;
        for (var i = 0; i < built.length; i++) {
          if (built[i] <= ms) expected = i;
        }
        expect(activeLyricLine(built, ms), expected, reason: 'at $ms ms');
      }
    });
  });

  group('what counts as synced', () {
    test('an UNSYNCED document is read as plain text', () {
      expect(
        isSynced(doc([line('one')], sync: LyricsSyncType.unsynced)),
        isFalse,
      );
    });

    test('a document claiming timing but carrying none is read as plain', () {
      // The claim is the Hub's; the timings are the provider's. Following a playhead against lines
      // that have no offsets would highlight nothing forever.
      expect(isSynced(doc([line('one'), line('two')])), isFalse);
    });

    test('one timed line is enough to follow', () {
      expect(isSynced(doc([line('one', at: 0), line('two')])), isTrue);
    });
  });

  group('the cache', () {
    test('a hit is fetched once and then remembered', () async {
      var calls = 0;
      final repository = LyricsRepository(
        fetch: (id) async {
          calls++;
          return doc([line('one', at: 0)]);
        },
      );

      expect((await repository.forTrack('track-1'))?.lines.length, 1);
      expect(await repository.forTrack('track-1'), isNotNull);
      expect(calls, 1);
    });

    test('a 404 is remembered as "no lyrics", not raised', () async {
      var calls = 0;
      final repository = LyricsRepository(
        fetch: (id) async {
          calls++;
          throw _missing;
        },
      );

      expect(await repository.forTrack('track-1'), isNull);
      expect(await repository.forTrack('track-1'), isNull);
      // The point of the negative cache: shuffling back to a track with no lyrics does not ask the
      // Hub again, and the Hub does not ask its provider again.
      expect(calls, 1);
    });

    test('the miss expires so lyrics added elsewhere can appear', () async {
      var now = 0;
      var calls = 0;
      final repository = LyricsRepository(
        missTtl: const Duration(minutes: 5),
        clock: () => now,
        fetch: (id) async {
          calls++;
          return calls == 1 ? throw _missing : doc([line('one', at: 0)]);
        },
      );

      expect(await repository.forTrack('track-1'), isNull);
      now += const Duration(minutes: 4).inMilliseconds;
      expect(await repository.forTrack('track-1'), isNull);
      expect(calls, 1);

      // "No lyrics" is a statement about the provider today, not about the song. Somebody who
      // writes lyrics on the desktop should not have to restart the phone.
      now += const Duration(minutes: 2).inMilliseconds;
      expect(await repository.forTrack('track-1'), isNotNull);
      expect(calls, 2);
    });

    test('a hit does not expire', () async {
      var now = 0;
      var calls = 0;
      final repository = LyricsRepository(
        clock: () => now,
        fetch: (id) async {
          calls++;
          return doc([line('one', at: 0)]);
        },
      );

      await repository.forTrack('track-1');
      now += const Duration(days: 1).inMilliseconds;
      expect(await repository.forTrack('track-1'), isNotNull);
      expect(calls, 1);
    });

    test('a failure that is not a 404 propagates and is not cached', () async {
      var calls = 0;
      final repository = LyricsRepository(
        fetch: (id) async {
          calls++;
          throw _offline;
        },
      );

      // A tunnel is not evidence about the song, and caching it as "no lyrics" would outlive the
      // tunnel by five minutes.
      await expectLater(repository.forTrack('track-1'), throwsA(_offline));
      await expectLater(repository.forTrack('track-1'), throwsA(_offline));
      expect(calls, 2);
    });

    test('two readers of the same track share one request', () async {
      var calls = 0;
      final gate = Completer<Lyrics>();
      final repository = LyricsRepository(
        fetch: (id) {
          calls++;
          return gate.future;
        },
      );

      final first = repository.forTrack('track-1');
      final second = repository.forTrack('track-1');
      gate.complete(doc([line('one', at: 0)]));
      expect(await first, isNotNull);
      expect(await second, isNotNull);
      expect(calls, 1);
    });

    test('the oldest track is dropped once the cache is full', () async {
      var calls = 0;
      final repository = LyricsRepository(
        capacity: 2,
        fetch: (id) async {
          calls++;
          return doc([line(id, at: 0)]);
        },
      );

      await repository.forTrack('a');
      await repository.forTrack('b');
      await repository.forTrack('c');
      expect(calls, 3);

      // `b` and `c` are still held; `a` was evicted and costs another request.
      await repository.forTrack('c');
      await repository.forTrack('b');
      expect(calls, 3);
      await repository.forTrack('a');
      expect(calls, 4);
    });

    test('forgetting a track re-asks for it', () async {
      var calls = 0;
      final repository = LyricsRepository(
        fetch: (id) async {
          calls++;
          return doc([line('one', at: 0)]);
        },
      );

      await repository.forTrack('track-1');
      repository.forget('track-1');
      await repository.forTrack('track-1');
      expect(calls, 2);
    });
  });
}
