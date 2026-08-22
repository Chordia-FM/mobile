/// Coercions the generated models use to read JSON.
///
/// They exist so a shape surprise fails at the field that caused it, naming the field, instead of
/// surfacing later as a `type 'Null' is not a subtype of type 'String'` from somewhere unrelated.
library;

/// Raised when a value is not the shape the schema promised.
class JsonShapeException implements Exception {
  const JsonShapeException(this.expected, this.actual);

  final String expected;
  final Object? actual;

  @override
  String toString() =>
      'Expected $expected but got ${actual == null ? 'null' : '${actual.runtimeType} ($actual)'}';
}

String asString(Object? v) =>
    v is String ? v : throw JsonShapeException('a string', v);

String? asStringOrNull(Object? v) => v == null ? null : asString(v);

/// Reads an integer, tolerating a JSON number that arrived as a double.
///
/// Epoch milliseconds and byte counts exceed 2^53, so they must stay integers — but a value that
/// round-tripped through a float (some proxies re-encode JSON) comes back as `1.7e12`. Accepting a
/// whole double is safe; a fractional one is a real shape error.
int asInt(Object? v) {
  if (v is int) return v;
  if (v is double && v == v.roundToDouble()) return v.toInt();
  throw JsonShapeException('an integer', v);
}

int? asIntOrNull(Object? v) => v == null ? null : asInt(v);

double asDouble(Object? v) {
  if (v is double) return v;
  if (v is int) return v.toDouble();
  throw JsonShapeException('a number', v);
}

double? asDoubleOrNull(Object? v) => v == null ? null : asDouble(v);

bool asBool(Object? v) =>
    v is bool ? v : throw JsonShapeException('a boolean', v);

bool? asBoolOrNull(Object? v) => v == null ? null : asBool(v);

Map<String, Object?> asObject(Object? v) => v is Map
    ? v.cast<String, Object?>()
    : throw JsonShapeException('an object', v);

Map<String, Object?>? asObjectOrNull(Object? v) =>
    v == null ? null : asObject(v);

List<Object?> asList(Object? v) =>
    v is List ? v : throw JsonShapeException('a list', v);

List<Object?>? asListOrNull(Object? v) => v == null ? null : asList(v);
