import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/config.dart';
import 'i18n/translations.dart';
import 'i18n/translations_provider.dart';

/// Shared entry point for every flavour.
///
/// Everything the app needs before the first frame is resolved here rather than inside the widget
/// tree, because the audio service can be started by Android Auto with no UI attached at all — the
/// dependency graph has to stand up without a `BuildContext`.
Future<void> bootstrap(AppConfig config) async {
  WidgetsFlutterBinding.ensureInitialized();

  final locale = await resolveStartupLocale();
  final translations = await Translations.load(locale);

  runApp(
    ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(config),
        translationsProvider.overrideWith((ref) => translations),
      ],
      child: const ChordiaApp(),
    ),
  );
}
