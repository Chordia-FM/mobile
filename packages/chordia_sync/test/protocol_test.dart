import 'dart:convert';

import 'package:chordia_sync/chordia_sync.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  group('wire shape', () {
    test('a snapshot frame carries the snapshot pre-serialised as a string', () {
      final wire = PlayerSyncProtocol.encode(
        SnapshotMessage(tabId: 'aaa', claimAt: 5, snapshot: testSnapshot()),
      );

      expect(wire['type'], 'snapshot');
      expect(wire['tabId'], 'aaa');
      expect(wire['claimAt'], 5);
      // The quirk the whole port hangs on: an object here instead of a string would make every web
      // peer reject the frame.
      expect(wire['snapshot'], isA<String>());
      final embedded = jsonDecode(wire['snapshot'] as String) as Map;
      expect(embedded['queue'], hasLength(2));
      expect(embedded['currentIndex'], 0);
    });

    test(
      'a transfer frame carries the same pre-serialised snapshot, or null',
      () {
        final withSnapshot = PlayerSyncProtocol.encode(
          TransferMessage(
            requestId: 'r1',
            tabId: 'aaa',
            previousTargetId: 'aaa',
            targetTabId: 'bbb',
            claimAt: 9,
            snapshot: testSnapshot(),
          ),
        );
        expect(withSnapshot['snapshot'], isA<String>());

        final withoutSnapshot = PlayerSyncProtocol.encode(
          const TransferMessage(
            requestId: 'r1',
            tabId: 'aaa',
            previousTargetId: null,
            targetTabId: 'bbb',
            claimAt: 9,
            snapshot: null,
          ),
        );
        expect(withoutSnapshot.containsKey('snapshot'), isTrue);
        expect(withoutSnapshot['snapshot'], isNull);
        expect(withoutSnapshot['previousTargetId'], isNull);
      },
    );

    test('an inlined snapshot object is rejected, not silently accepted', () {
      final decoded = PlayerSyncProtocol.decode({
        'type': 'snapshot',
        'tabId': 'aaa',
        'claimAt': 5,
        'snapshot': testSnapshot().toJson(),
      });

      expect(decoded, isNull);
    });

    test('every message type round-trips through encode and decode', () {
      final messages = <PlayerSyncMessage>[
        const AnnounceMessage(
          tabId: 'aaa',
          label: 'Chrome on Windows · aaa',
          at: 1000,
          deviceId: 'device-1',
        ),
        const WhoIsThereMessage(tabId: 'aaa'),
        const DepartureMessage(tabId: 'aaa', at: 1000),
        const ClaimMessage(tabId: 'aaa', at: 1000),
        SnapshotMessage(tabId: 'aaa', claimAt: 1000, snapshot: testSnapshot()),
        const PositionMessage(
          tabId: 'aaa',
          claimAt: 1000,
          position: PlayerPositionTick(
            positionMs: 4200,
            durationMs: 210000,
            state: PlaybackState.playing,
            tickAt: 1000,
          ),
        ),
        CommandMessage(
          tabId: 'bbb',
          activeTabId: 'aaa',
          command: PlayQueueCommand(
            tracks: [testTrack('a')],
            startIndex: 0,
            context: const RadioContext(id: 'seed', name: 'A Station'),
          ),
        ),
        const TransferRequestMessage(
          requestId: 'r1',
          tabId: 'bbb',
          activeTabId: 'aaa',
          activeClaimAt: 1000,
          targetTabId: 'bbb',
        ),
        TransferMessage(
          requestId: 'r1',
          tabId: 'aaa',
          previousTargetId: 'aaa',
          targetTabId: 'bbb',
          claimAt: 1001,
          snapshot: testSnapshot(),
        ),
        const ReleasedMessage(tabId: 'aaa', at: 1000),
        const WhoIsActiveMessage(tabId: 'aaa'),
      ];

      for (final message in messages) {
        final decoded = PlayerSyncProtocol.decode(
          PlayerSyncProtocol.encode(message),
        );
        expect(decoded, isNotNull, reason: 'failed on ${message.type}');
        expect(decoded!.type, message.type);
        expect(decoded.tabId, message.tabId);
      }
    });

    test('a frame this build cannot read still yields a dedupe key', () {
      // Forward compatibility: a newer peer's message type is unknown, but its (tabId, seq) is not,
      // so a duplicate of it must still be recognised.
      expect(
        PlayerSyncProtocol.dedupeKey({
          'type': 'somethingNew',
          'tabId': 'aaa',
          'seq': 12,
        }),
        'aaa:12',
      );
      expect(PlayerSyncProtocol.dedupeKey({'type': 'announce'}), isNull);
    });
  });

  group('decoding a frame built the way the web client builds it', () {
    test('a hand-written announce decodes with every field', () {
      const raw =
          '{"type":"announce","tabId":"tab-1","label":"Chrome on Windows '
          '\\u00b7 tab","at":1712345678901,"deviceId":"dev-1","seq":3}';
      final decoded = PlayerSyncProtocol.decode(jsonDecode(raw));

      expect(decoded, isA<AnnounceMessage>());
      final announce = decoded! as AnnounceMessage;
      expect(announce.tabId, 'tab-1');
      expect(announce.label, 'Chrome on Windows · tab');
      // Epoch milliseconds stay a plain int; nothing in the mesh works in DateTime.
      expect(announce.at, 1712345678901);
      expect(announce.deviceId, 'dev-1');
    });

    test('a fractional position is rounded rather than rejected', () {
      final decoded = PlayerSyncProtocol.decode({
        'type': 'position',
        'tabId': 'tab-1',
        'claimAt': 1000,
        'position': {
          'positionMs': 4200.6,
          'durationMs': 210000,
          'state': 'playing',
          'tickAt': 1712345678901,
        },
      });

      expect((decoded! as PositionMessage).position.positionMs, 4201);
    });

    test('a queue index that is not an integer is a real shape error', () {
      final snapshot = testSnapshot().toJson();
      snapshot['currentIndex'] = 1.5;

      expect(PlayerSyncSnapshot.tryFromJson(snapshot), isNull);
    });

    test('a malformed track fails the whole snapshot', () {
      final snapshot = testSnapshot().toJson();
      (snapshot['queue']! as List)[1] = {'id': 'no-title'};

      expect(PlayerSyncSnapshot.tryFromJson(snapshot), isNull);
    });

    test('a track-end sleep timer with a stray field is rejected', () {
      // The web validator counts the keys, so a snapshot carrying an extra one here would be
      // dropped by every peer. Reject it locally too rather than emit something they discard.
      expect(
        SleepTimer.tryFromJson(const {'kind': 'track', 'endsAt': 5}),
        isNull,
      );
      expect(
        SleepTimer.tryFromJson(const {'kind': 'track'}),
        const SleepAtTrackEnd(),
      );
    });
  });

  group('domain round-trips', () {
    test('a station cursor keeps absent, exhausted and set apart', () {
      const unasked = RadioContext(id: 'seed', name: 'Station');
      const exhausted = RadioContext(
        id: 'seed',
        name: 'Station',
        stationCursor: StationCursor(null),
      );
      const paged = RadioContext(
        id: 'seed',
        name: 'Station',
        stationKind: StationKind.genre,
        stationCursor: StationCursor('page-2'),
      );

      expect(unasked.toJson().containsKey('stationCursor'), isFalse);
      expect(exhausted.toJson()['stationCursor'], isNull);
      expect(exhausted.toJson().containsKey('stationCursor'), isTrue);
      expect(paged.toJson()['stationCursor'], 'page-2');

      for (final context in [unasked, exhausted, paged]) {
        expect(PlayContext.tryFromJson(context.toJson()), context);
      }
    });

    test('every context kind survives a round-trip', () {
      const contexts = <PlayContext>[
        AlbumContext(id: '1', name: 'Album'),
        ArtistContext(id: '2', name: 'Artist'),
        RadioContext(id: '3', name: 'Radio', stationKind: StationKind.track),
        PlaylistContext(id: '4', name: 'Playlist'),
        SmartPlaylistContext(id: '5', name: 'Smart'),
        LibraryContext(id: '6', name: 'Library'),
        LikedContext(name: 'Liked'),
        SearchContext(name: 'Search'),
      ];

      for (final context in contexts) {
        expect(PlayContext.tryFromJson(context.toJson()), context);
      }
      // A smart playlist must not decode as a plain one: they index different tables.
      expect(
        PlayContext.tryFromJson(
          const SmartPlaylistContext(id: '5', name: 'Smart').toJson(),
        ),
        isNot(const PlaylistContext(id: '5', name: 'Smart')),
      );
    });

    test('an optional track field absent stays absent on the way back out', () {
      const bare = PlayerTrack(
        id: 'x',
        title: 'Title',
        artist: 'Artist',
        album: null,
        durationMs: 1000,
        libraryId: 'lib',
        trackRef: 'ref',
        contentHash: 'hash',
      );
      final json = bare.toJson();

      expect(json.containsKey('qid'), isFalse);
      expect(json.containsKey('advisory'), isFalse);
      expect(json.containsKey('artists'), isFalse);
      // `album` is `string | null` on the web, always present.
      expect(json.containsKey('album'), isTrue);
      expect(json['album'], isNull);
      expect(PlayerTrack.tryFromJson(json), bare);
    });

    test('every sleep-timer option keeps its wire form', () {
      expect(const SleepAfterMinutes(30).toWire(), 30);
      expect(const SleepAfterCurrentTrack().toWire(), 'track');
      expect(
        PlayerSyncProtocol.decodeCommand(
          const SetSleepTimerCommand(SleepAfterMinutes(45)).toJson(),
        ),
        isA<SetSleepTimerCommand>().having(
          (command) => command.option,
          'option',
          const SleepAfterMinutes(45),
        ),
      );
      expect(
        PlayerSyncProtocol.decodeCommand(
          const SetSleepTimerCommand(null).toJson(),
        ),
        isA<SetSleepTimerCommand>().having(
          (command) => command.option,
          'option',
          isNull,
        ),
      );
    });

    test('every simple command survives a round-trip', () {
      for (final kind in SimpleCommandKind.values) {
        expect(
          PlayerSyncProtocol.decodeCommand(SimpleCommand(kind).toJson()),
          SimpleCommand(kind),
        );
      }
      expect(
        PlayerSyncProtocol.decodeCommand(const {'type': 'selfDestruct'}),
        isNull,
      );
    });
  });
}
