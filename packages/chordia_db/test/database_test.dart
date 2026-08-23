import 'package:chordia_db/chordia_db.dart';
import 'package:test/test.dart';

import 'support/in_memory.dart';

void main() {
  late ChordiaDatabase db;

  setUp(() => db = openTestDatabase());
  tearDown(() => db.close());

  test('a fresh database has every declared table and index', () async {
    // Read back from SQLite rather than from the drift schema objects, so this fails if `onCreate`
    // ever stops creating everything the schema declares — which is what a hand-written migration
    // step gets wrong.
    final rows = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type IN ('table', 'index')",
        )
        .get();
    final names = rows.map((row) => row.read<String>('name')).toSet();

    expect(
      names,
      containsAll([
        'hubs',
        'downloads',
        'download_tasks',
        'scrobble_queue',
        'response_cache',
        'kv',
        'downloads_album_id',
        'downloads_artist',
        'download_tasks_state',
        'download_tasks_track_id',
        'scrobble_queue_created_at',
      ]),
    );
  });

  test('foreign key enforcement is on for the connection', () async {
    final row = await db.customSelect('PRAGMA foreign_keys').getSingle();
    expect(row.data.values.single, 1);
  });

  test('the schema version matches the migrations that exist', () async {
    final row = await db.customSelect('PRAGMA user_version').getSingle();
    expect(row.data.values.single, db.schemaVersion);
  });
}
