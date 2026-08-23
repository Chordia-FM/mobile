import 'dart:io';

import 'package:chordia_api/chordia_api.dart';
import 'package:chordia_db/chordia_db.dart';
import 'package:chordia_player/chordia_player.dart';
import 'package:chordia_sync/chordia_sync.dart';

/// Looks up the download row for a catalog track id, if this device holds one.
///
/// A function rather than the [DownloadsDao] itself so the rule below can be exercised without
/// standing up a database — the decision being tested is "downloaded before network", and that is
/// not a statement about SQLite.
typedef DownloadLookup = Future<DownloadedTrack?> Function(String trackId);

/// Whether a path still names a real file.
typedef FileProbe = bool Function(String path);

bool _exists(String path) => File(path).existsSync();

/// Turns a queue entry into something the engine can play.
///
/// One rule, in one place: **a downloaded copy wins, always.** It needs no capability token, no
/// pinned socket and no library server that happens to be awake, so preferring it is not merely an
/// optimisation — it is what makes a plane, a tunnel or a friend's offline server a non-event. Only
/// when there is no local copy does the tier question arise at all, and then the answer is the
/// listener's own tier capped by what the current link can be asked to carry.
class SourceResolver {
  const SourceResolver({
    required DownloadLookup downloads,
    required QualityProfile Function() quality,
    FileProbe probe = _exists,
  }) : _downloads = downloads,
       _quality = quality,
       _probe = probe;

  final DownloadLookup _downloads;
  final QualityProfile Function() _quality;
  final FileProbe _probe;

  Future<EngineSource> call(PlayerTrack track) async {
    final download = await _downloads(track.id);
    // A row whose file has gone — storage cleared from Android settings, a restore that did not
    // carry the audio — must fall through to streaming rather than handing the engine a path that
    // cannot open. The row is left alone: reconciling the index is the download subsystem's job,
    // and silently deleting somebody's download record from the playback path is not this class's
    // decision to make.
    if (download != null && _probe(download.filePath)) {
      return DownloadedSource(
        track: track,
        filePath: download.filePath,
        profile: QualityProfile.fromWire(download.profile),
      );
    }

    return StreamedSource(
      track: track,
      libraryId: track.libraryId,
      trackRef: track.trackRef,
      profile: _quality(),
      contentHash: track.contentHash,
    );
  }
}
