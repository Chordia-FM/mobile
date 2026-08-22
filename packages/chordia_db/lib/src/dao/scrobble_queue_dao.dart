import 'package:drift/drift.dart';

import '../database.dart';
import '../tables.dart';

part 'scrobble_queue_dao.g.dart';

/// The durable listening-event queue.
///
/// Everything here is ordered by `createdAt` and then `eventId`. The tiebreak matters: several
/// events can share a millisecond, and both the drain and the prune must agree on which of them is
/// older or a batch can be taken that the prune has just deleted underneath it.
@DriftAccessor(tables: [ScrobbleQueue])
class ScrobbleQueueDao extends DatabaseAccessor<ChordiaDatabase>
    with _$ScrobbleQueueDaoMixin {
  ScrobbleQueueDao(super.db);

  /// How many events a device may hold before the oldest are dropped.
  ///
  /// A phone that never regains network would otherwise grow a row per play forever. At roughly
  /// 300 bytes an event this caps the queue near 3 MB, which is months of listening — long enough
  /// that hitting it means the events were never going to be delivered.
  static const maxQueuedEvents = 10000;

  /// Queues an event. Re-enqueuing the same [eventId] is a no-op, since it is the idempotency key.
  Future<void> enqueue({
    required String eventId,
    required String payloadJson,
    required int createdAt,
  }) => into(scrobbleQueue).insert(
    ScrobbleQueueCompanion.insert(
      eventId: eventId,
      payloadJson: payloadJson,
      createdAt: createdAt,
    ),
    mode: InsertMode.insertOrIgnore,
  );

  /// The oldest [limit] events, for one `POST /v1/scrobbles:batch`.
  ///
  /// Reading rather than removing them is what makes delivery at-least-once: a request that fails
  /// after the server accepted it leaves the events queued, and the Hub dedupes the retry on
  /// `event_id`. Losing a play is unrecoverable; sending one twice is not.
  Future<List<QueuedScrobble>> takeBatch({int limit = 100}) =>
      (select(scrobbleQueue)
            ..orderBy([
              (e) => OrderingTerm.asc(e.createdAt),
              (e) => OrderingTerm.asc(e.eventId),
            ])
            ..limit(limit))
          .get();

  /// Removes events the Hub has acknowledged.
  Future<int> deleteByIds(List<String> eventIds) {
    if (eventIds.isEmpty) return Future.value(0);
    return (delete(scrobbleQueue)..where((e) => e.eventId.isIn(eventIds))).go();
  }

  Future<int> count() async {
    final total = scrobbleQueue.eventId.count();
    final query = selectOnly(scrobbleQueue)..addColumns([total]);
    return (await query.getSingle()).read(total) ?? 0;
  }

  /// Drops the oldest events beyond [cap], returning how many were discarded.
  ///
  /// Oldest first because the recent listening is what Wrapped and the history screen are about,
  /// and because the events most likely to be rejected as ancient are the ones at the front.
  Future<int> prune({int cap = maxQueuedEvents}) => transaction(() async {
    final excess = await count() - cap;
    if (excess <= 0) return 0;

    final doomed =
        await (select(scrobbleQueue)
              ..orderBy([
                (e) => OrderingTerm.asc(e.createdAt),
                (e) => OrderingTerm.asc(e.eventId),
              ])
              ..limit(excess))
            .map((event) => event.eventId)
            .get();
    return deleteByIds(doomed);
  });

  Future<void> clear() => delete(scrobbleQueue).go();
}
