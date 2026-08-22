import 'package:drift/drift.dart';

/// Where a queued download has got to.
///
/// The names double as the stored values — drift's [Table.textEnum] persists `.name`, so renaming
/// a variant is a schema change and needs a migration, not just a refactor.
enum DownloadState {
  queued,
  running,

  /// Stopped on purpose (by the user, or by the "wifi only" rule), and resumable from
  /// [DownloadTasks.bytesDone] with a Range request.
  paused,

  /// Stopped by an error. [DownloadTasks.error] says which.
  failed,

  /// The bytes are on disk and a [Downloads] row exists.
  done,
}

/// Every Hub this device has been paired with.
///
/// Chordia is deliberately multi-hub: a user can hold accounts on a friend's Hub and their own
/// without signing out of either, so the registry outlives any one session.
class Hubs extends Table {
  /// The Hub's own id, so the same Hub reached through two URLs is still one row.
  TextColumn get id => text()();

  /// What the Hub calls itself, for the switcher.
  TextColumn get name => text()();

  /// Origin of the control-plane API, e.g. `https://hub.example.com`.
  TextColumn get apiBase => text()();

  /// Origin of the Hub's web client, used to build shareable links.
  ///
  /// Nullable because a Hub deployed API-only has no web client to point at, and a share sheet
  /// that offers a dead link is worse than one that offers no link.
  TextColumn get frontendUrl => text().nullable()();

  /// Epoch milliseconds, like every timestamp Chordia stores.
  IntColumn get addedAt => integer()();

  /// At most one row may hold true; `HubsDao.setActive` is what keeps that so.
  BoolColumn get isActive => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// One row per track whose audio is on this device.
///
/// The display columns are a denormalised snapshot on purpose. A downloaded track has to render
/// and play with the radio off and the Hub unreachable, so everything the Downloads screen and the
/// player read is copied in at save time rather than joined from a catalog cache that may have
/// been evicted.
@TableIndex(name: 'downloads_album_id', columns: {#albumId})
@TableIndex(name: 'downloads_artist', columns: {#artist})
@DataClassName('DownloadedTrack')
class Downloads extends Table {
  /// The Hub's catalog id for the track — the id every other surface in the app keys on.
  TextColumn get trackId => text()();

  /// The library the audio came from, kept so a re-download can go straight to the right server.
  TextColumn get libraryId => text()();

  /// That library's own id for the track, which is what stream URLs are built from.
  TextColumn get trackRef => text()();

  /// SHA-256 of the source file, so a re-scan that moves the file can still recognise it.
  TextColumn get contentHash => text()();

  /// Quality profile the bytes were fetched at: `original`, `high`, `normal` or `data_saver`.
  ///
  /// Stored as the wire string rather than a Dart enum so this package stays independent of the
  /// generated API models, and so an unknown future profile round-trips instead of throwing.
  TextColumn get profile => text()();

  /// Absolute path of the audio file on this device.
  TextColumn get filePath => text()();

  IntColumn get sizeBytes => integer()();

  /// Epoch milliseconds the download completed.
  IntColumn get savedAt => integer()();

  TextColumn get title => text()();

  /// The full credited-artist line ("X feat. Y"), already assembled by the Hub.
  TextColumn get artist => text()();

  /// The credited artists as a JSON array of `ArtistRef`, for per-artist navigation offline.
  TextColumn get artistsJson => text().nullable()();

  TextColumn get album => text().nullable()();
  TextColumn get albumId => text().nullable()();
  IntColumn get durationMs => integer()();

  /// Hash half of the Hub's `/v1/images/{hash}` cover URL, so artwork resolves from the image
  /// cache without first re-fetching the track.
  TextColumn get coverSha => text().nullable()();

  /// Content advisory from the file's rating tag: `explicit`, `clean`, or null when unrated.
  TextColumn get advisory => text().nullable()();

  /// Title markers the Hub lifted out of the title (`live`, `remaster`, …) as a JSON array.
  ///
  /// Without these an offline row renders a bare title where the online one badges the recording,
  /// which reads as two different tracks.
  TextColumn get variantsJson => text().nullable()();

  IntColumn get trackNo => integer().nullable()();
  IntColumn get discNo => integer().nullable()();

  @override
  Set<Column> get primaryKey => {trackId};
}

/// The resumable download queue.
///
/// Separate from [Downloads] because the two have different lifetimes: a task exists while bytes
/// are still arriving and can be cleared once it is done, while the download row is the durable
/// record that offline playback reads.
@TableIndex(name: 'download_tasks_state', columns: {#state})
@TableIndex(name: 'download_tasks_track_id', columns: {#trackId})
class DownloadTasks extends Table {
  TextColumn get id => text()();
  TextColumn get trackId => text()();
  TextColumn get state => textEnum<DownloadState>()();

  /// Bytes already on disk — also the offset the next Range request resumes from.
  IntColumn get bytesDone => integer().withDefault(const Constant(0))();

  /// Zero until the server has told us the length.
  IntColumn get totalBytes => integer().withDefault(const Constant(0))();

  /// Why the last attempt failed, shown on the row so a retry is an informed choice.
  TextColumn get error => text().nullable()();

  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Listening events waiting to reach the Hub.
///
/// This queue is the whole reason scrobbles survive a tunnel, a dead battery or a week offline:
/// playback writes here synchronously and the sync worker drains it later.
@TableIndex(name: 'scrobble_queue_created_at', columns: {#createdAt})
@DataClassName('QueuedScrobble')
class ScrobbleQueue extends Table {
  /// The client-generated UUIDv7 that is also the Hub's idempotency key.
  ///
  /// Being the primary key means a double-enqueue of the same play is a no-op locally, and a batch
  /// that was delivered but whose response was lost is deduped again server-side on retry.
  TextColumn get eventId => text()();

  /// The full `ListeningEvent` as JSON, posted through to `/v1/scrobbles:batch` untouched.
  ///
  /// Opaque here deliberately: the queue must keep accepting events written by an older build of
  /// the app after the event shape gains a field.
  TextColumn get payloadJson => text()();

  /// Epoch milliseconds the event was queued — the drain and prune order.
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {eventId};
}

/// Stale-while-revalidate cache of Hub JSON responses.
@DataClassName('CachedResponse')
class ResponseCache extends Table {
  /// Cache key, conventionally the request's method, path and query.
  TextColumn get key => text()();

  /// The response body, stored verbatim so the decoder is the same one the network path uses.
  TextColumn get bodyJson => text()();

  /// Epoch milliseconds the response arrived.
  IntColumn get fetchedAt => integer()();

  /// Epoch milliseconds after which the body is served but revalidated in the background.
  IntColumn get staleAt => integer()();

  @override
  Set<Column> get primaryKey => {key};
}

/// Small scratch values: the device id, last volume, per-screen UI preferences.
///
/// Anything that deserves a column of its own should get one; this is for the handful of settings
/// that would each be a one-row table.
@DataClassName('KvEntry')
class KeyValues extends Table {
  @override
  String get tableName => 'kv';

  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}
