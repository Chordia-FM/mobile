import 'package:drift/drift.dart';
import 'package:meta/meta.dart';

import '../database.dart';
import '../tables.dart';

part 'response_cache_dao.g.dart';

/// A cached body together with the only thing the caller has to decide on: whether to revalidate.
@immutable
class CacheEntry {
  const CacheEntry({required this.response, required this.isStale});

  final CachedResponse response;

  /// True once `staleAt` has passed. The body is still returned — that is the point of
  /// stale-while-revalidate — but the caller should refresh it in the background.
  final bool isStale;

  String get bodyJson => response.bodyJson;
}

/// Stale-while-revalidate cache for Hub JSON.
@DriftAccessor(tables: [ResponseCache])
class ResponseCacheDao extends DatabaseAccessor<ChordiaDatabase>
    with _$ResponseCacheDaoMixin {
  ResponseCacheDao(super.db);

  /// The cached body for [key], or null on a miss.
  ///
  /// A stale entry is a hit, not a miss. Returning it is what makes a cold launch on a slow train
  /// show last night's library instantly instead of a spinner.
  Future<CacheEntry?> read(String key, {required int now}) async {
    final row = await (select(
      responseCache,
    )..where((r) => r.key.equals(key))).getSingleOrNull();
    if (row == null) return null;
    return CacheEntry(response: row, isStale: now >= row.staleAt);
  }

  Future<void> write({
    required String key,
    required String bodyJson,
    required int fetchedAt,
    required int staleAt,
  }) => into(responseCache).insertOnConflictUpdate(
    ResponseCacheCompanion.insert(
      key: key,
      bodyJson: bodyJson,
      fetchedAt: fetchedAt,
      staleAt: staleAt,
    ),
  );

  /// Deletes entries that went stale more than [grace] ago, returning how many were removed.
  ///
  /// Eviction trails staleness by a wide margin on purpose. Deleting the moment an entry goes
  /// stale would leave the offline case with nothing to serve, which is exactly when the cache is
  /// the only source there is.
  Future<int> evictExpired(
    int now, {
    Duration grace = const Duration(days: 7),
  }) =>
      (delete(responseCache)..where(
            (r) => r.staleAt.isSmallerOrEqualValue(now - grace.inMilliseconds),
          ))
          .go();

  /// Drops every entry whose key starts with [prefix], to invalidate a family of responses after
  /// a mutation — editing a playlist should not leave its old track list cached.
  ///
  /// Matched with `LIKE`, where `_` in a key stands for any character, so a prefix containing one
  /// can evict slightly more than it names. That costs a refetch and nothing else, which is a
  /// better trade than escaping every key on the way in.
  Future<int> evictPrefix(String prefix) =>
      (delete(responseCache)..where((r) => r.key.like('$prefix%'))).go();

  Future<void> clear() => delete(responseCache).go();
}
