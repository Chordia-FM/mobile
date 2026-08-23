import 'package:drift/drift.dart';

import '../database.dart';
import '../tables.dart';

part 'downloads_dao.g.dart';

/// The index of audio held on this device.
@DriftAccessor(tables: [Downloads])
class DownloadsDao extends DatabaseAccessor<ChordiaDatabase>
    with _$DownloadsDaoMixin {
  DownloadsDao(super.db);

  /// Records a finished download, replacing any earlier copy of the same track.
  ///
  /// Re-downloading at a different quality overwrites rather than accumulating: one track means
  /// one file, and the old profile's bytes are deleted by the caller that swapped them.
  Future<void> save(DownloadsCompanion download) =>
      into(downloads).insertOnConflictUpdate(download);

  Future<DownloadedTrack?> byTrack(String trackId) => (select(
    downloads,
  )..where((d) => d.trackId.equals(trackId))).getSingleOrNull();

  /// Everything downloaded, most recent first — the default order of the Downloads screen.
  Future<List<DownloadedTrack>> all() =>
      (select(downloads)..orderBy([(d) => OrderingTerm.desc(d.savedAt)])).get();

  Stream<List<DownloadedTrack>> watchAll() => (select(
    downloads,
  )..orderBy([(d) => OrderingTerm.desc(d.savedAt)])).watch();

  /// One album's downloaded tracks in playing order, not save order.
  Future<List<DownloadedTrack>> byAlbum(String albumId) =>
      (select(downloads)
            ..where((d) => d.albumId.equals(albumId))
            ..orderBy([
              (d) => OrderingTerm.asc(d.discNo),
              (d) => OrderingTerm.asc(d.trackNo),
            ]))
          .get();

  /// Everything credited to [artist], grouped by album so the artist page reads as a discography.
  Future<List<DownloadedTrack>> byArtist(String artist) =>
      (select(downloads)
            ..where((d) => d.artist.equals(artist))
            ..orderBy([
              (d) => OrderingTerm.asc(d.album),
              (d) => OrderingTerm.asc(d.discNo),
              (d) => OrderingTerm.asc(d.trackNo),
            ]))
          .get();

  /// Just the ids, for the downloaded badge on catalog rows.
  ///
  /// A list screen needs to mark hundreds of rows at once; asking per row would be a query per
  /// visible track, and hydrating full rows to read one column each wastes most of the work.
  Future<Set<String>> downloadedTrackIds() async {
    final query = selectOnly(downloads)..addColumns([downloads.trackId]);
    final rows = await query.get();
    return {for (final row in rows) row.read(downloads.trackId)!};
  }

  Future<void> remove(String trackId) =>
      (delete(downloads)..where((d) => d.trackId.equals(trackId))).go();

  Future<void> clear() => delete(downloads).go();

  Future<int> count() async {
    final total = downloads.trackId.count();
    final query = selectOnly(downloads)..addColumns([total]);
    return (await query.getSingle()).read(total) ?? 0;
  }

  /// Disk taken by downloaded audio, for the storage line in settings.
  Future<int> totalBytes() async {
    final total = downloads.sizeBytes.sum();
    final query = selectOnly(downloads)..addColumns([total]);
    return (await query.getSingle()).read(total) ?? 0;
  }
}
