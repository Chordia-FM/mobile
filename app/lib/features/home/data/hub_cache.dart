import 'dart:convert';

import 'package:chordia_db/open.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'local_store.dart';

/// A Hub response the app has already seen, plus whether it is due a refresh.
@immutable
class CachedJson {
  const CachedJson(this.json, {required this.isStale});

  /// The decoded body, exactly as it came off the wire.
  final Object? json;

  /// True once the freshness window has passed. The body is handed back either way — that is what
  /// makes a cold start paint last night's home instead of a spinner — but the caller should go and
  /// ask the Hub again.
  final bool isStale;
}

/// Stale-while-revalidate storage for Hub JSON.
///
/// An interface rather than the DAO itself so a screen test can run without a SQLite build: every
/// implementation here is thin, and the drift one is the only one that ships.
abstract interface class HubCache {
  Future<CachedJson?> read(String key);

  Future<void> write(String key, Object? json, {required Duration freshFor});
}

/// [HubCache] over the app's `response_cache` table.
class DriftHubCache implements HubCache {
  const DriftHubCache(this._dao, {DateTime Function() clock = DateTime.now})
    : _clock = clock;

  final ResponseCacheDao _dao;
  final DateTime Function() _clock;

  @override
  Future<CachedJson?> read(String key) async {
    final row = await _dao.read(key, now: _clock().millisecondsSinceEpoch);
    if (row == null) return null;
    try {
      return CachedJson(jsonDecode(row.bodyJson), isStale: row.isStale);
    } on FormatException {
      // A body we cannot parse is a miss, not a crash: the row was written by some earlier build.
      return null;
    }
  }

  @override
  Future<void> write(String key, Object? json, {required Duration freshFor}) {
    final now = _clock().millisecondsSinceEpoch;
    return _dao.write(
      key: key,
      bodyJson: jsonEncode(json),
      fetchedAt: now,
      staleAt: now + freshFor.inMilliseconds,
    );
  }
}

final hubCacheProvider = Provider<HubCache>(
  (ref) => DriftHubCache(ref.watch(responseCacheDaoProvider)),
);

/// The cache, or null when this device has none to offer.
///
/// Opening the database can fail — no disk, a corrupt file, or a process that never opened one at
/// all (a widget test, or the audio service starting into a headless isolate). A missing cache
/// costs the freshness of a cold start and nothing else, so every reader treats it as optional
/// rather than letting a storage problem take the screen down with it.
HubCache? readHubCache(Ref ref) {
  try {
    return ref.read(hubCacheProvider);
  } catch (_) {
    return null;
  }
}

/// Decodes a cached JSON array back into models.
///
/// Returns null for anything that is no longer the shape this build expects — a body written
/// before a model gained a required field has to read as a cache miss, never as a crash on launch.
List<T>? decodeCachedList<T>(
  Object? json,
  T Function(Map<String, Object?>) fromJson,
) {
  if (json is! List) return null;
  try {
    return json
        .map((e) => fromJson((e! as Map).cast<String, Object?>()))
        .toList(growable: false);
  } catch (_) {
    return null;
  }
}

/// As [decodeCachedList], for a body that is a single object.
T? decodeCachedObject<T>(
  Object? json,
  T Function(Map<String, Object?>) fromJson,
) {
  if (json is! Map) return null;
  try {
    return fromJson(json.cast<String, Object?>());
  } catch (_) {
    return null;
  }
}
