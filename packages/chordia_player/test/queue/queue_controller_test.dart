import 'dart:math';

import 'package:chordia_player/src/queue/continuation.dart';
import 'package:chordia_player/src/queue/queue_controller.dart';
import 'package:chordia_player/src/queue/queue_events.dart';
import 'package:chordia_sync/chordia_sync.dart';
import 'package:test/test.dart';

PlayerTrack t(String id) => PlayerTrack(
  id: id,
  title: 'Title $id',
  artist: 'Artist',
  album: 'Album',
  durationMs: 200000,
  libraryId: 'lib',
  trackRef: 'ref-$id',
  contentHash: 'hash-$id',
);

List<PlayerTrack> tracks(int n) => List.generate(n, (i) => t('t${i + 1}'));

/// Yields a scripted sequence, so a shuffle assertion is about behaviour rather than about luck.
class ScriptedRandom implements Random {
  ScriptedRandom(this.values);

  final List<int> values;
  var _at = 0;

  @override
  int nextInt(int max) {
    final v = values[_at % values.length];
    _at++;
    return v % max;
  }

  @override
  bool nextBool() => nextInt(2) == 0;

  @override
  double nextDouble() => nextInt(1000) / 1000;
}

/// Lets the microtasks a continuation runs on drain before assertions.
Future<void> settle() async {
  for (var i = 0; i < 4; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late List<QueueEvent> events;

  QueueController build({
    Random? random,
    ContinuationFetcher? fetcher,
    int lookahead = 3,
    void Function(String)? onExhausted,
  }) {
    var counter = 0;
    final c = QueueController(
      random: random,
      newQid: () => 'qid-${++counter}',
      lookahead: lookahead,
      continuationFetcher: fetcher,
      onSourceExhausted: onExhausted,
    );
    events = [];
    c.events.listen(events.add);
    return c;
  }

  List<int> played() =>
      events.whereType<PlayEntryRequested>().map((e) => e.index).toList();

  group('playQueue', () {
    test('starts at the requested index and reports it once', () {
      final c = build()..playQueue(tracks(4), startIndex: 2);

      expect(c.currentIndex, 2);
      expect(c.current!.id, 't3');
      expect(played(), [2]);
    });

    test('gives every entry a distinct qid so a repeat is addressable', () {
      final dup = t('same');
      final c = build()..playQueue([dup, dup, dup]);

      expect(
        c.queue.map((e) => e.qid).toSet(),
        hasLength(3),
        reason: 'the same track queued twice is two entries',
      );
    });
  });

  group('repeat', () {
    test('off stops at the end rather than wrapping', () {
      final c = build()..playQueue(tracks(3), startIndex: 2);
      c.next();

      expect(c.currentIndex, 2, reason: 'still on the last entry');
      expect(played(), [2], reason: 'nothing new was started');
    });

    test('all wraps to the top', () {
      final c = build()
        ..playQueue(tracks(3), startIndex: 2)
        ..setRepeatMode(RepeatMode.all)
        ..next();

      expect(c.currentIndex, 0);
    });

    test('one replays the same entry as a hard start', () {
      // A reload rather than a seek, matching the web client, so a repeated track's scrobble and
      // now-playing report look like any other track change.
      final c = build()
        ..playQueue(tracks(3))
        ..setRepeatMode(RepeatMode.one)
        ..next();

      expect(c.currentIndex, 0);
      expect(played(), [0, 0]);
    });
  });

  group('shuffle', () {
    test('never picks the entry already playing', () {
      // The web client loops `while (r === i)`; this shifts past the current index instead, which
      // is the same distribution but cannot hang against a scripted generator.
      for (var draw = 0; draw < 6; draw++) {
        final c = build(random: ScriptedRandom([draw]))
          ..playQueue(tracks(5), startIndex: 2)
          ..setShuffleMode(true)
          ..next();
        expect(c.currentIndex, isNot(2));
      }
    });

    test('reaches every other entry across draws', () {
      final seen = <int>{};
      for (var draw = 0; draw < 4; draw++) {
        final c = build(random: ScriptedRandom([draw]))
          ..playQueue(tracks(5))
          ..setShuffleMode(true)
          ..next();
        seen.add(c.currentIndex);
      }
      expect(seen, {1, 2, 3, 4});
    });

    test('a single-entry queue does not deadlock', () {
      final c = build(random: ScriptedRandom([0]))
        ..playQueue(tracks(1))
        ..setShuffleMode(true)
        ..next();

      expect(c.currentIndex, 0);
    });
  });

  group('prev', () {
    test('restarts the current track when past the threshold', () {
      final c = build()..playQueue(tracks(3), startIndex: 1);
      c.readPositionMs = () => 99999;

      c.prev();

      expect(c.currentIndex, 1);
      expect(events.whereType<RestartCurrentRequested>(), hasLength(1));
    });

    test('goes back a track when early in the current one', () {
      final c = build()..playQueue(tracks(3), startIndex: 1);
      c.readPositionMs = () => 0;

      c.prev();

      expect(c.currentIndex, 0);
    });

    test(
      'restarts at the head of the queue, where there is nowhere back to',
      () {
        final c = build()..playQueue(tracks(3));
        c.readPositionMs = () => 0;

        c.prev();

        expect(c.currentIndex, 0);
        expect(events.whereType<RestartCurrentRequested>(), hasLength(1));
      },
    );
  });

  group('removeFromQueue', () {
    test('removing before the current entry keeps the same track playing', () {
      final c = build()..playQueue(tracks(4), startIndex: 2);
      final playing = c.current!.qid;

      c.removeFromQueue(0);

      expect(c.currentIndex, 1, reason: 'the index shifted down with the list');
      expect(
        c.current!.qid,
        playing,
        reason: 'the same entry is still playing',
      );
    });

    test('removing after the current entry leaves the index alone', () {
      final c = build()..playQueue(tracks(4), startIndex: 1);

      c.removeFromQueue(3);

      expect(c.currentIndex, 1);
      expect(c.queue, hasLength(3));
    });

    test('removing the entry that is playing does not interrupt it', () {
      // Matches the web client (context.tsx removeFromQueue, which adjusts only for an index
      // BELOW the current one). Taking a track out of the up-next list is not a request to stop
      // hearing it, so the audio continues and `current` keeps naming what is actually sounding —
      // even though that entry is no longer in the queue behind it.
      final c = build()..playQueue(tracks(4), startIndex: 1);
      final playing = c.current!.qid;

      c.removeFromQueue(1);

      expect(c.current!.qid, playing);
      expect(c.current!.id, 't2');
      expect(c.queue.map((e) => e.id), ['t1', 't3', 't4']);
      expect(played(), [1], reason: 'nothing was restarted');
    });
  });

  group('reorderQueue', () {
    test('follows the entry that is playing', () {
      final c = build()..playQueue(tracks(4));
      final playing = c.current!.qid;

      c.reorderQueue(0, 3);

      expect(c.current!.qid, playing);
      expect(c.currentIndex, 3);
    });

    test('adjusts the index when another entry moves across it', () {
      final c = build()..playQueue(tracks(4), startIndex: 2);
      final playing = c.current!.qid;

      c.reorderQueue(0, 3);

      expect(c.current!.qid, playing);
      expect(c.currentIndex, 1);
    });
  });

  group('history', () {
    test('is capped and de-duplicated by track id', () {
      final c = build()..playQueue(tracks(60));
      for (var i = 0; i < 59; i++) {
        c.next();
      }

      expect(c.history.length, lessThanOrEqualTo(50));
      final ids = c.history.map((h) => h.id).toList();
      expect(
        ids.toSet(),
        hasLength(ids.length),
        reason: 'no repeats in history',
      );
    });
  });

  group('playNext and enqueue', () {
    test('playNext lands immediately after the current entry', () {
      final c = build()..playQueue(tracks(3));

      c.playNext(t('injected'));

      expect(c.queue[1].id, 'injected');
    });

    test('enqueue lands at the end', () {
      final c = build()..playQueue(tracks(3));

      c.enqueue(t('injected'));

      expect(c.queue.last.id, 'injected');
    });
  });

  group('continuation', () {
    test('fires within the lookahead and appends the page', () async {
      final requests = <ContinuationRequest>[];
      final c =
          build(
            fetcher: (r) async {
              requests.add(r);
              return ContinuationPage(tracks: [t('more1')], cursor: 'c2');
            },
          )..playQueue(
            tracks(4),
            context: const ArtistContext(id: 'artist-1', name: 'An Artist'),
          );

      c.next();
      await settle();

      expect(requests, isNotEmpty, reason: 'asked the station for more');
      expect(c.queue.map((e) => e.id), contains('more1'));
    });

    test('does not fire when the listener turned autoplay off', () async {
      var calls = 0;
      final c =
          build(
              fetcher: (r) async {
                calls++;
                return const ContinuationPage.empty();
              },
            )
            ..autoplay = false
            ..playQueue(
              tracks(2),
              context: const ArtistContext(id: 'a', name: 'A'),
            );

      c.next();
      await settle();

      expect(calls, 0);
    });

    test('an exhausted station is not asked again', () async {
      var calls = 0;
      final c =
          build(
            lookahead: 1,
            fetcher: (r) async {
              calls++;
              return const ContinuationPage.empty();
            },
          )..playQueue(
            tracks(2),
            context: const ArtistContext(id: 'a', name: 'A'),
          );

      c.next();
      await settle();
      final afterFirst = calls;

      c.next();
      await settle();

      expect(calls, afterFirst, reason: 'an empty page means stop, not retry');
    });

    test('a smart playlist reports that it ran out', () async {
      final exhausted = <String>[];
      final c = build(onExhausted: exhausted.add)
        ..playQueue(
          tracks(1),
          context: const SmartPlaylistContext(id: 'smart-1', name: 'Smart'),
        );

      c.next();
      await settle();

      expect(exhausted, ['smart-1']);
    });
  });

  group('sleep timer', () {
    test('stop-after-this-track is consumed at the track boundary', () {
      final c = build()
        ..playQueue(tracks(3))
        ..setSleepTimer(const SleepAfterCurrentTrack());

      c.onTrackEnded();

      expect(c.currentIndex, 0, reason: 'playback did not advance');
      expect(c.sleepTimer, isNull, reason: 'the timer disarmed itself');
    });

    test('a track ending without a timer advances normally', () {
      final c = build()..playQueue(tracks(3));

      c.onTrackEnded();

      expect(c.currentIndex, 1);
    });
  });
}
