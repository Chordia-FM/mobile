import 'package:drift/drift.dart';

import '../database.dart';
import '../tables.dart';

part 'kv_dao.g.dart';

/// Small scratch values that do not deserve a table of their own.
///
/// Deliberately not the place for anything secret: the database file is plain SQLite, so tokens
/// and keys belong in the platform keystore instead.
@DriftAccessor(tables: [KeyValues])
class KvDao extends DatabaseAccessor<ChordiaDatabase> with _$KvDaoMixin {
  KvDao(super.db);

  Future<String?> read(String key) async {
    final row = await (select(
      keyValues,
    )..where((e) => e.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Stream<String?> watch(String key) =>
      (select(keyValues)..where((e) => e.key.equals(key)))
          .watchSingleOrNull()
          .map((row) => row?.value);

  Future<void> write(String key, String value) =>
      into(keyValues).insertOnConflictUpdate(KvEntry(key: key, value: value));

  /// Reads [key], writing and returning [ifAbsent] the first time it is missing.
  ///
  /// One transaction because the device id is generated this way, and two callers racing on first
  /// launch would otherwise mint two ids and disagree about which device this is.
  Future<String> readOrCreate(String key, String Function() ifAbsent) =>
      transaction(() async {
        final existing = await read(key);
        if (existing != null) return existing;
        final created = ifAbsent();
        await write(key, created);
        return created;
      });

  Future<void> remove(String key) =>
      (delete(keyValues)..where((e) => e.key.equals(key))).go();

  Future<Map<String, String>> all() async {
    final rows = await select(keyValues).get();
    return {for (final row in rows) row.key: row.value};
  }

  Future<void> clear() => delete(keyValues).go();
}
