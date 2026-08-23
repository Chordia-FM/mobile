import 'package:chordia_db/chordia_db.dart';
import 'package:test/test.dart';

import 'support/in_memory.dart';

void main() {
  late ChordiaDatabase db;
  late DownloadsDao dao;

  setUp(() {
    db = openTestDatabase();
    dao = db.downloadsDao;
  });

  tearDown(() => db.close());

  test('saving the same track twice replaces the row', () async {
    await dao.save(download('t1', profile: 'normal', sizeBytes: 100));
    await dao.save(download('t1', profile: 'original', sizeBytes: 900));

    expect(await dao.count(), 1);
    final row = await dao.byTrack('t1');
    expect(row?.profile, 'original');
    expect(row?.sizeBytes, 900);
  });

  test('a saved row carries the snapshot offline playback needs', () async {
    await dao.save(
      download(
        't1',
        title: 'Marvins Room',
        artist: 'Drake',
        album: 'Take Care',
      ),
    );

    final row = await dao.byTrack('t1');
    expect(row?.title, 'Marvins Room');
    expect(row?.artist, 'Drake');
    expect(row?.album, 'Take Care');
    expect(row?.filePath, '/music/t1.flac');
    expect(row?.libraryId, 'lib-1');
    expect(row?.trackRef, 'ref-t1');
    expect(row?.durationMs, 180000);
  });

  test('an album lists in disc and track order, not save order', () async {
    await dao.save(download('t3', albumId: 'al-1', discNo: 2, trackNo: 1));
    await dao.save(download('t1', albumId: 'al-1', discNo: 1, trackNo: 1));
    await dao.save(download('t2', albumId: 'al-1', discNo: 1, trackNo: 2));
    await dao.save(download('other', albumId: 'al-2', discNo: 1, trackNo: 1));

    expect((await dao.byAlbum('al-1')).map((d) => d.trackId), [
      't1',
      't2',
      't3',
    ]);
  });

  test('an artist lists grouped by album', () async {
    await dao.save(
      download('t2', artist: 'Drake', album: 'Views', albumId: 'b', trackNo: 1),
    );
    await dao.save(
      download(
        't1',
        artist: 'Drake',
        album: 'Nothing',
        albumId: 'a',
        trackNo: 2,
      ),
    );
    await dao.save(
      download(
        't0',
        artist: 'Drake',
        album: 'Nothing',
        albumId: 'a',
        trackNo: 1,
      ),
    );
    await dao.save(download('x', artist: 'Someone Else'));

    expect((await dao.byArtist('Drake')).map((d) => d.trackId), [
      't0',
      't1',
      't2',
    ]);
  });

  test('all() is newest first', () async {
    await dao.save(download('t1', savedAt: 100));
    await dao.save(download('t2', savedAt: 300));
    await dao.save(download('t3', savedAt: 200));

    expect((await dao.all()).map((d) => d.trackId), ['t2', 't3', 't1']);
  });

  test('downloaded ids are the set the badge checks against', () async {
    await dao.save(download('t1'));
    await dao.save(download('t2'));

    expect(await dao.downloadedTrackIds(), {'t1', 't2'});
  });

  test('total bytes sums the library and survives an empty one', () async {
    expect(await dao.totalBytes(), 0);

    await dao.save(download('t1', sizeBytes: 400));
    await dao.save(download('t2', sizeBytes: 600));

    expect(await dao.totalBytes(), 1000);
  });

  test('removing a track drops it from every view', () async {
    await dao.save(download('t1', albumId: 'al-1'));
    await dao.save(download('t2', albumId: 'al-1'));

    await dao.remove('t1');

    expect(await dao.byTrack('t1'), isNull);
    expect((await dao.byAlbum('al-1')).map((d) => d.trackId), ['t2']);
    expect(await dao.downloadedTrackIds(), {'t2'});
  });
}
