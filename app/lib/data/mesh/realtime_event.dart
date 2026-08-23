/// What the Hub's realtime socket pushes, and which view each kind should refresh.
library;

import 'dart:convert';

/// One push from the Hub. Mirrors `WireEvent` / `EventKind` in the backend's `realtime.rs`.
enum RealtimeEventKind {
  liked('liked'),
  playlists('playlists'),
  playlist('playlist'),
  catalog('catalog'),
  social('social'),
  plays('plays'),

  /// A relayed mesh frame from another of this user's devices. Not a view refresh at all — the
  /// Hub never reads it, and neither does the event bus.
  player('player'),
  billing('billing');

  const RealtimeEventKind(this.wire);

  /// The string the Hub writes this kind as.
  final String wire;

  static RealtimeEventKind? tryParse(Object? value) {
    for (final candidate in values) {
      if (candidate.wire == value) return candidate;
    }
    return null;
  }
}

/// A decoded socket frame.
class RealtimeEvent {
  const RealtimeEvent({required this.kind, this.id, this.payload});

  final RealtimeEventKind kind;

  /// The entity the change is about, where the kind names one (a playlist id).
  final String? id;

  /// Only on [RealtimeEventKind.player]: the mesh frame, forwarded verbatim by the Hub.
  final Map<String, Object?>? payload;

  /// Decodes one socket text frame, or null for anything this build cannot read.
  ///
  /// Null is not an error path worth reporting. Both things this socket carries tolerate a lost
  /// frame by design — the mesh re-announces on a heartbeat, and the 60-second poll backstops a
  /// missed view refresh — so a frame that cannot be trusted is simply a frame that never arrived.
  static RealtimeEvent? tryParse(String text) {
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      return null;
    }
    if (decoded is! Map) return null;
    final json = decoded.cast<String, Object?>();
    final kind = RealtimeEventKind.tryParse(json['kind']);
    if (kind == null) return null;
    final id = json['id'];
    final payload = json['payload'];
    return RealtimeEvent(
      kind: kind,
      id: id is String ? id : null,
      payload: payload is Map ? payload.cast<String, Object?>() : null,
    );
  }

  /// Which refresh key this event fires, or null when it is not a view refresh.
  ///
  /// A `playlist` event names the one playlist that changed, so a screen showing a different
  /// playlist is not disturbed by it. A `playlist` frame that somehow arrives without an id falls
  /// back to the list, which is the smallest refresh that is certainly correct.
  String? get busKey => switch (kind) {
    RealtimeEventKind.player => null,
    RealtimeEventKind.playlist => id == null ? 'playlists' : 'playlist:$id',
    _ => kind.wire,
  };
}

/// How long a refresh key is held down after it fires.
///
/// The catalog enrichment and discography workers broadcast globally every twenty to thirty
/// seconds for as long as they have a backlog, so an un-coalesced bus would have every open client
/// refetching its current view on a loop. Leading-edge: the first event after a quiet spell fires
/// at once — enrichment should be watchable as it lands — and at most once per window after that,
/// with a guaranteed trailing fire so the newest state is never the one that got dropped.
///
/// The windows are the web client's (`frontend/src/lib/app/realtime.ts`), because the firehose
/// they are sized against is the same firehose.
const Map<String, Duration> kRealtimeCoalesceWindows = {
  'catalog': Duration(seconds: 5),
  'social': Duration(seconds: 5),
  'plays': Duration(seconds: 5),
};

/// The window for every key [kRealtimeCoalesceWindows] does not name.
const Duration kRealtimeDefaultCoalesce = Duration(seconds: 1);

/// How long [key] is held down after firing.
Duration coalesceWindowFor(String key) =>
    kRealtimeCoalesceWindows[key] ?? kRealtimeDefaultCoalesce;
