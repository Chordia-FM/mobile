/// What the mesh does to this device's own player, and what it tells the mesh about it.
library;

import 'dart:async';

import 'package:audio_service/audio_service.dart' as audio;
import 'package:chordia_player/chordia_player.dart';
import 'package:chordia_sync/chordia_sync.dart';

/// How long to wait for the engine to be ready before giving up on placing the playhead.
///
/// A hand-off that arrives while the phone is on a bad connection still has to start playing; the
/// worst outcome of the timeout is a track that begins at zero rather than where the other device
/// left it, which is far better than a queue that sits silent waiting for a seek.
const Duration kAdoptSeekTimeout = Duration(seconds: 20);

/// Binds the mesh to this device's engine, queue and media session.
///
/// Everything here is one half of a pair with [PlayerSyncHandlers]: the mesh decides *whether*
/// this device should act, and this class knows *how*. Keeping the two apart is what lets the
/// resolution rules be tested with no audio device, and it is why the callbacks are installed at
/// runtime rather than passed to the controller's constructor — the mesh exists from bootstrap and
/// wants a player that is only built when the app has one.
class MeshPlayback {
  MeshPlayback({
    required this.controller,
    required this.handler,
    required this.queue,
    required this.engine,
    Clock clock = systemClock,
  }) : _clock = clock;

  final PlayerSyncController controller;
  final ChordiaAudioHandler handler;
  final QueueController queue;
  final PlaybackEngine engine;
  final Clock _clock;

  final _subscriptions = <StreamSubscription<Object?>>[];

  /// The engine's output level, 0..1.
  ///
  /// Tracked here because nothing else does: the engine takes a volume but does not report one,
  /// and on a phone the level people actually reach for is the hardware one. It exists so a
  /// `setVolume` from another device is reflected in the next snapshot rather than silently
  /// disagreeing with what that device's slider shows.
  double _volume = 1;

  /// The level to restore on unmute, or null when not muted.
  double? _mutedFrom;

  bool _started = false;

  /// Install the handlers and start publishing.
  void start() {
    if (_started) return;
    _started = true;

    controller.handlers = PlayerSyncHandlers(
      onCommand: _apply,
      captureSnapshot: capture,
      capturePosition: capturePosition,
      onAdoptTransfer: (snapshot) => unawaited(adopt(snapshot)),
      onYield: () => unawaited(handler.pause()),
      onPause: () => unawaited(handler.pause()),
      onResume: () => unawaited(handler.play()),
    );

    _subscriptions.add(queue.events.listen(_onQueueEvent));
    // Only the two fields a mirror draws. `playbackState` also carries the playhead, which moves
    // twice a second — republishing a whole queue at that rate is what the mesh's own
    // once-a-second position tick exists to avoid.
    _subscriptions.add(
      handler.playbackState
          .map((state) => (state.playing, state.processingState))
          .distinct()
          .listen((_) => publish()),
    );
  }

  /// Publish this device's playback, if it is the device that owns it.
  void publish() {
    if (!controller.isOwner) return;
    final snapshot = capture();
    if (snapshot != null) controller.publishSnapshot(snapshot);
  }

  /// This device's playback as the mesh sees it, or null when there is nothing playing.
  PlayerSyncSnapshot? capture() {
    final current = queue.current;
    if (current == null) return null;
    final state = handler.playbackState.value;
    return PlayerSyncSnapshot(
      current: current,
      queue: queue.queue,
      history: queue.history,
      currentIndex: queue.currentIndex,
      state: _stateOf(state),
      shuffle: queue.shuffle,
      repeat: queue.repeat,
      volume: _volume,
      sleepTimer: queue.sleepTimer,
      context: queue.context,
      positionMs: state.updatePosition.inMilliseconds,
      // The catalog length, not the engine's. A lower tier is an on-the-fly transcode whose
      // measured duration reads short, and a mirror's scrubber must not shorten because the
      // OWNER's connection got worse.
      durationMs: current.durationMs,
      tickAt: _clock(),
    );
  }

  PlayerPositionTick? capturePosition() {
    final current = queue.current;
    if (current == null) return null;
    final state = handler.playbackState.value;
    return PlayerPositionTick(
      positionMs: state.updatePosition.inMilliseconds,
      durationMs: current.durationMs,
      state: _stateOf(state),
      tickAt: _clock(),
    );
  }

  /// Take over playback handed to this device.
  ///
  /// The queue arrives with the hand-off, so this restores it wholesale rather than resolving
  /// anything from the Hub — which is what makes a transfer work with the phone offline from
  /// everything except the library it is streaming from.
  Future<void> adopt(PlayerSyncSnapshot snapshot) async {
    if (snapshot.queue.isEmpty || snapshot.current == null) return;
    final target = Duration(
      milliseconds: interpolatePlayerPosition(
        positionMs: snapshot.positionMs,
        durationMs: snapshot.durationMs,
        state: snapshot.state,
        tickAt: snapshot.tickAt,
        now: _clock(),
      ),
    );

    // Subscribed BEFORE the queue starts the track: `playQueue` fires its event synchronously, and
    // a listener attached afterwards can miss the readiness it is waiting for.
    final ready = engine.states.firstWhere(
      (state) => state == EngineState.ready,
    );

    queue.setShuffleMode(snapshot.shuffle);
    queue.setRepeatMode(snapshot.repeat);
    queue.playQueue(
      snapshot.queue,
      startIndex: snapshot.currentIndex.clamp(0, snapshot.queue.length - 1),
      context: snapshot.context,
    );
    queue.setSleepTimer(_optionFor(snapshot.sleepTimer));

    if (target > Duration.zero) {
      try {
        await ready.timeout(kAdoptSeekTimeout);
        await handler.seek(target);
      } on TimeoutException {
        // Start from the top rather than never starting at all.
        return;
      }
    }
    // A hand-off of paused playback stays paused: moving your music to the kitchen speaker should
    // not start it playing if it was not playing a second ago.
    if (snapshot.state != PlaybackState.playing &&
        snapshot.state != PlaybackState.loading) {
      await handler.pause();
    }
  }

  Future<void> dispose() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    _started = false;
  }

  void _onQueueEvent(QueueEvent event) {
    // Playback starting here is this device claiming the mesh — but only if nobody live holds it.
    // Where somebody does, the claim is refused and the UI's own routing is what should have sent
    // the action to them instead.
    if (event is PlayEntryRequested) controller.claimIfNoLiveTarget();
    publish();
  }

  void _apply(PlayerSyncCommand command) {
    switch (command) {
      case PlayQueueCommand():
        queue.playQueue(
          command.tracks,
          startIndex: command.startIndex,
          context: command.context,
        );
      case PlayNowCommand():
        queue.playNow(command.track);
      case EnqueueCommand():
        queue.enqueue(command.track);
      case PlayNextCommand():
        queue.playNext(command.track);
      case RemoveFromQueueCommand():
        queue.removeFromQueue(command.index);
      case ReorderQueueCommand():
        queue.reorderQueue(command.from, command.to);
      case SetSleepTimerCommand():
        queue.setSleepTimer(command.option);
      case SeekCommand():
        unawaited(handler.seek(Duration(milliseconds: command.positionMs)));
      case SetVolumeCommand():
        unawaited(_setVolume(command.volume));
      case SimpleCommand():
        _applySimple(command.kind);
    }
  }

  void _applySimple(SimpleCommandKind kind) {
    switch (kind) {
      case SimpleCommandKind.next:
        queue.next();
      case SimpleCommandKind.prev:
        queue.prev();
      case SimpleCommandKind.pause:
        unawaited(handler.pause());
      case SimpleCommandKind.resume:
        unawaited(handler.play());
      case SimpleCommandKind.toggleMute:
        final restore = _mutedFrom;
        unawaited(
          _setVolume(restore ?? 0, mutedFrom: restore == null ? _volume : null),
        );
      case SimpleCommandKind.toggleShuffle:
        queue.toggleShuffle();
      case SimpleCommandKind.cycleRepeat:
        queue.cycleRepeat();
    }
  }

  Future<void> _setVolume(double volume, {double? mutedFrom}) async {
    _mutedFrom = mutedFrom;
    _volume = volume;
    await engine.setVolume(volume);
    publish();
  }

  /// The engine's state in the mesh's vocabulary.
  PlaybackState _stateOf(audio.PlaybackState state) {
    if (queue.current == null) return PlaybackState.idle;
    return switch (state.processingState) {
      audio.AudioProcessingState.idle => PlaybackState.idle,
      audio.AudioProcessingState.completed => PlaybackState.ended,
      audio.AudioProcessingState.loading ||
      audio.AudioProcessingState.buffering => PlaybackState.loading,
      audio.AudioProcessingState.error => PlaybackState.paused,
      audio.AudioProcessingState.ready =>
        state.playing ? PlaybackState.playing : PlaybackState.paused,
    };
  }

  /// Re-arms an inherited sleep timer.
  ///
  /// A timer crosses the wire as the deadline it resolved to, while the queue arms one from an
  /// option — so a wall-clock deadline has to be turned back into "this many minutes from now" on
  /// the receiving device. A deadline already in the past is dropped rather than armed at zero,
  /// which would stop the music the instant it arrived.
  SleepTimerOption? _optionFor(SleepTimer? timer) {
    switch (timer) {
      case null:
        return null;
      case SleepAtTrackEnd():
        return const SleepAfterCurrentTrack();
      case SleepAtTime():
        final remaining = timer.endsAt - _clock();
        return remaining <= 0 ? null : SleepAfterMinutes(remaining / 60000);
    }
  }
}
