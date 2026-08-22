/// The seam between the mesh and whatever carries it.
library;

/// A pipe out of this client, carrying mesh frames verbatim.
///
/// The controller talks through this rather than owning a socket, and that is the whole point: the
/// web client reaches the mesh over two pipes at once (a same-profile `BroadcastChannel` and a
/// relay through the Hub), the desktop app over one, and this app over the Hub's WebSocket — while
/// the protocol above is identical in all three. Keeping the transport out of the controller is
/// also what lets the resolution rules be tested against scripted peers with no socket, no timers,
/// and no device.
///
/// Frames are plain JSON maps. Encoding them — and wrapping them in the Hub's
/// `{"type":"player","payload":…}` envelope — belongs to the implementation, because that envelope
/// is the Hub relay's business and not the mesh's.
abstract interface class SyncLink {
  /// Send one frame. Throwing is a supported answer: the controller treats a throw as a dead pipe
  /// and drops back to local playback rather than waiting on a socket that will not recover.
  void send(Map<String, Object?> message);

  /// Frames from the other members. Must not echo this client's own sends — and the controller
  /// still ignores them if it does, because a repeated `next` skips two tracks.
  Stream<Map<String, Object?>> get onMessage;
}

/// Epoch milliseconds. Injected so the timing rules can be tested at whatever instant the test
/// needs, instead of by sleeping through a five-second liveness timeout.
typedef Clock = int Function();

/// The default clock: the real wall clock, which is what every frame's stamps are in.
int systemClock() => DateTime.now().millisecondsSinceEpoch;
