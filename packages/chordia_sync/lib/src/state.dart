/// The mesh's shared view of who is here and who is playing, and the pure functions that move it.
///
/// Split out from the controller so the resolution rules — which claim wins, when a device stops
/// counting as live, what a transfer is allowed to do — can be read and tested without a
/// transport. They are ports of the web client's, decision for decision.
library;

import 'package:meta/meta.dart';

import 'domain.dart';
import 'messages.dart';
import 'snapshot.dart';

/// How often a member re-announces itself.
const Duration kPlayerHeartbeatInterval = Duration(seconds: 2);

/// How long a member stays listed after its last announce.
///
/// Two and a half heartbeats: long enough that one dropped frame does not evict a live device from
/// somebody's picker, short enough that a device that closed mid-track stops being offered as a
/// playback target before the listener tries it.
const Duration kPlayerLivenessTimeout = Duration(seconds: 5);

/// This client's view of the mesh.
@immutable
class PlayerSyncState {
  const PlayerSyncState({
    this.available = false,
    this.hasKnownPlayback = false,
    this.activeTabId,
    this.activeClaimAt,
    this.latestSnapshot,
    this.latestPosition,
    this.lastPublishedAt,
    this.devices = const [],
    this.autoplayBlocked = false,
  });

  /// Whether this client has a working pipe to the mesh at all. False means "a mesh of one", and
  /// every consumer must fall back to plain local playback rather than mirroring nothing.
  final bool available;

  /// Whether anyone in the mesh has ever reported playback. Distinguishes "nobody is playing" from
  /// "nobody has said yet", which is the difference between starting locally and waiting.
  final bool hasKnownPlayback;

  /// Who owns playback, or null if nobody does.
  final String? activeTabId;

  /// The owner's claim time. Ordering key for every ownership decision.
  final int? activeClaimAt;

  final PlayerSyncSnapshot? latestSnapshot;
  final PlayerPositionTick? latestPosition;

  /// When this client last heard from the owner, for the playback-liveness sweep. Distinct from a
  /// device's `lastSeenAt`: a member can be announcing happily while its engine has gone quiet.
  final int? lastPublishedAt;

  final List<PlayerSyncDevice> devices;

  /// The owner could not start playback without a user gesture. Only meaningful on the owner.
  final bool autoplayBlocked;

  /// Only the fields that ever change without an ownership decision behind them. Everything
  /// else is rebuilt field by field at the call site, deliberately: an ownership change nulls
  /// several fields at once, and a `copyWith` whose null argument means "leave alone" cannot
  /// express that without a clear-flag per field.
  PlayerSyncState copyWith({
    bool? available,
    List<PlayerSyncDevice>? devices,
    bool? autoplayBlocked,
  }) => PlayerSyncState(
    available: available ?? this.available,
    hasKnownPlayback: hasKnownPlayback,
    activeTabId: activeTabId,
    activeClaimAt: activeClaimAt,
    latestSnapshot: latestSnapshot,
    latestPosition: latestPosition,
    lastPublishedAt: lastPublishedAt,
    devices: devices ?? this.devices,
    autoplayBlocked: autoplayBlocked ?? this.autoplayBlocked,
  );

  @override
  String toString() =>
      'PlayerSyncState(available: $available, active: $activeTabId@'
      '$activeClaimAt, devices: ${devices.length})';
}

/// What one applied message did.
@immutable
class PlayerSyncTransition {
  const PlayerSyncTransition({
    required this.state,
    required this.accepted,
    required this.shouldYield,
  });

  final PlayerSyncState state;

  /// Whether the message changed anything. A rejected claim is not an error — it is the losing
  /// side of a race that both sides resolve the same way.
  final bool accepted;

  /// Whether THIS client just lost ownership and must stop its engine now, before anything
  /// re-renders, so two devices never overlap.
  final bool shouldYield;
}

/// Which claim wins, decided identically on every device.
///
/// Later claim wins; a tie breaks on tab id. The tie-break is not arbitrary decoration — two
/// devices told to start at the same millisecond must reach the same answer with no further
/// messages, or both keep playing. Dart's `String.compareTo` orders by UTF-16 code unit, which is
/// what JavaScript's `>=` on strings does, so the two implementations agree on the tie.
bool claimWins(String tabId, int at, String? activeTabId, int? activeClaimAt) {
  if (activeTabId == null || activeClaimAt == null) return true;
  if (at != activeClaimAt) return at > activeClaimAt;
  return tabId.compareTo(activeTabId) >= 0;
}

List<PlayerSyncDevice> upsertPlayerDevice(
  List<PlayerSyncDevice> devices,
  PlayerSyncDevice device,
) {
  final index = devices.indexWhere(
    (candidate) => candidate.tabId == device.tabId,
  );
  if (index < 0) return [...devices, device];
  final next = [...devices];
  next[index] = device;
  return next;
}

/// Removes a device, returning the SAME list when there was nothing to remove.
///
/// Identity is the signal callers use to decide whether anything changed, here and in the state
/// itself — the same reference-equality contract the web client relies on.
List<PlayerSyncDevice> removePlayerDevice(
  List<PlayerSyncDevice> devices,
  String tabId,
) {
  if (!devices.any((device) => device.tabId == tabId)) return devices;
  return [
    for (final device in devices)
      if (device.tabId != tabId) device,
  ];
}

List<PlayerSyncDevice> expirePlayerDevices(
  List<PlayerSyncDevice> devices,
  int now, {
  Duration timeout = kPlayerLivenessTimeout,
}) {
  final live = [
    for (final device in devices)
      if (now - device.lastSeenAt <= timeout.inMilliseconds) device,
  ];
  return live.length == devices.length ? devices : live;
}

/// Where a freshly started playback should go.
@immutable
class PlayerNewPlaybackRoute {
  const PlayerNewPlaybackRoute({
    required this.remote,
    required this.targetTabId,
    required this.shouldClaim,
  });

  /// True when the target is another device and the action should be sent as a command.
  final bool remote;

  final String targetTabId;

  /// True when this client should claim ownership before playing locally.
  final bool shouldClaim;
}

PlayerNewPlaybackRoute resolveNewPlaybackRoute(
  PlayerSyncState state,
  String localTabId,
  int now, {
  Duration timeout = kPlayerLivenessTimeout,
}) {
  if (!state.available) {
    return PlayerNewPlaybackRoute(
      remote: false,
      targetTabId: localTabId,
      shouldClaim: false,
    );
  }
  final activeTabId = state.activeTabId;
  final targetIsLive =
      activeTabId != null &&
      state.devices.any(
        (device) =>
            device.tabId == activeTabId &&
            now - device.lastSeenAt <= timeout.inMilliseconds,
      );
  if (!targetIsLive) {
    return PlayerNewPlaybackRoute(
      remote: false,
      targetTabId: localTabId,
      shouldClaim: true,
    );
  }
  return activeTabId == localTabId
      ? PlayerNewPlaybackRoute(
          remote: false,
          targetTabId: localTabId,
          shouldClaim: false,
        )
      : PlayerNewPlaybackRoute(
          remote: true,
          targetTabId: activeTabId,
          shouldClaim: false,
        );
}

/// Freeze the last known playback as paused at [now].
///
/// Used wherever the owner disappears rather than hands over. A mirror that kept showing a
/// progress bar advancing for a device that is gone is worse than one showing a paused track: the
/// first is a lie the user acts on, the second is just stale.
({PlayerSyncSnapshot? snapshot, PlayerPositionTick? position}) _pauseSnapshot(
  PlayerSyncSnapshot? snapshot,
  PlayerPositionTick? position,
  int now,
) {
  final sourcePosition = position;
  final sourceSnapshot = snapshot;
  if (sourcePosition == null && sourceSnapshot == null) {
    return (snapshot: snapshot, position: position);
  }
  final positionMs = interpolatePlayerPosition(
    positionMs: sourcePosition?.positionMs ?? sourceSnapshot!.positionMs,
    durationMs: sourcePosition?.durationMs ?? sourceSnapshot!.durationMs,
    state: sourcePosition?.state ?? sourceSnapshot!.state,
    tickAt: sourcePosition?.tickAt ?? sourceSnapshot!.tickAt,
    now: now,
  );
  final durationMs = sourcePosition?.durationMs ?? sourceSnapshot!.durationMs;
  return (
    snapshot: sourceSnapshot?.copyWith(
      positionMs: positionMs,
      durationMs: durationMs,
      state: PlaybackState.paused,
      tickAt: now,
    ),
    position: PlayerPositionTick(
      positionMs: positionMs,
      durationMs: durationMs,
      state: PlaybackState.paused,
      tickAt: now,
    ),
  );
}

PlayerSyncState clearPlaybackTarget(
  PlayerSyncState state,
  int now, {
  List<PlayerSyncDevice>? devices,
}) {
  final paused = _pauseSnapshot(
    state.latestSnapshot,
    state.latestPosition,
    now,
  );
  return PlayerSyncState(
    available: state.available,
    hasKnownPlayback: state.hasKnownPlayback,
    activeTabId: null,
    activeClaimAt: null,
    latestSnapshot: paused.snapshot,
    latestPosition: paused.position,
    lastPublishedAt: null,
    devices: devices ?? state.devices,
    autoplayBlocked: false,
  );
}

/// Fold one decoded message into the state.
PlayerSyncTransition applyPlayerSyncMessage(
  PlayerSyncState state,
  PlayerSyncMessage message,
  String localTabId,
  int now,
) {
  switch (message) {
    case AnnounceMessage():
      return PlayerSyncTransition(
        state: state.copyWith(
          devices: upsertPlayerDevice(
            state.devices,
            PlayerSyncDevice(
              tabId: message.tabId,
              label: message.label,
              lastSeenAt: message.at,
              deviceId: message.deviceId,
            ),
          ),
        ),
        accepted: true,
        shouldYield: false,
      );

    case DepartureMessage():
      final devices = removePlayerDevice(state.devices, message.tabId);
      if (message.tabId == state.activeTabId) {
        return PlayerSyncTransition(
          state: clearPlaybackTarget(state, now, devices: devices),
          accepted: true,
          shouldYield: false,
        );
      }
      if (identical(devices, state.devices)) {
        return PlayerSyncTransition(
          state: state,
          accepted: false,
          shouldYield: false,
        );
      }
      return PlayerSyncTransition(
        state: state.copyWith(devices: devices),
        accepted: true,
        shouldYield: false,
      );

    case TransferMessage():
      // Three gates, and each closes a different hole: the hand-off must start from the owner this
      // device holds, it must be published BY that owner, and its claim must still win. Together
      // they serialise two hand-offs racing for the same playback.
      if (message.previousTargetId != state.activeTabId ||
          (message.previousTargetId != null &&
              message.tabId != message.previousTargetId) ||
          !claimWins(
            message.targetTabId,
            message.claimAt,
            state.activeTabId,
            state.activeClaimAt,
          )) {
        return PlayerSyncTransition(
          state: state,
          accepted: false,
          shouldYield: false,
        );
      }
      final changedOwner = state.activeTabId != message.targetTabId;
      final snapshot = message.snapshot;
      return PlayerSyncTransition(
        state: PlayerSyncState(
          available: state.available,
          hasKnownPlayback: state.hasKnownPlayback || snapshot != null,
          activeTabId: message.targetTabId,
          activeClaimAt: message.claimAt,
          latestSnapshot: snapshot,
          latestPosition: snapshot == null
              ? null
              : PlayerPositionTick(
                  positionMs: snapshot.positionMs,
                  durationMs: snapshot.durationMs,
                  state: snapshot.state,
                  tickAt: snapshot.tickAt,
                ),
          lastPublishedAt: snapshot == null ? null : now,
          devices: state.devices,
          autoplayBlocked: false,
        ),
        accepted: true,
        shouldYield:
            changedOwner &&
            state.activeTabId == localTabId &&
            message.targetTabId != localTabId,
      );

    case ClaimMessage():
      if (!claimWins(
        message.tabId,
        message.at,
        state.activeTabId,
        state.activeClaimAt,
      )) {
        return PlayerSyncTransition(
          state: state,
          accepted: false,
          shouldYield: false,
        );
      }
      final changedOwner = state.activeTabId != message.tabId;
      return PlayerSyncTransition(
        state: PlayerSyncState(
          available: state.available,
          hasKnownPlayback: true,
          activeTabId: message.tabId,
          activeClaimAt: message.at,
          latestSnapshot: changedOwner ? null : state.latestSnapshot,
          latestPosition: changedOwner ? null : state.latestPosition,
          lastPublishedAt: now,
          devices: state.devices,
          autoplayBlocked: changedOwner ? false : state.autoplayBlocked,
        ),
        accepted: true,
        shouldYield:
            changedOwner &&
            state.activeTabId == localTabId &&
            message.tabId != localTabId,
      );

    case SnapshotMessage():
      return _applyOwnerReport(
        state,
        localTabId,
        now,
        tabId: message.tabId,
        claimAt: message.claimAt,
        snapshot: message.snapshot,
        position: PlayerPositionTick(
          positionMs: message.snapshot.positionMs,
          durationMs: message.snapshot.durationMs,
          state: message.snapshot.state,
          tickAt: message.snapshot.tickAt,
        ),
      );

    case PositionMessage():
      return _applyOwnerReport(
        state,
        localTabId,
        now,
        tabId: message.tabId,
        claimAt: message.claimAt,
        snapshot: null,
        position: message.position,
      );

    case ReleasedMessage():
      if (message.tabId != state.activeTabId) {
        return PlayerSyncTransition(
          state: state,
          accepted: false,
          shouldYield: false,
        );
      }
      return PlayerSyncTransition(
        state: clearPlaybackTarget(state, now),
        accepted: true,
        shouldYield: false,
      );

    case WhoIsThereMessage():
    case WhoIsActiveMessage():
    case CommandMessage():
    case TransferRequestMessage():
      // Requests and commands, not state. The controller acts on them; nothing here changes.
      return PlayerSyncTransition(
        state: state,
        accepted: false,
        shouldYield: false,
      );
  }
}

/// Shared body of the `snapshot` and `position` cases: both assert ownership, and both are
/// rejected outright if the sender's claim has already lost.
PlayerSyncTransition _applyOwnerReport(
  PlayerSyncState state,
  String localTabId,
  int now, {
  required String tabId,
  required int claimAt,
  required PlayerSyncSnapshot? snapshot,
  required PlayerPositionTick position,
}) {
  if (!claimWins(tabId, claimAt, state.activeTabId, state.activeClaimAt)) {
    return PlayerSyncTransition(
      state: state,
      accepted: false,
      shouldYield: false,
    );
  }
  final changedOwner = state.activeTabId != tabId;
  return PlayerSyncTransition(
    state: PlayerSyncState(
      available: state.available,
      hasKnownPlayback: true,
      activeTabId: tabId,
      activeClaimAt: claimAt,
      // A position tick from a NEW owner arrives before that owner's first snapshot, and the one
      // this device holds belongs to the device that just lost playback. Keeping it would draw
      // somebody else's track under a progress bar that is now moving to a different one.
      latestSnapshot: snapshot ?? (changedOwner ? null : state.latestSnapshot),
      latestPosition: position,
      lastPublishedAt: now,
      devices: state.devices,
      // A remote owner's report says nothing about whether THIS device could autoplay, and
      // carrying the flag across an owner change is how a stale "tap to play" banner survives a
      // hand-off it has nothing to do with.
      autoplayBlocked: tabId == localTabId ? state.autoplayBlocked : false,
    ),
    accepted: true,
    shouldYield:
        changedOwner && state.activeTabId == localTabId && tabId != localTabId,
  );
}

/// Drop a playback target whose owner stopped reporting while claiming to play.
///
/// Only a *playing* owner is expired. A paused owner has nothing to report, so its silence is
/// normal and evicting it would clear the mirror of anyone who paused for more than five seconds.
PlayerSyncState expirePlayerLiveness(
  PlayerSyncState state,
  int now, {
  Duration timeout = kPlayerLivenessTimeout,
}) {
  final publishedState =
      state.latestPosition?.state ?? state.latestSnapshot?.state;
  final lastPublishedAt = state.lastPublishedAt;
  if (state.activeTabId == null ||
      publishedState != PlaybackState.playing ||
      lastPublishedAt == null ||
      now - lastPublishedAt <= timeout.inMilliseconds) {
    return state;
  }
  final paused = _pauseSnapshot(
    state.latestSnapshot,
    state.latestPosition,
    now,
  );
  return PlayerSyncState(
    available: state.available,
    hasKnownPlayback: state.hasKnownPlayback,
    activeTabId: null,
    activeClaimAt: null,
    latestSnapshot: paused.snapshot,
    latestPosition: paused.position,
    lastPublishedAt: null,
    devices: state.devices,
    autoplayBlocked: false,
  );
}
