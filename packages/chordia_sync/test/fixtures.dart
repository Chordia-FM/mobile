/// Scripted peers, a link that goes nowhere, and a clock the test moves by hand.
///
/// Everything the mesh does is timed — heartbeats, liveness, claim ordering — so a test that waited
/// for real durations would take five seconds per liveness case and still be flaky. Frames are
/// piped between controllers explicitly instead of over a shared bus, because half these cases turn
/// on what happens when two devices act BEFORE either has heard the other.
library;

import 'dart:async';

import 'package:chordia_sync/chordia_sync.dart';

/// A clock the test sets.
class MutableClock {
  MutableClock(this.now);

  int now;

  int call() => now;

  void advance(Duration by) => now += by.inMilliseconds;
}

/// A link that records what was sent and delivers whatever the test hands it.
///
/// Synchronous delivery, so a test reads as a sequence of steps rather than a chain of awaits. The
/// real link is a WebSocket and asynchronous, but nothing in the controller's handling depends on
/// which it is: every inbound frame is processed to completion before the next.
class RecordingLink implements SyncLink {
  final List<Map<String, Object?>> outbox = [];
  final StreamController<Map<String, Object?>> _inbound =
      StreamController<Map<String, Object?>>.broadcast(sync: true);

  /// When set, [send] throws — a socket that died between frames.
  bool broken = false;

  @override
  void send(Map<String, Object?> message) {
    if (broken) throw StateError('link is down');
    outbox.add(message);
  }

  @override
  Stream<Map<String, Object?>> get onMessage => _inbound.stream;

  /// Hand one frame to the controller, as if a peer had sent it.
  void deliverIn(Map<String, Object?> message) => _inbound.add(message);

  /// Take everything sent so far, clearing the outbox.
  List<Map<String, Object?>> drain() {
    final frames = [...outbox];
    outbox.clear();
    return frames;
  }

  Future<void> close() => _inbound.close();
}

/// One scripted member of the mesh: a controller, its link, and a record of what it was asked to do.
class TestPeer {
  TestPeer(
    this.tabId, {
    required this.clock,
    String? label,
    int? snapshotBudgetBytes,
    String Function()? newRequestId,
  }) {
    controller = PlayerSyncController(
      tabId: tabId,
      deviceLabel: label ?? 'Device $tabId',
      deviceId: 'device-$tabId',
      clock: clock.call,
      newRequestId: newRequestId ?? () => 'request-$tabId',
      snapshotBudgetBytes: snapshotBudgetBytes ?? kPlayerSnapshotBudgetBytes,
    );
    controller.handlers = PlayerSyncHandlers(
      onCommand: commands.add,
      captureSnapshot: () => captured,
      capturePosition: () => capturedPosition,
      onAdoptTransfer: adopted.add,
      onYield: () => yields += 1,
      onPause: () => pauses += 1,
      onResume: () => resumes += 1,
    );
    controller.attachLink(link);
  }

  final String tabId;
  final MutableClock clock;
  final RecordingLink link = RecordingLink();
  late final PlayerSyncController controller;

  final List<PlayerSyncCommand> commands = [];
  final List<PlayerSyncSnapshot> adopted = [];
  int yields = 0;
  int pauses = 0;
  int resumes = 0;

  /// What [PlayerSyncHandlers.captureSnapshot] will report.
  PlayerSyncSnapshot? captured;

  /// What [PlayerSyncHandlers.capturePosition] will report.
  PlayerPositionTick? capturedPosition;

  /// Pipe everything this peer has sent into [others].
  void flushTo(List<TestPeer> others) {
    for (final frame in link.drain()) {
      for (final other in others) {
        other.link.deliverIn(frame);
      }
    }
  }

  Future<void> dispose() async {
    await controller.dispose();
    await link.close();
  }
}

PlayerTrack testTrack(
  String id, {
  String? qid,
  int durationMs = 210000,
  String titleSuffix = '',
}) => PlayerTrack(
  id: id,
  title: 'Track $id$titleSuffix',
  artist: 'Artist $id',
  artistId: 'artist-$id',
  artists: [TrackArtist(id: 'artist-$id', name: 'Artist $id')],
  album: 'Album $id',
  albumId: 'album-$id',
  durationMs: durationMs,
  coverUrl: '/v1/images/cover-$id',
  libraryId: 'library-1',
  trackRef: 'ref-$id',
  contentHash: 'hash-$id',
  advisory: 'clean',
  variants: const [TrackVariant.remaster],
  qid: qid ?? 'q-$id',
);

PlayerSyncSnapshot testSnapshot({
  List<PlayerTrack>? queue,
  int currentIndex = 0,
  PlaybackState state = PlaybackState.playing,
  int positionMs = 30000,
  int durationMs = 210000,
  int tickAt = 1000,
  PlayContext? context,
  SleepTimer? sleepTimer,
}) {
  final tracks = queue ?? [testTrack('a'), testTrack('b')];
  return PlayerSyncSnapshot(
    current: tracks.isEmpty
        ? null
        : tracks[currentIndex.clamp(0, tracks.length - 1)],
    audio: const {'codec': 'flac', 'sample_rate_hz': 44100, 'lossless': true},
    queue: tracks,
    history: [testTrack('older')],
    currentIndex: currentIndex,
    state: state,
    shuffle: false,
    repeat: RepeatMode.off,
    volume: 0.8,
    sleepTimer: sleepTimer,
    context: context ?? const AlbumContext(id: 'album-1', name: 'An Album'),
    positionMs: positionMs,
    durationMs: durationMs,
    tickAt: tickAt,
  );
}
