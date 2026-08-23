import 'package:chordia_api/chordia_api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import 'settings_patch.dart';
import 'settings_providers.dart';

/// The listener's settings, and the one write every settings screen goes through.
///
/// Every edit is applied optimistically. On a phone the round trip to the Hub is long enough that
/// a switch which waits for it reads as a tap that did not register — which is exactly when people
/// tap again and undo themselves. The revert and the message on failure are therefore part of the
/// contract rather than an afterthought: a screen that keeps showing a change the server refused
/// is worse than one that never moved.
class SettingsController extends AsyncNotifier<UserSettings> {
  Object? _failure;

  /// Why the last [patch] did not stick. Read by the screen that got `false` back, so the message
  /// can be the Hub's own (already localised) problem title rather than a generic guess.
  Object? get failure => _failure;

  @override
  Future<UserSettings> build() {
    final api = ref.watch(settingsApiProvider);
    if (api == null) {
      // No hub, no session, nothing to read. An error rather than a default blob: showing
      // defaults here would invite somebody to "change" a setting into a save that overwrites
      // their real settings with this client's guesses.
      throw StateError('No hub session to read settings from.');
    }
    return api.read();
  }

  /// Applies [change] locally, persists it, and puts it back if the Hub refuses.
  ///
  /// Returns whether the change stuck. Never throws: the caller is a gesture handler with nothing
  /// useful to do with an exception.
  Future<bool> patch(SettingsPatch change) async {
    final api = ref.read(settingsApiProvider);
    final previous = state.value;
    if (api == null || previous == null) return false;

    final optimistic = change.applyTo(previous);
    state = AsyncData(optimistic);
    try {
      // The response, not the value sent: the Hub normalises what it stores (an accent it does
      // not recognise, a field a newer server defaults differently), and the screen should show
      // what was actually saved.
      state = AsyncData(await api.write(optimistic));
      _failure = null;
      // Playback reads its preferences from `userSettingsProvider`, which is a separate read of
      // the same document. Without this, turning off volume normalisation would take effect on
      // the settings screen and nowhere else until the app was restarted.
      ref.invalidate(userSettingsProvider);
      return true;
    } on Object catch (error) {
      _failure = error;
      // Only when this patch is still the one on screen. A later edit that superseded it owns the
      // state now, and putting the pre-patch blob back would silently undo something the user did
      // after this one.
      if (identical(state.value, optimistic)) state = AsyncData(previous);
      return false;
    }
  }

  /// Re-reads from the Hub, for a pull-to-refresh.
  Future<void> reload() async {
    final api = ref.read(settingsApiProvider);
    if (api == null) return;
    state = AsyncData(await api.read());
  }
}

/// The settings document, shared by every settings screen.
final settingsControllerProvider =
    AsyncNotifierProvider<SettingsController, UserSettings>(
      SettingsController.new,
    );
