import 'package:chordia_db/chordia_db.dart';
import 'package:test/test.dart';

import 'support/in_memory.dart';

void main() {
  late ChordiaDatabase db;
  late HubsDao dao;

  setUp(() {
    db = openTestDatabase();
    dao = db.hubsDao;
  });

  tearDown(() => db.close());

  /// Counted straight off the table rather than through `active()`, which reads a single row and
  /// would throw on a second — a test that asserted through it could not tell "invariant held"
  /// from "invariant broken in the other direction".
  Future<int> activeCount() async {
    final rows = await db.select(db.hubs).get();
    return rows.where((h) => h.isActive).length;
  }

  test('a newly added hub is not active until asked for', () async {
    await dao.upsert(hub('a'));

    expect(await dao.active(), isNull);
    expect(await activeCount(), 0);
  });

  test('setting one hub active clears the others', () async {
    await dao.upsert(hub('a', addedAt: 1));
    await dao.upsert(hub('b', addedAt: 2));
    await dao.upsert(hub('c', addedAt: 3));

    await dao.setActive('a');
    expect((await dao.active())?.id, 'a');

    await dao.setActive('b');
    expect((await dao.active())?.id, 'b');
    expect(await activeCount(), 1);

    await dao.setActive('c');
    expect((await dao.active())?.id, 'c');
    expect(await activeCount(), 1);
  });

  test('re-activating the current hub leaves it active', () async {
    await dao.upsert(hub('a'));
    await dao.setActive('a');
    await dao.setActive('a');

    expect((await dao.active())?.id, 'a');
    expect(await activeCount(), 1);
  });

  test(
    'upserting details of an idle hub does not steal the active slot',
    () async {
      await dao.upsert(hub('a', addedAt: 1));
      await dao.upsert(hub('b', addedAt: 2));
      await dao.setActive('a');

      await dao.upsert(hub('b', name: 'Renamed', addedAt: 2));

      expect((await dao.byId('b'))?.name, 'Renamed');
      expect((await dao.active())?.id, 'a');
      expect(await activeCount(), 1);
    },
  );

  test('upserting the active hub keeps it active', () async {
    await dao.upsert(hub('a'));
    await dao.setActive('a');

    await dao.upsert(hub('a', name: 'Renamed'));

    expect((await dao.byId('a'))?.name, 'Renamed');
    expect((await dao.active())?.id, 'a');
  });

  test('removing the active hub promotes the oldest remaining one', () async {
    await dao.upsert(hub('a', addedAt: 1));
    await dao.upsert(hub('b', addedAt: 2));
    await dao.setActive('b');

    await dao.remove('b');

    expect((await dao.active())?.id, 'a');
    expect(await activeCount(), 1);
  });

  test('removing an idle hub leaves the active one alone', () async {
    await dao.upsert(hub('a', addedAt: 1));
    await dao.upsert(hub('b', addedAt: 2));
    await dao.setActive('a');

    await dao.remove('b');

    expect((await dao.active())?.id, 'a');
    expect(await dao.all(), hasLength(1));
  });

  test('removing the last hub leaves none active', () async {
    await dao.upsert(hub('a'));
    await dao.setActive('a');

    await dao.remove('a');

    expect(await dao.all(), isEmpty);
    expect(await dao.active(), isNull);
  });

  test('all() lists hubs in pairing order', () async {
    await dao.upsert(hub('c', addedAt: 30));
    await dao.upsert(hub('a', addedAt: 10));
    await dao.upsert(hub('b', addedAt: 20));

    expect((await dao.all()).map((h) => h.id), ['a', 'b', 'c']);
  });

  test('a hub without a web client stores a null frontend url', () async {
    await dao.upsert(hub('a'));
    expect((await dao.byId('a'))?.frontendUrl, isNull);

    await dao.upsert(
      hub('a').copyWith(frontendUrl: const Value('https://a.example.com')),
    );
    expect((await dao.byId('a'))?.frontendUrl, 'https://a.example.com');
  });
}
