/// Everything Chordia keeps on the device.
///
/// Five of the six tables here exist because the network is not guaranteed: the scrobble queue
/// holds plays until the Hub can be reached, the download index describes files that must play
/// with the radio off, and the response cache answers a cold launch before the first request
/// returns. The hub registry and the key/value scratch are simply state no server owns.
///
/// This library is platform-free — it names a [ChordiaDatabase] and the executor it runs on, but
/// never opens one. The app opens it with `openChordiaDatabase` from
/// `package:chordia_db/open.dart`; tests hand the same class a `NativeDatabase.memory()`.
library;

export 'package:drift/drift.dart' show Value;

export 'src/dao/download_tasks_dao.dart' show DownloadTasksDao;
export 'src/dao/downloads_dao.dart' show DownloadsDao;
export 'src/dao/hubs_dao.dart' show HubsDao;
export 'src/dao/kv_dao.dart' show KvDao;
export 'src/dao/response_cache_dao.dart' show CacheEntry, ResponseCacheDao;
export 'src/dao/scrobble_queue_dao.dart' show ScrobbleQueueDao;
export 'src/database.dart';
export 'src/tables.dart' show DownloadState;
