import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:chordia_api/chordia_api.dart';
import 'package:chordia_player/src/engine/engine.dart';
import 'package:chordia_player/src/handler/audio_handler.dart';
import 'package:chordia_player/src/queue/queue_controller.dart';
import 'package:chordia_sync/chordia_sync.dart' hide PlaybackState;
import 'package:flutter_test/flutter_test.dart';

PlayerTrack t(String id, {int durationMs = 200000}) => PlayerTrack(
  id: id,
  title: 'Title $id',
  artist: 'Artist $id',
  album: 'Album',
  durationMs: durationMs,
  libraryId: 'lib',
  trackRef: 'ref-$id',
  contentHash: 'hash-$id',
);

/// A stand-in engine: records what it was asked to do and lets a test drive its streams.
class FakeEngine implements PlaybackEngine {
  final positionsCtl = StreamController<EnginePosition>.broadcast();
  final statesCtl = StreamController<EngineState>.broadcast();
  final healthCtl = StreamController<EngineHealth>.broadcast();
  final completionsCtl = StreamController<void>.broadcast();

  final calls = <String>[];
  final loaded = <EngineSource>[];
  double volume = 1;

  @override
  Stream<EnginePosition> get positions => positionsCtl.stream;
  @override
  Stream<EngineState> get states => statesCtl.stream;
  @override
  Stream<EngineHealth> get health => healthCtl.stream;
  @override
  Stream<void> get completions => completionsCtl.stream;

  @override
  Future<void> load(
    EngineSource source, {
    Duration initialPosition = Duration.zero,
    bool autoPlay = false,
  }) async {
    calls.add('load');
    loaded.add(source);
  }

  @override
  Future<void> setUpcoming(List<EngineSource> sources) async =>
      calls.add('setUpcoming');
  @override
  Future<void> play() async => calls.add('play');
  @override
  Future<void> pause() async => calls.add('pause');
  @override
  Future<void> stop() async => calls.add('stop');
  @override
  Future<void> seek(Duration position) async => calls.add('seek:$position');
  @override
  Future<void> setVolume(double v) async {
    volume = v;
    calls.add('setVolume:$v');
  }

  @override
  Future<void> setPreampGain(double linear) async =>
      calls.add('setPreampGain:$linear');
  @override
  Future<void> swapSource(EngineSource source) async => calls.add('swapSource');
  @override
  Future<void> crossfadeTo(EngineSource source, Duration fade) async =>
      calls.add('crossfadeTo');
  @override
  Future<void> setEq(EqConfig? config) async => calls.add('setEq');

  @override
  Future<void> dispose() async {
    await positionsCtl.close();
    await statesCtl.close();
    await healthCtl.close();
    await completionsCtl.close();
  }
}

void main() {
  late FakeEngine engine;
  late QueueController controller;
  late ChordiaAudioHandler handler;
  late List<Uri?> artRequested;

  setUp(() {
    engine = FakeEngine();
    var n = 0;
    controller = QueueController(newQid: () => 'qid-${++n}');
    artRequested = [];
    handler =
        ChordiaAudioHandler(
            engine: engine,
            controller: controller,
            resolveArt: (track) async {
              final uri = Uri.file('/covers/${track.id}.jpg');
              artRequested.add(uri);
              return uri;
            },
          )
          ..resolveSource = (track) async => StreamedSource(
            track: track,
            libraryId: track.libraryId,
            trackRef: track.trackRef,
            profile: QualityProfile.original,
          );
  });

  tearDown(() async {
    await handler.dispose();
  });

  /// Lets the handler's async reaction to a queue event finish.
  Future<void> settle() async {
    for (var i = 0; i < 4; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  group('what the system is told', () {
    test('a started track becomes the media item, with local artwork', () async {
      // The notification's art is fetched by native code that cannot use our pinned client, so a
      // file:// URI is the only kind that works against a self-hosted server.
      controller.playQueue([t('a')]);
      await settle();

      final item = handler.mediaItem.value!;
      expect(item.title, 'Title a');
      expect(item.artist, 'Artist a');
      expect(item.album, 'Album');
      expect(item.duration, const Duration(milliseconds: 200000));
      expect(item.artUri!.scheme, 'file');
      expect(item.extras!['trackId'], 'a');
    });

    test(
      'the collapsed controls are previous, play/pause, next in that order',
      () async {
        // Android 13+ builds the system controls from these actions, not from notification buttons,
        // and shows the first three collapsed — so this order is what a lock screen actually shows.
        controller.playQueue([t('a')]);
        await settle();

        final state = handler.playbackState.value;
        expect(state.controls.map((c) => c.action), [
          MediaAction.skipToPrevious,
          MediaAction.pause,
          MediaAction.skipToNext,
        ]);
        expect(state.androidCompactActionIndices, [0, 1, 2]);
      },
    );

    test('the play/pause control flips with playback', () async {
      controller.playQueue([t('a')]);
      await settle();
      await handler.pause();

      expect(
        handler.playbackState.value.controls.map((c) => c.action),
        contains(MediaAction.play),
      );
      expect(handler.playbackState.value.playing, isFalse);
    });

    test('seeking is offered, so a lock-screen scrubber works', () async {
      controller.playQueue([t('a')]);
      await settle();

      expect(
        handler.playbackState.value.systemActions,
        containsAll({
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        }),
      );
    });

    test('the queue is published for a head unit to browse', () async {
      controller.playQueue([t('a'), t('b'), t('c')]);
      await settle();

      expect(handler.queue.value.map((i) => i.title), [
        'Title a',
        'Title b',
        'Title c',
      ]);
    });

    test('engine buffering surfaces as a buffering state', () async {
      controller.playQueue([t('a')]);
      await settle();

      engine.statesCtl.add(EngineState.buffering);
      await settle();

      expect(
        handler.playbackState.value.processingState,
        AudioProcessingState.buffering,
      );
    });

    test(
      'shuffle and repeat are reported so their buttons render correctly',
      () async {
        controller
          ..playQueue([t('a'), t('b')])
          ..setShuffleMode(true)
          ..setRepeatMode(RepeatMode.one);
        await settle();

        expect(
          handler.playbackState.value.shuffleMode,
          AudioServiceShuffleMode.all,
        );
        expect(
          handler.playbackState.value.repeatMode,
          AudioServiceRepeatMode.one,
        );
      },
    );
  });

  group('transport from the system', () {
    test('play and pause reach the engine', () async {
      controller.playQueue([t('a')]);
      await settle();
      engine.calls.clear();

      await handler.pause();
      await handler.play();

      expect(engine.calls, ['pause', 'play']);
    });

    test('next advances the queue and loads the new track', () async {
      controller.playQueue([t('a'), t('b')]);
      await settle();
      engine.loaded.clear();

      await handler.skipToNext();
      await settle();

      expect(controller.currentIndex, 1);
      expect(engine.loaded.single.track.id, 'b');
    });

    test('previous restarts the track when past the threshold', () async {
      controller.playQueue([t('a'), t('b')], startIndex: 1);
      await settle();
      engine.calls.clear();

      // The handler feeds the queue its playhead, so a position tick is what makes "previous"
      // mean restart rather than go back.
      engine.positionsCtl.add(
        const EnginePosition(
          position: Duration(seconds: 30),
          buffered: Duration(seconds: 40),
          duration: Duration(seconds: 200),
          tick: Duration(milliseconds: 500),
        ),
      );
      await settle();

      await handler.skipToPrevious();
      await settle();

      expect(controller.currentIndex, 1, reason: 'stayed on the same track');
      expect(engine.calls.where((c) => c.startsWith('seek')), isNotEmpty);
    });

    test('the system shuffle toggle reaches the queue', () async {
      controller.playQueue([t('a'), t('b')]);
      await settle();

      await handler.setShuffleMode(AudioServiceShuffleMode.all);

      expect(controller.shuffle, isTrue);
    });

    test('skipping to a queue item jumps there', () async {
      controller.playQueue([t('a'), t('b'), t('c')]);
      await settle();

      await handler.skipToQueueItem(2);
      await settle();

      expect(controller.currentIndex, 2);
    });
  });

  group('scrobbling', () {
    test('reports a play once the threshold is crossed', () async {
      final scrobbled = <String>[];
      final h =
          ChordiaAudioHandler(
              engine: engine,
              controller: controller,
              resolveArt: (_) async => null,
              onScrobble: (track, ms) => scrobbled.add(track.id),
            )
            ..resolveSource = (track) async => StreamedSource(
              track: track,
              libraryId: track.libraryId,
              trackRef: track.trackRef,
              profile: QualityProfile.original,
            );

      controller.playQueue([t('a', durationMs: 60000)]);
      await settle();
      await h.play();

      for (var ms = 1000; ms <= 40000; ms += 1000) {
        engine.positionsCtl.add(
          EnginePosition(
            position: Duration(milliseconds: ms),
            buffered: Duration(milliseconds: ms + 5000),
            duration: const Duration(milliseconds: 60000),
            tick: const Duration(milliseconds: 1000),
          ),
        );
        await Future<void>.delayed(Duration.zero);
      }

      expect(scrobbled, [
        'a',
      ], reason: 'half of a 60s track is one play, reported once');
    });
  });

  group('a track ending', () {
    test('advances the queue', () async {
      controller.playQueue([t('a'), t('b')]);
      await settle();

      engine.completionsCtl.add(null);
      await settle();

      expect(controller.currentIndex, 1);
    });
  });
}
