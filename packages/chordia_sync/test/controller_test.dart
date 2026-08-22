import 'package:chordia_sync/chordia_sync.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  late MutableClock clock;

  setUp(() => clock = MutableClock(1000));

  /// A peer that owns playback, with its first claim already flushed out of the outbox.
  TestPeer owningPeer(String tabId) {
    final peer = TestPeer(tabId, clock: clock);
    peer.controller.claimIfNoLiveTarget();
    peer.link.drain();
    return peer;
  }

  group('membership', () {
    test('a device with no link plays locally and joins nothing', () {
      final controller = PlayerSyncController(
        tabId: 'aaa',
        deviceLabel: 'Phone',
        clock: clock.call,
      );

      expect(controller.state.available, isFalse);
      expect(controller.localPlaybackAllowed, isTrue);
      expect(controller.announce(), isFalse);
      expect(controller.claimIfNoLiveTarget(), isFalse);
    });

    test('an announce adds the sender to the device list', () async {
      final peer = TestPeer('aaa', clock: clock);
      peer.controller.announce();

      peer.link.deliverIn({
        'type': 'announce',
        'tabId': 'bbb',
        'label': 'Desktop',
        'at': clock.now,
        'deviceId': 'device-b',
        'seq': 1,
      });

      expect(
        peer.controller.state.devices.map((device) => device.tabId),
        containsAll(<String>['aaa', 'bbb']),
      );
      expect(
        peer.controller.state.devices
            .firstWhere((device) => device.tabId == 'bbb')
            .deviceId,
        'device-b',
      );
      await peer.dispose();
    });

    test('a device stops being listed once its announce goes stale', () async {
      final peer = TestPeer('aaa', clock: clock);
      peer.controller.announce();
      peer.link.deliverIn({
        'type': 'announce',
        'tabId': 'bbb',
        'label': 'Desktop',
        'at': clock.now,
        'seq': 1,
      });

      // Exactly at the timeout is still live — the boundary is inclusive, so one late heartbeat
      // does not evict a device somebody is about to send music to.
      clock.advance(kPlayerLivenessTimeout);
      peer.controller.expire();
      expect(peer.controller.state.devices, hasLength(2));

      clock.advance(const Duration(milliseconds: 1));
      peer.controller.expire();
      expect(peer.controller.state.devices.map((device) => device.tabId), [
        'aaa',
      ]);
      await peer.dispose();
    });

    test('this device never expires itself', () async {
      // A backgrounded phone's timers resume late. It is still here.
      final peer = TestPeer('aaa', clock: clock);
      peer.controller.announce();

      clock.advance(const Duration(minutes: 5));
      peer.controller.expire();

      expect(peer.controller.state.devices.map((device) => device.tabId), [
        'aaa',
      ]);
      await peer.dispose();
    });

    test(
      'a departure removes the sender and clears it as the playback target',
      () async {
        final peer = TestPeer('aaa', clock: clock);
        peer.controller.announce();
        peer.link
          ..deliverIn({
            'type': 'announce',
            'tabId': 'bbb',
            'label': 'Desktop',
            'at': clock.now,
            'seq': 1,
          })
          ..deliverIn({
            'type': 'claim',
            'tabId': 'bbb',
            'at': clock.now,
            'seq': 2,
          });
        expect(peer.controller.state.activeTabId, 'bbb');

        peer.link.deliverIn({
          'type': 'departure',
          'tabId': 'bbb',
          'at': clock.now,
          'seq': 3,
        });

        expect(peer.controller.state.activeTabId, isNull);
        expect(peer.controller.state.devices.map((device) => device.tabId), [
          'aaa',
        ]);
        await peer.dispose();
      },
    );

    test('a whoIsThere is answered with an announce', () async {
      final peer = TestPeer('aaa', clock: clock);
      peer.link.drain();

      peer.link.deliverIn({'type': 'whoIsThere', 'tabId': 'bbb', 'seq': 1});

      expect(peer.link.outbox.single['type'], 'announce');
      expect(peer.link.outbox.single['tabId'], 'aaa');
      await peer.dispose();
    });

    test(
      'losing the link drops the mesh and re-enables local playback',
      () async {
        final peer = TestPeer('aaa', clock: clock);
        peer.link.deliverIn({
          'type': 'claim',
          'tabId': 'bbb',
          'at': clock.now,
          'seq': 1,
        });
        expect(peer.controller.localPlaybackAllowed, isFalse);

        peer.link.broken = true;
        expect(peer.controller.announce(), isFalse);

        expect(peer.controller.state.available, isFalse);
        expect(peer.controller.state.activeTabId, isNull);
        expect(peer.controller.localPlaybackAllowed, isTrue);
        await peer.dispose();
      },
    );
  });

  group('de-duplication', () {
    test('a replayed (tabId, seq) is dispatched exactly once', () async {
      final peer = owningPeer('aaa');
      Map<String, Object?> nextCommand(int seq) => {
        'type': 'command',
        'tabId': 'bbb',
        'activeTabId': 'aaa',
        'command': const {'type': 'next'},
        'seq': seq,
      };

      peer.link
        ..deliverIn(nextCommand(7))
        ..deliverIn(nextCommand(7));

      // Twice would skip two tracks, which is the bug the set exists to prevent.
      expect(peer.commands, hasLength(1));
      expect(peer.commands.single, const SimpleCommand(SimpleCommandKind.next));
      await peer.dispose();
    });

    test('an out-of-order sequence number is still delivered', () async {
      // The rule a per-sender high-water mark would break: a command that lost a race to a later
      // message must not be swallowed.
      final peer = owningPeer('aaa');
      Map<String, Object?> command(String type, int seq) => {
        'type': 'command',
        'tabId': 'bbb',
        'activeTabId': 'aaa',
        'command': {'type': type},
        'seq': seq,
      };

      peer.link
        ..deliverIn(command('pause', 9))
        ..deliverIn(command('resume', 8));

      expect(peer.commands, [
        const SimpleCommand(SimpleCommandKind.pause),
        const SimpleCommand(SimpleCommandKind.resume),
      ]);
      await peer.dispose();
    });

    test('the seen set remembers exactly the last 512 frames', () async {
      final peer = owningPeer('aaa');
      Map<String, Object?> nextCommand(int seq) => {
        'type': 'command',
        'tabId': 'bbb',
        'activeTabId': 'aaa',
        'command': const {'type': 'next'},
        'seq': seq,
      };

      peer.link.deliverIn(nextCommand(1));
      // 511 more frames leaves the first still remembered...
      for (var seq = 0; seq < kSeenMessageLimit - 1; seq++) {
        peer.link.deliverIn({
          'type': 'aFutureMessageType',
          'tabId': 'ccc',
          'seq': seq,
        });
      }
      peer.link.deliverIn(nextCommand(1));
      expect(peer.commands, hasLength(1));

      // ...one more evicts it, and the replay is treated as new.
      peer.link.deliverIn({
        'type': 'aFutureMessageType',
        'tabId': 'ccc',
        'seq': kSeenMessageLimit,
      });
      peer.link.deliverIn(nextCommand(1));
      expect(peer.commands, hasLength(2));
      await peer.dispose();
    });

    test('a frame echoed back from this device is ignored', () async {
      final peer = owningPeer('aaa');

      peer.link.deliverIn({
        'type': 'command',
        'tabId': 'aaa',
        'activeTabId': 'aaa',
        'command': const {'type': 'next'},
        'seq': 1,
      });

      expect(peer.commands, isEmpty);
      await peer.dispose();
    });
  });

  group('ownership', () {
    test('two devices claiming at the same instant agree on one owner', () async {
      final a = TestPeer('aaa', clock: clock);
      final b = TestPeer('bbb', clock: clock);
      a.controller.announce();
      b.controller.announce();
      a.flushTo([b]);
      b.flushTo([a]);

      // Both claim before either has heard the other — the case the tie-break exists for.
      expect(a.controller.claimIfNoLiveTarget(), isTrue);
      expect(b.controller.claimIfNoLiveTarget(), isTrue);
      expect(a.controller.state.activeTabId, 'aaa');
      expect(b.controller.state.activeTabId, 'bbb');

      a.flushTo([b]);
      b.flushTo([a]);

      // Same claim time, so the higher tab id wins — on both devices, with no further messages.
      expect(a.controller.state.activeTabId, 'bbb');
      expect(b.controller.state.activeTabId, 'bbb');
      expect(
        a.controller.state.activeClaimAt,
        b.controller.state.activeClaimAt,
      );
      // The loser stops its engine before anything re-renders.
      expect(a.yields, 1);
      expect(b.yields, 0);
      await a.dispose();
      await b.dispose();
    });

    test('a later claim beats an earlier one regardless of tab id', () async {
      final peer = TestPeer('zzz', clock: clock);
      peer.controller.claimIfNoLiveTarget();

      peer.link.deliverIn({
        'type': 'claim',
        'tabId': 'aaa',
        'at': clock.now + 1,
        'seq': 1,
      });

      expect(peer.controller.state.activeTabId, 'aaa');
      expect(peer.yields, 1);
      await peer.dispose();
    });

    test('an older claim from a stale owner is rejected', () async {
      final peer = TestPeer('aaa', clock: clock);
      clock.advance(const Duration(seconds: 1));
      peer.controller.claimIfNoLiveTarget();

      peer.link.deliverIn({
        'type': 'claim',
        'tabId': 'bbb',
        'at': clock.now - 500,
        'seq': 1,
      });

      expect(peer.controller.state.activeTabId, 'aaa');
      expect(peer.yields, 0);
      await peer.dispose();
    });

    test('a command reaches only the device it is addressed to', () async {
      final peer = owningPeer('aaa');

      peer.link.deliverIn({
        'type': 'command',
        'tabId': 'bbb',
        'activeTabId': 'ccc',
        'command': const {'type': 'pause'},
        'seq': 1,
      });

      expect(peer.commands, isEmpty);
      await peer.dispose();
    });

    test('a whoIsActive makes the owner publish a snapshot', () async {
      final peer = owningPeer('aaa');
      peer.captured = testSnapshot();

      peer.link.deliverIn({'type': 'whoIsActive', 'tabId': 'bbb', 'seq': 1});

      final frame = peer.link.outbox.single;
      expect(frame['type'], 'snapshot');
      expect(frame['snapshot'], isA<String>());
      await peer.dispose();
    });

    test('a released owner leaves the last state frozen as paused', () async {
      final peer = TestPeer('aaa', clock: clock);
      peer.link.deliverIn({
        'type': 'snapshot',
        'tabId': 'bbb',
        'claimAt': clock.now,
        'snapshot': PlayerSyncProtocol.encodeSnapshot(
          testSnapshot(positionMs: 30000, tickAt: clock.now),
        ),
        'seq': 1,
      });
      clock.advance(const Duration(seconds: 4));

      peer.link.deliverIn({
        'type': 'released',
        'tabId': 'bbb',
        'at': clock.now,
        'seq': 2,
      });

      expect(peer.controller.state.activeTabId, isNull);
      expect(peer.controller.state.latestSnapshot!.state, PlaybackState.paused);
      // Frozen where it had got to, not where it was last reported.
      expect(peer.controller.state.latestSnapshot!.positionMs, 34000);
      await peer.dispose();
    });

    test('an owner that stops reporting while playing is expired', () async {
      final peer = TestPeer('aaa', clock: clock);
      peer.link
        ..deliverIn({
          'type': 'announce',
          'tabId': 'bbb',
          'label': 'Desktop',
          'at': clock.now,
          'seq': 1,
        })
        ..deliverIn({
          'type': 'position',
          'tabId': 'bbb',
          'claimAt': clock.now,
          'position': {
            'positionMs': 1000,
            'durationMs': 210000,
            'state': 'playing',
            'tickAt': clock.now,
          },
          'seq': 2,
        });
      expect(peer.controller.state.activeTabId, 'bbb');

      clock.advance(const Duration(milliseconds: 5001));
      peer.controller.expire();

      expect(peer.controller.state.activeTabId, isNull);
      expect(peer.controller.state.latestPosition!.state, PlaybackState.paused);
      await peer.dispose();
    });
  });

  group('transfer', () {
    test('a hand-off moves ownership, the queue, and the position', () async {
      final a = TestPeer('aaa', clock: clock);
      final b = TestPeer('bbb', clock: clock);
      a.controller.announce();
      b.controller.announce();
      a.flushTo([b]);
      b.flushTo([a]);

      a.controller.claimIfNoLiveTarget();
      a.captured = testSnapshot(
        queue: [testTrack('a'), testTrack('b'), testTrack('c')],
        currentIndex: 1,
        positionMs: 42000,
        tickAt: clock.now,
      );
      a.controller.publishSnapshot(a.captured!);
      a.flushTo([b]);
      expect(b.controller.state.activeTabId, 'aaa');

      expect(b.controller.requestTransfer('bbb'), isTrue);
      b.flushTo([a]);

      // The outgoing owner pauses before it publishes, so the two engines never overlap.
      expect(a.pauses, 1);
      expect(a.resumes, 0);
      expect(a.controller.state.activeTabId, 'bbb');
      expect(a.yields, 1);

      a.flushTo([b]);

      expect(b.controller.state.activeTabId, 'bbb');
      expect(b.adopted, hasLength(1));
      final adopted = b.adopted.single;
      expect(adopted.positionMs, 42000);
      expect(adopted.currentIndex, 1);
      expect(adopted.queue.map((track) => track.id), ['a', 'b', 'c']);
      expect(adopted.queue[adopted.currentIndex].id, 'b');
      await a.dispose();
      await b.dispose();
    });

    test(
      'a transfer request built against a superseded claim is ignored',
      () async {
        final peer = owningPeer('aaa');
        final staleClaimAt = peer.controller.state.activeClaimAt! - 1;

        peer.link.deliverIn({
          'type': 'transferRequest',
          'requestId': 'r1',
          'tabId': 'bbb',
          'activeTabId': 'aaa',
          'activeClaimAt': staleClaimAt,
          'targetTabId': 'bbb',
          'seq': 1,
        });

        expect(peer.pauses, 0);
        expect(peer.controller.state.activeTabId, 'aaa');
        await peer.dispose();
      },
    );

    test(
      'a hand-off that cannot be published restores playback locally',
      () async {
        final peer = owningPeer('aaa');
        peer.captured = testSnapshot();
        peer.link.broken = true;

        peer.link.deliverIn({
          'type': 'transferRequest',
          'requestId': 'r1',
          'tabId': 'bbb',
          'activeTabId': 'aaa',
          'activeClaimAt': peer.controller.state.activeClaimAt,
          'targetTabId': 'bbb',
          'seq': 1,
        });

        expect(peer.pauses, 1);
        // The pause must not be a silent stop with nobody picking playback up.
        expect(peer.resumes, 1);
        await peer.dispose();
      },
    );

    test('a transfer to a device nobody has heard from is refused', () async {
      final peer = owningPeer('aaa');

      expect(peer.controller.requestTransfer('ghost'), isFalse);
      await peer.dispose();
    });

    test(
      'a transfer whose previous owner does not match is rejected',
      () async {
        final peer = TestPeer('aaa', clock: clock);
        peer.link.deliverIn({
          'type': 'claim',
          'tabId': 'bbb',
          'at': clock.now,
          'seq': 1,
        });

        peer.link.deliverIn({
          'type': 'transfer',
          'requestId': 'r1',
          'tabId': 'ccc',
          'previousTargetId': 'ccc',
          'targetTabId': 'aaa',
          'claimAt': clock.now + 10,
          'snapshot': PlayerSyncProtocol.encodeSnapshot(testSnapshot()),
          'seq': 2,
        });

        expect(peer.controller.state.activeTabId, 'bbb');
        expect(peer.adopted, isEmpty);
        await peer.dispose();
      },
    );
  });

  group('position publishing', () {
    test('only the owner publishes, and each tick carries its claim', () async {
      final peer = TestPeer('aaa', clock: clock);
      peer.capturedPosition = PlayerPositionTick(
        positionMs: 1000,
        durationMs: 210000,
        state: PlaybackState.playing,
        tickAt: clock.now,
      );

      expect(peer.controller.publishOwnPosition(), isFalse);

      peer.controller.claimIfNoLiveTarget();
      peer.link.drain();
      expect(peer.controller.publishOwnPosition(), isTrue);

      final frame = peer.link.outbox.single;
      expect(frame['type'], 'position');
      expect(frame['claimAt'], peer.controller.state.activeClaimAt);
      await peer.dispose();
    });

    test('a mirrored position advances between ticks', () async {
      final peer = TestPeer('aaa', clock: clock);
      peer.link.deliverIn({
        'type': 'position',
        'tabId': 'bbb',
        'claimAt': clock.now,
        'position': {
          'positionMs': 10000,
          'durationMs': 210000,
          'state': 'playing',
          'tickAt': clock.now,
        },
        'seq': 1,
      });

      clock.advance(const Duration(milliseconds: 750));

      expect(peer.controller.interpolatedPosition().positionMs, 10750);
      await peer.dispose();
    });

    test('a paused mirror does not drift', () async {
      final peer = TestPeer('aaa', clock: clock);
      peer.link.deliverIn({
        'type': 'position',
        'tabId': 'bbb',
        'claimAt': clock.now,
        'position': {
          'positionMs': 10000,
          'durationMs': 210000,
          'state': 'paused',
          'tickAt': clock.now,
        },
        'seq': 1,
      });

      clock.advance(const Duration(seconds: 30));

      expect(peer.controller.interpolatedPosition().positionMs, 10000);
      await peer.dispose();
    });
  });

  group('sequence numbers', () {
    test('every outbound frame is stamped with a monotonic seq', () async {
      final peer = TestPeer('aaa', clock: clock);
      peer.link.drain();

      peer.controller
        ..announce()
        ..requestDevices()
        ..requestActive();

      expect(peer.link.outbox.map((frame) => frame['seq']), [1, 2, 3]);
      await peer.dispose();
    });
  });
}
