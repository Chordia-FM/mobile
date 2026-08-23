/// What one device tells the mesh about the playback it owns.
library;

import 'dart:math' as math;

import 'package:meta/meta.dart';

import 'coerce.dart';
import 'domain.dart';

/// The whole of an owner's playback, as the other devices see it.
///
/// Deliberately has no `==`: the state machine compares snapshots by identity, exactly as the web
/// client does with object references, and that is what decides whether a mirror re-renders. A
/// deep equality here would make two structurally identical snapshots from different ticks
/// indistinguishable, and `tickAt` is the only thing that moves while a track plays.
@immutable
class PlayerSyncSnapshot {
  const PlayerSyncSnapshot({
    required this.current,
    required this.queue,
    required this.history,
    required this.currentIndex,
    required this.state,
    required this.shuffle,
    required this.repeat,
    required this.volume,
    required this.sleepTimer,
    required this.context,
    required this.positionMs,
    required this.durationMs,
    required this.tickAt,
    this.audio,
    this.truncated = false,
  });

  final PlayerTrack? current;

  /// Source-file specs for [current], so a mirroring device can show the quality panel too.
  ///
  /// Carried opaquely, and for two reasons. It is not derivable from [current] — the owner gets it
  /// by calling the LIBRARY server directly after the track loads, and a mirror would need its own
  /// capability grant and a round-trip to fetch bytes the owner already holds. And its typed form
  /// (`AudioProperties`) lives in `chordia_api`, which depends on this package, so naming it here
  /// would be a cycle. A map also forwards fields a newer peer added that this build has no name
  /// for. Null until the owner's fetch lands, and while offline, where the panel simply hides.
  final Map<String, Object?>? audio;

  final List<PlayerTrack> queue;
  final List<PlayerTrack> history;

  /// Index of [current] within [queue]. Remapped when a snapshot is truncated to fit the relay.
  final int currentIndex;

  final PlaybackState state;
  final bool shuffle;
  final RepeatMode repeat;
  final double volume;
  final SleepTimer? sleepTimer;
  final PlayContext? context;

  /// Position at [tickAt]; interpolate forward from there while [state] is playing.
  final int positionMs;
  final int durationMs;

  /// Epoch milliseconds this was measured at.
  final int tickAt;

  /// Set when [queue] and [history] were trimmed to fit the Hub relay's frame cap.
  ///
  /// Not part of the web client's type and harmlessly ignored by it — its validator does not
  /// reject unknown fields. Here so a mirror can say "showing part of the queue" instead of
  /// quietly presenting a 40-track window as the whole thing.
  final bool truncated;

  static PlayerSyncSnapshot? tryFromJson(Object? raw) {
    final json = objectOrNull(raw);
    if (json == null) return null;
    final currentValue = json['current'];
    PlayerTrack? current;
    if (currentValue != null) {
      current = PlayerTrack.tryFromJson(currentValue);
      if (current == null) return null;
    }
    final queue = listOrNull(json['queue'], PlayerTrack.tryFromJson);
    final history = listOrNull(json['history'], PlayerTrack.tryFromJson);
    final currentIndex = intOrNull(json['currentIndex']);
    final state = PlaybackState.tryParse(json['state']);
    final shuffle = json['shuffle'];
    final repeat = RepeatMode.tryParse(json['repeat']);
    final volume = finiteOrNull(json['volume']);
    final positionMs = millisOrNull(json['positionMs']);
    final durationMs = millisOrNull(json['durationMs']);
    final tickAt = millisOrNull(json['tickAt']);
    if (queue == null ||
        history == null ||
        currentIndex == null ||
        state == null ||
        shuffle is! bool ||
        repeat == null ||
        volume == null ||
        positionMs == null ||
        durationMs == null ||
        tickAt == null) {
      return null;
    }
    final sleepTimerValue = json['sleepTimer'];
    SleepTimer? sleepTimer;
    if (sleepTimerValue != null) {
      sleepTimer = SleepTimer.tryFromJson(sleepTimerValue);
      if (sleepTimer == null) return null;
    }
    final contextValue = json['context'];
    PlayContext? context;
    if (contextValue != null) {
      context = PlayContext.tryFromJson(contextValue);
      if (context == null) return null;
    }
    return PlayerSyncSnapshot(
      current: current,
      audio: objectOrNull(json['audio']),
      queue: queue,
      history: history,
      currentIndex: currentIndex,
      state: state,
      shuffle: shuffle,
      repeat: repeat,
      volume: volume,
      sleepTimer: sleepTimer,
      context: context,
      positionMs: positionMs,
      durationMs: durationMs,
      tickAt: tickAt,
      truncated: json['truncated'] == true,
    );
  }

  Map<String, Object?> toJson() => {
    'current': current?.toJson(),
    'audio': audio,
    'queue': [for (final track in queue) track.toJson()],
    'history': [for (final track in history) track.toJson()],
    'currentIndex': currentIndex,
    'state': state.wire,
    'shuffle': shuffle,
    'repeat': repeat.wire,
    'volume': volume,
    'sleepTimer': sleepTimer?.toJson(),
    'context': context?.toJson(),
    'positionMs': positionMs,
    'durationMs': durationMs,
    'tickAt': tickAt,
    if (truncated) 'truncated': true,
  };

  PlayerSyncSnapshot copyWith({
    List<PlayerTrack>? queue,
    List<PlayerTrack>? history,
    int? currentIndex,
    PlaybackState? state,
    int? positionMs,
    int? durationMs,
    int? tickAt,
    bool? truncated,
  }) => PlayerSyncSnapshot(
    current: current,
    audio: audio,
    queue: queue ?? this.queue,
    history: history ?? this.history,
    currentIndex: currentIndex ?? this.currentIndex,
    state: state ?? this.state,
    shuffle: shuffle,
    repeat: repeat,
    volume: volume,
    sleepTimer: sleepTimer,
    context: context,
    positionMs: positionMs ?? this.positionMs,
    durationMs: durationMs ?? this.durationMs,
    tickAt: tickAt ?? this.tickAt,
    truncated: truncated ?? this.truncated,
  );

  @override
  String toString() =>
      'PlayerSyncSnapshot(${state.wire}, ${queue.length} queued, '
      'index $currentIndex, $positionMs/$durationMs ms)';
}

/// The cheap message an owner sends every second between snapshots.
@immutable
class PlayerPositionTick {
  const PlayerPositionTick({
    required this.positionMs,
    required this.durationMs,
    required this.state,
    required this.tickAt,
  });

  final int positionMs;
  final int durationMs;
  final PlaybackState state;

  /// Epoch milliseconds this was measured at, so a mirror can interpolate forward from it.
  final int tickAt;

  static PlayerPositionTick? tryFromJson(Object? raw) {
    final json = objectOrNull(raw);
    if (json == null) return null;
    final positionMs = millisOrNull(json['positionMs']);
    final durationMs = millisOrNull(json['durationMs']);
    final state = PlaybackState.tryParse(json['state']);
    final tickAt = millisOrNull(json['tickAt']);
    if (positionMs == null ||
        durationMs == null ||
        state == null ||
        tickAt == null) {
      return null;
    }
    return PlayerPositionTick(
      positionMs: positionMs,
      durationMs: durationMs,
      state: state,
      tickAt: tickAt,
    );
  }

  Map<String, Object?> toJson() => {
    'positionMs': positionMs,
    'durationMs': durationMs,
    'state': state.wire,
    'tickAt': tickAt,
  };

  @override
  bool operator ==(Object other) =>
      other is PlayerPositionTick &&
      other.positionMs == positionMs &&
      other.durationMs == durationMs &&
      other.state == state &&
      other.tickAt == tickAt;

  @override
  int get hashCode => Object.hash(positionMs, durationMs, state, tickAt);

  @override
  String toString() =>
      'PlayerPositionTick(${state.wire}, $positionMs/$durationMs ms @ $tickAt)';
}

/// One member of the mesh, as the device picker lists it.
@immutable
class PlayerSyncDevice {
  const PlayerSyncDevice({
    required this.tabId,
    required this.label,
    required this.lastSeenAt,
    this.deviceId,
  });

  /// The mesh's unit is the CLIENT INSTANCE, not the machine — a browser tab, or this app's
  /// process. That is what owns an engine, so that is what playback can move to.
  final String tabId;

  final String label;

  /// Epoch milliseconds of this member's last announce.
  final int lastSeenAt;

  /// Which physical device this instance belongs to, where one could be minted.
  ///
  /// Lets the picker tell "another window of the same browser" from "the phone", and keeps a
  /// device that is present live from being listed a second time out of the Hub's last-reported
  /// snapshot.
  final String? deviceId;

  @override
  bool operator ==(Object other) =>
      other is PlayerSyncDevice &&
      other.tabId == tabId &&
      other.label == label &&
      other.lastSeenAt == lastSeenAt &&
      other.deviceId == deviceId;

  @override
  int get hashCode => Object.hash(tabId, label, lastSeenAt, deviceId);

  @override
  String toString() => 'PlayerSyncDevice($tabId, $label, seen $lastSeenAt)';
}

/// Interpolate a position forward to [now], which is what makes a mirror's progress bar move
/// between the once-a-second ticks it is fed.
int interpolatePlayerPosition({
  required int positionMs,
  required int durationMs,
  required PlaybackState state,
  required int tickAt,
  required int now,
}) {
  final elapsed = state == PlaybackState.playing
      ? math.max(0, now - tickAt)
      : 0;
  final interpolated = math.max(0, positionMs + elapsed);
  return durationMs > 0 ? math.min(interpolated, durationMs) : interpolated;
}
