import 'package:chordia_db/chordia_db.dart';
import 'package:test/test.dart';

import 'support/in_memory.dart';

void main() {
  late ChordiaDatabase db;
  late KvDao dao;

  setUp(() {
    db = openTestDatabase();
    dao = db.kvDao;
  });

  tearDown(() => db.close());

  test('a missing key reads as null', () async {
    expect(await dao.read('volume'), isNull);
  });

  test('writing the same key overwrites', () async {
    await dao.write('volume', '0.4');
    await dao.write('volume', '0.9');

    expect(await dao.read('volume'), '0.9');
    expect(await dao.all(), {'volume': '0.9'});
  });

  test('readOrCreate mints once and reuses after', () async {
    var mints = 0;
    String mint() {
      mints++;
      return 'device-$mints';
    }

    expect(await dao.readOrCreate('device_id', mint), 'device-1');
    expect(await dao.readOrCreate('device_id', mint), 'device-1');
    expect(mints, 1);
  });

  test('removing a key leaves the rest', () async {
    await dao.write('volume', '0.9');
    await dao.write('theme', 'dark');

    await dao.remove('volume');

    expect(await dao.read('volume'), isNull);
    expect(await dao.all(), {'theme': 'dark'});
  });
}
