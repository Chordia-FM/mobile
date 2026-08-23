import 'package:chordia_api/chordia_api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/downloads/download_manager.dart';
import '../../data/downloads/download_request.dart';
import '../../i18n/keys.g.dart';
import '../library/data/formatting.dart' show Translate;
import 'data/downloads_providers.dart';

export '../../data/downloads/download_manager.dart'
    show DownloadBatch, DownloadClearResult, DownloadOutcome;

/// **The API the rest of the app calls to keep music offline.**
///
/// Catalog rows, album and playlist headers, the queue sheet and the Downloads screen all reach
/// downloads through this and nothing else. It is deliberately narrow — save, remove, and the four
/// verbs a queued task needs — so that no other feature learns what a partial file is, where the
/// audio directory lives, or which tier the bytes were fetched at.
///
/// Every method is safe to call twice: queuing a track already held reports [DownloadOutcome
/// .alreadyDownloaded] rather than fetching it again, and removing something already gone
/// succeeds.
class DownloadsApi {
  const DownloadsApi({
    required DownloadManager manager,
    required QualityProfile Function() quality,
  }) : _manager = manager,
       _quality = quality;

  final DownloadManager _manager;
  final QualityProfile Function() _quality;

  /// Picks up whatever the last run left unfinished. Called once, at app start.
  Future<void> start() => _manager.start();

  /// Saves one track.
  Future<DownloadOutcome> save(BrowseTrack track) =>
      _manager.enqueue(DownloadRequest.of(track, _quality()));

  /// Saves an album, a playlist, or any other set of rows a screen already holds.
  ///
  /// The tracks are passed in rather than fetched by id: every screen that offers this button has
  /// just rendered the rows, and re-fetching them would make a download impossible to start from a
  /// page loaded before the network dropped.
  Future<DownloadBatch> saveAll(Iterable<BrowseTrack> tracks) =>
      _manager.enqueueAll([
        for (final track in tracks) DownloadRequest.of(track, _quality()),
      ]);

  /// Deletes a download, file and row. False when the track is playing and was left alone.
  Future<bool> remove(String trackId) => _manager.remove(trackId);

  /// Deletes a collection's downloads, reporting how many were kept because they were sounding.
  Future<DownloadClearResult> removeAll(Iterable<String> trackIds) async {
    var removed = 0;
    var skipped = 0;
    for (final id in trackIds) {
      if (await _manager.remove(id)) {
        removed++;
      } else {
        skipped++;
      }
    }
    return DownloadClearResult(removed: removed, skipped: skipped);
  }

  /// Everything on this device, gone.
  Future<DownloadClearResult> clear() => _manager.clear();

  /// Abandons an in-flight download and the bytes it fetched.
  Future<void> cancel(String trackId) => _manager.cancel(trackId);

  /// Stops an in-flight download, keeping its bytes for [resume].
  Future<void> pause(String trackId) => _manager.pause(trackId);

  Future<void> resume(String trackId) => _manager.resume(trackId);

  Future<void> retry(String trackId) => _manager.retry(trackId);
}

final downloadsApiProvider = Provider<DownloadsApi>(
  (ref) => DownloadsApi(
    manager: ref.watch(downloadManagerProvider),
    quality: () => ref.read(downloadQualityProvider),
  ),
);

/// Turns the stable code stored on a failed task into a sentence in the reader's language.
///
/// The database holds a code rather than a message precisely so this can happen at render time: a
/// queue that survives a week offline outlives whatever language the app was showing when the
/// failure happened.
String describeDownloadError(String? code, Translate t) {
  if (code == null) return t(LibraryKeys.downloadsErrorUnknown);
  if (code.startsWith('${DownloadErrorCode.server}:')) {
    return t(LibraryKeys.downloadsErrorServer, {
      'status': code.split(':').last,
    });
  }
  return switch (code) {
    DownloadErrorCode.offline => t(LibraryKeys.downloadsErrorOffline),
    DownloadErrorCode.incomplete => t(LibraryKeys.downloadsErrorIncomplete),
    DownloadErrorCode.cap => t(LibraryKeys.downloadsErrorCap),
    DownloadErrorCode.storage => t(LibraryKeys.downloadsErrorStorage),
    _ => t(LibraryKeys.downloadsErrorUnknown),
  };
}
