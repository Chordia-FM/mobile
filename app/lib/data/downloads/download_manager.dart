import 'dart:async';
import 'dart:io';

import 'package:chordia_api/chordia_api.dart';
import 'package:chordia_db/chordia_db.dart';
import 'package:flutter/foundation.dart';

import 'download_foreground_service.dart';
import 'download_http.dart';
import 'download_request.dart';
import 'download_store.dart';

/// What [DownloadManager.enqueue] did with a request.
enum DownloadOutcome {
  queued,

  /// The bytes are already on this device. Nothing was fetched and nothing was queued.
  alreadyDownloaded,

  /// A task for this track was already in the queue.
  alreadyQueued,

  /// Downloads already fill the storage the user allowed. Refused up front rather than started
  /// and failed halfway, which would burn their data to reach the same answer.
  overCap,
}

/// The result of queuing a collection — an album, a playlist, a selection.
@immutable
class DownloadBatch {
  const DownloadBatch({
    required this.queued,
    required this.existing,
    required this.refused,
  });

  final int queued;

  /// Already downloaded or already queued: nothing to do, and not a failure to report.
  final int existing;

  /// Turned away by the storage cap.
  final int refused;

  int get total => queued + existing + refused;
}

/// What [DownloadManager.clear] managed to remove.
@immutable
class DownloadClearResult {
  const DownloadClearResult({required this.removed, required this.skipped});

  final int removed;

  /// Left in place because they were sounding. Deleting the file a player has open breaks
  /// playback mid-song (and on Windows simply fails), so the user is told rather than surprised.
  final int skipped;
}

/// Why a task stopped, as a stable code rather than a sentence.
///
/// Stored in `DownloadTasks.error` and localised at render time. A message written into the
/// database is frozen in whatever language the app was showing when it failed, and a queue that
/// survives a week offline outlives that choice.
abstract final class DownloadErrorCode {
  /// The library server could not be reached — no signal, asleep, or moved.
  static const offline = 'offline';

  /// The server answered, refusing. Suffixed with the status: `server:404`.
  static const server = 'server';

  /// The body ended before the length the server promised. Never published as a finished track:
  /// a truncated file plays as a song that stops early, which is indistinguishable from a bad
  /// master and impossible for a user to diagnose.
  static const incomplete = 'incomplete';

  /// Downloads would exceed the storage the user allowed.
  static const cap = 'cap';

  /// The device's own storage refused the write.
  static const storage = 'storage';

  static const unknown = 'unknown';

  /// Whether retrying this on the next launch is worth doing unasked.
  ///
  /// A cap failure is not transient — the storage situation is unchanged and retrying would fail
  /// identically — and a 4xx means the server has an opinion that will not change by itself.
  static bool isTransient(String? code) {
    if (code == null) return false;
    if (code == offline || code == incomplete || code == storage) return true;
    final status = int.tryParse(code.split(':').last);
    return code.startsWith('$server:') && status != null && status >= 500;
  }
}

/// Chordia's own download queue: durable, resumable, and pinned.
///
/// **Why not a platform download manager.** `background_downloader` and its peers hand the request
/// to the OS, whose HTTP stack does TLS where no Dart certificate callback can reach. Library
/// servers are pinned to the fingerprint the Hub directory advertises — that pin is the entire
/// reason self-signed libraries are safe to stream from — so an OS-managed download of library
/// audio would either fail on a self-signed certificate or, worse, succeed unpinned. One code path
/// that is always pinned beats OS-managed backgrounding of a path that quietly is not.
///
/// **What replaces OS backgrounding.** Two things. A foreground service of type
/// `FOREGROUND_SERVICE_DATA_SYNC` keeps a screen-off batch running, and the queue is a table on
/// disk where every task carries the byte offset it reached. Nothing depends on the first: a killed
/// process, a denied notification permission or a platform with no such service all land in the
/// same place, which is that [start] picks the batch back up on next launch.
///
/// WIRING (Android, one native class): the foreground service is driven over the method channel
/// `fm.chordia.mobile/downloads` with `start {done, total}` and `stop`. It needs a `Service` with
/// `android:foregroundServiceType="dataSync"` declared in the manifest — the permission is already
/// there. Until that exists the calls no-op and downloads simply stop when Android suspends the
/// process, which the durable queue then resumes.
class DownloadManager {
  DownloadManager({
    required DownloadTasksDao tasks,
    required DownloadsDao downloads,
    required DownloadStore store,
    required DownloadFetch fetch,
    DownloadForegroundService foreground = const NoDownloadForegroundService(),
    Future<int> Function()? capBytes,
    bool Function(String trackId)? isPlaying,
    this.maxConcurrent = 2,
    @visibleForTesting int Function()? clock,
    @visibleForTesting
    this.progressInterval = const Duration(milliseconds: 500),
  }) : _tasks = tasks,
       _downloads = downloads,
       _store = store,
       _fetch = fetch,
       _foreground = foreground,
       _capBytes = capBytes ?? (() async => 0),
       _isPlaying = isPlaying ?? ((_) => false),
       _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch);

  final DownloadTasksDao _tasks;
  final DownloadsDao _downloads;
  final DownloadStore _store;
  final DownloadFetch _fetch;
  final DownloadForegroundService _foreground;
  final Future<int> Function() _capBytes;
  final bool Function(String trackId) _isPlaying;
  final int Function() _clock;

  /// Two at a time. One leaves a phone's radio idle between chunks on a slow link; four does not
  /// finish the first song any sooner and makes every one of them contend for the same pipe.
  final int maxConcurrent;

  /// How often bytes-on-disk is written back to the queue row. The write is what the progress bar
  /// reads, so it is a UI cadence, not a durability one — the file itself is the durable part.
  final Duration progressInterval;

  final _active = <String, Future<void>>{};
  final _cancelled = <String>{};
  final _paused = <String>{};

  /// How to interrupt a task that is mid-body, keyed by track id.
  ///
  /// Without this, a cancel would only take effect at the next chunk boundary — and a download
  /// stalled on a server that has stopped sending has no next chunk. The user would tap Cancel and
  /// watch the row sit there until the socket timed out.
  final _aborts = <String, void Function(Object reason)>{};
  bool _pumping = false;
  int _batchDone = 0;

  /// Completed to interrupt the pump's wait when new work is queued. See [_pump].
  Completer<void>? _waiting;

  /// Everything still to do, oldest first — what the queue section of the UI draws.
  Stream<List<DownloadTask>> watchQueue() => _tasks.watchUnfinished();

  /// Adopts whatever the last run left behind, then works the queue.
  ///
  /// Tasks marked `running` belong to a process that no longer exists, so nothing is going to
  /// finish them; they go back in the queue. Transient failures are retried unasked, because
  /// "your signal came back" is exactly the condition the user would tap Retry for.
  Future<void> start() async {
    for (final task in await _tasks.all()) {
      final resumable =
          task.state == DownloadState.running ||
          (task.state == DownloadState.failed &&
              DownloadErrorCode.isTransient(task.error));
      if (resumable) {
        await _tasks.setState(task.id, DownloadState.queued, now: _clock());
      }
    }
    unawaited(_pump());
  }

  /// Queues one track. Safe to call twice — the second call reports what the first did.
  Future<DownloadOutcome> enqueue(DownloadRequest request) async {
    final outcome = await _enqueue(request);
    if (outcome == DownloadOutcome.queued) unawaited(_pump());
    return outcome;
  }

  /// Queues a whole album, playlist or selection.
  ///
  /// The cap is re-checked per track rather than once for the batch, so a queue that fills the
  /// allowance stops there instead of accepting everything and failing the tail.
  Future<DownloadBatch> enqueueAll(Iterable<DownloadRequest> requests) async {
    var queued = 0;
    var existing = 0;
    var refused = 0;
    for (final request in requests) {
      switch (await _enqueue(request)) {
        case DownloadOutcome.queued:
          queued++;
        case DownloadOutcome.alreadyDownloaded:
        case DownloadOutcome.alreadyQueued:
          existing++;
        case DownloadOutcome.overCap:
          refused++;
      }
    }
    if (queued > 0) unawaited(_pump());
    return DownloadBatch(queued: queued, existing: existing, refused: refused);
  }

  Future<DownloadOutcome> _enqueue(DownloadRequest request) async {
    final id = request.trackId;
    if (await _downloads.byTrack(id) != null) {
      return DownloadOutcome.alreadyDownloaded;
    }
    final task = await _tasks.byId(id);
    if (task != null && task.state != DownloadState.failed) {
      return DownloadOutcome.alreadyQueued;
    }
    if (!await _fits(0)) return DownloadOutcome.overCap;

    // A retry of the same track at the same tier keeps its manifest, and with it the ETag that
    // makes the partial bytes resumable. A different tier is a different encoding, so its bytes
    // cannot be appended to and are thrown away with the manifest that described them.
    final held = await _store.readManifest(id);
    final resumable =
        held != null &&
        held.request.profile == request.profile &&
        held.request.trackRef == request.trackRef;
    if (!resumable) {
      await _store.discardPartial(id);
      await _store.writeManifest(DownloadManifest(request: request));
    }

    final now = _clock();
    _cancelled.remove(id);
    _paused.remove(id);
    await _tasks.enqueue(
      // The task id IS the track id: one track means one file, so a second task for the same track
      // is never something to run alongside the first — it is the same request arriving twice, and
      // a primary-key conflict is the cheapest way to say so.
      DownloadTasksCompanion.insert(
        id: id,
        trackId: id,
        state: DownloadState.queued,
        bytesDone: Value(resumable ? await _store.bytesOnDisk(id) : 0),
        createdAt: now,
        updatedAt: now,
      ),
    );
    return DownloadOutcome.queued;
  }

  /// Stops a download and keeps its bytes, so resuming costs only what is left.
  Future<void> pause(String trackId) async {
    _paused.add(trackId);
    final running = _active[trackId];
    if (running != null) {
      _aborts[trackId]?.call(const _Paused());
      await running;
      return;
    }
    await _tasks.setState(trackId, DownloadState.paused, now: _clock());
  }

  Future<void> resume(String trackId) async {
    _paused.remove(trackId);
    await _tasks.setState(trackId, DownloadState.queued, now: _clock());
    unawaited(_pump());
  }

  /// Puts a failed task back in the queue.
  Future<void> retry(String trackId) => resume(trackId);

  /// Abandons a download entirely: the queue row and every byte fetched so far.
  ///
  /// Leaves nothing half-written on disk. A `.part` file with no task pointing at it would be
  /// storage the user is charged for and no screen can show them.
  Future<void> cancel(String trackId) async {
    _cancelled.add(trackId);
    final running = _active[trackId];
    if (running != null) {
      // Interrupts the body immediately; the task cleans up on its way out.
      _aborts[trackId]?.call(const _Cancelled());
      await running;
      return;
    }
    await _forget(trackId);
  }

  /// Deletes a finished download — the file and the row, in that order.
  ///
  /// Returns false when the track is playing. The row is the only index of the file, so removing
  /// one without the other either strands bytes on disk or points the player at nothing; and
  /// deleting a file an engine has open breaks the song that is sounding. Refusing and saying so
  /// is the only honest answer.
  Future<bool> remove(String trackId) async {
    final row = await _downloads.byTrack(trackId);
    if (row == null) {
      await cancel(trackId);
      return true;
    }
    if (_isPlaying(trackId)) return false;
    await _store.deleteFile(row.filePath);
    await _downloads.remove(trackId);
    return true;
  }

  /// Empties the queue and removes every download this device holds.
  Future<DownloadClearResult> clear() async {
    for (final task in await _tasks.all()) {
      await cancel(task.trackId);
    }
    var removed = 0;
    var skipped = 0;
    for (final row in await _downloads.all()) {
      if (await remove(row.trackId)) {
        removed++;
      } else {
        skipped++;
      }
    }
    return DownloadClearResult(removed: removed, skipped: skipped);
  }

  // ── the worker ──────────────────────────────────────────────────────────────────────────────

  /// Works the queue until it drains.
  ///
  /// Re-entrant calls do not start a second worker — they nudge the running one. That nudge is
  /// load-bearing: while a slot is free the pump is parked waiting for one of its downloads to
  /// finish, and without a way to interrupt that wait, tracks queued after the batch began would
  /// sit untouched until something already running happened to complete.
  Future<void> _pump() async {
    if (_pumping) {
      _nudge();
      return;
    }
    _pumping = true;
    try {
      while (true) {
        await _fill();
        if (_active.isEmpty) break;
        final queued = Completer<void>();
        _waiting = queued;
        // Wakes on whichever comes first: a slot freeing, or new work arriving. Waiting on the
        // whole batch instead would hold a worker idle for the difference between a 60 MB FLAC and
        // the 3 MB single beside it.
        await Future.any([..._active.values, queued.future]);
        _waiting = null;
      }
      await _tasks.clearFinished();
    } finally {
      _pumping = false;
      _batchDone = 0;
      await _foreground.stop();
    }
  }

  void _nudge() {
    final waiting = _waiting;
    _waiting = null;
    if (waiting != null && !waiting.isCompleted) waiting.complete();
  }

  Future<void> _fill() async {
    while (_active.length < maxConcurrent) {
      final next = await _tasks.nextQueued();
      if (next == null) break;
      // Claimed — and the write is awaited — before the next read, so one row can never be handed
      // to two workers.
      await _tasks.setState(next.id, DownloadState.running, now: _clock());
      final id = next.trackId;
      // A block body, not an arrow: `whenComplete` awaits a Future its callback returns, and
      // `Map.remove` returns the very future being awaited.
      _active[id] = _runTask(next).whenComplete(() {
        _active.remove(id);
      });
    }
    await _publishProgress();
  }

  Future<void> _runTask(DownloadTask task) async {
    final id = task.trackId;
    try {
      if (_cancelled.contains(id)) throw const _Cancelled();
      if (_paused.contains(id)) throw const _Paused();
      final manifest = await _store.readManifest(id);
      if (manifest == null) {
        // The description of what these bytes are is gone (an OS storage sweep, a restore without
        // media). There is nothing left to resume towards, so the task goes rather than sitting
        // in the queue failing forever.
        await _forget(id);
        return;
      }
      await _download(manifest);
    } on _Cancelled {
      await _forget(id);
    } on _Paused {
      _paused.add(id);
      await _tasks.setState(id, DownloadState.paused, now: _clock());
    } on Object catch (error) {
      // The partial is kept: a failure is the case resuming exists for.
      await _tasks.setState(
        id,
        DownloadState.failed,
        error: _codeFor(error),
        now: _clock(),
      );
    } finally {
      _batchDone++;
    }
  }

  Future<void> _download(DownloadManifest manifest) async {
    final request = manifest.request;
    final id = request.trackId;
    var held = manifest;
    var from = await _store.bytesOnDisk(id);

    if (from > 0) from = await _revalidate(held, from);

    var response = await _fetch(request, from: from);
    if (response.status == HttpStatus.requestedRangeNotSatisfiable &&
        from > 0) {
      // The file upstream is now shorter than what we hold. Same conclusion as a changed ETag:
      // these bytes are not part of the file being fetched.
      await response.release();
      await _store.discardPartial(id);
      from = 0;
      response = await _fetch(request, from: 0);
    }

    try {
      if (response.status != HttpStatus.ok &&
          response.status != HttpStatus.partialContent) {
        throw ApiException(
          status: response.status,
          title: 'The library refused the download.',
          method: 'GET',
          path: '/v1/stream/${request.trackRef}',
        );
      }
      // A 200 in reply to a Range request means the server sent the whole file regardless; the
      // bytes we hold are about to be sent again, so they are not a prefix of anything.
      if (response.status == HttpStatus.ok && from > 0) {
        await _store.discardPartial(id);
        from = 0;
      }

      if (response.etag != held.etag ||
          response.contentType != held.contentType) {
        held = held.copyWith(
          etag: response.etag,
          contentType: response.contentType,
        );
        await _store.writeManifest(held);
      }

      final total = response.totalBytes;
      // The whole file, not the bytes still to come: a partial is not counted against the
      // allowance while it is arriving, so a resume must still ask whether the finished file fits.
      if (total != null && !await _fits(total)) {
        await _store.discardPartial(id);
        throw const _CapExceeded();
      }

      // A cancel that landed while the request was in flight has no subscription to interrupt yet.
      if (_cancelled.contains(id)) throw const _Cancelled();
      if (_paused.contains(id)) throw const _Paused();

      final written = await _drain(response, id, from: from, total: total);

      // Never publish a short file. Without this check a connection cut at 90% becomes a song that
      // stops early and looks like a bad master rather than a failed download.
      if (total != null && written != total) throw const _Incomplete();

      final now = _clock();
      await _tasks.recordProgress(
        id,
        bytesDone: written,
        totalBytes: total ?? written,
        now: now,
      );
      final published = await _store.publish(
        id,
        extension: extensionForContentType(held.contentType),
      );
      await _downloads.save(
        request.toRow(
          filePath: published.path,
          sizeBytes: written,
          savedAt: now,
        ),
      );
      await _tasks.setState(id, DownloadState.done, now: now);
    } finally {
      await response.release();
    }
  }

  /// Confirms that the bytes already on disk still belong to the file upstream.
  ///
  /// Sent as `If-None-Match`, which HTTP evaluates *before* `Range` — so a match answers `304` and
  /// nothing else, and a miss answers with the current file. That ordering is what makes one
  /// request able to say "your partial is stale" instead of silently handing back a range of a
  /// different encoding to be appended onto the old one. Returns the offset to resume from: the
  /// bytes held, or zero when they were discarded.
  Future<int> _revalidate(DownloadManifest manifest, int bytesHeld) async {
    final etag = manifest.etag;
    if (etag == null) {
      // Nothing to check against. Bytes we cannot vouch for are never stitched onto.
      await _store.discardPartial(manifest.request.trackId);
      return 0;
    }
    final probe = await _fetch(
      manifest.request,
      from: bytesHeld,
      ifNoneMatch: etag,
    );
    await probe.release();
    if (probe.status == HttpStatus.notModified) return bytesHeld;
    await _store.discardPartial(manifest.request.trackId);
    return 0;
  }

  /// Writes the body to the partial file, returning the total bytes it now holds.
  Future<int> _drain(
    DownloadResponse response,
    String id, {
    required int from,
    required int? total,
  }) async {
    final file = await _store.partial(id);
    final sink = file.openWrite(
      mode: from == 0 ? FileMode.write : FileMode.append,
    );
    var written = from;
    var lastReport = _clock();
    final finished = Completer<void>();
    late final StreamSubscription<List<int>> subscription;

    void stop(Object reason) {
      if (finished.isCompleted) return;
      finished.completeError(reason);
      unawaited(subscription.cancel());
    }

    subscription = response.stream.listen(
      (chunk) {
        sink.add(chunk);
        written += chunk.length;
        final now = _clock();
        if (now - lastReport < progressInterval.inMilliseconds) return;
        lastReport = now;
        // Paused for the duration of the write-back, which is also the backpressure: without it a
        // fast link would buffer the whole file in memory while the disk caught up.
        //
        // The file is flushed before the row is written, so a process killed a moment later finds
        // a file at least as long as the offset the queue claims. The reverse — a row ahead of the
        // file — would resume from a gap and produce a track with a hole in it.
        subscription.pause(
          sink.flush().then(
            (_) => _tasks.recordProgress(
              id,
              bytesDone: written,
              totalBytes: total,
              now: now,
            ),
          ),
        );
      },
      onError: stop,
      onDone: () {
        if (!finished.isCompleted) finished.complete();
      },
      cancelOnError: true,
    );
    _aborts[id] = stop;

    try {
      await finished.future;
      await sink.flush();
    } finally {
      _aborts.remove(id);
      try {
        await sink.close();
      } on Object {
        // The stream is already being unwound by a cancellation or a socket error; a close that
        // fails on top of it has nothing left to report that the original does not say better.
      }
    }
    return written;
  }

  /// Drops a task and everything it wrote.
  Future<void> _forget(String trackId) async {
    _cancelled.remove(trackId);
    _paused.remove(trackId);
    await _tasks.remove(trackId);
    await _store.discard(trackId);
  }

  /// Whether [extra] more bytes fit inside the storage the user allowed. A cap of zero or less is
  /// "no limit", which is what the default is until somebody sets one.
  Future<bool> _fits(int extra) async {
    final cap = await _capBytes();
    if (cap <= 0) return true;
    return await _downloads.totalBytes() + extra <= cap;
  }

  Future<void> _publishProgress() async {
    final remaining = (await _tasks.all())
        .where(
          (task) =>
              task.state == DownloadState.queued ||
              task.state == DownloadState.running ||
              task.state == DownloadState.paused,
        )
        .length;
    if (remaining == 0) return;
    await _foreground.update(done: _batchDone, total: _batchDone + remaining);
  }

  static String _codeFor(Object error) => switch (error) {
    _CapExceeded() => DownloadErrorCode.cap,
    _Incomplete() => DownloadErrorCode.incomplete,
    ApiException(status: 0) => DownloadErrorCode.offline,
    ApiException(:final status) => '${DownloadErrorCode.server}:$status',
    FileSystemException() => DownloadErrorCode.storage,
    _ => DownloadErrorCode.unknown,
  };
}

/// Thrown out of the byte loop when the user abandoned this download.
class _Cancelled implements Exception {
  const _Cancelled();
}

/// Thrown out of the byte loop when the user paused; the bytes stay.
class _Paused implements Exception {
  const _Paused();
}

class _CapExceeded implements Exception {
  const _CapExceeded();
}

class _Incomplete implements Exception {
  const _Incomplete();
}
