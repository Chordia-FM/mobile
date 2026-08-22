import 'package:chordia_db/chordia_db.dart';
import 'package:test/test.dart';

import 'support/in_memory.dart';

void main() {
  late ChordiaDatabase db;
  late ScrobbleQueueDao dao;

  setUp(() {
    db = openTestDatabase();
    dao = db.scrobbleQueueDao;
  });

  tearDown(() => db.close());

  Future<void> enqueue(String id, {required int at}) => dao.enqueue(
    eventId: id,
    payloadJson: '{"event_id":"$id"}',
    createdAt: at,
  );

  test('enqueue, batch and delete round-trip', () async {
    await enqueue('e1', at: 100);
    await enqueue('e2', at: 200);
    expect(await dao.count(), 2);

    final batch = await dao.takeBatch();
    expect(batch.map((e) => e.eventId), ['e1', 'e2']);
    expect(batch.first.payloadJson, '{"event_id":"e1"}');

    expect(await dao.deleteByIds(batch.map((e) => e.eventId).toList()), 2);
    expect(await dao.count(), 0);
    expect(await dao.takeBatch(), isEmpty);
  });

  test(
    'taking a batch leaves the events queued until they are acknowledged',
    () async {
      await enqueue('e1', at: 100);

      await dao.takeBatch();

      expect(await dao.count(), 1, reason: 'delivery must be at-least-once');
    },
  );

  test('a batch is the oldest events, bounded by the limit', () async {
    for (var i = 0; i < 5; i++) {
      await enqueue('e$i', at: i);
    }

    final batch = await dao.takeBatch(limit: 3);

    expect(batch.map((e) => e.eventId), ['e0', 'e1', 'e2']);
  });

  test('events sharing a millisecond come back in a stable order', () async {
    await enqueue('e3', at: 100);
    await enqueue('e1', at: 100);
    await enqueue('e2', at: 100);

    expect((await dao.takeBatch()).map((e) => e.eventId), ['e1', 'e2', 'e3']);
  });

  test('re-enqueuing the same event id is a no-op', () async {
    await enqueue('e1', at: 100);
    await dao.enqueue(
      eventId: 'e1',
      payloadJson: '{"ms_played":9999}',
      createdAt: 500,
    );

    expect(await dao.count(), 1);
    final only = (await dao.takeBatch()).single;
    expect(only.payloadJson, '{"event_id":"e1"}');
    expect(only.createdAt, 100);
  });

  test('deleting an empty list touches nothing', () async {
    await enqueue('e1', at: 100);

    expect(await dao.deleteByIds([]), 0);
    expect(await dao.count(), 1);
  });

  test('prune drops the oldest events beyond the cap', () async {
    for (var i = 0; i < 5; i++) {
      await enqueue('e$i', at: i);
    }

    expect(await dao.prune(cap: 2), 3);
    expect((await dao.takeBatch()).map((e) => e.eventId), ['e3', 'e4']);
  });

  test('prune leaves a queue under the cap alone', () async {
    await enqueue('e1', at: 1);
    await enqueue('e2', at: 2);

    expect(await dao.prune(cap: 10), 0);
    expect(await dao.count(), 2);
  });

  test('prune keeps the queue at the cap however often it runs', () async {
    for (var i = 0; i < 12; i++) {
      await enqueue('e${i.toString().padLeft(2, '0')}', at: i);
      await dao.prune(cap: 5);
    }

    expect(await dao.count(), 5);
    expect((await dao.takeBatch()).map((e) => e.eventId), [
      'e07',
      'e08',
      'e09',
      'e10',
      'e11',
    ]);
  });
}
