import 'dart:async';
import 'dart:convert';

import 'package:chordia_api/chordia_api.dart' show EqConfig, QualityProfile;
import 'package:chordia_mobile/data/mesh/mesh_connection.dart';
import 'package:chordia_mobile/data/mesh/mesh_playback.dart';
import 'package:chordia_mobile/data/mesh/mirror.dart';
import 'package:chordia_mobile/data/mesh/realtime_bus.dart';
import 'package:chordia_mobile/data/mesh/realtime_event.dart';
import 'package:chordia_mobile/data/mesh/realtime_socket.dart';
import 'package:chordia_mobile/data/playback/player_state.dart';
import 'package:chordia_player/chordia_player.dart';
import 'package:chordia_sync/chordia_sync.dart' hide PlaybackState;
import 'package:chordia_sync/chordia_sync.dart' as sync show PlaybackState;
import 'package:flutter_test/flutter_test.dart';

/// Lets every pending microtask and zero-delay future settle.
///
/// The connection's own steps are asynchronous — asking for a token, opening a socket, tearing one
/// down — so a test that asserts straight after firing a timer is asserting on a half-finished
/// reconnect. Five turns is comfortably more than the deepest chain here.
Future<void> pump() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// An access token whose payload carries [expiresAt].
///
/// Built by hand rather than mocked, so the expiry really is read by `expiryOf` — and so this test
/// would notice if Chordia's epoch-MILLISECONDS `exp` were ever reinterpreted as seconds.
String tokenExpiringAt(String id, int expiresAt) {
  String segment(Map<String, Object?> claims) =>
      base64Url.encode(utf8.encode(jsonEncode(claims))).replaceAll('=', '');
  return '${segment({'alg': 'EdDSA'})}.'
      '${segment({'sub': id, 'exp': expiresAt})}.signature';
}

/// A socket that goes nowhere: records what was written, and is fed by hand.
class FakeSocket implements RealtimeSocket {
  FakeSocket(this.url);

  final Uri url;
  final sent = <String>[];
  final _incoming = StreamController<String>();
  bool closed = false;

  @override
  Stream<String> get messages => _incoming.stream;

  @override
  void send(String text) {
    if (closed) throw StateError('the realtime socket is closed');
    sent.add(text);
  }

  @override
  Future<void> close() async {
    if (closed) return;
    closed = true;
    await _incoming.close();
  }

  /// A frame arriving from the Hub.
  void receive(Map<String, Object?> frame) => _incoming.add(jsonEncode(frame));

  /// The connection dying underneath us, as a lost network does.
  void drop() {
    if (closed) return;
    closed = true;
    unawaited(_incoming.close());
  }

  /// The decoded payloads of every mesh frame written to this socket.
  List<Map<String, Object?>> get payloads => [
    for (final text in sent)
      ((jsonDecode(text) as Map)['payload'] as Map).cast<String, Object?>(),
  ];
}

class FakeTimer implements Timer {
  FakeTimer(this.duration, this.onFire);

  final Duration duration;
  final void Function() onFire;
  bool cancelled = false;

  @override
  void cancel() => cancelled = true;

  @override
  bool get isActive => !cancelled;

  @override
  int get tick => 0;
}

/// Hands out timers that only fire when a test says so.
class TimerLog {
  final timers = <FakeTimer>[];

  Timer create(Duration duration, void Function() onFire) {
    final timer = FakeTimer(duration, onFire);
    timers.add(timer);
    return timer;
  }

  FakeTimer get last => timers.last;

  /// Fires the most recently scheduled timer, if it has not been cancelled.
  void fireLast() {
    final timer = last;
    if (timer.cancelled) return;
    timer.cancelled = true;
    timer.onFire();
  }
}

/// A stand-in engine, so "did this reach the local audio" is a list a test can read.
class FakeEngine implements PlaybackEngine {
  final statesCtl = StreamController<EngineState>.broadcast();
  final positionsCtl = StreamController<EnginePosition>.broadcast();
  final healthCtl = StreamController<EngineHealth>.broadcast();
  final completionsCtl = StreamController<void>.broadcast();
  final errorsCtl = StreamController<EngineError>.broadcast();

  final calls = <String>[];

  @override
  Stream<EngineState> get states => statesCtl.stream;
  @override
  Stream<EnginePosition> get positions => positionsCtl.stream;
  @override
  Stream<EngineHealth> get health => healthCtl.stream;
  @override
  Stream<void> get completions => completionsCtl.stream;
  @override
  Stream<EngineError> get errors => errorsCtl.stream;

  @override
  Future<void> load(
    EngineSource source, {
    Duration initialPosition = Duration.zero,
    bool autoPlay = false,
  }) async => calls.add('load');
  @override
  Future<void> setUpcoming(List<EngineSource> sources) async =>
      calls.add('setUpcoming');
  @override
  Future<void> play() async => calls.add('play');
  @override
  Future<void> pause() async => calls.add('pause');
  @override
  Future<void> stop() async => calls.add('stop');
  Duration? seekedTo;

  @override
  Future<void> seek(Duration position) async {
    seekedTo = position;
    calls.add('seek');
  }

  @override
  Future<void> setVolume(double volume) async => calls.add('setVolume');
  @override
  Future<void> setPreampGain(double linear) async => calls.add('setPreampGain');
  @override
  Future<void> swapSource(EngineSource source) async => calls.add('swapSource');
  @override
  Future<void> crossfadeTo(EngineSource source, Duration fade) async =>
      calls.add('crossfadeTo');
  @override
  Future<void> setEq(EqConfig? config) async => calls.add('setEq');

  @override
  Future<void> dispose() async {
    await statesCtl.close();
    await positionsCtl.close();
    await healthCtl.close();
    await completionsCtl.close();
  }
}

PlayerTrack track(String id) => PlayerTrack(
  id: id,
  title: 'Title $id',
  artist: 'Artist $id',
  album: 'Album',
  durationMs: 200000,
  libraryId: 'lib',
  trackRef: 'ref-$id',
  contentHash: 'hash-$id',
);

/// One connected device, with every seam replaced.
class Harness {
  Harness({List<String>? tokens, bool failOpen = false})
    : _tokens = tokens ?? const ['token-a'],
      _failOpen = failOpen {
    controller = PlayerSyncController(
      tabId: 'tab-a',
      deviceLabel: 'Test phone',
      deviceId: 'device-1',
      clock: () => now,
    );
    bus = RealtimeEventBus(clock: () => now, timerFactory: timers.create);
    connection = MeshConnection(
      controller: controller,
      bus: bus,
      baseUrl: Uri.parse('https://hub.example'),
      accessToken: () async =>
          _tokens[_tokenIndex.clamp(0, _tokens.length - 1)],
      open: (url) async {
        opened.add(url);
        if (_failOpen) throw const SocketFailure();
        final socket = FakeSocket(url);
        sockets.add(socket);
        return socket;
      },
      clock: () => now,
      timerFactory: timers.create,
    );
  }

  final List<String> _tokens;
  final bool _failOpen;

  int now = 1700000000000;
  int _tokenIndex = 0;

  final timers = TimerLog();
  final opened = <Uri>[];
  final sockets = <FakeSocket>[];
  final busKeys = <String>[];

  late final PlayerSyncController controller;
  late final RealtimeEventBus bus;
  late final MeshConnection connection;

  FakeSocket get socket => sockets.last;

  /// Advance to the next token the session manager would hand out.
  void rotateToken() => _tokenIndex += 1;

  Future<void> start() async {
    bus.keys.listen(busKeys.add);
    await connection.start();
    await pump();
  }

  Future<void> dispose() async {
    await connection.stop();
    await bus.dispose();
  }
}

/// What the opener throws when there is no server to reach.
class SocketFailure implements Exception {
  const SocketFailure();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the link', () {
    test(
      'joins by announcing, then asking who is there and who is playing',
      () async {
        final harness = Harness();
        await harness.start();

        expect(
          harness.opened.single.toString(),
          startsWith('wss://hub.example/v1/realtime?token='),
        );
        expect(harness.opened.single.queryParameters['token'], 'token-a');
        expect(harness.socket.payloads.map((frame) => frame['type']), [
          'announce',
          'whoIsThere',
          'whoIsActive',
        ]);

        await harness.dispose();
      },
    );

    test('wraps an outbound mesh message in the Hub relay envelope', () async {
      final harness = Harness();
      await harness.start();
      harness.socket.sent.clear();

      harness.controller.announce();

      final frame = jsonDecode(harness.socket.sent.single) as Map;
      // The Hub reads only the wrapper — it routes on `type` and forwards `payload` unread — so
      // these two keys are the entire contract between this client and the relay.
      expect(frame.keys, unorderedEquals(<String>['type', 'payload']));
      expect(frame['type'], 'player');

      final payload = (frame['payload'] as Map).cast<String, Object?>();
      expect(payload['type'], 'announce');
      expect(payload['tabId'], 'tab-a');
      expect(payload['label'], 'Test phone');
      expect(payload['deviceId'], 'device-1');
      expect(payload['at'], harness.now);
      // Stamped by the controller, and what pairs with `tabId` to de-duplicate a message that
      // arrives twice.
      expect(payload['seq'], isA<int>());

      await harness.dispose();
    });

    test('a non-player kind reaches the refresh bus and never the mesh', () async {
      final harness = Harness();
      await harness.start();

      final delivered = <String>[];
      harness.controller.messages.listen(
        (message) => delivered.add(message.type),
      );

      harness.socket
        ..receive({'kind': 'catalog'})
        ..receive({'kind': 'playlist', 'id': 'pl-1'})
        ..receive({
          'kind': 'player',
          'payload': {
            'type': 'announce',
            'tabId': 'tab-b',
            'label': 'Desktop',
            'at': harness.now,
            'seq': 1,
          },
        });
      await pump();

      // A `catalog` frame decoded as a mesh message would be dropped silently; the failure this
      // guards is the opposite one, where a view refresh is handed to the player.
      expect(delivered, ['announce']);
      expect(harness.busKeys, ['catalog', 'playlist:pl-1']);
      expect(
        harness.controller.state.devices.map((device) => device.tabId),
        contains('tab-b'),
      );

      await harness.dispose();
    });

    test('a player frame with no payload reaches nothing at all', () async {
      final harness = Harness();
      await harness.start();

      final delivered = <String>[];
      harness.controller.messages.listen(
        (message) => delivered.add(message.type),
      );

      harness.socket.receive({'kind': 'player'});
      await pump();

      expect(delivered, isEmpty);
      // The bug this pins: falling through to the bus would refetch an open screen on every
      // position tick another device sends, once a second, forever.
      expect(harness.busKeys, isEmpty);

      await harness.dispose();
    });
  });

  group('lifecycle', () {
    test(
      'a rotated token opens a fresh socket before the old one expires',
      () async {
        final harness = Harness(
          tokens: [
            tokenExpiringAt('a', 1700000000000 + 3600000),
            tokenExpiringAt('b', 1700000000000 + 7200000),
          ],
        );
        await harness.start();
        final first = harness.socket;

        // Scheduled for the renewal margin ahead of expiry, not for the expiry itself: the socket
        // has to be replaced while the old one still works.
        expect(
          harness.timers.last.duration,
          const Duration(minutes: 59, seconds: 30),
        );

        harness.rotateToken();
        harness.timers.fireLast();
        await pump();

        expect(harness.opened, hasLength(2));
        expect(
          harness.opened.last.queryParameters['token'],
          tokenExpiringAt('b', 1700000000000 + 7200000),
        );
        expect(first.closed, isTrue);
        // Re-announced on the new socket, so the other devices never see this one disappear.
        expect(harness.socket.payloads.first['type'], 'announce');

        await harness.dispose();
      },
    );

    test('an unrotated token keeps the socket and asks again later', () async {
      final harness = Harness(
        tokens: [tokenExpiringAt('a', 1700000000000 + 3600000)],
      );
      await harness.start();

      harness.timers.fireLast();
      await pump();

      // The live socket is still authenticated; tearing it down to re-present the same credential
      // would drop this device out of every picker for nothing.
      expect(harness.opened, hasLength(1));
      expect(harness.socket.closed, isFalse);
      expect(harness.timers.last.duration, kMeshTokenRenewRetry);

      await harness.dispose();
    });

    test('a failed connection backs off, doubling to a cap', () async {
      final harness = Harness(failOpen: true);
      await harness.start();

      final delays = <Duration>[harness.timers.last.duration];
      for (var i = 0; i < 6; i++) {
        harness.timers.fireLast();
        await pump();
        delays.add(harness.timers.last.duration);
      }

      expect(delays, [
        const Duration(seconds: 1),
        const Duration(seconds: 2),
        const Duration(seconds: 4),
        const Duration(seconds: 8),
        const Duration(seconds: 16),
        kMeshMaxBackoff,
        kMeshMaxBackoff,
      ]);

      await harness.dispose();
    });

    test(
      'a dropped socket reconnects, and a successful open resets the backoff',
      () async {
        final harness = Harness();
        await harness.start();

        harness.socket.drop();
        await pump();

        // Detached, so the phone is a mesh of one and free to play its own music rather than
        // deferring to an owner it can no longer hear.
        expect(harness.controller.state.available, isFalse);
        expect(harness.connection.isConnected, isFalse);

        harness.timers.fireLast();
        await pump();

        expect(harness.opened, hasLength(2));
        expect(harness.controller.state.available, isTrue);
        expect(harness.connection.attempts, 0);

        await harness.dispose();
      },
    );

    test('stopping leaves the mesh and closes the socket', () async {
      final harness = Harness();
      await harness.start();
      final socket = harness.socket;

      await harness.connection.stop();

      expect(socket.closed, isTrue);
      expect(harness.controller.state.available, isFalse);
      // A departure so every other picker drops this device now rather than after a liveness
      // timeout, then the close.
      expect(socket.payloads.last['type'], 'departure');

      await harness.bus.dispose();
    });
  });

  group('the refresh bus', () {
    test(
      'fires at once, then at most once per window, with a trailing fire',
      () async {
        var now = 0;
        final timers = TimerLog();
        final bus = RealtimeEventBus(
          clock: () => now,
          timerFactory: timers.create,
        );
        final fired = <String>[];
        bus.keys.listen(fired.add);

        bus.emit('catalog');
        await pump();
        expect(fired, [
          'catalog',
        ], reason: 'the first push after a quiet spell is immediate');

        now = 1000;
        bus
          ..emit('catalog')
          ..emit('catalog')
          ..emit('catalog');
        await pump();
        expect(fired, ['catalog'], reason: 'a burst inside the window is held');
        // One trailing fire, not one per arrival.
        expect(timers.timers, hasLength(1));
        expect(timers.last.duration, const Duration(seconds: 4));

        now = 5000;
        timers.fireLast();
        await pump();
        expect(fired, ['catalog', 'catalog']);

        await bus.dispose();
      },
    );

    test('the firehose kinds are held longer than everything else', () async {
      var now = 100000;
      final timers = TimerLog();
      final bus = RealtimeEventBus(
        clock: () => now,
        timerFactory: timers.create,
      );
      bus.keys.listen((_) {});

      for (final key in ['catalog', 'social', 'plays', 'liked']) {
        bus
          ..emit(key)
          ..emit(key);
      }
      await pump();

      expect(timers.timers.map((timer) => timer.duration), [
        const Duration(seconds: 5),
        const Duration(seconds: 5),
        const Duration(seconds: 5),
        kRealtimeDefaultCoalesce,
      ]);

      await bus.dispose();
    });

    test('each key is throttled on its own', () async {
      var now = 100000;
      final timers = TimerLog();
      final bus = RealtimeEventBus(
        clock: () => now,
        timerFactory: timers.create,
      );
      final fired = <String>[];
      bus.keys.listen(fired.add);

      bus.emit('catalog');
      now = 100100;
      // A different key must not be swallowed by the one that just fired — a like should feel
      // instant however busy the enrichment worker is.
      bus.emit('liked');
      await pump();

      expect(fired, ['catalog', 'liked']);
      expect(timers.timers, isEmpty);

      await bus.dispose();
    });
  });

  group('mirror mode', () {
    late FakeEngine engine;
    late QueueController queue;
    late ChordiaAudioHandler handler;
    late Harness harness;

    /// Hands playback to `tab-b`, playing [current].
    Future<void> remoteOwns(PlayerTrack current) async {
      final at = harness.now;
      final snapshot = PlayerSyncSnapshot(
        current: current,
        queue: [current],
        history: const [],
        currentIndex: 0,
        state: sync.PlaybackState.playing,
        shuffle: false,
        repeat: RepeatMode.off,
        volume: 1,
        sleepTimer: null,
        context: null,
        positionMs: 42000,
        durationMs: current.durationMs,
        tickAt: at,
      );
      harness.socket
        ..receive({
          'kind': 'player',
          'payload': {
            'type': 'announce',
            'tabId': 'tab-b',
            'label': 'Desktop',
            'at': at,
            'seq': 1,
          },
        })
        ..receive({
          'kind': 'player',
          'payload': {'type': 'claim', 'tabId': 'tab-b', 'at': at, 'seq': 2},
        })
        ..receive({
          'kind': 'player',
          'payload': {
            'type': 'snapshot',
            'tabId': 'tab-b',
            'claimAt': at,
            'snapshot': jsonEncode(snapshot.toJson()),
            'seq': 3,
          },
        });
      await pump();
    }

    setUp(() async {
      engine = FakeEngine();
      queue = QueueController();
      handler = ChordiaAudioHandler(
        engine: engine,
        controller: queue,
        resolveArt: (_) async => null,
      );
      harness = Harness();
      await harness.start();
    });

    tearDown(() async {
      await harness.dispose();
      await handler.dispose();
    });

    test('transport goes to the owner rather than the local engine', () async {
      await remoteOwns(track('t1'));
      final transport = MeshTransport(
        controller: harness.controller,
        local: PlayerActions(handler: handler, queue: queue),
      );
      expect(transport.remote, isTrue);
      harness.socket.sent.clear();

      transport
        ..setPlaying(false)
        ..next()
        ..seek(const Duration(seconds: 90))
        ..cycleRepeat();

      // Nothing sounded here. This is the failure the mesh exists to prevent: two devices playing
      // the same queue at once, each convinced it is the one in charge.
      expect(engine.calls, isEmpty);

      final commands = harness.socket.payloads;
      expect(commands.map((frame) => frame['type']), everyElement('command'));
      // Addressed to the owner the sender believed in, so a command that raced a hand-off is
      // dropped by the new owner rather than run twice.
      expect(
        commands.map((frame) => frame['activeTabId']),
        everyElement('tab-b'),
      );
      expect(commands.map((frame) => (frame['command'] as Map)['type']), [
        'pause',
        'next',
        'seek',
        'cycleRepeat',
      ]);
      expect((commands[2]['command'] as Map)['positionMs'], 90000);
    });

    test(
      'the mirror draws the owner, its track and an advancing playhead',
      () async {
        await remoteOwns(track('t1'));

        final mirror = MirrorState.of(harness.controller.state, 'tab-a');
        expect(mirror.active, isTrue);
        expect(mirror.deviceLabel, 'Desktop');
        expect(mirror.track?.id, 't1');
        expect(mirror.playing, isTrue);

        expect(harness.controller.interpolatedPosition().positionMs, 42000);
        // Interpolated forward from the owner's last tick, which is what moves a scrubber between
        // the once-a-second positions it is fed.
        harness.now += 2000;
        expect(harness.controller.interpolatedPosition().positionMs, 44000);
      },
    );

    test('a hand-off restores the queue here and lands on the playhead', () async {
      handler.resolveSource = (entry) async => StreamedSource(
        track: entry,
        libraryId: entry.libraryId,
        trackRef: entry.trackRef,
        profile: QualityProfile.high,
      );
      final playback = MeshPlayback(
        controller: harness.controller,
        handler: handler,
        queue: queue,
        engine: engine,
        clock: () => harness.now,
      )..start();

      final handed = PlayerSyncSnapshot(
        current: track('t2'),
        queue: [track('t1'), track('t2')],
        history: const [],
        currentIndex: 1,
        state: sync.PlaybackState.playing,
        shuffle: true,
        repeat: RepeatMode.all,
        volume: 1,
        sleepTimer: null,
        context: const AlbumContext(id: 'al-1', name: 'An album'),
        positionMs: 61000,
        durationMs: 200000,
        // Measured four seconds ago, so the playhead this device lands on has to be interpolated
        // forward rather than taken literally — a hand-off that rewinds is one people notice.
        tickAt: harness.now - 4000,
      );

      final adopting = playback.adopt(handed);
      await pump();
      engine.statesCtl.add(EngineState.ready);
      await adopting;

      expect(queue.queue.map((entry) => entry.id), ['t1', 't2']);
      expect(queue.currentIndex, 1);
      expect(queue.shuffle, isTrue);
      expect(queue.repeat, RepeatMode.all);
      expect(queue.context, const AlbumContext(id: 'al-1', name: 'An album'));
      expect(engine.calls, containsAllInOrder(['load', 'seek']));
      expect(engine.seekedTo, const Duration(milliseconds: 65000));

      await playback.dispose();
    });

    test('with no owner the same transport drives the local engine', () async {
      final transport = MeshTransport(
        controller: harness.controller,
        local: PlayerActions(handler: handler, queue: queue),
      );
      expect(transport.remote, isFalse);

      transport.setPlaying(true);
      await pump();

      expect(engine.calls, contains('play'));
      // Nothing was addressed to anybody: with no owner there is nobody to address.
      expect(
        harness.socket.payloads.map((frame) => frame['type']),
        isNot(contains('command')),
      );
    });
  });
}
