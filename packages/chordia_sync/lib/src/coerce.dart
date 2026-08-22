/// Null-returning JSON coercions, mirroring the web client's validators.
///
/// The mesh protocol treats a malformed message as a message that never arrived — the sender
/// re-announces on a heartbeat and re-publishes on every state change, so there is nothing useful
/// to do with a shape error except drop it. That is why these return `null` instead of throwing,
/// unlike `chordia_api`'s coercions, which are decoding a response somebody is waiting on.
library;

/// A JSON object, or null for anything else (including a list, which `is Map` would not catch).
Map<String, Object?>? objectOrNull(Object? value) =>
    value is Map ? value.cast<String, Object?>() : null;

String? stringOrNull(Object? value) => value is String ? value : null;

/// True when the value is absent or a string — the `string | undefined` fields.
bool isOptionalString(Object? value) => value == null || value is String;

/// A finite number, matching JS `Number.isFinite`.
///
/// `NaN` and the infinities cannot appear in JSON, but they can appear in a message a peer built
/// in memory and handed straight to [PlayerSyncProtocol.decode] — which is exactly what a test
/// with scripted peers does.
double? finiteOrNull(Object? value) {
  if (value is int) return value.toDouble();
  if (value is double) return value.isFinite ? value : null;
  return null;
}

/// A finite number rounded to whole milliseconds.
///
/// Epoch stamps and positions cross the wire as plain numbers, and the web client mints them from
/// `Date.now()` (integral) and from an `HTMLMediaElement.currentTime` in seconds scaled to
/// milliseconds (not integral). Rounding here rather than rejecting keeps a fractional position
/// from discarding the whole message.
int? millisOrNull(Object? value) {
  final number = finiteOrNull(value);
  return number?.round();
}

/// An integer, matching JS `Number.isInteger` — a fractional value is a real shape error for a
/// queue index, not a rounding artefact.
int? intOrNull(Object? value) {
  if (value is int) return value;
  if (value is double && value.isFinite && value == value.roundToDouble()) {
    return value.toInt();
  }
  return null;
}

/// Decodes every element of a JSON list, failing the whole list if any element fails.
///
/// All-or-nothing because the consumers are queues: a queue silently missing its third track is
/// worse than a snapshot that never applied, since the next one is at most a second away.
List<T>? listOrNull<T extends Object>(
  Object? value,
  T? Function(Object? element) decode,
) {
  if (value is! List) return null;
  final out = <T>[];
  for (final element in value) {
    final decoded = decode(element);
    if (decoded == null) return null;
    out.add(decoded);
  }
  return out;
}

bool listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
