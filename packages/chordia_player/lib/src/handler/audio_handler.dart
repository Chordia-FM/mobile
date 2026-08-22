import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
// `PlaybackState` exists in both packages and means different things: audio_service's is what the
// operating system is told, ours is what the mesh publishes. This file speaks the former.
import 'package:chordia_sync/chordia_sync.dart' hide PlaybackState;

import '../engine/engine.dart';
import '../queue/queue_controller.dart';
import '../queue/queue_events.dart';
import '../scrobble/scrobble_latch.dart';

/// Resolves a local file for a track's cover, for the media notification.
///
/// A `file://` URI rather than an `https://` one because the notification's artwork is fetched by
/// native code, which knows nothing of our pinned client and would fail against a self-hosted
/// server. Returns null when there is no art, which the notification renders as its own default.
typedef ArtResolver = Future<Uri?> Function(PlayerTrack track);

/// Called when a track has been listened to for long enough to count.
typedef ScrobbleSink = void Function(PlayerTrack track, int msPlayed);

/// Called at the start of each track so other devices can see what is playing.
typedef NowPlayingSink = void Function(PlayerTrack track);

/// The bridge between Chordia's playback and the operating system's idea of a media session.
///
/// Everything the phone shows outside the app — the notification, the lock screen, a car head
/// unit, a headset button — is driven from what this class broadcasts. It is deliberately the only
/// place that translates between the two vocabularies: the queue and engine know nothing about
/// [MediaItem], and audio_service knows nothing about capability tokens or play contexts.
///
/// Constructed before `runApp` and outliving every screen, because Android can start it into a
/// process with no UI at all — a headset button pressed after the app was swiped away, or Android
/// Auto asking to resume. Anything it needs must therefore come from its constructor rather than
/// from a widget tree that may never exist.
class ChordiaAudioHandler extends BaseAudioHandler with SeekHandler {
  ChordiaAudioHandler({
    required this.engine,
    required this.controller,
    required ArtResolver resolveArt,
    ScrobbleSink? onScrobble,
    NowPlayingSink? onNowPlaying,
    ScrobbleLatch? latch,
  }) : _resolveArt = resolveArt,
       _onScrobble = onScrobble,
       _onNowPlaying = onNowPlaying,
       _latch = latch ?? ScrobbleLatch() {
    _subs
      ..add(controller.events.listen(_onQueueEvent))
      ..add(engine.positions.listen(_onPosition))
      ..add(engine.states.listen(_onEngineState))
      ..add(engine.completions.listen((_) => controller.onTrackEnded()));

    controller.readPositionMs = () => _position.inMilliseconds;
  }

  final PlaybackEngine engine;

  /// Chordia's queue. Named apart from [queue], which is the MediaItem list `BaseAudioHandler`
  /// publishes to the system — the two are different views of the same thing and must not merge.
  final QueueController controller;
  final ArtResolver _resolveArt;
  final ScrobbleSink? _onScrobble;
  final NowPlayingSink? _onNowPlaying;
  final ScrobbleLatch _latch;

  final _subs = <StreamSubscription<Object?>>[];

  Duration _position = Duration.zero;
  bool _playing = false;
  EngineState _engineState = EngineState.idle;

  /// Prepares audio focus, so another app taking the output pauses us rather than talking over us.
  Future<void> configureSession() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());

    session.interruptionEventStream.listen((event) async {
      if (event.begin) {
        switch (event.type) {
          case AudioInterruptionType.duck:
            await engine.setVolume(0.3);
          case AudioInterruptionType.pause:
          case AudioInterruptionType.unknown:
            // Remembered so a phone call that ends returns the listener to where they were, but a
            // deliberate pause during the call is not overridden.
            _wasPlayingBeforeInterruption = _playing;
            await pause();
        }
      } else {
        switch (event.type) {
          case AudioInterruptionType.duck:
            await engine.setVolume(1);
          case AudioInterruptionType.pause:
            if (_wasPlayingBeforeInterruption) await play();
          case AudioInterruptionType.unknown:
            break;
        }
      }
    });

    // Unplugging headphones stops playback rather than moving it to the phone's speaker, which is
    // the behaviour every music app has and the one that avoids a room full of surprise.
    session.becomingNoisyEventStream.listen((_) => pause());
  }

  bool _wasPlayingBeforeInterruption = false;

  // ── the system's transport controls ─────────────────────────────────────────────────────────

  @override
  Future<void> play() async {
    await engine.play();
    _playing = true;
    _publishState();
  }

  @override
  Future<void> pause() async {
    await engine.pause();
    _playing = false;
    _publishState();
  }

  @override
  Future<void> stop() async {
    await engine.stop();
    _playing = false;
    _latch.clear();
    _publishState(processing: AudioProcessingState.idle);
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) async {
    await engine.seek(position);
    _position = position;
    _publishState();
  }

  @override
  Future<void> skipToNext() async => controller.next();

  @override
  Future<void> skipToPrevious() async => controller.prev();

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    controller.setShuffleMode(shuffleMode != AudioServiceShuffleMode.none);
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    controller.setRepeatMode(switch (repeatMode) {
      AudioServiceRepeatMode.none => RepeatMode.off,
      AudioServiceRepeatMode.one => RepeatMode.one,
      AudioServiceRepeatMode.all ||
      AudioServiceRepeatMode.group => RepeatMode.all,
    });
  }

  @override
  Future<void> skipToQueueItem(int index) async => controller.jumpTo(index);

  // ── reacting to our own state ───────────────────────────────────────────────────────────────

  void _onQueueEvent(QueueEvent event) {
    switch (event) {
      case QueueStateChanged():
        _publishQueue();
        _publishState();
      case PlayEntryRequested(:final track):
        unawaited(_startTrack(track));
      case RestartCurrentRequested():
        unawaited(seek(Duration.zero));
      case SleepTimerElapsed():
        unawaited(pause());
    }
  }

  Future<void> _startTrack(PlayerTrack track) async {
    _latch.start(qid: track.qid ?? track.id, durationMs: track.durationMs);
    _onNowPlaying?.call(track);

    await _publishItem(track);
    // The source a track resolves to — downloaded file, cached bytes, or a stream at the chosen
    // tier — is the app's decision, so it supplies the resolver rather than this class guessing.
    final source = await resolveSource!(track);
    await engine.load(source, autoPlay: true);
    _playing = true;
    _publishState();
  }

  /// Turns a queue entry into something the engine can play. Injected because the choice depends
  /// on downloads, the listener's quality tier and the current network, none of which belong here.
  Future<EngineSource> Function(PlayerTrack track)? resolveSource;

  void _onPosition(EnginePosition position) {
    _position = position.position;

    final fired = _latch.sample(
      position.position.inMilliseconds,
      playing: _playing,
    );
    if (fired != null) {
      final track = controller.current;
      if (track != null) _onScrobble?.call(track, _latch.msPlayed);
    }

    _publishState();
  }

  void _onEngineState(EngineState state) {
    _engineState = state;
    _publishState();
  }

  Future<void> _publishItem(PlayerTrack track) async {
    final art = await _resolveArt(track);
    mediaItem.add(
      MediaItem(
        id: track.qid ?? track.id,
        title: track.title,
        artist: track.artist,
        album: track.album,
        duration: Duration(milliseconds: track.durationMs),
        artUri: art,
        extras: {
          'trackId': track.id,
          'libraryId': track.libraryId,
          'trackRef': track.trackRef,
        },
      ),
    );
  }

  void _publishQueue() {
    queue.add([
      for (final t in controller.queue)
        MediaItem(
          id: t.qid ?? t.id,
          title: t.title,
          artist: t.artist,
          album: t.album,
          duration: Duration(milliseconds: t.durationMs),
        ),
    ]);
  }

  void _publishState({AudioProcessingState? processing}) {
    playbackState.add(
      PlaybackState(
        // Android 13 and newer build the system's media controls from these actions rather than
        // from the notification's buttons, and it shows the first three in the collapsed view — so
        // the order here is what a listener actually sees on their lock screen.
        controls: [
          MediaControl.skipToPrevious,
          if (_playing) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState:
            processing ??
            switch (_engineState) {
              EngineState.idle => AudioProcessingState.idle,
              EngineState.loading => AudioProcessingState.loading,
              EngineState.buffering => AudioProcessingState.buffering,
              EngineState.ready => AudioProcessingState.ready,
              EngineState.completed => AudioProcessingState.completed,
            },
        playing: _playing,
        updatePosition: _position,
        queueIndex: controller.currentIndex,
        shuffleMode: controller.shuffle
            ? AudioServiceShuffleMode.all
            : AudioServiceShuffleMode.none,
        repeatMode: switch (controller.repeat) {
          RepeatMode.off => AudioServiceRepeatMode.none,
          RepeatMode.one => AudioServiceRepeatMode.one,
          RepeatMode.all => AudioServiceRepeatMode.all,
        },
      ),
    );
  }

  Future<void> dispose() async {
    for (final s in _subs) {
      await s.cancel();
    }
    await engine.dispose();
    await controller.dispose();
  }
}
