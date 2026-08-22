import 'package:drift/drift.dart';

import 'dao/download_tasks_dao.dart';
import 'dao/downloads_dao.dart';
import 'dao/hubs_dao.dart';
import 'dao/kv_dao.dart';
import 'dao/response_cache_dao.dart';
import 'dao/scrobble_queue_dao.dart';
import 'tables.dart';

part 'database.g.dart';

/// Everything Chordia keeps on the device.
///
/// The class takes a [QueryExecutor] instead of opening one, which is what lets it stay free of
/// Flutter: tests hand it `NativeDatabase.memory()` and run on the plain Dart VM, while the app
/// calls `openChordiaDatabase` from `package:chordia_db/open.dart`.
@DriftDatabase(
  tables: [
    Hubs,
    Downloads,
    DownloadTasks,
    ScrobbleQueue,
    ResponseCache,
    KeyValues,
  ],
  daos: [
    HubsDao,
    DownloadsDao,
    DownloadTasksDao,
    ScrobbleQueueDao,
    ResponseCacheDao,
    KvDao,
  ],
)
class ChordiaDatabase extends _$ChordiaDatabase {
  ChordiaDatabase(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) => migrator.createAll(),
    onUpgrade: (migrator, from, to) async {
      // Version 1 is the first schema, so nothing reaches here yet. Each future bump adds its own
      // `if (from < n)` block in ascending order and never an `else`: a device that skipped
      // several releases arrives with an old `from` and has to run every intervening step.
      //
      // Two rules that this schema's data makes concrete. Never drop `scrobble_queue` or
      // `downloads` to reshape them — the first holds plays the Hub has not seen and the second is
      // the only index of files on disk, so a rebuild loses user data that no server can return.
      // And add columns nullable or with a default, since an in-place `ALTER TABLE ADD COLUMN`
      // cannot invent values for rows that already exist.
    },
    beforeOpen: (details) async {
      // Off by default in SQLite, and per connection rather than per database, so it has to be
      // re-asserted on every open for any future foreign key to actually be enforced.
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
