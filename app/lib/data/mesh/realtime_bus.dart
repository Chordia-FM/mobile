/// The refresh bus the Hub's non-player pushes land on.
library;

import 'dart:async';

import 'package:chordia_sync/chordia_sync.dart' show Clock, systemClock;

import 'realtime_event.dart';

/// Creates the one-shot timer a coalescing window runs on. Injected so a test can fire a window by
/// hand rather than waiting out five seconds of wall clock.
typedef MeshTimerFactory =
    Timer Function(Duration duration, void Function() onFire);

Timer realMeshTimer(Duration duration, void Function() onFire) =>
    Timer(duration, onFire);

/// Fans the Hub's view-refresh pushes out to whoever is watching, at a rate a screen can survive.
///
/// The socket is one pipe carrying two unrelated things. Mesh frames go straight to the player
/// controller — they are already de-duplicated and already cheap. Everything else is "something you
/// are looking at may be stale", and those arrive in bursts a background worker sets the pace of,
/// so they are coalesced here rather than at each listener. See [kRealtimeCoalesceWindows].
class RealtimeEventBus {
  RealtimeEventBus({
    Clock clock = systemClock,
    MeshTimerFactory timerFactory = realMeshTimer,
  }) : _clock = clock,
       _timerFactory = timerFactory;

  final Clock _clock;
  final MeshTimerFactory _timerFactory;

  final _keys = StreamController<String>.broadcast();

  /// When each key last fired, so a burst is measured against the last delivery rather than the
  /// last arrival.
  final _lastFired = <String, int>{};

  /// Trailing fires already scheduled, one per key at most.
  final _pending = <String, Timer>{};

  /// Refresh keys, as fast as [kRealtimeCoalesceWindows] allows. Broadcast, and it replays
  /// nothing: a listener that attaches late has missed nothing it could not refetch.
  Stream<String> get keys => _keys.stream;

  /// Route one decoded frame. Player frames are not this bus's business and are ignored.
  void deliver(RealtimeEvent event) {
    final key = event.busKey;
    if (key != null) emit(key);
  }

  /// Fire [key], or hold it until its window is up.
  ///
  /// Public because a local mutation should refresh instantly rather than through the throttle —
  /// only the server's firehose needs slowing down — and because it is what a test drives.
  void emit(String key) {
    if (_keys.isClosed) return;
    final window = coalesceWindowFor(key).inMilliseconds;
    final now = _clock();
    // Absent means never fired, which always fires — as distinct from "fired at zero". Reading a
    // missing entry as a timestamp would hold the very first push of a key behind a window it was
    // never inside.
    final last = _lastFired[key];
    final sinceLast = last == null ? window : now - last;
    if (sinceLast >= window) {
      _lastFired[key] = now;
      _keys.add(key);
      return;
    }
    // A trailing fire is already booked; a second arrival inside the window changes nothing about
    // when the newest state gets delivered.
    if (_pending.containsKey(key)) return;
    _pending[key] = _timerFactory(
      Duration(milliseconds: window - sinceLast),
      () {
        _pending.remove(key);
        _lastFired[key] = _clock();
        if (!_keys.isClosed) _keys.add(key);
      },
    );
  }

  Future<void> dispose() async {
    for (final timer in _pending.values) {
      timer.cancel();
    }
    _pending.clear();
    await _keys.close();
  }
}
