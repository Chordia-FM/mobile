import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/config.dart';
import 'translations.dart';

/// Build-time configuration, injected in `bootstrap`.
final appConfigProvider = Provider<AppConfig>(
  (ref) =>
      throw StateError('appConfigProvider must be overridden in bootstrap'),
);

/// The loaded catalogs. Overridden in `bootstrap` with the locale resolved before the first frame,
/// and replaced when the user picks a different language.
final translationsProvider = Provider<Translations>(
  (ref) =>
      throw StateError('translationsProvider must be overridden in bootstrap'),
);

/// Reads the locale to start in: the user's saved choice if there is one, else the device's.
///
/// Persisting happens through settings once a session exists; before sign-in the device locale is
/// the only signal available, and it is also the right default.
Future<String> resolveStartupLocale() async {
  final device = ui.PlatformDispatcher.instance.locale;
  return device.toLanguageTag();
}

/// `context.t(...)` — the call every screen uses.
extension TranslateX on WidgetRef {
  String Function(String, [Map<String, Object?>]) get t {
    final translations = read(translationsProvider);
    return (key, [args = const {}]) => translations(key, args);
  }
}
