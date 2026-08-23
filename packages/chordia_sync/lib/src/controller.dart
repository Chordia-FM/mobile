/// Membership, ownership, and hand-off for the cross-device player mesh.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:meta/meta.dart';
import 'package:uuid/uuid.dart';

import 'coerce.dart';
import 'domain.dart';
import 'link.dart';
import 'messages.dart';
import 'protocol.dart';
import 'snapshot.dart';
import 'state.dart';

/// How many recently-seen `(sender, seq)` pairs to remember.
///
/// Position ticks dominate mesh traffic at one per second per playing device, so 512 entries is
/// several minutes of history — comfortably long enough that a command sandwiched between ticks is
/// still remembered when a duplicate of it arrives.
///
/// An EXACT set, not a per-sender high-water mark, and the difference matters. The web client sits
/// on two pipes with different latencies, so messages genuinely arrive out of order; "drop
/// anything older than the newest from this sender" would silently swallow a command that lost the
/// race to a position tick. This client has one pipe and would not hit that case — but the rule is
/// what keeps it interoperable, and it is the correct rule regardless.
const int kSeenMessageLimit = 512;

/// How often an owning device publishes its position between snapshots.
const Duration kPlayerPositionInterval = Duration(seconds: 1);

/// What the mesh calls back into when an inbound frame needs the player to do something.
///
/// Callbacks rather than a subclass hook so the controller stays constructible before the engine
/// exists — this app builds the mesh at bootstrap and the player when the first screen mounts.
@immutable
class PlayerSyncHandlers {
  const PlayerSyncHandlers({
    this.onCommand,
    this.captureSnapshot,
    this.capturePosition,
    this.onAdoptTransfer,
    this.onYield,
    this.onPause,
    this.onResume,
  });

  /// A transport command addressed to this device while it owns playback.
  final void Function(PlayerSyncCommand command)? onCommand;

  /// This device's current playback, for a snapshot publish or a hand-off. Null when there is
  /// nothing playing.
  final PlayerSyncSnapshot? Function()? captureSnapshot;

  /// This device's live position, published once a second while it owns playback.
  final PlayerPositionTick? Function()? capturePosition;

  /// Playback has been handed TO this device: restore the queue and resume from the position.
  final void Function(PlayerSyncSnapshot snapshot)? onAdoptTransfer;

  /// Another device won ownership. Stop the local engine now, before any UI catches up, so two
  /// devices never play at once.
  final void Function()? onYield;

  /// Pause before publishing a hand-off, so the new owner cannot start while this one still holds
  /// the audio focus.
  final void Function()? onPause;

  /// Undo that pause when the hand-off could not be published after all.
  final void Function()? onResume;
}

/// One device's membership of the player mesh.
///
/// Owns the protocol and none of the transport: frames go out through an injected [SyncLink] and
/// come back in through its stream, so the same controller runs over the Hub's WebSocket in the
/// app and over a scripted fake in a test.
class PlayerSyncController {
  PlayerSyncController({
    required this.tabId,
    required this.deviceLabel,
    this.deviceId,
    Clock clock = systemClock,
    String Function()? newRequestId,
    this.heartbeatInterval = kPlayerHeartbeatInterval,
    this.positionInterval = kPlayerPositionInterval,
    this.livenessTimeout = kPlayerLivenessTimeout,
    this.snapshotBudgetBytes = kPlayerSnapshotBudgetBytes,
    this.handlers = const PlayerSyncHandlers(),
  }) : _clock = clock,
       _newRequestId = newRequestId ?? _uuid.v4;

  static final Uuid _uuid = const Uuid();

  /// This client instance's id — a browser tab on the web, this process here.
  ///
  /// Minted by the caller and NOT persisted: it identifies an engine, and a relaunched app is a
  /// new engine. The stable per-machine identity is [deviceId].
  final String tabId;

  /// What the other devices call this one in their picker.
  final String deviceLabel;

  /// This machine's stable id, where the app could mint one. Null is a supported answer — a member
  /// with no device id is simply unattributable, and every consumer treats it as its own.
  final String? deviceId;

  final Duration heartbeatInterval;
  final Duration positionInterval;
  final Duration livenessTimeout;
  final int snapshotBudgetBytes;

  /// Replaceable so the app can install them once the engine exists.
  PlayerSyncHandlers handlers;

  final Clock _clock;
  final String Function() _newRequestId;

  final StreamController<PlayerSyncState> _stateEvents =
      StreamController<PlayerSyncState>.broadcast();
  final StreamController<PlayerSyncMessage> _messageEvents =
      StreamController<PlayerSyncMessage>.broadcast();

  /// Insertion-ordered and capped at [kSeenMessageLimit]; the oldest entry is the first one
  /// iteration yields, which is what makes eviction O(1) to find.
  final LinkedHashSet<String> _seen = LinkedHashSet<String>();

  PlayerSyncState _state = const PlayerSyncState();

  /// Monotonic per-client counter. Paired with [tabId] it identifies one message.
  int _seq = 0;

  SyncLink? _link;
  StreamSubscription<Map<String, Object?>>? _linkSubscription;
  Timer? _heartbeat;
  Timer? _positionTimer;

  PlayerSyncState get state => _state;

  /// Fires whenever the mesh's shared view changes. Broadcast, and it does NOT replay the current
  /// value — read [state] for that.
  Stream<PlayerSyncState> get states => _stateEvents.stream;

  /// Every decoded inbound frame, after it has been folded into [state]. For surfaces that want to
  /// react to a message rather than to the state it produced.
  Stream<PlayerSyncMessage> get messages => _messageEvents.stream;

  /// True while this device owns playback.
  bool get isOwner => _state.activeTabId == tabId;

  /// Whether this device may drive its own engine.
  ///
  /// True when there is no mesh at all, when this device owns playback, and when nobody owns it
  /// and nobody ever has. That last case is what keeps a fresh single-device session from
  /// swallowing the first tap on play while it waits for an answer that is never coming.
  bool get localPlaybackAllowed =>
      !_state.available ||
      _state.activeTabId == tabId ||
      (_state.activeTabId == null && !_state.hasKnownPlayback);

  /// Attach the pipe and join the mesh.
  ///
  /// Replaces any previous link, so a reconnect re-attaches rather than leaving a stale sender
  /// pointed at a closed socket.
  void attachLink(SyncLink link) {
    _linkSubscription?.cancel();
    _link = link;
    _linkSubscription = link.onMessage.listen(deliver);
    if (!_state.available) {
      _state = _state.copyWith(available: true);
      _emitState();
    }
  }

  /// Detach the pipe and forget the mesh.
  ///
  /// Everything is dropped, not just the link: with no pipe this device is a mesh of one, and a
  /// remembered owner it can no longer hear would leave it mirroring a device that may have
  /// stopped an hour ago — and refusing to play, because it believes somebody else is.
  void detachLink() {
    _linkSubscription?.cancel();
    _linkSubscription = null;
    _link = null;
    _seen.clear();
    _state = const PlayerSyncState();
    _emitState();
  }

  /// Start the heartbeat, the liveness sweep, and (if [PlayerSyncHandlers.capturePosition] is set)
  /// the position publisher.
  void start() {
    stop();
    _heartbeat = Timer.periodic(heartbeatInterval, (_) => tick());
    _positionTimer = Timer.periodic(
      positionInterval,
      (_) => publishOwnPosition(),
    );
    join();
  }

  void stop() {
    _heartbeat?.cancel();
    _heartbeat = null;
    _positionTimer?.cancel();
    _positionTimer = null;
  }

  /// Announce, then ask who else is here and who is playing.
  ///
  /// Sent on join rather than waited for: the alternative is a picker that fills in two seconds,
  /// which reads as broken on the one screen the user opened to find their other devices.
  void join() {
    announce();
    requestDevices();
    requestActive();
  }

  /// One heartbeat: re-announce, and expire anybody who has stopped.
  ///
  /// Public so a test can drive the timing rules against an injected clock instead of sleeping
  /// through a five-second timeout.
  void tick() {
    announce();
    expire();
  }

  /// Hand an inbound frame to the mesh.
  ///
  /// De-duplication lives here rather than in the link because the same message can legitimately
  /// arrive down more than one pipe, and no single pipe can see the others.
  void deliver(Map<String, Object?> raw) {
    final key = PlayerSyncProtocol.dedupeKey(raw);
    if (key != null) {
      // Our own frame, relayed back. The Hub excludes the sending connection, so this only happens
      // if a pipe ever starts echoing — cheap to rule out, expensive to debug.
      if (stringOrNull(raw['tabId']) == tabId) return;
      if (!_seen.add(key)) return;
      if (_seen.length > kSeenMessageLimit) _seen.remove(_seen.first);
    }
    final message = PlayerSyncProtocol.decode(raw);
    if (message != null) _receive(message, _clock());
  }

  bool announce() {
    if (!_state.available) return false;
    final now = _clock();
    final message = AnnounceMessage(
      tabId: tabId,
      label: deviceLabel,
      at: now,
      deviceId: deviceId,
    );
    if (!_post(PlayerSyncProtocol.encode(message))) return false;
    _receive(message, now);
    return true;
  }

  void requestDevices() {
    _post(PlayerSyncProtocol.encode(WhoIsThereMessage(tabId: tabId)));
  }

  void requestActive() {
    _post(PlayerSyncProtocol.encode(WhoIsActiveMessage(tabId: tabId)));
  }

  /// Leave the mesh, so every picker drops this device now rather than after a liveness timeout.
  void depart() {
    if (!_state.available) return;
    final now = _clock();
    final message = DepartureMessage(tabId: tabId, at: now);
    if (!_post(PlayerSyncProtocol.encode(message))) return;
    _receive(message, now);
  }

  /// Take ownership if nobody live holds it. Returns false when somebody does — the caller should
  /// then route its action to them as a command instead.
  bool claimIfNoLiveTarget() {
    if (!_state.available) return false;
    final now = _clock();
    expire();
    final route = resolveNewPlaybackRoute(
      _state,
      tabId,
      now,
      timeout: livenessTimeout,
    );
    if (!route.shouldClaim) return false;
    final message = ClaimMessage(tabId: tabId, at: _nextClaimAt(now));
    if (!_post(PlayerSyncProtocol.encode(message))) return false;
    _receive(message, now);
    return true;
  }

  /// Publish this device's full playback state, trimmed if it would not survive the relay.
  ///
  /// The trimmed copy is what this device records locally too, so its own view of the mesh matches
  /// what every other member received.
  bool publishSnapshot(PlayerSyncSnapshot snapshot) {
    final claimAt = _localClaimAt();
    if (claimAt == null) return false;
    final fitted = PlayerSyncProtocol.fitSnapshot(
      snapshot,
      budgetBytes: snapshotBudgetBytes,
    );
    final message = SnapshotMessage(
      tabId: tabId,
      claimAt: claimAt,
      snapshot: fitted.snapshot,
    );
    if (!_post(PlayerSyncProtocol.encode(message, fitted: fitted))) {
      return false;
    }
    _receive(message, _clock());
    return true;
  }

  bool publishPosition(PlayerPositionTick position) {
    final claimAt = _localClaimAt();
    if (claimAt == null) return false;
    final message = PositionMessage(
      tabId: tabId,
      claimAt: claimAt,
      position: position,
    );
    if (!_post(PlayerSyncProtocol.encode(message))) return false;
    _receive(message, _clock());
    return true;
  }

  /// Publish the position [PlayerSyncHandlers.capturePosition] reports, if this device owns
  /// playback. Driven by [start]'s timer; public so a test can step it.
  bool publishOwnPosition() {
    if (!isOwner) return false;
    final position = handlers.capturePosition?.call();
    return position == null ? false : publishPosition(position);
  }

  /// Send a transport action to whoever owns playback. False means nobody heard it and the caller
  /// should act locally instead.
  bool sendCommand(PlayerSyncCommand command) {
    final activeTabId = _state.activeTabId;
    if (!_state.available || activeTabId == null) return false;
    return _post(
      PlayerSyncProtocol.encode(
        CommandMessage(
          tabId: tabId,
          activeTabId: activeTabId,
          command: command,
        ),
      ),
    );
  }

  /// Ask for playback to move to [targetTabId].
  ///
  /// Where somebody owns it, this is a request the owner fulfils — it holds the queue and the
  /// position, and only it can pause before letting go. Where nobody owns it, there is nothing to
  /// ask for and the hand-off is published directly.
  bool requestTransfer(String targetTabId) {
    if (!_state.available) return false;
    final now = _clock();
    expire();
    final live = _state.devices.any(
      (device) =>
          device.tabId == targetTabId &&
          now - device.lastSeenAt <= livenessTimeout.inMilliseconds,
    );
    if (!live) return false;
    final activeTabId = _state.activeTabId;
    if (activeTabId == targetTabId) return true;
    final requestId = _newRequestId();
    if (activeTabId == null) {
      return completeTransfer(
        requestId: requestId,
        previousTargetId: null,
        targetTabId: targetTabId,
        snapshot: _transferSnapshot(now),
      );
    }
    final activeClaimAt = _state.activeClaimAt;
    if (activeClaimAt == null) return false;
    final message = TransferRequestMessage(
      requestId: requestId,
      tabId: tabId,
      activeTabId: activeTabId,
      activeClaimAt: activeClaimAt,
      targetTabId: targetTabId,
    );
    if (!_post(PlayerSyncProtocol.encode(message))) return false;
    // Transferring away from ourselves: nothing will come back down the pipe, so the request has
    // to be applied here for the hand-off to happen at all.
    if (activeTabId == tabId) _receive(message, now);
    return true;
  }

  /// Publish a hand-off. Rejected unless this device still holds the owner it was built against.
  bool completeTransfer({
    required String requestId,
    required String? previousTargetId,
    required String targetTabId,
    required PlayerSyncSnapshot? snapshot,
  }) {
    if (!_state.available || _state.activeTabId != previousTargetId) {
      return false;
    }
    final now = _clock();
    final fitted = snapshot == null
        ? null
        : PlayerSyncProtocol.fitSnapshot(
            snapshot,
            budgetBytes: snapshotBudgetBytes,
          );
    final message = TransferMessage(
      requestId: requestId,
      tabId: tabId,
      previousTargetId: previousTargetId,
      targetTabId: targetTabId,
      claimAt: _nextClaimAt(now),
      snapshot: fitted?.snapshot,
    );
    if (!_post(PlayerSyncProtocol.encode(message, fitted: fitted))) {
      return false;
    }
    _receive(message, now);
    return true;
  }

  /// Record that this device could not start playback without a user gesture. Meaningful only
  /// while it owns playback.
  void setAutoplayBlocked(bool autoplayBlocked) {
    if (_state.activeTabId != tabId ||
        _state.autoplayBlocked == autoplayBlocked) {
      return;
    }
    _state = _state.copyWith(autoplayBlocked: autoplayBlocked);
    _emitState();
  }

  /// Give up playback without leaving the mesh.
  void release() {
    if (_state.activeTabId != tabId) return;
    final now = _clock();
    final message = ReleasedMessage(tabId: tabId, at: now);
    if (!_post(PlayerSyncProtocol.encode(message))) return;
    _receive(message, now);
  }

  /// Drop members that have stopped announcing, and a playback target that has gone quiet.
  void expire() {
    final now = _clock();
    // A device whose own timers resumed late — this app after the OS froze it in the background —
    // is still present, and must not expire its own target before its heartbeat catches up.
    var next = _state.activeTabId == tabId
        ? _state
        : expirePlayerLiveness(_state, now, timeout: livenessTimeout);
    final expirable = [
      for (final device in next.devices)
        if (device.tabId != tabId) device,
    ];
    final liveRemote = expirePlayerDevices(
      expirable,
      now,
      timeout: livenessTimeout,
    );
    final devices = liveRemote.length == expirable.length
        ? next.devices
        : [
            for (final device in next.devices)
              if (device.tabId == tabId ||
                  liveRemote.any((live) => live.tabId == device.tabId))
                device,
          ];
    if (!identical(devices, next.devices)) {
      next = next.copyWith(devices: devices);
    }
    final activeTabId = next.activeTabId;
    if (activeTabId != null &&
        activeTabId != tabId &&
        !devices.any((device) => device.tabId == activeTabId)) {
      next = clearPlaybackTarget(next, now, devices: devices);
    }
    if (!identical(next, _state)) {
      _state = next;
      _emitState();
    }
  }

  /// The mirrored position, advanced to now so a progress bar moves between the once-a-second
  /// ticks it is fed.
  ({int positionMs, int durationMs}) interpolatedPosition() {
    final position = _state.latestPosition;
    final snapshot = _state.latestSnapshot;
    if (position == null && snapshot == null) {
      return (positionMs: 0, durationMs: 0);
    }
    final durationMs = position?.durationMs ?? snapshot!.durationMs;
    return (
      positionMs: interpolatePlayerPosition(
        positionMs: position?.positionMs ?? snapshot!.positionMs,
        durationMs: durationMs,
        state: position?.state ?? snapshot!.state,
        tickAt: position?.tickAt ?? snapshot!.tickAt,
        now: _clock(),
      ),
      durationMs: durationMs,
    );
  }

  /// The device new playback should be routed to, or null when this one should claim it.
  String? liveTargetId() {
    final route = resolveNewPlaybackRoute(
      _state,
      tabId,
      _clock(),
      timeout: livenessTimeout,
    );
    return route.shouldClaim ? null : route.targetTabId;
  }

  Future<void> dispose() async {
    stop();
    release();
    depart();
    _linkSubscription?.cancel();
    _linkSubscription = null;
    _link = null;
    await _stateEvents.close();
    await _messageEvents.close();
  }

  /// A claim time strictly after the current owner's, so the tie-break never has to run against a
  /// claim this device knows it is superseding.
  int _nextClaimAt(int now) {
    final activeClaimAt = _state.activeClaimAt;
    return activeClaimAt == null ? now : math.max(now, activeClaimAt + 1);
  }

  int? _localClaimAt() {
    if (!_state.available || _state.activeTabId != tabId) return null;
    return _state.activeClaimAt;
  }

  /// The last known playback, advanced to [now], for handing over when this device is not the one
  /// playing it.
  PlayerSyncSnapshot? _transferSnapshot(int now) {
    final snapshot = _state.latestSnapshot;
    if (snapshot == null) return null;
    final position = _state.latestPosition;
    final durationMs = position?.durationMs ?? snapshot.durationMs;
    return snapshot.copyWith(
      positionMs: interpolatePlayerPosition(
        positionMs: position?.positionMs ?? snapshot.positionMs,
        durationMs: durationMs,
        state: position?.state ?? snapshot.state,
        tickAt: position?.tickAt ?? snapshot.tickAt,
        now: now,
      ),
      durationMs: durationMs,
      state: position?.state ?? snapshot.state,
      tickAt: now,
    );
  }

  void _receive(PlayerSyncMessage message, int now) {
    final previous = _state;
    final transition = applyPlayerSyncMessage(previous, message, tabId, now);
    _state = transition.state;
    if (previous.available != _state.available ||
        previous.activeTabId != _state.activeTabId ||
        previous.activeClaimAt != _state.activeClaimAt ||
        !identical(previous.latestSnapshot, _state.latestSnapshot) ||
        !identical(previous.devices, _state.devices) ||
        previous.autoplayBlocked != _state.autoplayBlocked) {
      _emitState();
    }
    if (!_messageEvents.isClosed) _messageEvents.add(message);
    _act(message, transition, now);
    if (message is WhoIsThereMessage && message.tabId != tabId) announce();
  }

  /// The half of message handling that touches the player rather than the state.
  void _act(
    PlayerSyncMessage message,
    PlayerSyncTransition transition,
    int now,
  ) {
    if (transition.shouldYield) {
      // A newer claim wins deterministically. Stop first, before anything re-renders, so the old
      // engine cannot overlap the claimant while the UI catches up.
      handlers.onYield?.call();
    }
    switch (message) {
      case CommandMessage() when message.activeTabId == tabId && isOwner:
        handlers.onCommand?.call(message.command);
      case TransferRequestMessage()
          when message.activeTabId == tabId &&
              isOwner &&
              message.activeClaimAt == _state.activeClaimAt:
        final snapshot = handlers.captureSnapshot?.call();
        final wasPlaying =
            snapshot?.state == PlaybackState.playing ||
            snapshot?.state == PlaybackState.loading;
        // Pause BEFORE publishing the hand-off, so the new owner cannot begin until this engine
        // has yielded.
        handlers.onPause?.call();
        final completed = completeTransfer(
          requestId: message.requestId,
          previousTargetId: message.activeTabId,
          targetTabId: message.targetTabId,
          snapshot: snapshot,
        );
        // A failed coordination write must restore the already-playing local path; otherwise the
        // pause above is a silent stop with nobody picking playback up.
        if (!completed && wasPlaying) handlers.onResume?.call();
      case TransferMessage()
          when transition.accepted &&
              message.targetTabId == tabId &&
              message.snapshot != null:
        setAutoplayBlocked(false);
        handlers.onAdoptTransfer?.call(message.snapshot!);
      case WhoIsActiveMessage() when isOwner:
        final snapshot = handlers.captureSnapshot?.call();
        if (snapshot != null) publishSnapshot(snapshot);
      default:
        break;
    }
  }

  /// Stamp a frame with this client's sequence number and send it.
  ///
  /// The return value means "nobody heard this" — it is what decides whether a caller falls back
  /// to acting locally, so a pipe that took the frame must report true even if the mesh turns out
  /// to be empty.
  bool _post(Map<String, Object?> wire) {
    final link = _link;
    if (link == null || !_state.available) return false;
    _seq += 1;
    try {
      link.send({...wire, 'seq': _seq});
      return true;
    } catch (_) {
      // A dead pipe is the link's problem to reconnect. Until it does, this device is a mesh of
      // one and must be free to play locally.
      detachLink();
      return false;
    }
  }

  void _emitState() {
    if (!_stateEvents.isClosed) _stateEvents.add(_state);
  }
}
