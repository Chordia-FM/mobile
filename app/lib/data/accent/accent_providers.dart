/// The accent, from the account down to the pixels.
///
/// `UserSettings` already carries `accent`, `accent_mode`, `accent_palette` and `accent_speed`,
/// and the app already reads that document — so a colour chosen on the desktop shows up here on
/// the next read without anything else being wired. What was missing was everything downstream of
/// it: the phone hard-coded the surfaces the web derives.
library;

import 'package:chordia_api/chordia_api.dart' show AccentMode, AccentSpeed;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import 'accent_engine.dart';
import 'accent_palette.dart';
import 'artwork_color.dart';

/// The accent this deployment wears before a listener has chosen their own.
///
/// A seam rather than a fetch. `GET /v1/instance` carries the operator's choice and the hub probe
/// reads it when a server is paired, but nothing keeps it after that, so today the phone resolves
/// `'default'` to the built-in. Override this provider once the paired-hub record carries it and
/// every consumer below follows.
final instanceAccentProvider = Provider<String?>((ref) => null);

/// Everything the engine needs, assembled from the account.
///
/// [AccentConfig] compares by value, so this only publishes when something actually changed — a
/// settings poll that returns the same document does not restart a cross-fade mid-step.
final accentConfigProvider = Provider<AccentConfig>((ref) {
  final settings = ref.watch(userSettingsProvider).value;
  return AccentConfig(
    accent: resolveAccent(
      settings?.accent,
      instanceAccent: ref.watch(instanceAccentProvider),
    ),
    mode: settings?.accentMode ?? AccentMode.staticValue,
    palette: settings?.accentPalette ?? const [],
    // `artwork_color.dart` owns the extraction, its cache and its staleness rules; null means
    // "no colour worth using", and the engine falls back to the chosen accent for it.
    albumColor: ref.watch(artworkAccentProvider),
    speed: settings?.accentSpeed ?? AccentSpeed.steady,
  );
});

/// The one running accent.
///
/// Two engines fight over the colour and produce a flicker whose cause is invisible in the widget
/// inspector, so there is exactly one, owned here. It stops ticking while the app is backgrounded
/// and repaints once on return: a background app cross-fading a colour nobody can see is pure
/// battery.
final accentEngineProvider = Provider<AccentEngine>((ref) {
  final engine = AccentEngine();
  final lifecycle = AppLifecycleListener(
    onStateChange: (state) => engine.setHidden(
      state == AppLifecycleState.paused ||
          state == AppLifecycleState.detached ||
          state == AppLifecycleState.hidden,
    ),
  );
  ref.listen(
    accentConfigProvider,
    (_, next) => engine.apply(next),
    fireImmediately: true,
  );
  ref.onDispose(() {
    lifecycle.dispose();
    engine.dispose();
  });
  return engine;
});

/// The full token set the app's surfaces are painted from.
///
/// Derived from `AccentConfig.surfaceAccent` rather than from the live frame, which is what keeps
/// a cross-fade from rebuilding the whole tree seven times a second. See `accent_scope.dart`.
final accentSurfacesProvider = Provider<ChordiaSurfaces>((ref) {
  final config = ref.watch(accentConfigProvider);
  final stops = config.stops;
  return ChordiaSurfaces.of(
    config.surfaceAccent,
    // Gradient mode lights the ambient wash with the palette's far end instead of the fixed blue,
    // which is what puts the user's colours on the largest surface in the app rather than only on
    // its buttons.
    gradientEnd: config.mode == AccentMode.gradient && stops.length >= 2
        ? stops.last
        : null,
  );
});

/// The app's theme. Rebuilds when the account's accent changes, and at no other time.
final chordiaThemeProvider = Provider<ThemeData>(
  (ref) => buildChordiaTheme(ref.watch(accentSurfacesProvider)),
);
