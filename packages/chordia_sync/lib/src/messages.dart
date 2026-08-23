/// Every frame the player mesh speaks, and the transport commands one carries.
///
/// The message set and its field names are the web client's (`frontend/src/lib/player/sync.ts`)
/// and have to stay identical: a phone is an ordinary member of the mesh the web and desktop
/// clients already form, so a renamed field does not degrade gracefully — it makes this device
/// invisible in somebody's picker.
library;

import 'package:meta/meta.dart';

import 'domain.dart';
import 'snapshot.dart';

/// One transport action, routed to whichever device owns playback.
@immutable
sealed class PlayerSyncCommand {
  const PlayerSyncCommand();

  /// The `type` discriminator on the wire.
  String get type;

  Map<String, Object?> toJson();
}

/// Replace the queue and start playing at [startIndex].
@immutable
class PlayQueueCommand extends PlayerSyncCommand {
  const PlayQueueCommand({
    required this.tracks,
    required this.startIndex,
    required this.context,
  });

  final List<PlayerTrack> tracks;
  final int startIndex;
  final PlayContext? context;

  @override
  String get type => 'playQueue';

  @override
  Map<String, Object?> toJson() => {
    'type': type,
    'tracks': [for (final track in tracks) track.toJson()],
    'startIndex': startIndex,
    'context': context?.toJson(),
  };
}

/// Play one track now, keeping the rest of the queue.
@immutable
class PlayNowCommand extends PlayerSyncCommand {
  const PlayNowCommand(this.track);

  final PlayerTrack track;

  @override
  String get type => 'playNow';

  @override
  Map<String, Object?> toJson() => {'type': type, 'track': track.toJson()};
}

/// Append to the end of the queue.
@immutable
class EnqueueCommand extends PlayerSyncCommand {
  const EnqueueCommand(this.track);

  final PlayerTrack track;

  @override
  String get type => 'enqueue';

  @override
  Map<String, Object?> toJson() => {'type': type, 'track': track.toJson()};
}

/// Insert directly after the current track.
@immutable
class PlayNextCommand extends PlayerSyncCommand {
  const PlayNextCommand(this.track);

  final PlayerTrack track;

  @override
  String get type => 'playNext';

  @override
  Map<String, Object?> toJson() => {'type': type, 'track': track.toJson()};
}

@immutable
class RemoveFromQueueCommand extends PlayerSyncCommand {
  const RemoveFromQueueCommand(this.index);

  final int index;

  @override
  String get type => 'removeFromQueue';

  @override
  Map<String, Object?> toJson() => {'type': type, 'index': index};
}

@immutable
class ReorderQueueCommand extends PlayerSyncCommand {
  const ReorderQueueCommand({required this.from, required this.to});

  final int from;
  final int to;

  @override
  String get type => 'reorderQueue';

  @override
  Map<String, Object?> toJson() => {'type': type, 'from': from, 'to': to};
}

/// Arm or cancel the sleep timer. A null [option] cancels.
@immutable
class SetSleepTimerCommand extends PlayerSyncCommand {
  const SetSleepTimerCommand(this.option);

  final SleepTimerOption? option;

  @override
  String get type => 'setSleepTimer';

  @override
  Map<String, Object?> toJson() => {'type': type, 'option': option?.toWire()};
}

@immutable
class SeekCommand extends PlayerSyncCommand {
  const SeekCommand(this.positionMs);

  final int positionMs;

  @override
  String get type => 'seek';

  @override
  Map<String, Object?> toJson() => {'type': type, 'positionMs': positionMs};
}

@immutable
class SetVolumeCommand extends PlayerSyncCommand {
  const SetVolumeCommand(this.volume);

  final double volume;

  @override
  String get type => 'setVolume';

  @override
  Map<String, Object?> toJson() => {'type': type, 'volume': volume};
}

/// A transport action with no arguments: `next`, `prev`, `pause`, `resume`, `toggleMute`,
/// `toggleShuffle`, `cycleRepeat`.
///
/// One class rather than seven, because nothing in the protocol or the dispatcher distinguishes
/// them beyond the tag — and a `switch` over [SimpleCommandKind] stays exhaustive the same way a
/// `switch` over seven classes would.
@immutable
class SimpleCommand extends PlayerSyncCommand {
  const SimpleCommand(this.kind);

  final SimpleCommandKind kind;

  @override
  String get type => kind.wire;

  @override
  Map<String, Object?> toJson() => {'type': type};

  @override
  bool operator ==(Object other) =>
      other is SimpleCommand && other.kind == kind;

  @override
  int get hashCode => kind.hashCode;
}

enum SimpleCommandKind {
  next('next'),
  prev('prev'),
  pause('pause'),
  resume('resume'),
  toggleMute('toggleMute'),
  toggleShuffle('toggleShuffle'),
  cycleRepeat('cycleRepeat');

  const SimpleCommandKind(this.wire);

  final String wire;

  static SimpleCommandKind? tryParse(Object? value) {
    for (final candidate in values) {
      if (candidate.wire == value) return candidate;
    }
    return null;
  }
}

/// One frame of the mesh protocol, decoded.
///
/// The two snapshot-bearing frames hold a decoded [PlayerSyncSnapshot] here and a pre-serialised
/// JSON string on the wire; see [PlayerSyncProtocol].
@immutable
sealed class PlayerSyncMessage {
  const PlayerSyncMessage();

  /// The `type` discriminator on the wire.
  String get type;

  /// The member that SENT this frame. Every frame carries one, which is what pairs with `seq` to
  /// identify a message for de-duplication.
  String get tabId;
}

/// "I am here, and this is what to call me." Sent on join and on every heartbeat.
@immutable
class AnnounceMessage extends PlayerSyncMessage {
  const AnnounceMessage({
    required this.tabId,
    required this.label,
    required this.at,
    this.deviceId,
  });

  @override
  final String tabId;

  final String label;

  /// Epoch milliseconds, which doubles as this member's liveness stamp.
  final int at;

  /// Absent from an older peer, or where no id could be minted.
  final String? deviceId;

  @override
  String get type => 'announce';
}

/// "Everyone announce yourselves." Sent on join so the picker fills immediately instead of over
/// the next heartbeat.
@immutable
class WhoIsThereMessage extends PlayerSyncMessage {
  const WhoIsThereMessage({required this.tabId});

  @override
  final String tabId;

  @override
  String get type => 'whoIsThere';
}

/// "I am leaving." Removes the sender from every picker at once rather than after a liveness
/// timeout.
@immutable
class DepartureMessage extends PlayerSyncMessage {
  const DepartureMessage({required this.tabId, required this.at});

  @override
  final String tabId;

  final int at;

  @override
  String get type => 'departure';
}

/// "I am taking playback." Resolved against the current owner by claim time, then by tab id.
@immutable
class ClaimMessage extends PlayerSyncMessage {
  const ClaimMessage({required this.tabId, required this.at});

  @override
  final String tabId;

  /// The claim time, which is also the ordering key ownership is resolved on.
  final int at;

  @override
  String get type => 'claim';
}

/// The owner's full playback state.
@immutable
class SnapshotMessage extends PlayerSyncMessage {
  const SnapshotMessage({
    required this.tabId,
    required this.claimAt,
    required this.snapshot,
  });

  @override
  final String tabId;

  /// The sender's claim time, so a stale owner's snapshot loses to the current one.
  final int claimAt;

  final PlayerSyncSnapshot snapshot;

  @override
  String get type => 'snapshot';
}

/// The owner's once-a-second position tick.
@immutable
class PositionMessage extends PlayerSyncMessage {
  const PositionMessage({
    required this.tabId,
    required this.claimAt,
    required this.position,
  });

  @override
  final String tabId;

  final int claimAt;
  final PlayerPositionTick position;

  @override
  String get type => 'position';
}

/// A transport action aimed at whoever owns playback.
@immutable
class CommandMessage extends PlayerSyncMessage {
  const CommandMessage({
    required this.tabId,
    required this.activeTabId,
    required this.command,
  });

  @override
  final String tabId;

  /// Who the sender believed the owner was. The owner ignores a command addressed to somebody
  /// else, so a command that raced a hand-off is dropped rather than run twice.
  final String activeTabId;

  final PlayerSyncCommand command;

  @override
  String get type => 'command';
}

/// "Owner, hand playback to [targetTabId]." Only the named owner acts on it.
@immutable
class TransferRequestMessage extends PlayerSyncMessage {
  const TransferRequestMessage({
    required this.requestId,
    required this.tabId,
    required this.activeTabId,
    required this.activeClaimAt,
    required this.targetTabId,
  });

  final String requestId;

  @override
  final String tabId;

  final String activeTabId;

  /// The owner's claim time as the requester saw it. The owner checks this against its own, so a
  /// request built against a hand-off that has already happened is ignored.
  final int activeClaimAt;

  final String targetTabId;

  @override
  String get type => 'transferRequest';
}

/// "Playback is now [targetTabId]'s, and here is where it was." Sent by the outgoing owner.
@immutable
class TransferMessage extends PlayerSyncMessage {
  const TransferMessage({
    required this.requestId,
    required this.tabId,
    required this.previousTargetId,
    required this.targetTabId,
    required this.claimAt,
    required this.snapshot,
  });

  final String requestId;

  @override
  final String tabId;

  /// Who owned playback before this hand-off, or null if nobody did. Peers reject the frame
  /// unless it matches the owner they hold, which serialises concurrent hand-offs.
  final String? previousTargetId;

  final String targetTabId;
  final int claimAt;

  /// Null when there was no playback to hand over.
  final PlayerSyncSnapshot? snapshot;

  @override
  String get type => 'transfer';
}

/// "I am no longer playing." Clears the mesh's playback target without ending the sender's
/// membership.
@immutable
class ReleasedMessage extends PlayerSyncMessage {
  const ReleasedMessage({required this.tabId, required this.at});

  @override
  final String tabId;

  final int at;

  @override
  String get type => 'released';
}

/// "Whoever owns playback, publish a snapshot." Sent on join so a new member mirrors immediately
/// rather than at the owner's next state change.
@immutable
class WhoIsActiveMessage extends PlayerSyncMessage {
  const WhoIsActiveMessage({required this.tabId});

  @override
  final String tabId;

  @override
  String get type => 'whoIsActive';
}
