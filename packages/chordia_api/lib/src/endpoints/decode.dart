/// Decoding shorthands the endpoint surface leans on.
///
/// Not exported from the package: they are spelling, not API. Every one of them exists so a call
/// site stays a single expression, because an endpoint method that needs a body is a method whose
/// path and its decoder have drifted apart.
library;

import '../json.dart';

/// Decodes a JSON array of objects into models.
List<T> listOf<T>(Object? json, T Function(Map<String, Object?>) fromJson) =>
    asList(json).map((e) => fromJson(asObject(e))).toList();

/// Decodes a JSON array of bare strings — the few endpoints that answer with ids and nothing else.
List<String> stringsOf(Object? json) => asList(json).map(asString).toList();

/// Reads nothing from a response that promises nothing.
///
/// A 204 reaches the decoder as `null`; so does a 200 whose body was unparseable. For an endpoint
/// that returns no value the two are the same event, and neither is an error.
void discard(Object? _) {}

/// Escapes one free-form path segment.
///
/// Handles, genre slugs and station seeds are user- or catalog-derived text, not UUIDs. A `/` or a
/// `#` in one would otherwise change which route the Hub matches rather than which row it looks up.
/// Percent-escapes already present are preserved by `Uri`, so this cannot double-encode.
String seg(String value) => Uri.encodeComponent(value);
