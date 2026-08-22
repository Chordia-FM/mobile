import 'dart:convert';

import 'package:chordia_api/chordia_api.dart';
import 'package:chordia_db/chordia_db.dart';
import 'package:chordia_player/src/scrobble/scrobble_latch.dart';
import 'package:chordia_player/src/scrobble/scrobble_service.dart';
import 'package:chordia_sync/chordia_sync.dart';
import 'package:drift/native.dart';
import 'package:test/test.dart';

PlayerTrack track({int durationMs = 300000}) => PlayerTrack(
  qid: 'qid-1',
  id: 'track-1',
  title: 'A Song',
  artist: 'An Artist',
  album: 'An Album',
  durationMs: durationMs,
  libraryId: 'lib-1',
  trackRef: 'ref-1',
  contentHash: 'hash-1',
);

ScrobbleBatchResponse ok(List<ListeningEvent> events) => ScrobbleBatchResponse(
  accepted: events.length,
  duplicates: 0,
  rejected: const [],
);

void main() {
  group('ScrobbleLatch', () {
    test('fires at half a track shorter than eight minutes', () {
      // 300s track -> threshold 150s.
      final latch = ScrobbleLatch()..start(qid: 'q', durationMs: 300000);

      String? fired;
      for (var ms = 1000; ms <= 200000; ms += 1000) {
        fired ??= latch.sample(ms);
      }

      expect(fired, 'q');
      expect(latch.thresholdMs, 150000);
    });

    test('does not fire one sample short of the threshold', () {
      final latch = ScrobbleLatch()..start(qid: 'q', durationMs: 300000);

      String? fired;
      for (var ms = 1000; ms <= 149000; ms += 1000) {
        fired ??= latch.sample(ms);
      }

      expect(fired, isNull, reason: '149s of a 150s threshold is not a play');
    });

    test('a long track needs four minutes rather than half of it', () {
      // 20 minutes: half would be 10, but the absolute arm caps it at 4.
      final latch = ScrobbleLatch()..start(qid: 'q', durationMs: 1200000);
      expect(latch.thresholdMs, 240000);

      String? fired;
      for (var ms = 1000; ms <= 241000; ms += 1000) {
        fired ??= latch.sample(ms);
      }
      expect(fired, 'q');
    });

    test('fires exactly once however long playback continues', () {
      final latch = ScrobbleLatch()..start(qid: 'q', durationMs: 60000);

      final fires = <String>[];
      for (var ms = 1000; ms <= 60000; ms += 1000) {
        final f = latch.sample(ms);
        if (f != null) fires.add(f);
      }

      expect(fires, hasLength(1));
    });

    test('a pause accrues nothing', () {
      final latch = ScrobbleLatch()..start(qid: 'q', durationMs: 60000);

      for (var ms = 1000; ms <= 10000; ms += 1000) {
        latch.sample(ms);
      }
      final atPause = latch.msPlayed;
      for (var i = 0; i < 20; i++) {
        latch.sample(10000, playing: false);
      }

      expect(
        latch.msPlayed,
        atPause,
        reason: 'paused time is not listened time',
      );
    });

    test('seeking forward does not credit audio that was skipped', () {
      // The whole point of accruing deltas rather than reading the playhead: a listener who drags
      // to the end has not heard the track.
      final latch = ScrobbleLatch()..start(qid: 'q', durationMs: 300000);

      latch.sample(1000);
      final fired = latch.sample(280000);

      expect(fired, isNull);
      expect(latch.msPlayed, lessThan(5000));
    });

    test('a rewind does not double-count the replayed stretch', () {
      final latch = ScrobbleLatch()..start(qid: 'q', durationMs: 300000);

      for (var ms = 1000; ms <= 100000; ms += 1000) {
        latch.sample(ms);
      }
      final afterFirstPass = latch.msPlayed;

      latch.sample(0); // rewind to the start
      for (var ms = 1000; ms <= 40000; ms += 1000) {
        latch.sample(ms);
      }

      expect(latch.msPlayed, afterFirstPass + 40000);
    });

    test('restarting the same entry lets it scrobble again', () {
      // Repeat-one replays the same qid, and each replay is its own play.
      final latch = ScrobbleLatch()..start(qid: 'q', durationMs: 60000);
      for (var ms = 1000; ms <= 60000; ms += 1000) {
        latch.sample(ms);
      }
      expect(latch.hasFired, isTrue);

      latch.start(qid: 'q', durationMs: 60000);
      expect(latch.hasFired, isFalse);
      expect(latch.msPlayed, 0);
    });

    test('an unknown duration falls back to the four-minute arm', () {
      final latch = ScrobbleLatch()..start(qid: 'q', durationMs: 0);
      expect(latch.thresholdMs, ScrobbleLatch.fullPlayCeilingMs);
    });

    test('samples arriving after clear accrue nothing', () {
      final latch = ScrobbleLatch()..start(qid: 'q', durationMs: 60000);
      latch.sample(1000);
      latch.clear();

      expect(latch.sample(2000), isNull);
      expect(latch.msPlayed, 0);
    });
  });

  group('ScrobbleService', () {
    late ChordiaDatabase db;
    late ScrobbleQueueDao queue;

    setUp(() {
      db = ChordiaDatabase(NativeDatabase.memory());
      queue = db.scrobbleQueueDao;
    });

    tearDown(() => db.close());

    ScrobbleService build({
      required ScrobbleBatchSender send,
      int Function()? clock,
    }) => ScrobbleService(
      queue: queue,
      send: send,
      clock: clock,
      deviceId: 'device-1',
      deviceLabel: 'A Phone',
    );

    test('writes the event before any network call', () async {
      var sendCalls = 0;
      final service = build(
        send: (events) async {
          sendCalls++;
          return ok(events);
        },
      );

      await service.record(track: track(), startedAt: 1700000000000);

      expect(await queue.count(), 1, reason: 'durable first');
      expect(sendCalls, 0, reason: 'recording does not send');
    });

    test('stamps the event as coming from mobile, with its library', () async {
      final service = build(send: (e) async => ok(e));

      final event = await service.record(
        track: track(),
        startedAt: 1700000000000,
      );

      expect(event.clientType, ClientType.mobile);
      expect(event.libraryId, 'lib-1');
      expect(event.fingerprint.contentHash, 'hash-1');
      expect(event.eventId, isNotEmpty);
    });

    test('a successful flush clears what the Hub accepted', () async {
      final service = build(send: (e) async => ok(e));
      await service.record(track: track(), startedAt: 1);
      await service.record(track: track(), startedAt: 2);

      final result = await service.flush();

      expect(result.accepted, 2);
      expect(await queue.count(), 0);
    });

    test(
      'duplicates are cleared too, since the Hub already has them',
      () async {
        final service = build(
          send: (e) async => ScrobbleBatchResponse(
            accepted: 0,
            duplicates: e.length,
            rejected: const [],
          ),
        );
        await service.record(track: track(), startedAt: 1);

        final result = await service.flush();

        expect(result.duplicates, 1);
        expect(
          await queue.count(),
          0,
          reason: 'retrying a duplicate achieves nothing',
        );
      },
    );

    test('rejected events are dropped rather than retried forever', () async {
      // The web client clears unconditionally and never reads this list; keeping a rejected event
      // would block every younger one behind it.
      late String rejectedId;
      final service = build(
        send: (e) async {
          rejectedId = e.first.eventId;
          return ScrobbleBatchResponse(
            accepted: 0,
            duplicates: 0,
            rejected: [rejectedId],
          );
        },
      );
      await service.record(track: track(), startedAt: 1);

      final result = await service.flush();

      expect(result.rejected, 1);
      expect(await queue.count(), 0);
    });

    test('a network failure keeps everything for the next attempt', () async {
      final service = build(
        send: (e) async => throw const ApiException(
          status: 0,
          title: 'offline',
          method: 'POST',
          path: '/v1/scrobbles:batch',
        ),
      );
      await service.record(track: track(), startedAt: 1);

      final result = await service.flush();

      expect(result.outcome, ScrobbleFlushOutcome.failed);
      expect(
        await queue.count(),
        1,
        reason: 'nothing is lost to a flaky network',
      );
    });

    test('backs off rather than hammering after a failure', () async {
      var calls = 0;
      var now = 1000;
      final service = build(
        clock: () => now,
        send: (e) async {
          calls++;
          throw const ApiException(
            status: 0,
            title: 'offline',
            method: 'POST',
            path: '/v1/scrobbles:batch',
          );
        },
      );
      await service.record(track: track(), startedAt: 1);

      await service.flush();
      expect(calls, 1);

      final deferred = await service.flush();
      expect(deferred.outcome, ScrobbleFlushOutcome.deferred);
      expect(
        calls,
        1,
        reason: 'the second attempt was inside the backoff window',
      );

      now = service.nextAttemptAt + 1;
      await service.flush();
      expect(calls, 2, reason: 'and allowed once the window passed');
    });

    test('force sends even inside the backoff window', () async {
      var calls = 0;
      var now = 1000;
      var fail = true;
      final service = build(
        clock: () => now,
        send: (e) async {
          calls++;
          if (fail) {
            throw const ApiException(
              status: 0,
              title: 'offline',
              method: 'POST',
              path: '/v1/scrobbles:batch',
            );
          }
          return ok(e);
        },
      );
      await service.record(track: track(), startedAt: 1);
      await service.flush();
      fail = false;

      final result = await service.flush(force: true);

      expect(calls, 2);
      expect(result.outcome, ScrobbleFlushOutcome.delivered);
    });

    test('concurrent flushes share one attempt', () async {
      var calls = 0;
      final service = build(
        send: (e) async {
          calls++;
          await Future<void>.delayed(const Duration(milliseconds: 10));
          return ok(e);
        },
      );
      await service.record(track: track(), startedAt: 1);

      await Future.wait([service.flush(), service.flush(), service.flush()]);

      expect(calls, 1);
    });

    test(
      'an unreadable payload is dropped instead of blocking the queue',
      () async {
        // A poison pill would otherwise sit at the head forever and every younger event behind it.
        await queue.enqueue(
          eventId: 'bad-1',
          payloadJson: '{not json',
          createdAt: 1,
        );
        final service = build(send: (e) async => ok(e));

        final result = await service.flush();

        expect(result.rejected, 1);
        expect(await queue.count(), 0);
      },
    );

    test('the persisted payload round-trips back into an event', () async {
      final service = build(send: (e) async => ok(e));
      final written = await service.record(track: track(), startedAt: 42);

      final rows = await queue.takeBatch(limit: 10);
      final decoded = ListeningEvent.fromJson(
        jsonDecode(rows.single.payloadJson) as Map<String, Object?>,
      );

      expect(decoded.eventId, written.eventId);
      expect(decoded.startedAt, 42);
      expect(decoded.clientType, ClientType.mobile);
    });
  });
}
