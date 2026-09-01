import 'dart:async';
import 'dart:io';

import 'package:chordia_api/chordia_api.dart';
import 'package:chordia_db/chordia_db.dart';
import 'package:chordia_mobile/data/downloads/download_http.dart';
import 'package:chordia_mobile/data/downloads/download_manager.dart';
import 'package:chordia_mobile/data/downloads/download_request.dart';
import 'package:chordia_mobile/data/downloads/download_storage.dart';
import 'package:chordia_mobile/data/downloads/download_store.dart';
import 'package:chordia_mobile/features/library/data/downloads_grouping.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ChordiaDatabase db;
  late Directory directory;
  late DownloadStore store;
  late _FakeLibrary library;

  setUp(() {
    db = ChordiaDatabase(NativeDatabase.memory());
    directory = Directory.systemTemp.createTempSync('chordia_downloads');
    store = DownloadStore(directory: Future.value(directory));
    library = _FakeLibrary();
  });

  tearDown(() async {
    await db.close();
    try {
      directory.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows refuses to delete a directory while a handle into it is still closing. The temp
      // directory is the OS's to reclaim, and failing teardown over it would hide the real result.
    }
  });

  DownloadManager managerFor({
    int maxConcurrent = 2,
    Future<int> Function()? capBytes,
    bool Function(String trackId)? isPlaying,
  }) => DownloadManager(
    tasks: db.downloadTasksDao,
    downloads: db.downloadsDao,
    store: store,
    fetch: library.fetch,
    maxConcurrent: maxConcurrent,
    capBytes: capBytes,
    isPlaying: isPlaying,
    // Every chunk reports, so bytes reach disk (and the queue row) at points a test can observe
    // rather than only after a real throttle window has passed.
    progressInterval: Duration.zero,
  );

  /// Pumps the event loop until [reached] holds.
  ///
  /// A download is several event-loop turns per chunk — a flush, a row write, a resumed
  /// subscription — so a fixed pump count is a race dressed up as a constant.
  Future<void> settleUntil(
    Future<bool> Function() reached, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    // A DEADLINE, not a round count. The round count was 200, and the comment below already
    // described why that is the wrong unit: progress here is real file I/O, so the budget is spent
    // in wall-clock time by a loaded machine rather than in iterations by a stuck queue. On
    // 2026-09-01 CI proved it, failing 'runs exactly two downloads at a time' on a runner that was
    // simply busy. A deadline gives a slow machine more rounds instead of failing it.
    //
    // This cannot mask the thing the tests are checking. Every caller waits for a state to be
    // REACHED and then asserts what is true once it is -- the concurrency test pumps 50 more times
    // after two bodies open and requires there to still be exactly two -- so waiting longer only
    // ever changes whether the check gets to run.
    final elapsed = Stopwatch()..start();
    var rounds = 0;
    while (true) {
      if (await reached()) return;
      if (elapsed.elapsed >= timeout) {
        fail(
          'the download queue never reached the state the test was waiting for '
          'after ${timeout.inSeconds}s and $rounds rounds',
        );
      }
      rounds++;
      await pumpEventQueue(times: 10);
      // Draining microtasks is not enough on its own: the queue writes real files, and that
      // progress happens off the Dart event loop. Without a moment of real time each round, a
      // machine busy running the rest of the suite makes no progress between checks.
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
  }

  Future<void> settleUntilSaved(int count) =>
      settleUntil(() async => await db.downloadsDao.count() == count);

  Future<void> settleUntilFailed(String trackId) => settleUntil(
    () async =>
        (await db.downloadTasksDao.byId(trackId))?.state ==
        DownloadState.failed,
  );

  /// Leaves the state a killed process would: some bytes on disk, and a manifest describing them.
  Future<void> leavePartial(
    DownloadRequest request, {
    required int bytes,
    required String etag,
  }) async {
    await store.writeManifest(
      DownloadManifest(request: request, etag: etag, contentType: 'audio/flac'),
    );
    final partial = await store.partial(request.trackId);
    await partial.writeAsBytes(
      library.bytesOf(request.trackRef).sublist(0, bytes),
    );
  }

  Future<List<int>> savedBytes(String trackId) async {
    final row = await db.downloadsDao.byTrack(trackId);
    return File(row!.filePath).readAsBytes();
  }

  group('resuming a partial download', () {
    test('an unchanged file is continued from where it stopped', () async {
      final request = _request();
      await leavePartial(request, bytes: 24, etag: library.etag);

      await managerFor().enqueue(request);
      await settleUntilSaved(1);

      // Two requests and no more: one asking whether the 24 bytes are still valid, one fetching
      // the rest. Both start at 24 — a resume that quietly re-fetched from zero would still
      // produce a correct file, which is why the offset is asserted and not only the bytes.
      expect(library.calls, [
        (from: 24, ifNoneMatch: library.etag),
        (from: 24, ifNoneMatch: null),
      ]);
      expect(library.bytesServed, 64 - 24);
      expect(await savedBytes('t1'), library.bytesOf('r1'));
    });

    test('a changed ETag throws the partial away and starts over', () async {
      final request = _request();
      // The bytes on disk came from a version the library no longer serves — the file was
      // re-encoded, retagged or replaced since.
      await leavePartial(request, bytes: 24, etag: '"stale"');

      await managerFor().enqueue(request);
      await settleUntilSaved(1);

      expect(library.calls, [
        (from: 24, ifNoneMatch: '"stale"'),
        (from: 0, ifNoneMatch: null),
      ]);
      // The whole file, fetched again. Stitching new bytes onto the old ones would have produced a
      // file of the right LENGTH built from two different encodings — which plays as a burst of
      // noise and looks like a corrupt download rather than a stale one.
      expect(await savedBytes('t1'), library.bytesOf('r1'));
      expect((await db.downloadsDao.byTrack('t1'))!.sizeBytes, 64);
    });

    test('a partial with no recorded validator is never stitched onto', () async {
      final request = _request();
      await store.writeManifest(DownloadManifest(request: request));
      await (await store.partial('t1')).writeAsBytes(const [1, 2, 3, 4]);

      await managerFor().enqueue(request);
      await settleUntilSaved(1);

      // Nothing to revalidate against, so the only safe move is to start again.
      expect(library.calls, [(from: 0, ifNoneMatch: null)]);
      expect(await savedBytes('t1'), library.bytesOf('r1'));
    });
  });

  group('the queue', () {
    test('runs exactly two downloads at a time', () async {
      library.hold = true;
      final manager = managerFor();
      for (var i = 1; i <= 4; i++) {
        await manager.enqueue(_request(trackId: 't$i', trackRef: 'r$i'));
      }
      await settleUntil(() async => library.openBodies == 2);
      // Nothing is waiting on a slot, so a queue that ran three at a time would have started the
      // third by now.
      await pumpEventQueue(times: 50);

      expect(library.calls, hasLength(2));
      expect(library.openBodies, 2);
      final states = [
        for (final task in await db.downloadTasksDao.all()) task.state,
      ];
      expect(
        states.where((s) => s == DownloadState.running),
        hasLength(2),
        reason: 'two in flight',
      );
      expect(
        states.where((s) => s == DownloadState.queued),
        hasLength(2),
        reason: 'two still waiting for a slot',
      );

      // Let each pair finish; the next pair starts as slots free.
      for (var round = 0; round < 4; round++) {
        await library.releaseAll();
        await pumpEventQueue(times: 30);
      }
      await settleUntilSaved(4);
      expect(library.calls, hasLength(4));
      expect(await db.downloadTasksDao.all(), isEmpty);
    });

    test('a cancel mid-flight leaves no half file behind', () async {
      library.hold = true;
      final manager = managerFor();
      await manager.enqueue(_request());
      // Bytes really are on disk before the cancel — otherwise this would pass on a download that
      // had not started.
      await settleUntil(() async => await store.bytesOnDisk('t1') > 0);

      await manager.cancel('t1');
      await pumpEventQueue(times: 30);

      expect((await store.partial('t1')).existsSync(), isFalse);
      expect(await store.readManifest('t1'), isNull);
      expect(await db.downloadTasksDao.byId('t1'), isNull);
      expect(await db.downloadsDao.byTrack('t1'), isNull);
      // Nothing at all under this track's name: a stray file no row points at is storage the user
      // is charged for and no screen can show them.
      expect(directory.listSync(), isEmpty);
    });

    test('a body that stops short is failed, not published', () async {
      library.truncateAfter = 32;
      await managerFor().enqueue(_request());
      await settleUntilFailed('t1');

      // A song that stops early is indistinguishable from a bad master and impossible for a user
      // to diagnose, so a short body never becomes a download row.
      expect(await db.downloadsDao.byTrack('t1'), isNull);
      expect(
        (await db.downloadTasksDao.byId('t1'))!.error,
        DownloadErrorCode.incomplete,
      );
      // The bytes are kept: a failure is the case resuming exists for.
      expect(await store.bytesOnDisk('t1'), 32);
    });
  });

  group('removing a download', () {
    test('deletes the file and the row together', () async {
      final manager = managerFor();
      await manager.enqueue(_request());
      await settleUntilSaved(1);
      final row = await db.downloadsDao.byTrack('t1');
      expect(File(row!.filePath).existsSync(), isTrue);

      expect(await manager.remove('t1'), isTrue);
      expect(File(row.filePath).existsSync(), isFalse);
      expect(await db.downloadsDao.byTrack('t1'), isNull);
    });

    test('refuses to delete the file that is playing', () async {
      final manager = managerFor(isPlaying: (trackId) => trackId == 't1');
      await manager.enqueue(_request());
      await settleUntilSaved(1);
      final row = await db.downloadsDao.byTrack('t1');

      expect(await manager.remove('t1'), isFalse);
      // Both halves survive. Deleting the row alone strands the bytes; deleting the file alone
      // breaks the song that is sounding — so the refusal has to cover both.
      expect(File(row!.filePath).existsSync(), isTrue);
      expect(await db.downloadsDao.byTrack('t1'), isNotNull);
    });

    test('clearing keeps whatever is playing and says how many', () async {
      final manager = managerFor(isPlaying: (trackId) => trackId == 't2');
      await manager.enqueue(_request(trackId: 't1', trackRef: 'r1'));
      await manager.enqueue(_request(trackId: 't2', trackRef: 'r2'));
      await settleUntilSaved(2);

      final result = await manager.clear();
      expect(result.removed, 1);
      expect(result.skipped, 1);
      expect(await db.downloadsDao.count(), 1);
      // One file left standing, and it is the one still being played.
      expect(directory.listSync(), hasLength(1));
    });
  });

  group('the storage cap', () {
    test('refuses a file that would not fit, leaving nothing behind', () async {
      // Room for less than one file. The refusal lands once the server has said how long the body
      // is, which is the earliest moment the answer is knowable.
      await managerFor(capBytes: () async => 32).enqueue(_request());
      await settleUntilFailed('t1');

      expect(
        (await db.downloadTasksDao.byId('t1'))!.error,
        DownloadErrorCode.cap,
      );
      expect(await db.downloadsDao.byTrack('t1'), isNull);
      expect(await store.bytesOnDisk('t1'), 0);
    });

    test('a full allowance turns a new request away up front', () async {
      var cap = 1 << 20;
      final manager = managerFor(capBytes: () async => cap);
      await manager.enqueue(_request(trackId: 't1', trackRef: 'r1'));
      await settleUntilSaved(1);

      cap = 8; // now smaller than what is already stored
      expect(
        await manager.enqueue(_request(trackId: 't2', trackRef: 'r2')),
        DownloadOutcome.overCap,
      );
      // Turned away before a byte is spent, rather than started and failed halfway.
      expect(library.calls, hasLength(1));
    });
  });

  group('what the storage row shows', () {
    test('totals and grouping come from the rows the pipeline wrote', () async {
      final manager = managerFor();
      await manager.enqueue(
        _request(trackId: 't1', trackRef: 'r1', trackNo: 2),
      );
      await manager.enqueue(
        _request(trackId: 't2', trackRef: 'r2', trackNo: 1),
      );
      await settleUntilSaved(2);

      final rows = await db.downloadsDao.all();
      final used = await db.downloadsDao.totalBytes();
      expect(used, 128);
      // The header sums the rows on screen and the DAO sums the table; the storage line would be a
      // lie the moment those two disagreed.
      expect(totalDownloadBytes(rows), used);

      expect(
        DownloadStorage(
          usedBytes: used,
          trackCount: rows.length,
          capBytes: used * 2,
        ).fraction,
        0.5,
      );
      expect(
        DownloadStorage(
          usedBytes: used,
          trackCount: rows.length,
          capBytes: used,
        ).isFull,
        isTrue,
      );
      // No cap is the shipped default, and it must never read as "full".
      expect(
        DownloadStorage(
          usedBytes: used,
          trackCount: rows.length,
          capBytes: 0,
        ).isFull,
        isFalse,
      );

      // The snapshot the pipeline saved is enough to group by, with no catalog and no network: one
      // album heading, its tracks in the album's own order rather than the order they landed.
      final groups = groupDownloads(rows);
      expect(groups, hasLength(1));
      expect(groups.single.album, 'Ten Songs');
      expect(groups.single.artist, 'A Band');
      expect(groups.single.coverSha, 'abc123');
      expect(
        [for (final row in groups.single.tracks) row.trackId],
        ['t2', 't1'],
      );
      expect(groups.single.sizeBytes, used);
    });

    test('a finished download is playable and pinned to its tier', () async {
      await managerFor().enqueue(_request());
      await settleUntilSaved(1);

      final row = await db.downloadsDao.byTrack('t1');
      // Recorded as the wire string, so playback resolves the local copy at exactly what was
      // fetched — never re-negotiated against whatever network the phone is on later.
      expect(row!.profile, QualityProfile.original.wire);
      // FLAC in, `.flac` out: the player infers the content type back from this extension, so an
      // extension that did not survive the round trip would make every download claim to be MP3.
      expect(row.filePath, endsWith('.flac'));
      expect(await File(row.filePath).readAsBytes(), library.bytesOf('r1'));
      // The queue row is gone; the download row is what survives.
      expect(await db.downloadTasksDao.all(), isEmpty);
    });
  });
}

DownloadRequest _request({
  String trackId = 't1',
  String trackRef = 'r1',
  int? trackNo,
}) => DownloadRequest(
  trackId: trackId,
  libraryId: 'lib',
  trackRef: trackRef,
  contentHash: 'hash-$trackRef',
  profile: QualityProfile.original,
  title: 'Song $trackRef',
  artist: 'A Band',
  durationMs: 200000,
  album: 'Ten Songs',
  albumId: 'al1',
  coverSha: 'abc123',
  trackNo: trackNo,
);

/// A library server's stream endpoint, in memory.
///
/// Stands in for the pinned HTTPS leg so the queue's behaviour — resuming, revalidating, running
/// two at a time, cleaning up after a cancel — can be asserted without a socket or a certificate.
class _FakeLibrary {
  /// The version of every file served. An `If-None-Match` matching this answers 304 and nothing
  /// else, exactly as the library does: HTTP evaluates the validator before the range.
  String etag = '"v1"';

  String contentType = 'audio/flac';

  int chunkSize = 16;

  /// Deliver the first chunk and then wait for [releaseAll], so a test can look at the queue while
  /// downloads are genuinely in flight.
  bool hold = false;

  /// Ends the body after this many bytes, as a connection cut partway does.
  int? truncateAfter;

  final calls = <({int from, String? ifNoneMatch})>[];

  /// Body bytes actually delivered, which is what tells a resume from a silent restart.
  int bytesServed = 0;

  final _held = <_HeldBody>[];

  /// Bodies that have started and not finished — the concurrency the queue is actually running.
  int get openBodies => _held.length;

  /// 64 bytes per track, distinct per [trackRef] so a file written under the wrong name shows up.
  List<int> bytesOf(String trackRef) =>
      List<int>.generate(64, (i) => (i + trackRef.codeUnitAt(1)) % 256);

  DownloadFetch get fetch =>
      (request, {int from = 0, String? ifNoneMatch}) async {
        calls.add((from: from, ifNoneMatch: ifNoneMatch));
        final file = bytesOf(request.trackRef);

        if (ifNoneMatch != null && ifNoneMatch == etag) {
          return _response(HttpStatus.notModified, const Stream.empty(), null);
        }
        if (from > file.length) {
          return _response(
            HttpStatus.requestedRangeNotSatisfiable,
            const Stream.empty(),
            file.length,
          );
        }

        var body = file.sublist(from);
        final cut = truncateAfter;
        if (cut != null && cut < body.length) body = body.sublist(0, cut);

        final chunks = <List<int>>[
          for (var i = 0; i < body.length; i += chunkSize)
            body.sublist(
              i,
              i + chunkSize > body.length ? body.length : i + chunkSize,
            ),
        ];
        final controller = StreamController<List<int>>();
        final held = _HeldBody(controller, chunks.skip(hold ? 1 : 0).toList());
        for (final chunk in chunks.take(hold ? 1 : chunks.length)) {
          controller.add(chunk);
          bytesServed += chunk.length;
        }
        if (hold) {
          _held.add(held);
        } else {
          unawaited(controller.close());
        }

        return _response(
          from > 0 ? HttpStatus.partialContent : HttpStatus.ok,
          controller.stream,
          file.length,
          onRelease: () {
            _held.remove(held);
            if (!controller.isClosed) unawaited(controller.close());
          },
        );
      };

  /// Finishes every held body.
  Future<void> releaseAll() async {
    final bodies = List<_HeldBody>.of(_held);
    _held.clear();
    for (final body in bodies) {
      for (final chunk in body.rest) {
        if (body.controller.isClosed) break;
        body.controller.add(chunk);
        bytesServed += chunk.length;
      }
      if (!body.controller.isClosed) await body.controller.close();
    }
  }

  DownloadResponse _response(
    int status,
    Stream<List<int>> stream,
    int? totalBytes, {
    void Function()? onRelease,
  }) => DownloadResponse(
    status: status,
    stream: stream,
    totalBytes: totalBytes,
    etag: etag,
    contentType: contentType,
    release: () async => onRelease?.call(),
  );
}

class _HeldBody {
  _HeldBody(this.controller, this.rest);

  final StreamController<List<int>> controller;
  final List<List<int>> rest;
}
