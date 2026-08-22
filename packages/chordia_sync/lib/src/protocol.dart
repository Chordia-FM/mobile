/// Encoding and decoding for every mesh frame.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:meta/meta.dart';

import 'coerce.dart';
import 'domain.dart';
import 'messages.dart';
import 'snapshot.dart';

/// Largest frame the Hub's player relay will forward (`MAX_PLAYER_FRAME_BYTES` in the backend's
/// `realtime.rs`). A frame over this is dropped silently — the relay has nothing useful to reply
/// and logging one line per oversized frame would hand any authenticated client the disk.
const int kPlayerFrameCapBytes = 256 * 1024;

/// How large a serialised snapshot this client will send.
///
/// Under [kPlayerFrameCapBytes] by a margin, because the cap is measured on the whole socket text
/// — `{"type":"player","payload":<frame>}` — and the frame wraps the snapshot string in a JSON
/// string literal, where every quote and backslash in the queue's titles becomes two bytes. A
/// snapshot measured right at the cap would therefore arrive over it, and the failure mode is the
/// bad kind: the relay drops it in silence, so the other devices simply stop updating and nothing
/// anywhere says why. 16 KiB of headroom costs a handful of queue entries in the rare case that
/// hits it.
const int kPlayerSnapshotBudgetBytes = 240 * 1024;

/// A snapshot together with the JSON that goes on the wire, after the size guard has run.
@immutable
class FittedSnapshot {
  const FittedSnapshot(this.snapshot, this.json);

  /// What peers will actually receive — the original, or a trimmed copy.
  final PlayerSyncSnapshot snapshot;

  /// [snapshot] serialised, ready to be embedded as the frame's `snapshot` string.
  final String json;

  /// Whether the queue had to be trimmed to fit.
  bool get truncated => snapshot.truncated;
}

/// Wire encoding and decoding for the player mesh.
///
/// Byte-for-byte compatible with `frontend/src/lib/player/sync.ts`, including the quirk that the
/// two snapshot-bearing frames carry the snapshot **pre-serialised as a JSON string** rather than
/// inlined as an object. That started as an optimisation for `BroadcastChannel`, which
/// structured-clones its payload and would otherwise deep-clone a whole queue per message — but it
/// is now simply part of the format, and inlining the object instead would make every web peer
/// reject the frame.
abstract final class PlayerSyncProtocol {
  /// The de-duplication key for a raw inbound frame, or null if it carries no `(tabId, seq)`.
  ///
  /// Read off the raw map rather than the decoded message because it has to work for a frame this
  /// build cannot decode: an unknown message type from a newer peer is still worth remembering, so
  /// its twin down a second pipe is not counted as a fresh arrival.
  static String? dedupeKey(Map<String, Object?> raw) {
    final tabId = stringOrNull(raw['tabId']);
    final seq = finiteOrNull(raw['seq']);
    if (tabId == null || seq == null) return null;
    return '$tabId:${seq.toInt()}';
  }

  /// Serialise a snapshot for embedding in a frame.
  static String encodeSnapshot(PlayerSyncSnapshot snapshot) =>
      jsonEncode(snapshot.toJson());

  /// Parse an embedded snapshot string, returning null on malformed JSON or a bad shape.
  static PlayerSyncSnapshot? decodeSnapshot(String json) {
    try {
      return PlayerSyncSnapshot.tryFromJson(jsonDecode(json));
    } on FormatException {
      return null;
    }
  }

  /// Serialise a snapshot, trimming it if it would not survive the relay.
  ///
  /// The queue is the only part of a snapshot whose size is the user's, not a constant, so it is
  /// the only part worth trimming — and it is trimmed around the current index rather than from
  /// the end, because what a mirror needs most is what is about to play. History goes first: it
  /// only feeds the "previous" stack, and losing it costs less than losing the queue ahead.
  ///
  /// A snapshot that still does not fit with an empty queue is sent anyway. There is nothing left
  /// to give up, and a frame the relay drops leaves the mesh exactly where sending nothing would.
  static FittedSnapshot fitSnapshot(
    PlayerSyncSnapshot snapshot, {
    int budgetBytes = kPlayerSnapshotBudgetBytes,
  }) {
    final full = encodeSnapshot(snapshot);
    if (_byteLength(full) <= budgetBytes) return FittedSnapshot(snapshot, full);

    final withoutHistory = _trimmed(snapshot, snapshot.queue.length);
    final withoutHistoryJson = encodeSnapshot(withoutHistory);
    if (_byteLength(withoutHistoryJson) <= budgetBytes) {
      return FittedSnapshot(withoutHistory, withoutHistoryJson);
    }

    // Largest queue window that fits, by bisection. Each probe re-serialises, so this is a handful
    // of passes over a queue that is by definition already enormous — and only on the rare
    // snapshot that overruns at all.
    var low = 0;
    var high = snapshot.queue.length;
    var best = _trimmed(snapshot, 0);
    var bestJson = encodeSnapshot(best);
    while (low < high) {
      final probe = (low + high + 1) ~/ 2;
      final candidate = _trimmed(snapshot, probe);
      final candidateJson = encodeSnapshot(candidate);
      if (_byteLength(candidateJson) <= budgetBytes) {
        best = candidate;
        bestJson = candidateJson;
        low = probe;
      } else {
        high = probe - 1;
      }
    }
    return FittedSnapshot(best, bestJson);
  }

  /// Drop the history and keep at most [keep] queue entries around the current index, remapping
  /// `currentIndex` onto the window so the entry that is playing is still the one it points at.
  static PlayerSyncSnapshot _trimmed(PlayerSyncSnapshot snapshot, int keep) {
    if (keep >= snapshot.queue.length) {
      return snapshot.copyWith(history: const [], truncated: true);
    }
    // Three quarters of the window ahead of the current track: a mirror shows what is coming, and
    // only the queue panel scrolls backwards.
    final anchor = snapshot.queue.isEmpty
        ? 0
        : snapshot.currentIndex.clamp(0, snapshot.queue.length - 1);
    final behind = math.min(anchor, keep ~/ 4);
    var start = anchor - behind;
    final end = math.min(snapshot.queue.length, start + keep);
    start = math.max(0, end - keep);
    final inWindow =
        snapshot.currentIndex >= start && snapshot.currentIndex < end;
    return snapshot.copyWith(
      queue: snapshot.queue.sublist(start, end),
      history: const [],
      currentIndex: inWindow
          ? snapshot.currentIndex - start
          : snapshot.currentIndex,
      truncated: true,
    );
  }

  static int _byteLength(String json) => utf8.encode(json).length;

  /// Encode a message into its wire map, pre-serialising the snapshot where one is carried.
  ///
  /// [fitted] supplies an already-measured serialisation for the snapshot frames, so the size
  /// guard runs once per send rather than once here and once in the caller.
  static Map<String, Object?> encode(
    PlayerSyncMessage message, {
    FittedSnapshot? fitted,
  }) {
    switch (message) {
      case AnnounceMessage():
        return {
          'type': message.type,
          'tabId': message.tabId,
          'label': message.label,
          'at': message.at,
          if (message.deviceId != null) 'deviceId': message.deviceId,
        };
      case WhoIsThereMessage():
        return {'type': message.type, 'tabId': message.tabId};
      case DepartureMessage():
        return {'type': message.type, 'tabId': message.tabId, 'at': message.at};
      case ClaimMessage():
        return {'type': message.type, 'tabId': message.tabId, 'at': message.at};
      case SnapshotMessage():
        return {
          'type': message.type,
          'tabId': message.tabId,
          'claimAt': message.claimAt,
          'snapshot': fitted?.json ?? encodeSnapshot(message.snapshot),
        };
      case PositionMessage():
        return {
          'type': message.type,
          'tabId': message.tabId,
          'claimAt': message.claimAt,
          'position': message.position.toJson(),
        };
      case CommandMessage():
        return {
          'type': message.type,
          'tabId': message.tabId,
          'activeTabId': message.activeTabId,
          'command': message.command.toJson(),
        };
      case TransferRequestMessage():
        return {
          'type': message.type,
          'requestId': message.requestId,
          'tabId': message.tabId,
          'activeTabId': message.activeTabId,
          'activeClaimAt': message.activeClaimAt,
          'targetTabId': message.targetTabId,
        };
      case TransferMessage():
        final snapshot = message.snapshot;
        return {
          'type': message.type,
          'requestId': message.requestId,
          'tabId': message.tabId,
          'previousTargetId': message.previousTargetId,
          'targetTabId': message.targetTabId,
          'claimAt': message.claimAt,
          'snapshot': snapshot == null
              ? null
              : fitted?.json ?? encodeSnapshot(snapshot),
        };
      case ReleasedMessage():
        return {'type': message.type, 'tabId': message.tabId, 'at': message.at};
      case WhoIsActiveMessage():
        return {'type': message.type, 'tabId': message.tabId};
    }
  }

  /// Decode an inbound frame, returning null for anything malformed.
  ///
  /// Null is not an error path the caller has to report: the mesh tolerates lost messages by
  /// design — members re-announce on a heartbeat and the owner re-publishes on every state change
  /// — so a frame that cannot be trusted is simply a frame that never arrived.
  static PlayerSyncMessage? decode(Object? raw) {
    final json = objectOrNull(raw);
    if (json == null) return null;
    final tabId = stringOrNull(json['tabId']);
    if (tabId == null) return null;
    switch (json['type']) {
      case 'announce':
        final label = stringOrNull(json['label']);
        final at = millisOrNull(json['at']);
        if (label == null || at == null) return null;
        return AnnounceMessage(
          tabId: tabId,
          label: label,
          at: at,
          deviceId: stringOrNull(json['deviceId']),
        );
      case 'whoIsThere':
        return WhoIsThereMessage(tabId: tabId);
      case 'departure':
        final at = millisOrNull(json['at']);
        return at == null ? null : DepartureMessage(tabId: tabId, at: at);
      case 'claim':
        final at = millisOrNull(json['at']);
        return at == null ? null : ClaimMessage(tabId: tabId, at: at);
      case 'snapshot':
        final claimAt = millisOrNull(json['claimAt']);
        final encoded = stringOrNull(json['snapshot']);
        if (claimAt == null || encoded == null) return null;
        final snapshot = decodeSnapshot(encoded);
        return snapshot == null
            ? null
            : SnapshotMessage(
                tabId: tabId,
                claimAt: claimAt,
                snapshot: snapshot,
              );
      case 'position':
        final claimAt = millisOrNull(json['claimAt']);
        final position = PlayerPositionTick.tryFromJson(json['position']);
        if (claimAt == null || position == null) return null;
        return PositionMessage(
          tabId: tabId,
          claimAt: claimAt,
          position: position,
        );
      case 'command':
        final activeTabId = stringOrNull(json['activeTabId']);
        final command = decodeCommand(json['command']);
        if (activeTabId == null || command == null) return null;
        return CommandMessage(
          tabId: tabId,
          activeTabId: activeTabId,
          command: command,
        );
      case 'transferRequest':
        final requestId = stringOrNull(json['requestId']);
        final activeTabId = stringOrNull(json['activeTabId']);
        final activeClaimAt = millisOrNull(json['activeClaimAt']);
        final targetTabId = stringOrNull(json['targetTabId']);
        if (requestId == null ||
            activeTabId == null ||
            activeClaimAt == null ||
            targetTabId == null) {
          return null;
        }
        return TransferRequestMessage(
          requestId: requestId,
          tabId: tabId,
          activeTabId: activeTabId,
          activeClaimAt: activeClaimAt,
          targetTabId: targetTabId,
        );
      case 'transfer':
        final requestId = stringOrNull(json['requestId']);
        final targetTabId = stringOrNull(json['targetTabId']);
        final claimAt = millisOrNull(json['claimAt']);
        final previousTargetIdValue = json['previousTargetId'];
        if (requestId == null ||
            targetTabId == null ||
            claimAt == null ||
            !isOptionalString(previousTargetIdValue)) {
          return null;
        }
        final encoded = json['snapshot'];
        PlayerSyncSnapshot? snapshot;
        if (encoded != null) {
          if (encoded is! String) return null;
          snapshot = decodeSnapshot(encoded);
          // A snapshot that was sent but cannot be read is not a hand-off with no state — it is a
          // hand-off whose state was lost, and accepting it would strand the queue.
          if (snapshot == null) return null;
        }
        return TransferMessage(
          requestId: requestId,
          tabId: tabId,
          previousTargetId: previousTargetIdValue as String?,
          targetTabId: targetTabId,
          claimAt: claimAt,
          snapshot: snapshot,
        );
      case 'released':
        final at = millisOrNull(json['at']);
        return at == null ? null : ReleasedMessage(tabId: tabId, at: at);
      case 'whoIsActive':
        return WhoIsActiveMessage(tabId: tabId);
      default:
        return null;
    }
  }

  /// Decode the `command` object out of a `command` frame.
  static PlayerSyncCommand? decodeCommand(Object? raw) {
    final json = objectOrNull(raw);
    if (json == null) return null;
    switch (json['type']) {
      case 'playQueue':
        final tracks = listOrNull(json['tracks'], PlayerTrack.tryFromJson);
        final startIndex = intOrNull(json['startIndex']);
        if (tracks == null || startIndex == null) return null;
        final contextValue = json['context'];
        PlayContext? context;
        if (contextValue != null) {
          context = PlayContext.tryFromJson(contextValue);
          if (context == null) return null;
        }
        return PlayQueueCommand(
          tracks: tracks,
          startIndex: startIndex,
          context: context,
        );
      case 'playNow':
        final track = PlayerTrack.tryFromJson(json['track']);
        return track == null ? null : PlayNowCommand(track);
      case 'enqueue':
        final track = PlayerTrack.tryFromJson(json['track']);
        return track == null ? null : EnqueueCommand(track);
      case 'playNext':
        final track = PlayerTrack.tryFromJson(json['track']);
        return track == null ? null : PlayNextCommand(track);
      case 'removeFromQueue':
        final index = intOrNull(json['index']);
        return index == null ? null : RemoveFromQueueCommand(index);
      case 'reorderQueue':
        final from = intOrNull(json['from']);
        final to = intOrNull(json['to']);
        if (from == null || to == null) return null;
        return ReorderQueueCommand(from: from, to: to);
      case 'setSleepTimer':
        final option = json['option'];
        if (option == null) return const SetSleepTimerCommand(null);
        final parsed = SleepTimerOption.tryFromWire(option);
        return parsed == null ? null : SetSleepTimerCommand(parsed);
      case 'seek':
        final positionMs = millisOrNull(json['positionMs']);
        return positionMs == null ? null : SeekCommand(positionMs);
      case 'setVolume':
        final volume = finiteOrNull(json['volume']);
        return volume == null ? null : SetVolumeCommand(volume);
      default:
        final kind = SimpleCommandKind.tryParse(json['type']);
        return kind == null ? null : SimpleCommand(kind);
    }
  }
}
