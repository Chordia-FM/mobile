import 'package:chordia_db/chordia_db.dart';
import 'package:drift/native.dart';

/// A throwaway database backed by SQLite's in-memory mode.
///
/// This is the reason [ChordiaDatabase] takes an executor rather than opening one: the same class
/// the app runs against is exercised here on the plain Dart VM, with no Flutter binding, no
/// temporary directory to clean up and no state carried between tests.
ChordiaDatabase openTestDatabase() => ChordiaDatabase(NativeDatabase.memory());

/// A hub row with everything but the parts a test is asserting on filled in.
///
/// `isActive` is stated rather than left absent on purpose: a caller mapping a pairing response
/// into a companion writes every column, and it is that shape — not one that happens to omit the
/// flag — which must not be able to disturb the active hub.
HubsCompanion hub(String id, {String? name, int addedAt = 0}) =>
    HubsCompanion.insert(
      id: id,
      name: name ?? 'Hub $id',
      apiBase: 'https://$id.example.com',
      addedAt: addedAt,
      isActive: const Value(false),
    );

/// A downloaded-track row, with the display snapshot defaulted so each test only states the
/// columns it cares about.
DownloadsCompanion download(
  String trackId, {
  String title = 'Song',
  String artist = 'Artist',
  String? album,
  String? albumId,
  int? discNo,
  int? trackNo,
  String profile = 'original',
  int sizeBytes = 1000,
  int savedAt = 0,
}) => DownloadsCompanion.insert(
  trackId: trackId,
  libraryId: 'lib-1',
  trackRef: 'ref-$trackId',
  contentHash: 'sha-$trackId',
  profile: profile,
  filePath: '/music/$trackId.flac',
  sizeBytes: sizeBytes,
  savedAt: savedAt,
  title: title,
  artist: artist,
  album: Value(album),
  albumId: Value(albumId),
  durationMs: 180000,
  discNo: Value(discNo),
  trackNo: Value(trackNo),
);
