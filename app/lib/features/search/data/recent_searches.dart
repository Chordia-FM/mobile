import 'dart:convert';

import 'package:chordia_db/open.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';

/// The terms someone searched for last, newest first.
abstract interface class RecentSearchStore {
  Future<List<String>> read();

  /// Records [term] and answers with the new list.
  Future<List<String>> remember(String term);

  Future<void> clear();
}

/// The three operations [KvRecentSearches] needs from a key/value table.
///
/// Narrow on purpose: it is what lets the rules below — de-duplication, ordering, the cap — be
/// tested against a map instead of a SQLite build, which is the only reason they are tested at all.
abstract interface class ScratchStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> remove(String key);
}

/// [ScratchStore] over the app's key/value table.
class KvScratch implements ScratchStore {
  const KvScratch(this._kv);

  final KvDao _kv;

  @override
  Future<String?> read(String key) => _kv.read(key);

  @override
  Future<void> write(String key, String value) => _kv.write(key, value);

  @override
  Future<void> remove(String key) => _kv.remove(key);
}

/// Recent searches as a JSON list under one key.
///
/// Deliberately not per-hub: what a person typed is about them, not about which server answered,
/// and a query that found nothing on one hub is exactly the query worth offering on the next.
class KvRecentSearches implements RecentSearchStore {
  const KvRecentSearches(this._store, {this.limit = 8});

  static const storageKey = 'search.recent';

  final ScratchStore _store;

  /// Long enough to hold the handful of things someone keeps coming back to, short enough that the
  /// list stays scannable above the keyboard.
  final int limit;

  @override
  Future<List<String>> read() async {
    final raw = await _store.read(storageKey);
    if (raw == null) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded.whereType<String>().toList(growable: false);
    } on FormatException {
      // Written by some earlier build, or truncated. An unreadable history is an empty one.
      return const [];
    }
  }

  @override
  Future<List<String>> remember(String term) async {
    final trimmed = term.trim();
    if (trimmed.isEmpty) return read();
    final existing = await read();
    // Case-insensitive de-duplication, but the new spelling wins: someone who retypes a name with
    // different capitalisation has just told us how they think of it.
    final next = [
      trimmed,
      ...existing.where((e) => e.toLowerCase() != trimmed.toLowerCase()),
    ].take(limit).toList(growable: false);
    await _store.write(storageKey, jsonEncode(next));
    return next;
  }

  @override
  Future<void> clear() => _store.remove(storageKey);
}

final recentSearchesProvider = Provider<RecentSearchStore>(
  (ref) => KvRecentSearches(KvScratch(ref.watch(kvDaoProvider))),
);
