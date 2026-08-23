import 'package:chordia_player/chordia_player.dart';
// `PlaybackState` means one thing in audio_service and another in chordia_sync. Nothing in this
// file needs either, and hiding it keeps that from being a surprise for whoever adds the first use.
import 'package:chordia_sync/chordia_sync.dart' hide PlaybackState;
import 'package:flutter/foundation.dart';

/// Everything the player UI draws except the playhead.
///
/// The playhead is deliberately absent. It moves twice a second, and folding it in here would
/// rebuild every widget that reads any of these fields at that rate — a whole full-screen player
/// re-laid-out to advance a scrubber by four pixels. It has its own provider, watched only by the
/// two small widgets that actually draw time.
@immutable
class PlayerSnapshot {
  const PlayerSnapshot({
    required this.current,
    required this.queue,
    required this.currentIndex,
    required this.playing,
    required this.buffering,
    required this.shuffle,
    required this.repeat,
    required this.sleepTimer,
    required this.context,
  });

  static const empty = PlayerSnapshot(
    current: null,
    queue: [],
    currentIndex: -1,
    playing: false,
    buffering: false,
    shuffle: false,
    repeat: RepeatMode.off,
    sleepTimer: null,
    context: null,
  );

  final PlayerTrack? current;
  final List<PlayerTrack> queue;
  final int currentIndex;
  final bool playing;

  /// Loading or re-buffering. Distinct from `!playing`: the transport still reads as playing, and
  /// showing a play button here would invite a tap that does nothing.
  final bool buffering;
  final bool shuffle;
  final RepeatMode repeat;
  final SleepTimer? sleepTimer;

  /// Where this queue was started from, for the "Playing from …" line.
  final PlayContext? context;

  /// The catalog length of the current track.
  ///
  /// From the queue entry rather than from the engine on purpose: a lower tier is an on-the-fly
  /// transcode whose measured duration reads short, and a scrubber that shortens when the network
  /// gets worse is the kind of detail that makes a player feel unreliable.
  Duration get duration => Duration(milliseconds: current?.durationMs ?? 0);

  bool get hasTrack => current != null;

  /// Entries after the current one — what a queue sheet calls "next up".
  List<PlayerTrack> get upcoming =>
      currentIndex < 0 || currentIndex + 1 >= queue.length
      ? const []
      : queue.sublist(currentIndex + 1);

  /// Value equality, so a snapshot recomputed on a playhead tick that changed nothing is
  /// recognised as the same state and notifies nobody.
  ///
  /// [queue] is compared by identity first. The notifier hands out the same list instance until
  /// the queue actually changes, so the common case — twice a second, forever — costs one pointer
  /// comparison rather than a walk of every entry.
  @override
  bool operator ==(Object other) =>
      other is PlayerSnapshot &&
      other.current == current &&
      other.currentIndex == currentIndex &&
      other.playing == playing &&
      other.buffering == buffering &&
      other.shuffle == shuffle &&
      other.repeat == repeat &&
      other.sleepTimer == sleepTimer &&
      other.context == context &&
      (identical(other.queue, queue) || listEquals(other.queue, queue));

  @override
  int get hashCode => Object.hash(
    current,
    currentIndex,
    playing,
    buffering,
    shuffle,
    repeat,
    sleepTimer,
    context,
    queue.length,
  );
}

/// Every way the UI can move the player.
///
/// Queue commands go to the [QueueController] directly rather than through the handler: the handler
/// subscribes to the same controller and republishes to the operating system, so the lock screen
/// stays in step either way, and routing through it would only add a translation into a vocabulary
/// (`AudioServiceRepeatMode` and friends) that this app does not otherwise speak. Transport
/// commands that touch the audio itself do go through the handler, because it is what owns the
/// engine and what has to report the result.
@immutable
class PlayerActions {
  const PlayerActions({required this.handler, required this.queue});

  final ChordiaAudioHandler handler;
  final QueueController queue;

  Future<void> play() => handler.play();
  Future<void> pause() => handler.pause();
  Future<void> setPlaying(bool playing) => playing ? play() : pause();
  Future<void> stop() => handler.stop();
  Future<void> seek(Duration position) => handler.seek(position);

  void next() => queue.next();
  void prev() => queue.prev();

  void setShuffle(bool on) => queue.setShuffleMode(on);
  void cycleRepeat() => queue.cycleRepeat();
  void setSleepTimer(SleepTimerOption? option) => queue.setSleepTimer(option);

  void playQueue(
    List<PlayerTrack> tracks, {
    int startIndex = 0,
    PlayContext? context,
  }) => queue.playQueue(tracks, startIndex: startIndex, context: context);

  void playNow(PlayerTrack track) => queue.playNow(track);
  void enqueue(PlayerTrack track) => queue.enqueue(track);
  void playNext(PlayerTrack track) => queue.playNext(track);

  void jumpTo(int index) => queue.jumpTo(index);
  void removeFromQueue(int index) => queue.removeFromQueue(index);
  void reorderQueue(int from, int to) => queue.reorderQueue(from, to);
  void clear() => queue.clear();
}
