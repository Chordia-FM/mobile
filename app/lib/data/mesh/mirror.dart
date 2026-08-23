/// Mirroring another device, and deciding where a transport tap actually goes.
library;

import 'package:chordia_sync/chordia_sync.dart';
import 'package:flutter/foundation.dart';

import '../playback/player_state.dart';

/// What the mesh is playing somewhere that is not here.
///
/// Built from [PlayerSyncState] rather than being a second copy of it, so there is exactly one
/// answer to "who owns playback" in the app and the UI cannot drift from the protocol's view of
/// it. Null-ish everywhere when this device owns playback or when there is no mesh: the ordinary
/// local player is what draws that case.
@immutable
class MirrorState {
  const MirrorState({
    required this.active,
    required this.deviceLabel,
    required this.track,
    required this.queue,
    required this.state,
    required this.shuffle,
    required this.repeat,
    required this.durationMs,
    required this.truncated,
    required this.context,
  });

  static const idle = MirrorState(
    active: false,
    deviceLabel: null,
    track: null,
    queue: [],
    state: PlaybackState.idle,
    shuffle: false,
    repeat: RepeatMode.off,
    durationMs: 0,
    truncated: false,
    context: null,
  );

  /// True when another device owns playback and this one should draw a mirror.
  final bool active;

  /// What the owner calls itself, or null where it announced before this device joined.
  final String? deviceLabel;

  final PlayerTrack? track;
  final List<PlayerTrack> queue;
  final PlaybackState state;
  final bool shuffle;
  final RepeatMode repeat;
  final int durationMs;

  /// The owner's queue was trimmed to fit the Hub relay, so this is a window onto it rather than
  /// the whole thing. Worth saying out loud instead of presenting forty tracks as the lot.
  final bool truncated;

  final PlayContext? context;

  bool get playing => state == PlaybackState.playing;
  bool get buffering => state == PlaybackState.loading;

  /// Read the mesh's view from the perspective of [tabId].
  static MirrorState of(PlayerSyncState mesh, String tabId) {
    final activeTabId = mesh.activeTabId;
    if (!mesh.available || activeTabId == null || activeTabId == tabId) {
      return idle;
    }
    final snapshot = mesh.latestSnapshot;
    final position = mesh.latestPosition;
    String? label;
    for (final device in mesh.devices) {
      if (device.tabId == activeTabId) label = device.label;
    }
    return MirrorState(
      active: true,
      deviceLabel: label,
      track: snapshot?.current,
      queue: snapshot?.queue ?? const [],
      // The position tick is newer than the snapshot between state changes, so it is the better
      // answer for "is it playing" even though everything else comes from the snapshot.
      state: position?.state ?? snapshot?.state ?? PlaybackState.idle,
      shuffle: snapshot?.shuffle ?? false,
      repeat: snapshot?.repeat ?? RepeatMode.off,
      durationMs: position?.durationMs ?? snapshot?.durationMs ?? 0,
      truncated: snapshot?.truncated ?? false,
      context: snapshot?.context,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MirrorState &&
      other.active == active &&
      other.deviceLabel == deviceLabel &&
      other.track == track &&
      other.state == state &&
      other.shuffle == shuffle &&
      other.repeat == repeat &&
      other.durationMs == durationMs &&
      other.truncated == truncated &&
      other.context == context &&
      (identical(other.queue, queue) || listEquals(other.queue, queue));

  @override
  int get hashCode => Object.hash(
    active,
    deviceLabel,
    track,
    state,
    shuffle,
    repeat,
    durationMs,
    truncated,
    context,
    queue.length,
  );
}

/// Every transport action, aimed at whichever device is actually playing.
///
/// The whole point of the mesh from a screen's perspective: a play button does not need to know
/// whether the audio is coming out of this phone or the desktop in the next room. Where another
/// device owns playback the action crosses the wire as a command; where this one does — or where
/// there is no mesh at all — it drives the local engine exactly as before.
///
/// A refused send falls back to acting locally rather than doing nothing. `sendCommand` returning
/// false means nobody heard it, and a tap that silently vanishes is worse than one that starts
/// playing on the device the listener is holding.
@immutable
class MeshTransport {
  const MeshTransport({required this.controller, required this.local});

  final PlayerSyncController controller;

  /// The plain local player, used whenever this device is the one that should act.
  final PlayerActions local;

  /// True when transport belongs to another device, so the UI should draw a mirror.
  bool get remote =>
      controller.state.activeTabId != null &&
      controller.state.activeTabId != controller.tabId;

  void setPlaying(bool playing) => _route(
    SimpleCommand(playing ? SimpleCommandKind.resume : SimpleCommandKind.pause),
    () => local.setPlaying(playing),
  );

  void next() =>
      _route(const SimpleCommand(SimpleCommandKind.next), () => local.next());

  void prev() =>
      _route(const SimpleCommand(SimpleCommandKind.prev), () => local.prev());

  void seek(Duration position) =>
      _route(SeekCommand(position.inMilliseconds), () => local.seek(position));

  void setShuffle(bool on) => _route(
    const SimpleCommand(SimpleCommandKind.toggleShuffle),
    () => local.setShuffle(on),
  );

  void cycleRepeat() => _route(
    const SimpleCommand(SimpleCommandKind.cycleRepeat),
    () => local.cycleRepeat(),
  );

  void setSleepTimer(SleepTimerOption? option) =>
      _route(SetSleepTimerCommand(option), () => local.setSleepTimer(option));

  void removeFromQueue(int index) =>
      _route(RemoveFromQueueCommand(index), () => local.removeFromQueue(index));

  void reorderQueue(int from, int to) => _route(
    ReorderQueueCommand(from: from, to: to),
    () => local.reorderQueue(from, to),
  );

  /// Start a queue on whichever device should be playing it.
  ///
  /// Deliberately not routed by [remote] alone: a mesh where nobody owns playback and nobody ever
  /// has is one this device should simply claim, and waiting for an answer that is never coming is
  /// what swallows the first tap on play in a fresh single-device session.
  void playQueue(
    List<PlayerTrack> tracks, {
    int startIndex = 0,
    PlayContext? context,
  }) => _start(
    PlayQueueCommand(tracks: tracks, startIndex: startIndex, context: context),
    () => local.playQueue(tracks, startIndex: startIndex, context: context),
  );

  void playNow(PlayerTrack track) =>
      _start(PlayNowCommand(track), () => local.playNow(track));

  void enqueue(PlayerTrack track) =>
      _route(EnqueueCommand(track), () => local.enqueue(track));

  void playNext(PlayerTrack track) =>
      _route(PlayNextCommand(track), () => local.playNext(track));

  /// Move playback to [tabId]. Passing this device's own tab id brings it here.
  bool transferTo(String tabId) => controller.requestTransfer(tabId);

  /// Bring playback to this device, queue and playhead included.
  bool bringHere() => controller.requestTransfer(controller.tabId);

  void _route(PlayerSyncCommand command, void Function() fallback) {
    if (remote && controller.sendCommand(command)) return;
    fallback();
  }

  void _start(PlayerSyncCommand command, void Function() fallback) {
    final target = controller.liveTargetId();
    if (target != null &&
        target != controller.tabId &&
        controller.sendCommand(command)) {
      return;
    }
    controller.claimIfNoLiveTarget();
    fallback();
  }
}
