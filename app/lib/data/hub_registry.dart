import 'dart:convert';

import 'hub.dart';
import 'secret_store.dart';

/// Where the list of known hubs and the choice of active one live.
///
/// An interface rather than a class because the storage underneath is going to change: the drift
/// database (`chordia_db`) gains a `hubs` table and a `kv` store, and a `DriftHubRegistry` will
/// implement exactly this. Nothing above this line — providers, screens, the router — knows or
/// cares which implementation it holds, so that swap is one line in `providers.dart`.
abstract interface class HubRegistry {
  /// Every hub, plus which is active. The one read the app makes at launch.
  Future<HubRegistrySnapshot> list();

  /// Adds (or replaces) a hub and makes it active. Callers probe first — see `HubProbe`.
  Future<HubRegistrySnapshot> add(Hub hub);

  /// Forgets a hub. Clearing its stored session is the caller's job: the registry deliberately
  /// knows nothing about credentials.
  Future<HubRegistrySnapshot> remove(String id);

  /// Points the app at [id]. An unknown id leaves the registry untouched.
  Future<HubRegistrySnapshot> setActive(String id);

  /// True when nothing has ever been written here — a first launch, not an emptied list.
  ///
  /// The difference is what makes seeding a default hub safe to do once. Somebody who removes the
  /// last server has expressed an opinion, and putting it back on the next launch would override
  /// it silently; a fresh install has expressed nothing.
  Future<bool> isPristine();
}

/// The registry as one JSON blob in the keystore.
///
/// **Interim.** It lives beside the sessions purely because that is the only storage this layer
/// already has while `chordia_db` is being built in parallel; none of it is secret, and a drift
/// table is the right home for a list that will grow columns. The blob is versioned so the
/// migration into drift can recognise and drain it.
class SecretsHubRegistry implements HubRegistry {
  const SecretsHubRegistry(this._secrets);

  static const storageKey = 'chordia_hubs::v1';

  final SecretStore _secrets;

  @override
  Future<bool> isPristine() async => await _secrets.read(storageKey) == null;

  @override
  Future<HubRegistrySnapshot> list() async {
    final raw = await _secrets.read(storageKey);
    if (raw == null) return HubRegistrySnapshot.empty;
    return _decode(raw);
  }

  @override
  Future<HubRegistrySnapshot> add(Hub hub) async {
    final current = await list();
    final hubs = [
      for (final existing in current.hubs)
        if (existing.id != hub.id) existing,
      hub,
    ];
    return _save(HubRegistrySnapshot(hubs: hubs, activeId: hub.id));
  }

  @override
  Future<HubRegistrySnapshot> remove(String id) async {
    final current = await list();
    final hubs = [
      for (final hub in current.hubs)
        if (hub.id != id) hub,
    ];
    // Removing the active hub promotes the first survivor rather than leaving the app pointed at
    // nothing — being dropped onto "choose a server" with one server listed is a dead end.
    final activeId = current.activeId == id
        ? (hubs.isEmpty ? null : hubs.first.id)
        : current.activeId;
    return _save(HubRegistrySnapshot(hubs: hubs, activeId: activeId));
  }

  @override
  Future<HubRegistrySnapshot> setActive(String id) async {
    final current = await list();
    if (!current.hubs.any((h) => h.id == id)) return current;
    return _save(HubRegistrySnapshot(hubs: current.hubs, activeId: id));
  }

  Future<HubRegistrySnapshot> _save(HubRegistrySnapshot snapshot) async {
    await _secrets.write(
      storageKey,
      jsonEncode({
        'version': 1,
        'active': snapshot.activeId,
        'hubs': [for (final hub in snapshot.hubs) hub.toJson()],
      }),
    );
    return snapshot;
  }

  static HubRegistrySnapshot _decode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return HubRegistrySnapshot.empty;
      final hubs = <Hub>[];
      final entries = decoded['hubs'];
      if (entries is List) {
        for (final entry in entries) {
          final hub = Hub.fromJson(entry);
          if (hub != null) hubs.add(hub);
        }
      }
      final active = decoded['active'];
      return HubRegistrySnapshot(
        hubs: hubs,
        activeId: active is String && hubs.any((h) => h.id == active)
            ? active
            : (hubs.isEmpty ? null : hubs.first.id),
      );
    } on FormatException {
      return HubRegistrySnapshot.empty;
    }
  }
}
