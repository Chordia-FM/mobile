import 'dart:async';
import 'dart:io';

import 'package:chordia_api/chordia_api.dart';
import 'package:chordia_mobile/data/playback/playback_errors.dart';
import 'package:chordia_mobile/data/playback/playback_service.dart';
import 'package:chordia_mobile/data/playback/quality.dart';
import 'package:chordia_mobile/data/playback/source_resolver.dart';
import 'package:chordia_mobile/i18n/translations.dart';
import 'package:chordia_player/chordia_player.dart';
import 'package:chordia_sync/chordia_sync.dart' hide PlaybackState;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// What the tests below are really about: a track that will not play must never leave the app
/// sitting in silence behind a play button that claims to be playing. Every case here ends with
/// the listener told something and the player somewhere other than where it got stuck.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('classifying a failure', () {
    test('a dropped connection is worth another go', () {
      for (final error in <Object>[
        const ApiException(
          status: 0,
          title: 'no route to host',
          method: 'GET',
          path: '/stream',
        ),
        const ApiException(
          status: 503,
          title: 'busy',
          method: 'GET',
          path: '/stream',
        ),
        const SocketException('closed'),
        TimeoutException('slow'),
      ]) {
        expect(
          JustAudioEngine.classifyFailure(error),
          EngineErrorKind.transient,
          reason: '$error should be retried',
        );
      }
    });

    test('a refusal is not', () {
      // 403 is a capability token the Hub declined to widen and 404 a track the library no longer
      // holds; a second identical request gets an identical answer, and the delay is silence.
      for (final status in [401, 403, 404, 409]) {
        expect(
          JustAudioEngine.classifyFailure(
            ApiException(
              status: status,
              title: 'no',
              method: 'GET',
              path: '/stream',
            ),
          ),
          EngineErrorKind.fatal,
          reason: '$status should not be retried',
        );
      }
      // Bytes that arrived and would not decode: a platform error with no upstream cause behind
      // it, which is exactly as true the second time.
      expect(
        JustAudioEngine.classifyFailure(const FormatException('bad frame')),
        EngineErrorKind.fatal,
      );
    });
  });

  group('a track that will not play', () {
    test('is retried once, then given up on and skipped', () async {
      final rig = _Rig()..start();
      rig.play([_track('t1'), _track('t2')]);
      await pumpEventQueue();
      expect(rig.engine.loads, ['t1'], reason: 'the first track was started');

      rig.fail(_transient);
      await pumpEventQueue();
      expect(rig.failures.map((f) => f.recovery), [PlaybackRecovery.retrying]);
      expect(
        rig.engine.loads,
        ['t1', 't1'],
        reason: 'a transient failure earns exactly one more attempt',
      );
      expect(rig.queue.current?.id, 't1', reason: 'the retry is not a skip');

      rig.fail(_transient);
      await pumpEventQueue();
      expect(rig.failures.map((f) => f.recovery), [
        PlaybackRecovery.retrying,
        PlaybackRecovery.skipped,
      ]);
      expect(rig.queue.current?.id, 't2');
      await rig.dispose();
    });

    test('is skipped immediately when retrying could not help', () async {
      final rig = _Rig()..start();
      rig.play([_track('t1'), _track('t2')]);
      await pumpEventQueue();

      rig.fail(_fatal);
      await pumpEventQueue();
      expect(rig.failures.single.recovery, PlaybackRecovery.skipped);
      expect(rig.failures.single.track.id, 't1');
      expect(rig.queue.current?.id, 't2');
      await rig.dispose();
    });

    test('stops, and says so, when there is nowhere to skip to', () async {
      final rig = _Rig()..start();
      rig.play([_track('only')]);
      await pumpEventQueue();
      expect(rig.handler.playbackState.value.playing, isTrue);

      rig.fail(_fatal);
      await pumpEventQueue();
      expect(rig.failures.single.recovery, PlaybackRecovery.stopped);
      // The stuck play button is the whole bug: the transport has to stop claiming to play.
      expect(rig.handler.playbackState.value.playing, isFalse);
      await rig.dispose();
    });

    test('does not skip the whole queue when every track fails', () async {
      // An unreachable library fails all of them identically. Racing to the end of a forty-track
      // queue, a notification per track, is worse than stopping and saying so.
      final rig = _Rig()..start();
      rig.play([for (var i = 0; i < 10; i++) _track('t$i')]);
      await pumpEventQueue();

      for (var i = 0; i < PlaybackService.maxConsecutiveFailures; i++) {
        rig.fail(_fatal);
        await pumpEventQueue();
      }

      expect(rig.failures.last.recovery, PlaybackRecovery.stopped);
      expect(
        rig.queue.current?.id,
        't${PlaybackService.maxConsecutiveFailures - 1}',
        reason:
            'it stopped where the cap said, rather than running the queue out',
      );
      expect(rig.handler.playbackState.value.playing, isFalse);
      await rig.dispose();
    });

    test(
      'a track that plays clears the run, so the cap is per outage',
      () async {
        final rig = _Rig()..start();
        rig.play([_track('t1'), _track('t2'), _track('t3')]);
        await pumpEventQueue();

        rig.fail(_fatal);
        await pumpEventQueue();
        expect(rig.queue.current?.id, 't2');

        // t2 actually sounds.
        rig.engine.statesCtl.add(EngineState.ready);
        await pumpEventQueue();

        rig.fail(_fatal);
        await pumpEventQueue();
        expect(
          rig.failures.map((f) => f.recovery),
          [PlaybackRecovery.skipped, PlaybackRecovery.skipped],
          reason: 'the second failure is a fresh one, not the second of a run',
        );
        expect(rig.queue.current?.id, 't3');
        await rig.dispose();
      },
    );
  });

  group('what the listener is told', () {
    late Translations translations;
    setUpAll(() async {
      translations = await Translations.load('en', bundle: rootBundle);
    });

    test('names the track, in the listener\'s language, for every outcome', () {
      for (final recovery in PlaybackRecovery.values) {
        final message = playbackFailureMessage(
          translations.call,
          PlaybackFailure(
            track: _track('t1', title: 'Weightless'),
            recovery: recovery,
            cause: _fatal.cause,
          ),
        );
        expect(message, contains('Weightless'));
        // A raw key path reaching a user is the failure this guards.
        expect(message, isNot(contains('errors:')));
      }
    });
  });
}

const _transientCause = ApiException(
  status: 0,
  title: 'the library dropped the connection',
  method: 'GET',
  path: '/stream',
);

const _fatalCause = ApiException(
  status: 403,
  title: 'the library refused the stream request',
  method: 'GET',
  path: '/stream',
);

const _transient = EngineError(
  kind: EngineErrorKind.transient,
  cause: _transientCause,
  status: 0,
);

const _fatal = EngineError(
  kind: EngineErrorKind.fatal,
  cause: _fatalCause,
  status: 403,
);

PlayerTrack _track(String id, {String title = 'Track'}) => PlayerTrack(
  id: id,
  title: title,
  artist: 'Artist',
  album: 'Album',
  durationMs: 180000,
  libraryId: 'lib-1',
  trackRef: 'ref-$id',
  contentHash: 'hash-$id',
);

/// The real queue, the real media session and the real service, over an engine that sounds nothing.
///
/// Deliberately not a mock of the service: what is being tested is the conversation between the
/// three of them — an engine failure has to become a queue advance and a message, and only the
/// wiring can be wrong.
class _Rig {
  _Rig() {
    handler = ChordiaAudioHandler(
      engine: engine,
      controller: queue,
      resolveArt: (_) async => null,
      onNowPlaying: (track) => service.onTrackStarted(track),
    );
    service = PlaybackService(
      handler: handler,
      engine: engine,
      queue: queue,
      resolver: SourceResolver(
        downloads: (_) async => null,
        quality: () => QualityProfile.original,
      ),
      recordPlay:
          (
            track, {
            required startedAt,
            required msPlayed,
            context,
            source = PlaybackSource.ownLibrary,
          }) async {},
      flush: ({bool force = false}) async {},
      reportNowPlaying: (_) {},
      readLoudness: (_) async => null,
      preferences: () => const PlaybackPreferences(),
      network: () => NetworkStatus.unknown,
    );
  }

  final engine = _FakeEngine();
  final queue = QueueController();
  late final ChordiaAudioHandler handler;
  late final PlaybackService service;
  final failures = <PlaybackFailure>[];
  StreamSubscription<PlaybackFailure>? _sub;

  void start() {
    service.start();
    _sub = service.failures.listen(failures.add);
  }

  void play(List<PlayerTrack> tracks) => queue.playQueue(tracks);

  void fail(EngineError error) => engine.errorsCtl.add(
    EngineError(
      kind: error.kind,
      cause: error.cause,
      status: error.status,
      track: queue.current,
    ),
  );

  Future<void> dispose() async {
    await _sub?.cancel();
    await service.dispose();
    await handler.dispose();
  }
}

class _FakeEngine implements PlaybackEngine {
  final positionsCtl = StreamController<EnginePosition>.broadcast(sync: true);
  final statesCtl = StreamController<EngineState>.broadcast(sync: true);
  final healthCtl = StreamController<EngineHealth>.broadcast(sync: true);
  final completionsCtl = StreamController<void>.broadcast(sync: true);
  final errorsCtl = StreamController<EngineError>.broadcast(sync: true);

  /// The track id behind every load, in order.
  final loads = <String>[];

  @override
  Stream<EnginePosition> get positions => positionsCtl.stream;
  @override
  Stream<EngineState> get states => statesCtl.stream;
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
  }) async => loads.add(source.track.id);

  @override
  Future<void> setUpcoming(List<EngineSource> sources) async {}
  @override
  Future<void> play() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> seek(Duration position) async {}
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> setPreampGain(double linear) async {}
  @override
  Future<void> swapSource(EngineSource source) async {}
  @override
  Future<void> crossfadeTo(EngineSource source, Duration fade) async {}
  @override
  Future<void> setEq(EqConfig? config) async {}

  @override
  Future<void> dispose() async {
    await positionsCtl.close();
    await statesCtl.close();
    await healthCtl.close();
    await completionsCtl.close();
    await errorsCtl.close();
  }
}
