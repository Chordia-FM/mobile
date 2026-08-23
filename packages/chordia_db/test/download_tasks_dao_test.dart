import 'package:chordia_db/chordia_db.dart';
import 'package:test/test.dart';

import 'support/in_memory.dart';

void main() {
  late ChordiaDatabase db;
  late DownloadTasksDao dao;

  setUp(() {
    db = openTestDatabase();
    dao = db.downloadTasksDao;
  });

  tearDown(() => db.close());

  Future<void> enqueue(String id, {required int at}) => dao.enqueue(
    DownloadTasksCompanion.insert(
      id: id,
      trackId: 'track-$id',
      state: DownloadState.queued,
      createdAt: at,
      updatedAt: at,
    ),
  );

  test('a new task starts at zero bytes', () async {
    await enqueue('d1', at: 10);

    final task = await dao.byId('d1');
    expect(task?.state, DownloadState.queued);
    expect(task?.bytesDone, 0);
    expect(task?.totalBytes, 0);
    expect(task?.error, isNull);
  });

  test('the worker picks up the oldest queued task', () async {
    await enqueue('d2', at: 20);
    await enqueue('d1', at: 10);
    await dao.setState('d1', DownloadState.running, now: 30);

    expect((await dao.nextQueued())?.id, 'd2');
  });

  test('nextQueued is null when nothing is waiting', () async {
    await enqueue('d1', at: 10);
    await dao.setState('d1', DownloadState.done, now: 20);

    expect(await dao.nextQueued(), isNull);
  });

  test(
    'progress accumulates and learns the total once headers arrive',
    () async {
      await enqueue('d1', at: 10);

      await dao.recordProgress('d1', bytesDone: 512, now: 20, totalBytes: 4096);
      await dao.recordProgress('d1', bytesDone: 1024, now: 30);

      final task = await dao.byId('d1');
      expect(task?.bytesDone, 1024);
      expect(
        task?.totalBytes,
        4096,
        reason: 'a later update must not erase it',
      );
      expect(task?.updatedAt, 30);
    },
  );

  test('failing a task records why, and retrying clears it', () async {
    await enqueue('d1', at: 10);

    await dao.setState(
      'd1',
      DownloadState.failed,
      error: 'connection closed',
      now: 20,
    );
    expect((await dao.byId('d1'))?.error, 'connection closed');

    await dao.setState('d1', DownloadState.queued, now: 30);
    final retried = await dao.byId('d1');
    expect(retried?.state, DownloadState.queued);
    expect(retried?.error, isNull);
  });

  test('a paused task keeps its offset so it can resume', () async {
    await enqueue('d1', at: 10);
    await dao.recordProgress('d1', bytesDone: 2048, now: 20, totalBytes: 4096);

    await dao.setState('d1', DownloadState.paused, now: 30);

    expect((await dao.byId('d1'))?.bytesDone, 2048);
  });

  test('the unfinished stream carries everything still in flight', () async {
    await enqueue('d1', at: 10);
    await enqueue('d2', at: 20);
    await enqueue('d3', at: 30);
    await enqueue('d4', at: 40);
    await dao.setState('d2', DownloadState.running, now: 50);
    await dao.setState('d3', DownloadState.paused, now: 50);
    await dao.setState('d4', DownloadState.done, now: 50);

    final unfinished = await dao.watchUnfinished().first;

    expect(unfinished.map((t) => t.id), ['d1', 'd2', 'd3']);
  });

  test('clearing finished tasks leaves the ones still working', () async {
    await enqueue('d1', at: 10);
    await enqueue('d2', at: 20);
    await dao.setState('d1', DownloadState.done, now: 30);

    expect(await dao.clearFinished(), 1);
    expect((await dao.all()).map((t) => t.id), ['d2']);
  });

  test('a task is findable by the track it is fetching', () async {
    await enqueue('d1', at: 10);

    expect((await dao.byTrack('track-d1'))?.id, 'd1');
    expect(await dao.byTrack('track-unknown'), isNull);
  });
}
