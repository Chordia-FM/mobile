import 'dart:async';

import 'package:chordia_api/chordia_api.dart';
import 'package:chordia_db/chordia_db.dart';
import 'package:chordia_mobile/features/library/data/downloads_grouping.dart';
import 'package:chordia_mobile/features/library/data/formatting.dart';
import 'package:chordia_mobile/features/library/data/liked_controller.dart';
import 'package:chordia_mobile/features/library/data/library_api.dart';
import 'package:chordia_mobile/features/library/data/playlist_detail_controller.dart';
import 'package:chordia_mobile/features/library/data/reorder.dart';
import 'package:chordia_mobile/features/library/data/rules_summary.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('reorder arithmetic', () {
    test('a move lands the track exactly where the finger let go', () {
      expect(moveItem(['a', 'b', 'c', 'd'], 0, 2), ['b', 'c', 'a', 'd']);
      expect(moveItem(['a', 'b', 'c', 'd'], 3, 1), ['a', 'd', 'b', 'c']);
    });

    test('an impossible move changes nothing', () {
      // A drag that ends where it started, and an index off the end, both reach this. Throwing
      // would take down a gesture handler that has nothing useful to do with the exception.
      expect(moveItem(['a', 'b'], 1, 1), ['a', 'b']);
      expect(moveItem(['a', 'b'], 0, 5), ['a', 'b']);
      expect(moveItem(['a', 'b'], -1, 0), ['a', 'b']);
    });
  });

  group('optimistic playlist reorder', () {
    test('the new order shows before the server has answered', () async {
      final api = _FakePlaylistApi(_playlist(['t1', 't2', 't3']));
      final controller = _controllerFor(api);
      await controller.load();

      // The server call is held open, so what the list shows here is purely the optimistic apply.
      api.blockReorder = true;
      final pending = controller.moveTrack(0, 2);
      expect(_ids(controller), ['t2', 't3', 't1']);

      api.completeReorder();
      expect(await pending, isTrue);
      expect(_ids(controller), ['t2', 't3', 't1']);
      // The whole running order goes up, not a move: the Hub permutes the ids it is sent into the
      // positions they already occupy.
      expect(api.sentOrder, ['t2', 't3', 't1']);
    });

    test('a refused reorder puts the old order back and reports it', () async {
      final api = _FakePlaylistApi(_playlist(['t1', 't2', 't3']))
        ..failReorder = true;
      final failures = <Object>[];
      final controller = _controllerFor(api, onFailure: failures.add);
      await controller.load();

      expect(await controller.moveTrack(2, 0), isFalse);
      // Not merely "some order": the exact order from before the drag. A revert that restored a
      // stale snapshot would be just as wrong as no revert at all.
      expect(_ids(controller), ['t1', 't2', 't3']);
      expect(failures, hasLength(1));
    });

    test('a removed track takes its runtime and the count with it', () async {
      final api = _FakePlaylistApi(_playlist(['t1', 't2', 't3']));
      final controller = _controllerFor(api);
      await controller.load();
      final removed = controller.detail!.tracks[1];

      expect(await controller.removeTrack(removed), isTrue);
      expect(_ids(controller), ['t1', 't3']);
      // The header must never contradict the rows it sits above, so the count and the runtime
      // move on the optimistic apply rather than waiting for a refetch.
      expect(controller.detail!.trackCount, 2);
      expect(controller.detail!.totalDurationMs, 400000);
    });

    test(
      'a refused removal puts the row, the count and the runtime back',
      () async {
        final api = _FakePlaylistApi(_playlist(['t1', 't2', 't3']))
          ..failRemove = true;
        final controller = _controllerFor(api);
        await controller.load();

        expect(
          await controller.removeTrack(controller.detail!.tracks[0]),
          isFalse,
        );
        expect(_ids(controller), ['t1', 't2', 't3']);
        expect(controller.detail!.trackCount, 3);
        expect(controller.detail!.totalDurationMs, 600000);
      },
    );

    test('a failed load keeps the playlist that is already on screen', () async {
      final api = _FakePlaylistApi(_playlist(['t1']));
      final controller = _controllerFor(api);
      await controller.load();

      api.failDetail = true;
      await controller.load();

      // A background refresh that fails is a reason to say so, not a reason to blank a playlist
      // somebody is looking at.
      expect(_ids(controller), ['t1']);
      expect(controller.error, isNotNull);
    });
  });

  group('liked songs', () {
    test('unliking drops the row without waiting for the server', () async {
      final api = _FakeLikedApi(['t1', 't2', 't3']);
      final controller = LikedController(api: api, onFailure: (_) {});
      await controller.load();

      api.blockUnlike = true;
      final pending = controller.unlike(controller.tracks[1]);
      expect(controller.tracks.map((t) => t.id), ['t1', 't3']);
      expect(controller.durationMs, 400000);

      api.completeUnlike();
      expect(await pending, isTrue);
      expect(api.unliked, ['t2']);
    });

    test('a refused unlike puts the song back and reports it', () async {
      final api = _FakeLikedApi(['t1', 't2'])..failUnlike = true;
      final failures = <Object>[];
      final controller = LikedController(api: api, onFailure: failures.add);
      await controller.load();

      expect(await controller.unlike(controller.tracks[0]), isFalse);
      expect(controller.tracks.map((t) => t.id), ['t1', 't2']);
      expect(failures, hasLength(1));
    });
  });

  group('downloads', () {
    late ChordiaDatabase database;

    setUp(() => database = ChordiaDatabase(NativeDatabase.memory()));
    tearDown(() => database.close());

    test('rows group by album, newest album first, in album order', () async {
      final dao = database.downloadsDao;
      // Deliberately saved out of order and out of album sequence: the grouping has to impose
      // both orders itself rather than inherit whatever the queue happened to finish in.
      await dao.save(
        _download(
          'a2',
          album: 'Older',
          albumId: 'alb-1',
          trackNo: 2,
          savedAt: 10,
        ),
      );
      await dao.save(
        _download(
          'a1',
          album: 'Older',
          albumId: 'alb-1',
          trackNo: 1,
          savedAt: 30,
        ),
      );
      await dao.save(
        _download(
          'b1',
          album: 'Newer',
          albumId: 'alb-2',
          trackNo: 1,
          savedAt: 90,
        ),
      );

      final groups = groupDownloads(await dao.all());

      expect(groups.map((g) => g.album), ['Newer', 'Older']);
      expect(groups[1].tracks.map((t) => t.trackId), ['a1', 'a2']);
    });

    test('two albums sharing a title stay two groups', () async {
      final dao = database.downloadsDao;
      // Grouping on the title alone would fold these into one heading over tracks from both.
      await dao.save(_download('x', album: 'Greatest Hits', albumId: 'alb-1'));
      await dao.save(_download('y', album: 'Greatest Hits', albumId: 'alb-2'));

      expect(groupDownloads(await dao.all()), hasLength(2));
    });

    test('a group credits one artist only when every track agrees', () async {
      final dao = database.downloadsDao;
      await dao.save(
        _download('c1', album: 'Split', albumId: 'alb-3', artist: 'Anna'),
      );
      await dao.save(
        _download('c2', album: 'Split', albumId: 'alb-3', artist: 'Bo'),
      );

      // A compilation credited to whichever track sorted first would be a confident lie.
      expect(groupDownloads(await dao.all()).single.artist, isNull);
    });

    test('the total is the sum of what is on screen', () async {
      final dao = database.downloadsDao;
      await dao.save(_download('s1', albumId: 'alb-1', sizeBytes: 1500));
      await dao.save(_download('s2', albumId: 'alb-1', sizeBytes: 2500));
      await dao.save(_download('s3', albumId: 'alb-2', sizeBytes: 6000));

      final rows = await dao.all();
      expect(totalDownloadBytes(rows), 10000);
      // Per group as well: the album headings and the header figure have to add up.
      final groups = groupDownloads(rows);
      expect(groups.map((g) => g.sizeBytes).reduce((a, b) => a + b), 10000);
    });

    test(
      'nothing downloaded is an empty list, not a zero-byte group',
      () async {
        final rows = await database.downloadsDao.all();
        expect(groupDownloads(rows), isEmpty);
        expect(totalDownloadBytes(rows), 0);
      },
    );

    test('a downloaded row maps back to the track it is a snapshot of', () async {
      final dao = database.downloadsDao;
      await dao.save(_download('m1', album: 'Mapped', albumId: 'alb-9'));

      final track = browseTrackOf((await dao.all()).single);
      expect(track.id, 'm1');
      // The stream URL is built from the library's own id, not the Hub's — losing this in the
      // mapping is what would make a downloaded song unplayable offline.
      expect(track.trackRef, 'ref-m1');
      expect(track.libraryId, 'lib-1');
      // Stored as a bare hash, handed on in the path form every cover consumer expects.
      expect(track.coverUrl, '/v1/images/${'0' * 64}');
    });
  });

  group('formatting', () {
    test('bytes climb the same ladder the web client uses', () {
      // The same download must not read as "1.0 MB" on the phone and "1,024 KB" in the browser.
      expect(formatBytes(512), '512 B');
      expect(formatBytes(2048), '2 KB');
      expect(formatBytes(5 * 1024 * 1024), '5.0 MB');
      expect(formatBytes(3 * 1024 * 1024 * 1024), '3.00 GB');
    });

    test('a runtime rounds to the nearest minute rather than truncating', () {
      // 47m50s is "48 min", not "47 min": this is a header stat, not a seek target.
      expect(
        totalDuration(47 * 60000 + 50000, _echo),
        'catalog:album.durationMin minutes=48',
      );
      // Past an hour it splits, and the remainder is minutes rather than a decimal hour.
      expect(
        totalDuration(61 * 60000 + 30000, _echo),
        'catalog:album.durationHrMin count=1,minutes=2',
      );
    });

    test('a track length is m:ss with a padded seconds field', () {
      expect(trackClock(65000), '1:05');
      expect(trackClock(9000), '0:09');
      expect(trackClock(600000), '10:00');
    });
  });

  group('smart rule summary', () {
    test('the joiner is the match mode', () {
      const rules = SmartRules(
        matchMode: SmartMatch.any,
        conditions: [
          SmartCondition(
            field: SmartField.artist,
            op: SmartOp.equals,
            value: 'Bjork',
          ),
          SmartCondition(
            field: SmartField.genre,
            op: SmartOp.contains,
            value: 'jazz',
          ),
        ],
      );
      // "all of:" as a prefix leaves an "any" list looking identical to an "all" list once the
      // prefix scrolls off a truncated line, which is the one distinction a reader cannot lose.
      expect(summariseSmartRules(rules, _echo), contains('playlists:smart.or'));
    });

    test('a rule listing several values names every one of them', () {
      const rules = SmartRules(
        conditions: [
          SmartCondition(
            field: SmartField.artist,
            op: SmartOp.equals,
            value: 'Bjork',
            valuesValue: ['Bjork', 'Dua Lipa'],
          ),
        ],
      );
      // A summary reading "Artist is Bjork" when the rule also matches Dua Lipa is worse than no
      // summary at all.
      expect(summariseSmartRules(rules, _echo), contains('Bjork, Dua Lipa'));
    });

    test('a boolean rule is the whole phrase, with no field in front', () {
      const rules = SmartRules(
        conditions: [
          SmartCondition(
            field: SmartField.liked,
            op: SmartOp.isValue,
            value: 'true',
          ),
        ],
      );
      // "Liked is liked" is what putting the field in front would produce.
      expect(
        summariseSmartRules(rules, _echo),
        'playlists:smart.bool.likedTrue',
      );
    });

    test('no rules summarise to nothing rather than to punctuation', () {
      expect(summariseSmartRules(const SmartRules(), _echo), isEmpty);
    });

    test('a refresh schedule reads in whole units', () {
      expect(smartRefreshLabel(0, _echo), 'playlists:smart.refresh.never');
      expect(
        smartRefreshLabel(360, _echo),
        'playlists:smart.refresh.everyHour count=6',
      );
      expect(
        smartRefreshLabel(2880, _echo),
        'playlists:smart.refresh.everyDay count=2',
      );
      // 90 minutes is not "1.5 hours" — it falls through to the minutes tier rather than
      // rendering a fraction of a unit.
      expect(
        smartRefreshLabel(90, _echo),
        'playlists:smart.refresh.everyMinute count=90',
      );
    });
  });
}

/// A translator that answers with the key and the arguments it was handed.
///
/// These tests are about rule and format LOGIC, not about copy: asserting on English prose would
/// make them fail the next time somebody improves a sentence in the catalogs. The arguments are
/// echoed because they are where the logic lives — a formatter that rounded the wrong way would
/// still pick the right key.
String _echo(String key, [Map<String, Object?> args = const {}]) => args.isEmpty
    ? key
    : '$key ${args.entries.map((e) => '${e.key}=${e.value}').join(',')}';

PlaylistDetailController _controllerFor(
  PlaylistApi api, {
  void Function(Object error)? onFailure,
}) => PlaylistDetailController(
  playlistId: 'pl-1',
  api: api,
  onFailure: onFailure ?? (_) {},
);

List<String> _ids(PlaylistDetailController controller) => [
  for (final track in controller.detail!.tracks) track.id,
];

PlaylistDetail _playlist(List<String> trackIds) => PlaylistDetail(
  id: 'pl-1',
  name: 'Road trip',
  owner: const PublicUser(displayName: 'Kanin', handle: 'kanin', id: 'u-1'),
  tracks: [for (final id in trackIds) _track(id)],
  canEdit: true,
  owned: true,
  trackCount: trackIds.length,
  totalDurationMs: trackIds.length * 200000,
);

BrowseTrack _track(String id) => BrowseTrack(
  artist: 'Artist',
  contentHash: 'sha-$id',
  durationMs: 200000,
  id: id,
  libraryId: 'lib-1',
  title: 'Song $id',
  trackRef: 'ref-$id',
);

DownloadsCompanion _download(
  String trackId, {
  String? album,
  String? albumId,
  String artist = 'Artist',
  int? trackNo,
  int sizeBytes = 1000,
  int savedAt = 0,
}) => DownloadsCompanion.insert(
  trackId: trackId,
  libraryId: 'lib-1',
  trackRef: 'ref-$trackId',
  contentHash: 'sha-$trackId',
  profile: 'original',
  filePath: '/music/$trackId.flac',
  sizeBytes: sizeBytes,
  savedAt: savedAt,
  title: 'Song $trackId',
  artist: artist,
  album: Value(album),
  albumId: Value(albumId),
  durationMs: 180000,
  trackNo: Value(trackNo),
  coverSha: Value('0' * 64),
);

class _FakePlaylistApi implements PlaylistApi {
  _FakePlaylistApi(this._detail);

  PlaylistDetail _detail;

  bool failDetail = false;
  bool failReorder = false;
  bool failRemove = false;

  /// Holds the reorder call open so a test can look at the list mid-flight — which is the only
  /// way to tell an optimistic apply from a refetch that happened to be fast.
  bool blockReorder = false;
  final _reorderGate = Completer<void>();

  List<String>? sentOrder;

  void completeReorder() {
    if (!_reorderGate.isCompleted) _reorderGate.complete();
  }

  @override
  Future<PlaylistDetail> detail(String playlistId) async {
    if (failDetail) throw StateError('detail refused');
    return _detail;
  }

  @override
  Future<void> reorderTracks(String playlistId, List<String> trackIds) async {
    sentOrder = trackIds;
    if (blockReorder) await _reorderGate.future;
    if (failReorder) throw StateError('reorder refused');
    _detail = _playlist(trackIds);
  }

  @override
  Future<void> removeTrack(String playlistId, String trackId) async {
    if (failRemove) throw StateError('remove refused');
  }

  @override
  Future<void> update(String playlistId, PlaylistPatch changes) async {}

  @override
  Future<void> setCover(String playlistId, String hash) async {}

  @override
  Future<void> clearCover(String playlistId) async {}

  @override
  Future<void> addCollaborator(String playlistId, String handle) async {}

  @override
  Future<void> removeCollaborator(String playlistId, String userId) async {}
}

class _FakeLikedApi implements LikedApi {
  _FakeLikedApi(List<String> ids)
    : _tracks = [for (final id in ids) _track(id)];

  final List<BrowseTrack> _tracks;
  final unliked = <String>[];

  bool failUnlike = false;
  bool blockUnlike = false;
  final _unlikeGate = Completer<void>();

  void completeUnlike() {
    if (!_unlikeGate.isCompleted) _unlikeGate.complete();
  }

  @override
  Future<List<BrowseTrack>> tracks() async => _tracks;

  @override
  Future<void> unlike(String trackId) async {
    if (blockUnlike) await _unlikeGate.future;
    if (failUnlike) throw StateError('unlike refused');
    unliked.add(trackId);
  }
}
