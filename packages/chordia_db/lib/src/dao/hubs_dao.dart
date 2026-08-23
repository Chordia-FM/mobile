import 'package:drift/drift.dart';

import '../database.dart';
import '../tables.dart';

part 'hubs_dao.g.dart';

/// The multi-hub registry, and the one place the "exactly one active hub" rule lives.
@DriftAccessor(tables: [Hubs])
class HubsDao extends DatabaseAccessor<ChordiaDatabase> with _$HubsDaoMixin {
  HubsDao(super.db);

  /// Every paired hub, oldest pairing first, so the switcher does not reorder itself.
  Future<List<Hub>> all() =>
      (select(hubs)..orderBy([(h) => OrderingTerm.asc(h.addedAt)])).get();

  Stream<List<Hub>> watchAll() =>
      (select(hubs)..orderBy([(h) => OrderingTerm.asc(h.addedAt)])).watch();

  Future<Hub?> byId(String id) =>
      (select(hubs)..where((h) => h.id.equals(id))).getSingleOrNull();

  /// The hub every request currently goes to, or null before the first pairing.
  Future<Hub?> active() =>
      (select(hubs)..where((h) => h.isActive)).getSingleOrNull();

  Stream<Hub?> watchActive() =>
      (select(hubs)..where((h) => h.isActive)).watchSingleOrNull();

  /// Inserts a hub, or refreshes the details of one already paired.
  ///
  /// `isActive` is left out of the update so re-pairing an idle hub — which a heartbeat or a
  /// renamed server triggers — cannot quietly steal the active slot from the hub in use.
  Future<void> upsert(HubsCompanion hub) => into(
    hubs,
  ).insertOnConflictUpdate(hub.copyWith(isActive: const Value.absent()));

  /// Makes [id] the active hub and clears every other row.
  ///
  /// One statement each way inside a transaction: a partial application would leave two hubs
  /// claiming to be active, and `active()` fetches a single row, so the next read would throw
  /// rather than merely pick wrong.
  Future<void> setActive(String id) => transaction(() async {
    await (update(hubs)..where((h) => h.isActive & h.id.equals(id).not()))
        .write(const HubsCompanion(isActive: Value(false)));
    await (update(hubs)..where((h) => h.id.equals(id))).write(
      const HubsCompanion(isActive: Value(true)),
    );
  });

  /// Forgets a hub, handing the active slot to the next one if [id] held it.
  ///
  /// Promoting here rather than leaving it to the caller keeps the app out of the state where
  /// hubs exist but none is selected, which every screen would then have to render.
  Future<void> remove(String id) => transaction(() async {
    final wasActive = (await byId(id))?.isActive ?? false;
    await (delete(hubs)..where((h) => h.id.equals(id))).go();
    if (!wasActive) return;

    final successor =
        await (select(hubs)
              ..orderBy([(h) => OrderingTerm.asc(h.addedAt)])
              ..limit(1))
            .getSingleOrNull();
    if (successor != null) await setActive(successor.id);
  });
}
