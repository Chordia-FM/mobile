import 'package:drift/drift.dart';

import '../database.dart';
import '../tables.dart';

part 'download_tasks_dao.g.dart';

/// The resumable download queue.
@DriftAccessor(tables: [DownloadTasks])
class DownloadTasksDao extends DatabaseAccessor<ChordiaDatabase>
    with _$DownloadTasksDaoMixin {
  DownloadTasksDao(super.db);

  /// The states a task can still make progress from, as the strings the column stores.
  static final _unfinished = [
    DownloadState.queued,
    DownloadState.running,
    DownloadState.paused,
  ].map((state) => state.name).toList(growable: false);

  Future<void> enqueue(DownloadTasksCompanion task) =>
      into(downloadTasks).insertOnConflictUpdate(task);

  Future<DownloadTask?> byId(String id) =>
      (select(downloadTasks)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<DownloadTask?> byTrack(String trackId) => (select(
    downloadTasks,
  )..where((t) => t.trackId.equals(trackId))).getSingleOrNull();

  /// The whole queue, oldest first — which is also the order it will be worked through.
  Future<List<DownloadTask>> all() => (select(
    downloadTasks,
  )..orderBy([(t) => OrderingTerm.asc(t.createdAt)])).get();

  Stream<List<DownloadTask>> watchAll() => (select(
    downloadTasks,
  )..orderBy([(t) => OrderingTerm.asc(t.createdAt)])).watch();

  /// Tasks that are queued, running or paused, for the "downloading" section.
  Stream<List<DownloadTask>> watchUnfinished() =>
      (select(downloadTasks)
            ..where((t) => t.state.isIn(_unfinished))
            ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
          .watch();

  /// The next task the worker should pick up, or null when the queue is idle.
  Future<DownloadTask?> nextQueued() =>
      (select(downloadTasks)
            ..where((t) => t.state.equalsValue(DownloadState.queued))
            ..orderBy([(t) => OrderingTerm.asc(t.createdAt)])
            ..limit(1))
          .getSingleOrNull();

  /// Records bytes landed on disk. [totalBytes] only once the response headers reveal it.
  Future<void> recordProgress(
    String id, {
    required int bytesDone,
    required int now,
    int? totalBytes,
  }) => (update(downloadTasks)..where((t) => t.id.equals(id))).write(
    DownloadTasksCompanion(
      bytesDone: Value(bytesDone),
      totalBytes: totalBytes == null ? const Value.absent() : Value(totalBytes),
      updatedAt: Value(now),
    ),
  );

  /// Moves a task to [state], attaching [error] when it failed and clearing it otherwise.
  ///
  /// Clearing on every non-failure is deliberate: a stale message left on a task that has since
  /// been retried shows the user a problem that no longer exists.
  Future<void> setState(
    String id,
    DownloadState state, {
    String? error,
    required int now,
  }) => (update(downloadTasks)..where((t) => t.id.equals(id))).write(
    DownloadTasksCompanion(
      state: Value(state),
      error: Value(state == DownloadState.failed ? error : null),
      updatedAt: Value(now),
    ),
  );

  Future<void> remove(String id) =>
      (delete(downloadTasks)..where((t) => t.id.equals(id))).go();

  /// Drops completed tasks; the [Downloads] rows they produced are what survives.
  Future<int> clearFinished() => (delete(
    downloadTasks,
  )..where((t) => t.state.equalsValue(DownloadState.done))).go();
}
