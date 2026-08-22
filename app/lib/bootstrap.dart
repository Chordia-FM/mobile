import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:chordia_db/open.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'app/app.dart';
import 'app/config.dart';
import 'app/providers.dart';
import 'app/theme.dart';
import 'data/mesh/providers.dart';
import 'data/playback/adaptive.dart';
import 'features/downloads/downloads_api.dart';
import 'i18n/keys.g.dart';
import 'i18n/translations.dart';
import 'i18n/translations_provider.dart';

/// The key this install's device id lives under.
const _deviceIdKey = 'device_id';

/// The Android media notification channel.
///
/// A user-visible channel is created under this id the first time the service runs, and changing it
/// later leaves the old one behind in the app's settings — so it is a constant, not something
/// derived from the flavour.
const _notificationChannelId = 'fm.chordia.mobile.audio';

/// Shared entry point for every flavour.
///
/// Everything the app needs before the first frame is resolved here rather than inside the widget
/// tree, because the audio service can be started by Android Auto with no UI attached at all — the
/// dependency graph has to stand up without a `BuildContext`.
Future<void> bootstrap(AppConfig config) async {
  WidgetsFlutterBinding.ensureInitialized();

  final locale = await resolveStartupLocale();
  final translations = await Translations.load(locale);

  final database = openChordiaDatabase();
  final deviceId = await database.kvDao.readOrCreate(
    _deviceIdKey,
    const Uuid().v4,
  );

  // Partial audio belongs in the cache directory, not application support: it is reconstructible
  // from the library server, so an OS storage sweep is welcome to take it. Downloads and the
  // scrobble queue, which are not reconstructible, live in the database instead.
  final cacheRoot = await getApplicationCacheDirectory();

  final container = ProviderContainer(
    overrides: [
      appConfigProvider.overrideWithValue(config),
      translationsProvider.overrideWith((ref) => translations),
      databaseProvider.overrideWithValue(database),
      deviceIdProvider.overrideWithValue(deviceId),
      audioCacheDirectoryProvider.overrideWithValue(
        Directory('${cacheRoot.path}${Platform.pathSeparator}audio'),
      ),
    ],
  );

  // Before `runApp`, and not merely as an ordering preference: Android can start this service into
  // a process with no UI — a headset button pressed after the app was swiped away, or Android Auto
  // asking to resume — and the handler it finds has to be one that already exists.
  await AudioService.init(
    builder: () => container.read(audioHandlerProvider),
    config: AudioServiceConfig(
      androidNotificationChannelId: _notificationChannelId,
      androidNotificationChannelName: translations(
        PlayerKeys.notificationChannelName,
      ),
      // Ongoing while playing, and dismissed the moment playback stops. The two go together:
      // audio_service refuses an ongoing notification that cannot be swiped away when paused,
      // and Android would otherwise leave a dead notification behind for the rest of the session.
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
      notificationColor: ChordiaColors.accent,
    ),
  );

  await container.read(audioHandlerProvider).configureSession();
  container.read(playbackServiceProvider).start();

  // Adopts whatever the last run left queued. A download interrupted by the process dying resumes
  // from the bytes already on disk rather than starting the file again.
  unawaited(container.read(downloadsApiProvider).start());

  // Held open for the life of the app rather than by whichever screen happens to want them.
  //
  // The mesh has to be joined whenever the listener is signed in, not only while the device picker
  // is on screen — the whole point is that their other devices can see this phone and hand playback
  // to it. `listen` rather than `read` because both rebuild when the active hub or the session
  // changes, and a rebuilt provider with no listener is disposed immediately.
  container
    ..listen(meshConnectionProvider, (_, _) {}, fireImmediately: true)
    ..listen(adaptiveQualityProvider, (_, _) {}, fireImmediately: true);

  runApp(
    UncontrolledProviderScope(container: container, child: const ChordiaApp()),
  );
}
