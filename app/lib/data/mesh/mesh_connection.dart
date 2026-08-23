/// This device's one pipe into the cross-device player mesh.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:chordia_api/chordia_api.dart' show expiryOf;
import 'package:chordia_sync/chordia_sync.dart'
    show Clock, PlayerSyncController, SyncLink, systemClock;
import 'package:flutter/foundation.dart' show visibleForTesting;

import 'realtime_bus.dart';
import 'realtime_event.dart';
import 'realtime_socket.dart';

/// Longest wait between reconnection attempts.
const Duration kMeshMaxBackoff = Duration(seconds: 30);

/// How far ahead of the access token's expiry to reconnect.
///
/// **Must be shorter than the session manager's refresh skew** (one minute), and that is the whole
/// mechanism: the token rides in the socket's query string and is checked once, at the upgrade, so
/// a socket outlives its own credential and only finds out at the next reconnect — which on a
/// phone can be hours later, in the middle of the evening's listening. Asking for a token inside
/// the skew window is what makes the session manager mint a new one, and a new one is what tells
/// us to open a fresh socket. Widen this past the skew and the same token comes back every time,
/// so the reconnect never fires and the socket dies on the server's terms instead.
const Duration kMeshTokenRenewMargin = Duration(seconds: 30);

/// How soon to ask again when the renewal check found the same token.
const Duration kMeshTokenRenewRetry = Duration(seconds: 30);

/// When to check for a new token if the current one's expiry could not be read.
///
/// Chordia's access tokens last an hour; three quarters of that is early enough that a token this
/// client cannot introspect still gets replaced before it expires.
const Duration kMeshTokenRenewFallback = Duration(minutes: 45);

/// The Hub's realtime endpoint for [baseUrl], carrying [token].
///
/// The token goes in the query string because that is the only place a WebSocket can carry a
/// credential — browsers cannot set an `Authorization` header on the handshake, so the Hub accepts
/// it here and this client speaks the same dialect rather than a second one nobody else supports.
Uri realtimeUrl(Uri baseUrl, String token) {
  // A hub address people type ends in a slash about half the time, and `//v1/realtime` is a 404
  // rather than a redirect. Cheap to normalise; the failure it avoids looks like a Hub that does
  // not support the mesh at all.
  final base = baseUrl.path.endsWith('/')
      ? baseUrl.path.substring(0, baseUrl.path.length - 1)
      : baseUrl.path;
  return baseUrl.replace(
    scheme: baseUrl.scheme == 'https' ? 'wss' : 'ws',
    path: '$base/v1/realtime',
    queryParameters: {'token': token},
  );
}

/// Keeps this phone attached to the mesh, and routes everything else the socket carries.
///
/// **This is the only pipe on mobile.** The web client reaches the mesh over two — a same-profile
/// `BroadcastChannel` and this relay — and can lose either one; here there is no second pipe, so
/// when this connection is down the phone is simply not in the mesh, and the player falls back to
/// plain local playback (which is exactly what [PlayerSyncController] does with no link attached).
///
/// The socket also dies whenever the process is frozen, and that is expected rather than a fault
/// to engineer around: while something is playing the media foreground service keeps the process —
/// and therefore this socket — alive, and when nothing is playing a backgrounded phone has nothing
/// to contribute to a mesh anyway.
class MeshConnection {
  MeshConnection({
    required this.controller,
    required this.bus,
    required Uri baseUrl,
    required Future<String?> Function() accessToken,
    required RealtimeSocketOpener open,
    Clock clock = systemClock,
    MeshTimerFactory timerFactory = realMeshTimer,
    this.maxBackoff = kMeshMaxBackoff,
    this.renewMargin = kMeshTokenRenewMargin,
    this.renewRetry = kMeshTokenRenewRetry,
  }) : _baseUrl = baseUrl,
       _accessToken = accessToken,
       _open = open,
       _clock = clock,
       _timerFactory = timerFactory;

  /// The mesh itself. Attached on every open and detached on every close.
  final PlayerSyncController controller;

  /// Where the socket's non-player pushes go.
  final RealtimeEventBus bus;

  final Uri _baseUrl;
  final Future<String?> Function() _accessToken;
  final RealtimeSocketOpener _open;
  final Clock _clock;
  final MeshTimerFactory _timerFactory;

  final Duration maxBackoff;
  final Duration renewMargin;
  final Duration renewRetry;

  bool _started = false;
  RealtimeSocket? _socket;
  _MeshSyncLink? _link;
  StreamSubscription<String>? _subscription;
  Timer? _reconnectTimer;
  Timer? _renewTimer;
  int _attempts = 0;

  /// The token the live socket was authenticated with, so a renewal can tell a rotation from a
  /// cache hit.
  String? _openedWith;

  /// Bumped whenever the current attempt stops being the one we care about. Async work started by
  /// an older generation must not install a socket the newer one has already replaced.
  int _generation = 0;

  bool get isConnected => _socket != null;

  /// Consecutive failed attempts, which is what sizes the backoff.
  @visibleForTesting
  int get attempts => _attempts;

  /// Connect, and keep reconnecting until [stop].
  Future<void> start() async {
    if (_started) return;
    _started = true;
    await _connect();
  }

  /// Leave the mesh and close the socket. Call on sign-out: a socket authenticated for a session
  /// the user has ended is a credential nobody expects the app to still be holding.
  Future<void> stop() async {
    if (!_started && _socket == null) return;
    _started = false;
    _generation += 1;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _renewTimer?.cancel();
    _renewTimer = null;
    _attempts = 0;
    // Announced, not merely dropped: `release` clears the playback target this device was holding
    // and `depart` takes it out of every other picker now, rather than five seconds from now when
    // its liveness runs out. A reconnect deliberately does NOT do this — see `_renew`, which
    // replaces the socket without ever leaving the mesh.
    controller.release();
    controller.depart();
    controller.stop();
    await _teardown();
  }

  Future<void> _connect() async {
    if (!_started || _socket != null) return;
    final generation = _generation;

    final token = await _accessToken();
    if (!_started || generation != _generation) return;
    // No token means signed out, or a refresh that could not reach the Hub. Neither is retried
    // from here: `start` runs again when a session appears, and retrying a sign-out would be a
    // loop with no exit.
    if (token == null) return;

    final RealtimeSocket socket;
    try {
      socket = await _open(realtimeUrl(_baseUrl, token));
    } on Object {
      if (_started && generation == _generation) _scheduleReconnect();
      return;
    }
    if (!_started || generation != _generation) {
      await socket.close();
      return;
    }

    _socket = socket;
    _openedWith = token;
    _attempts = 0;

    final link = _MeshSyncLink(socket);
    _link = link;
    _subscription = socket.messages.listen(
      (text) => _onFrame(link, text),
      onDone: () => _onClosed(generation),
    );

    controller.attachLink(link);
    // Heartbeat, liveness sweep, position ticks — and a join, which is what re-announces this
    // device on a reopen instead of leaving it missing from every picker for a heartbeat.
    controller.start();
    _scheduleRenew(token);
  }

  void _onFrame(_MeshSyncLink link, String text) {
    final event = RealtimeEvent.tryParse(text);
    if (event == null) return;
    if (event.kind == RealtimeEventKind.player) {
      final payload = event.payload;
      // A player frame with no body is nothing the mesh can act on, and it must NOT fall through
      // to the bus: `player` is not a view refresh, and firing one would refetch a screen on every
      // position tick another device sends.
      if (payload != null) link.deliver(payload);
      return;
    }
    bus.deliver(event);
  }

  void _onClosed(int generation) {
    if (generation != _generation) return;
    _renewTimer?.cancel();
    _renewTimer = null;
    unawaited(_teardown());
    if (_started) _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (!_started || _reconnectTimer != null) return;
    // Doubling from a second, capped. The shift is clamped so a phone left in a tunnel overnight
    // cannot overflow its way back to an instant retry.
    final backoff = 1000 * (1 << math.min(_attempts, 16));
    final delay = Duration(
      milliseconds: math.min(maxBackoff.inMilliseconds, backoff),
    );
    _attempts += 1;
    _reconnectTimer = _timerFactory(delay, () {
      _reconnectTimer = null;
      unawaited(_connect());
    });
  }

  void _scheduleRenew(String token) {
    _renewTimer?.cancel();
    final expiresAt = expiryOf(token);
    final delay = expiresAt == null
        ? kMeshTokenRenewFallback
        : Duration(
            milliseconds: math.max(
              1000,
              expiresAt - renewMargin.inMilliseconds - _clock(),
            ),
          );
    _renewTimer = _timerFactory(delay, () {
      _renewTimer = null;
      unawaited(_renew());
    });
  }

  Future<void> _renew() async {
    if (!_started || _socket == null) return;
    final generation = _generation;
    final token = await _accessToken();
    if (!_started || generation != _generation || _socket == null) return;

    if (token == null || token == _openedWith) {
      // Nothing has rotated yet — or the refresh could not reach the Hub. Either way the live
      // socket is still authenticated, so ask again shortly rather than tearing it down.
      _renewTimer = _timerFactory(renewRetry, () {
        _renewTimer = null;
        unawaited(_renew());
      });
      return;
    }

    // Replace the socket on OUR schedule. Bumping the generation first is what stops the imminent
    // `onDone` from booking a backoff reconnect on top of the immediate one below.
    _generation += 1;
    await _teardown();
    await _connect();
  }

  Future<void> _teardown() async {
    final socket = _socket;
    _socket = null;
    _openedWith = null;
    _link?.dispose();
    _link = null;
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
    // Everything is dropped, not just the pipe: a remembered owner this device can no longer hear
    // would leave it mirroring a device that may have stopped an hour ago, and refusing to play
    // because it believes somebody else is.
    controller.detachLink();
    if (socket != null) {
      try {
        await socket.close();
      } on Object {
        // Already gone. There is nothing a close can fail at that a reconnect does not fix.
      }
    }
  }
}

/// The mesh's view of one open socket.
///
/// The Hub's `{"type":"player","payload":…}` envelope is applied here rather than in the mesh,
/// because that envelope is the relay's business: the Hub reads the wrapper to decide who to
/// forward the body to, and never looks inside it.
class _MeshSyncLink implements SyncLink {
  _MeshSyncLink(this._socket);

  final RealtimeSocket _socket;
  final _inbound = StreamController<Map<String, Object?>>.broadcast();
  bool _closed = false;

  @override
  void send(Map<String, Object?> message) {
    // Throwing is the contract: the controller reads it as a dead pipe, detaches, and lets this
    // device play locally rather than waiting on a socket that will not recover.
    if (_closed) throw StateError('the realtime socket is closed');
    _socket.send(jsonEncode({'type': 'player', 'payload': message}));
  }

  @override
  Stream<Map<String, Object?>> get onMessage => _inbound.stream;

  void deliver(Map<String, Object?> frame) {
    if (!_inbound.isClosed) _inbound.add(frame);
  }

  void dispose() {
    _closed = true;
    unawaited(_inbound.close());
  }
}
