import 'dart:io';

import 'package:chordia_api/chordia_api.dart';
import 'package:chordia_db/chordia_db.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../app/providers.dart';
import '../../../data/downloads/download_foreground_service.dart';
import '../../../data/downloads/download_http.dart';
import '../../../data/downloads/download_manager.dart';
import '../../../data/downloads/download_request.dart';
import '../../../data/downloads/download_storage.dart';
import '../../../data/downloads/download_store.dart';

/// Where downloaded audio is kept.
///
/// Application support, not the cache directory: the cache is what an OS storage sweep is entitled
/// to delete, and a download is the one audio artefact on the device that no server hands back on
/// demand. The path is resolved lazily inside [DownloadStore] so this provider stays synchronous.
final downloadStoreProvider = Provider<DownloadStore>(
  (ref) => DownloadStore(
    directory: getApplicationSupportDirectory().then(
      (base) => Directory('${base.path}${Platform.pathSeparator}downloads'),
    ),
  ),
);

final downloadBudgetProvider = Provider<DownloadBudget>(
  (ref) => DownloadBudget(ref.watch(kvDaoProvider)),
);

/// The storage limit, live, so raising it re-enables downloading without a restart.
final downloadCapProvider = StreamProvider<int>(
  (ref) => ref.watch(downloadBudgetProvider).watch(),
);

/// The download queue.
///
/// Built once for the life of the process and never rebuilt on a hub switch: it reads its
/// capability tokens through [playbackGrantsProvider], the same indirection playback uses, so a
/// batch queued against one hub keeps running while the user looks at another.
final downloadManagerProvider = Provider<DownloadManager>((ref) {
  return DownloadManager(
    tasks: ref.watch(databaseProvider).downloadTasksDao,
    downloads: ref.watch(downloadsDaoProvider),
    store: ref.watch(downloadStoreProvider),
    fetch: pinnedDownloadFetch(
      grants: ref.watch(playbackGrantsProvider),
      factory: ref.watch(httpClientFactoryProvider),
    ),
    foreground: defaultForegroundService(),
    // Read per check rather than watched: the cap can change while a batch runs, and the answer
    // that matters is the one at the moment the next file would be written.
    capBytes: () => ref.read(downloadBudgetProvider).read(),
    isPlaying: (trackId) => ref.read(currentTrackProvider)?.id == trackId,
  );
});

/// Everything still downloading, waiting or failed.
final downloadQueueProvider = StreamProvider<List<DownloadTask>>(
  (ref) => ref.watch(downloadManagerProvider).watchQueue(),
);

/// A queued download with enough of its request to draw a row.
///
/// The queue table stores only a track id — everything a row wants to say is in the manifest
/// beside the partial bytes, because that is the copy that survives the app being killed.
@immutable
class QueuedDownload {
  const QueuedDownload({required this.task, this.request});

  final DownloadTask task;

  /// Null when the manifest is unreadable, which is the state a storage sweep leaves behind. The
  /// row still renders, and the task still cancels.
  final DownloadRequest? request;
}

/// The queue, each row carrying its title and artist.
///
/// Manifests are read once per track and remembered: the queue stream fires on every progress
/// write — twice a second per active download — and re-reading a file per row per tick would turn
/// a progress bar into disk traffic. The display half of a request never changes for a given
/// track, which is what makes caching it safe.
final downloadQueueDetailsProvider = StreamProvider<List<QueuedDownload>>((
  ref,
) {
  final store = ref.watch(downloadStoreProvider);
  final known = <String, DownloadRequest?>{};
  return ref.watch(downloadManagerProvider).watchQueue().asyncMap((
    tasks,
  ) async {
    final live = {for (final task in tasks) task.trackId};
    known.removeWhere((trackId, _) => !live.contains(trackId));
    for (final task in tasks) {
      if (known.containsKey(task.trackId)) continue;
      known[task.trackId] = (await store.readManifest(task.trackId))?.request;
    }
    return [
      for (final task in tasks)
        QueuedDownload(task: task, request: known[task.trackId]),
    ];
  });
});

/// The ids of tracks held on this device, for the downloaded badge on catalog rows.
///
/// A set rather than a query per row: a list screen marks hundreds of rows at once, and asking
/// per row would be a query per visible track.
final downloadedTrackIdsProvider = StreamProvider<Set<String>>(
  (ref) => ref
      .watch(downloadsDaoProvider)
      .watchAll()
      .map((rows) => {for (final row in rows) row.trackId}),
);

/// What downloads occupy, against what the user allowed.
final downloadStorageProvider = StreamProvider<DownloadStorage>((ref) {
  final cap = ref.watch(downloadCapProvider).value ?? 0;
  return ref
      .watch(downloadsDaoProvider)
      .watchAll()
      .map(
        (rows) => DownloadStorage(
          // Summed over the same rows the screen lists, so the figure in the storage line can
          // never disagree with the songs printed under it.
          usedBytes: rows.fold(0, (sum, row) => sum + row.sizeBytes),
          trackCount: rows.length,
          capBytes: cap,
        ),
      );
});

/// The tier downloads are fetched at: the listener's chosen quality, uncapped.
///
/// Streaming applies a network ceiling because the bytes are spent as they are heard; a download
/// is a deliberate act with a lasting result, and silently saving a permanent `data_saver` copy
/// because the phone happened to be on cellular would be a worse outcome than a slower download.
final downloadQualityProvider = Provider<QualityProfile>(
  (ref) => ref.watch(playbackPreferencesProvider).quality,
);
