import 'package:chordia_db/chordia_db.dart';
import 'package:test/test.dart';

import 'support/in_memory.dart';

void main() {
  late ChordiaDatabase db;
  late ResponseCacheDao dao;

  setUp(() {
    db = openTestDatabase();
    dao = db.responseCacheDao;
  });

  tearDown(() => db.close());

  Future<void> write(
    String key, {
    required int fetchedAt,
    required int staleAt,
  }) => dao.write(
    key: key,
    bodyJson: '{"key":"$key"}',
    fetchedAt: fetchedAt,
    staleAt: staleAt,
  );

  test('a miss reads as null', () async {
    expect(await dao.read('GET /v1/me', now: 0), isNull);
  });

  test('an entry is fresh right up to its stale time', () async {
    await write('GET /v1/me', fetchedAt: 1000, staleAt: 2000);

    final justBefore = await dao.read('GET /v1/me', now: 1999);
    expect(justBefore?.isStale, isFalse);
    expect(justBefore?.bodyJson, '{"key":"GET /v1/me"}');
  });

  test(
    'an entry is stale from its stale time onwards, and still served',
    () async {
      await write('GET /v1/me', fetchedAt: 1000, staleAt: 2000);

      final atBoundary = await dao.read('GET /v1/me', now: 2000);
      expect(atBoundary?.isStale, isTrue);
      expect(atBoundary?.bodyJson, '{"key":"GET /v1/me"}');

      final wellAfter = await dao.read('GET /v1/me', now: 999999);
      expect(wellAfter?.isStale, isTrue);
      expect(wellAfter?.response.fetchedAt, 1000);
    },
  );

  test('writing the same key replaces the entry and refreshes it', () async {
    await write('GET /v1/me', fetchedAt: 1000, staleAt: 2000);
    await dao.write(
      key: 'GET /v1/me',
      bodyJson: '{"key":"second"}',
      fetchedAt: 3000,
      staleAt: 4000,
    );

    final entry = await dao.read('GET /v1/me', now: 3500);
    expect(entry?.bodyJson, '{"key":"second"}');
    expect(entry?.isStale, isFalse);
  });

  test(
    'eviction keeps stale entries until the grace period has passed',
    () async {
      await write('GET /v1/me', fetchedAt: 0, staleAt: 1000);

      const grace = Duration(seconds: 10);
      expect(await dao.evictExpired(9000, grace: grace), 0);
      expect(await dao.read('GET /v1/me', now: 9000), isNotNull);

      expect(await dao.evictExpired(11000, grace: grace), 1);
      expect(await dao.read('GET /v1/me', now: 11000), isNull);
    },
  );

  test('eviction leaves fresh entries alone', () async {
    await write('fresh', fetchedAt: 0, staleAt: 100000);
    await write('ancient', fetchedAt: 0, staleAt: 1);

    expect(await dao.evictExpired(50000, grace: Duration.zero), 1);
    expect(await dao.read('fresh', now: 50000), isNotNull);
    expect(await dao.read('ancient', now: 50000), isNull);
  });

  test('evicting by prefix invalidates one family of responses', () async {
    await write('GET /v1/playlists/p1', fetchedAt: 0, staleAt: 100000);
    await write('GET /v1/playlists/p1/tracks', fetchedAt: 0, staleAt: 100000);
    await write('GET /v1/albums/a1', fetchedAt: 0, staleAt: 100000);

    expect(await dao.evictPrefix('GET /v1/playlists/p1'), 2);
    expect(await dao.read('GET /v1/albums/a1', now: 0), isNotNull);
  });

  test('clear empties the cache', () async {
    await write('a', fetchedAt: 0, staleAt: 1);
    await write('b', fetchedAt: 0, staleAt: 1);

    await dao.clear();

    expect(await dao.read('a', now: 0), isNull);
    expect(await dao.read('b', now: 0), isNull);
  });
}
