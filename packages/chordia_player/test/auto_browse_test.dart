import 'package:chordia_player/src/handler/auto_browse.dart';
import 'package:chordia_sync/chordia_sync.dart';
import 'package:flutter_test/flutter_test.dart';

PlayerTrack track(String id) => PlayerTrack(
  id: id,
  title: 'Title $id',
  artist: 'Artist $id',
  album: 'Album',
  durationMs: 200000,
  libraryId: 'lib-1',
  trackRef: 'ref-$id',
  contentHash: 'hash-$id',
);

/// A scripted catalog. Records what it was asked for, so the paging arithmetic can be checked
/// without inventing a Hub.
class FakeSource implements AutoBrowseSource {
  FakeSource({this.rows = const [], this.result, this.one});

  final List<BrowseNode> rows;
  final BrowsePlayback? result;
  final BrowseNode? one;

  final asked = <({BrowseId parent, int offset, int limit})>[];

  @override
  Future<List<BrowseNode>> children(
    BrowseId parent, {
    required int offset,
    required int limit,
  }) async {
    asked.add((parent: parent, offset: offset, limit: limit));
    return rows.skip(offset).take(limit).toList();
  }

  @override
  Future<BrowseNode?> node(BrowseId id) async => one;

  @override
  Future<BrowsePlayback?> playback(BrowseId id) async => result;
}

List<BrowseNode> sections() => [
  const BrowseNode(id: BrowseId(BrowseId.home), title: 'Home'),
  const BrowseNode(id: BrowseId(BrowseId.library), title: 'Library'),
  const BrowseNode(id: BrowseId(BrowseId.downloads), title: 'Downloads'),
];

void main() {
  group('media ids survive the round trip', () {
    test('a section is its own name', () {
      const id = BrowseId(BrowseId.downloads);
      expect(id.encode(), 'downloads');
      expect(BrowseId.decode('downloads'), id);
    });

    test('a collection carries its id', () {
      final id = BrowseId.of(BrowseId.playlist, 'pl-42');
      expect(id.encode(), 'playlist:pl-42');
      expect(BrowseId.decode(id.encode()), id);
    });

    test('a track carries the library and the ref the engine needs', () {
      // Not the Hub catalog id: a cold `playFromMediaId` has to reach a library server without
      // first asking the Hub what a catalog id resolves to.
      final id = BrowseId.forTrack(track('t1'));
      expect(id.encode(), 'track:lib-1:ref-t1');
      final back = BrowseId.decode(id.encode())!;
      expect(back.kind, BrowseId.track);
      expect(back.args, ['lib-1', 'ref-t1']);
    });

    test('an argument containing a colon cannot reshape the id', () {
      // A library track ref is opaque. If one ever contains a separator, an unescaped id would
      // decode into a different number of arguments and address something else entirely.
      const id = BrowseId(BrowseId.track, ['lib:1', 'a:b:c']);
      expect(id.encode(), 'track:lib%3A1:a%3Ab%3Ac');
      expect(BrowseId.decode(id.encode()), id);
      expect(BrowseId.decode(id.encode())!.args.length, 2);
    });

    test('unicode and spaces survive', () {
      const id = BrowseId(BrowseId.playlist, ['Søndag ☕ / mix']);
      expect(BrowseId.decode(id.encode()), id);
    });

    test('a malformed id is refused rather than half-read', () {
      expect(BrowseId.decode(''), isNull);
      // `%zz` is not an escape. Auto hands back ids it stored across an app upgrade, and one that
      // cannot be parsed must not become a request for something else.
      expect(BrowseId.decode('track:%zz'), isNull);
    });

    test('equality is by kind and arguments, not by identity', () {
      expect(
        BrowseId.of(BrowseId.album, 'a1'),
        BrowseId.of(BrowseId.album, 'a1'),
      );
      expect(
        BrowseId.of(BrowseId.album, 'a1').hashCode,
        BrowseId.of(BrowseId.album, 'a1').hashCode,
      );
      expect(
        BrowseId.of(BrowseId.album, 'a1'),
        isNot(BrowseId.of(BrowseId.playlist, 'a1')),
      );
    });
  });

  group('the tree', () {
    test('the root is the three sections the app supplied', () async {
      final browse = AutoBrowse(sections: sections(), source: FakeSource());
      final children = await browse.getChildren(AutoBrowse.rootId);

      expect(children.map((i) => i.id), ['home', 'library', 'downloads']);
      // Sections are folders, not songs: a car that treats them as playable would try to stream
      // "Library".
      expect(children.map((i) => i.playable), everyElement(isFalse));
    });

    test('a section asks the app for its contents', () async {
      final source = FakeSource(
        rows: [
          BrowseNode(
            id: BrowseId.of(BrowseId.playlist, 'p1'),
            title: 'Morning',
          ),
        ],
      );
      final browse = AutoBrowse(sections: sections(), source: source);

      final children = await browse.getChildren('library');
      expect(children.single.id, 'playlist:p1');
      expect(source.asked.single.parent, const BrowseId(BrowseId.library));
    });

    test('a track row is playable and carries what a car draws', () async {
      final source = FakeSource(
        rows: [
          BrowseNode(
            id: BrowseId.forTrack(track('t1')),
            title: 'Title t1',
            subtitle: 'Artist t1',
            album: 'Album',
            duration: const Duration(milliseconds: 200000),
            playable: true,
          ),
        ],
      );
      final browse = AutoBrowse(sections: sections(), source: source);

      final item = (await browse.getChildren('downloads')).single;
      expect(item.playable, isTrue);
      expect(item.title, 'Title t1');
      expect(item.artist, 'Artist t1');
      expect(item.duration, const Duration(milliseconds: 200000));
    });

    test('an unreadable parent is an empty shelf, not a crash', () async {
      final browse = AutoBrowse(sections: sections(), source: FakeSource());
      // Inside the media service there is no UI to show an error in, and a throw here takes the
      // whole browse session down.
      expect(await browse.getChildren('%zz'), isEmpty);
    });

    test('the hierarchy stops at the depth Auto allows', () async {
      final source = FakeSource(
        rows: [const BrowseNode(id: BrowseId(BrowseId.home), title: 'x')],
      );
      final browse = AutoBrowse(sections: sections(), source: source);

      // A collection is level 2, so its children are the last level the tree has.
      expect(await browse.getChildren('album:a1'), isNotEmpty);
      // A song is that last level. Asking what is under it returns nothing and never reaches the
      // source: there is no fifth screen for a driver to land on.
      expect(await browse.getChildren('track:lib-1:ref-t1'), isEmpty);
      expect(source.asked, hasLength(1));
    });
  });

  group('paging', () {
    List<BrowseNode> manyRows(int count) => [
      for (var i = 0; i < count; i++)
        BrowseNode(id: BrowseId.of(BrowseId.album, 'a$i'), title: 'Album $i'),
    ];

    test('no options means the first page', () async {
      final source = FakeSource(rows: manyRows(250));
      final browse = AutoBrowse(sections: sections(), source: source);

      final children = await browse.getChildren('albums');
      expect(children, hasLength(AutoBrowse.maxPageSize));
      expect(source.asked.single.offset, 0);
      expect(source.asked.single.limit, AutoBrowse.maxPageSize);
    });

    test('a page request becomes an offset', () async {
      final source = FakeSource(rows: manyRows(250));
      final browse = AutoBrowse(sections: sections(), source: source);

      final children = await browse.getChildren('albums', {
        AutoBrowse.pageKey: 2,
        AutoBrowse.pageSizeKey: 20,
      });
      expect(source.asked.single.offset, 40);
      expect(source.asked.single.limit, 20);
      expect(children.first.title, 'Album 40');
    });

    test('a page size beyond the cap is clamped', () async {
      final source = FakeSource(rows: manyRows(1000));
      final browse = AutoBrowse(sections: sections(), source: source);

      // A car asking for a thousand rows still gets a list a driver can use, and a response the
      // binder can carry.
      await browse.getChildren('albums', {AutoBrowse.pageSizeKey: 1000});
      expect(source.asked.single.limit, AutoBrowse.maxPageSize);
    });

    test('the root is not paged', () async {
      final browse = AutoBrowse(sections: sections(), source: FakeSource());
      expect(await browse.getChildren(AutoBrowse.rootId), hasLength(3));
      expect(
        await browse.getChildren(AutoBrowse.rootId, {AutoBrowse.pageKey: 1}),
        isEmpty,
      );
    });
  });

  group('playing from an id', () {
    test('a known id resolves to tracks and a start', () async {
      final source = FakeSource(
        result: BrowsePlayback(
          tracks: [track('t1'), track('t2'), track('t3')],
          startIndex: 1,
          context: const PlaylistContext(id: 'p1', name: 'Morning'),
        ),
      );
      final browse = AutoBrowse(sections: sections(), source: source);

      final playback = await browse.playback('track:lib-1:ref-t2');
      expect(playback!.tracks, hasLength(3));
      // Picking the second song of a playlist leaves the rest of the playlist behind it, rather
      // than a queue of exactly one.
      expect(playback.startIndex, 1);
      expect(playback.context?.name, 'Morning');
    });

    test('an id that cannot be parsed plays nothing', () async {
      final browse = AutoBrowse(
        sections: sections(),
        source: FakeSource(result: BrowsePlayback(tracks: [track('t1')])),
      );
      expect(await browse.playback('%zz'), isNull);
    });
  });

  group('a single item', () {
    test('an id resolves to its own description', () async {
      final source = FakeSource(
        one: BrowseNode(
          id: BrowseId.of(BrowseId.playlist, 'p1'),
          title: 'Morning',
        ),
      );
      final browse = AutoBrowse(sections: sections(), source: source);
      expect((await browse.getMediaItem('playlist:p1'))?.title, 'Morning');
    });

    test('the root is not an item', () async {
      final browse = AutoBrowse(sections: sections(), source: FakeSource());
      expect(await browse.getMediaItem(AutoBrowse.rootId), isNull);
    });
  });
}
