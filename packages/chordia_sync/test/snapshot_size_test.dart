import 'dart:convert';

import 'package:chordia_sync/chordia_sync.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

/// A queue long enough to overrun the relay's frame cap.
PlayerSyncSnapshot hugeSnapshot({int length = 6000, int currentIndex = 3000}) =>
    testSnapshot(
      queue: [
        for (var i = 0; i < length; i++)
          testTrack(
            'track-$i',
            titleSuffix: ' — a title long enough to make this queue realistic',
          ),
      ],
      currentIndex: currentIndex,
    );

int byteLength(String json) => utf8.encode(json).length;

void main() {
  group('the relay frame cap', () {
    test('a normal snapshot passes through untouched', () {
      final snapshot = testSnapshot();
      final fitted = PlayerSyncProtocol.fitSnapshot(snapshot);

      expect(fitted.truncated, isFalse);
      expect(identical(fitted.snapshot, snapshot), isTrue);
      expect(fitted.snapshot.history, isNotEmpty);
    });

    test('an oversized snapshot is trimmed to fit and marked truncated', () {
      final snapshot = hugeSnapshot();
      expect(
        byteLength(PlayerSyncProtocol.encodeSnapshot(snapshot)),
        greaterThan(kPlayerSnapshotBudgetBytes),
      );

      final fitted = PlayerSyncProtocol.fitSnapshot(snapshot);

      expect(fitted.truncated, isTrue);
      expect(
        byteLength(fitted.json),
        lessThanOrEqualTo(kPlayerSnapshotBudgetBytes),
      );
      // Comfortably under the Hub's own cap, which is measured on the whole envelope.
      expect(byteLength(fitted.json), lessThan(kPlayerFrameCapBytes));
      expect(fitted.snapshot.queue.length, lessThan(snapshot.queue.length));
      expect(fitted.snapshot.history, isEmpty);
    });

    test('the trimmed queue still points at the track that is playing', () {
      final snapshot = hugeSnapshot();
      final fitted = PlayerSyncProtocol.fitSnapshot(snapshot);

      // Remapping the index is the whole difference between a hand-off that resumes the right
      // track and one that starts something else 3000 entries away.
      expect(
        fitted.snapshot.queue[fitted.snapshot.currentIndex].id,
        snapshot.queue[snapshot.currentIndex].id,
      );
      expect(fitted.snapshot.current, snapshot.current);
    });

    test('the window keeps more of the queue ahead than behind', () {
      final fitted = PlayerSyncProtocol.fitSnapshot(hugeSnapshot());
      final index = fitted.snapshot.currentIndex;
      final ahead = fitted.snapshot.queue.length - index - 1;

      expect(ahead, greaterThan(index));
    });

    test(
      'a queue near the end of the list keeps the tail rather than overrunning it',
      () {
        final snapshot = hugeSnapshot(currentIndex: 5999);
        final fitted = PlayerSyncProtocol.fitSnapshot(snapshot);

        expect(
          fitted.snapshot.queue[fitted.snapshot.currentIndex].id,
          'track-5999',
        );
        expect(fitted.snapshot.queue.last.id, 'track-5999');
      },
    );

    test('dropping the history alone is preferred to trimming the queue', () {
      final snapshot = testSnapshot(
        queue: [for (var i = 0; i < 20; i++) testTrack('q$i')],
        currentIndex: 5,
      ).copyWith(history: [for (var i = 0; i < 400; i++) testTrack('h$i')]);
      final full = byteLength(PlayerSyncProtocol.encodeSnapshot(snapshot));

      final fitted = PlayerSyncProtocol.fitSnapshot(
        snapshot,
        budgetBytes: full ~/ 2,
      );

      expect(fitted.truncated, isTrue);
      expect(fitted.snapshot.history, isEmpty);
      expect(fitted.snapshot.queue, hasLength(20));
      expect(fitted.snapshot.currentIndex, 5);
    });

    test('a snapshot that cannot fit at all is still sent', () {
      // Nothing left to give up. A frame the relay drops leaves the mesh exactly where sending
      // nothing would, so refusing to send would only lose the fields that DO fit.
      final fitted = PlayerSyncProtocol.fitSnapshot(
        testSnapshot(),
        budgetBytes: 10,
      );

      expect(fitted.snapshot.queue, isEmpty);
      expect(fitted.json, isNotEmpty);
    });

    test('the truncation flag survives the wire', () {
      final fitted = PlayerSyncProtocol.fitSnapshot(hugeSnapshot());
      final decoded = PlayerSyncProtocol.decodeSnapshot(fitted.json);

      expect(decoded!.truncated, isTrue);
      expect(decoded.queue.length, fitted.snapshot.queue.length);
    });

    test(
      'publishing an oversized snapshot sends and records the trimmed copy',
      () async {
        final clock = MutableClock(1000);
        final peer = TestPeer('aaa', clock: clock);
        peer.controller.claimIfNoLiveTarget();
        peer.link.drain();

        final snapshot = hugeSnapshot();
        expect(peer.controller.publishSnapshot(snapshot), isTrue);

        final frame = peer.link.outbox.single;
        final wire = frame['snapshot']! as String;
        expect(byteLength(wire), lessThanOrEqualTo(kPlayerSnapshotBudgetBytes));

        // What this device believes it published has to be what the others received, or its own
        // picker and theirs disagree about the queue.
        final recorded = peer.controller.state.latestSnapshot!;
        expect(recorded.truncated, isTrue);
        expect(recorded.queue.length, lessThan(snapshot.queue.length));
        expect(
          jsonDecode(wire),
          isA<Map<String, Object?>>().having(
            (json) => (json['queue']! as List).length,
            'queue length',
            recorded.queue.length,
          ),
        );
        await peer.dispose();
      },
    );
  });
}
