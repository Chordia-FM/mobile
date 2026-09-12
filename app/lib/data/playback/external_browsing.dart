import 'package:chordia_db/chordia_db.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';

/// Whether apps outside Chordia may browse the collection through Android's media service.
///
/// The service has to be exported for a car head unit to reach it at all, and the platform gives
/// Dart nothing to identify the app that bound it: `audio_service` answers every caller with a
/// browsable root and its own validator hook is commented out. So the choice is made here instead
/// of at the caller, and it starts **off** — an Android Auto head unit is worth one switch, and
/// until it is flipped no other app on the phone can walk the playlists, liked songs and downloads
/// the tree serves.
///
/// Device-local on purpose: it is a statement about this phone and the things plugged into it, not
/// about the account.
class ExternalBrowsingSetting {
  const ExternalBrowsingSetting(this._kv);

  final KvDao _kv;

  static const _key = 'playback.externalBrowsing';

  /// Absent counts as off, so a phone that has never been asked serves nothing.
  Future<bool> allowed() async => await _kv.read(_key) == 'on';

  Future<void> set({required bool allowed}) =>
      _kv.write(_key, allowed ? 'on' : 'off');
}

final externalBrowsingSettingProvider = Provider<ExternalBrowsingSetting>(
  (ref) => ExternalBrowsingSetting(ref.watch(kvDaoProvider)),
);

/// The switch's own state, for the settings row.
final externalBrowsingControllerProvider =
    AsyncNotifierProvider<ExternalBrowsingController, bool>(
      ExternalBrowsingController.new,
    );

class ExternalBrowsingController extends AsyncNotifier<bool> {
  @override
  Future<bool> build() => ref.watch(externalBrowsingSettingProvider).allowed();

  Future<void> set({required bool allowed}) async {
    state = AsyncData(allowed);
    await ref.read(externalBrowsingSettingProvider).set(allowed: allowed);
  }
}
