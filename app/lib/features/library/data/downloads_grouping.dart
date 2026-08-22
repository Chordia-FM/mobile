import 'package:chordia_api/chordia_api.dart';
import 'package:chordia_db/chordia_db.dart';
import 'package:flutter/foundation.dart';

/// One album's worth of downloaded audio, as the Downloads screen renders it.
///
/// Grouping is by [albumId] rather than by album title: two different albums can share a name,
/// and folding them together would show one heading over tracks from both. Rows with no album id
/// at all are the loose singles a library holds, and they are grouped by title instead so a
/// download of "Song (from a compilation nobody tagged)" still lands under something readable.
@immutable
class DownloadGroup {
  const DownloadGroup({
    required this.key,
    required this.album,
    required this.artist,
    required this.coverSha,
    required this.tracks,
  });

  /// Stable identity for the group — an album id where there is one, else the album title.
  final String key;

  /// Album title, or null for downloads that carry no album at all.
  final String? album;

  /// The artist line to show under the heading. The album's own artist where every track agrees,
  /// null where they do not: a compilation credited to whichever track happened to sort first
  /// would be a confident lie.
  final String? artist;

  final String? coverSha;
  final List<DownloadedTrack> tracks;

  int get sizeBytes => tracks.fold(0, (sum, t) => sum + t.sizeBytes);

  int get durationMs => tracks.fold(0, (sum, t) => sum + t.durationMs);
}

/// Groups downloaded tracks by album, newest download first.
///
/// Group order follows the most recently saved track in each group, which is what makes a freshly
/// downloaded album appear at the top of the screen instead of wherever its title sorts. Inside a
/// group the order is the album's own — disc, then track number — because that is the order the
/// songs are meant to be heard in, and a save-order tracklist reads as shuffled.
List<DownloadGroup> groupDownloads(List<DownloadedTrack> rows) {
  final buckets = <String, List<DownloadedTrack>>{};
  final order = <String>[];
  for (final row in rows) {
    final key = row.albumId ?? row.album ?? row.trackId;
    final bucket = buckets.putIfAbsent(key, () {
      order.add(key);
      return <DownloadedTrack>[];
    });
    bucket.add(row);
  }

  // Sort by the newest save in each bucket, keeping first-seen order as the tie-break so a group
  // never jumps around between builds when two downloads share a millisecond. The tie-break reads
  // a snapshot of the original positions: `indexOf` on the list being sorted would answer from a
  // half-permuted list and make the comparator inconsistent.
  final seen = {for (var i = 0; i < order.length; i++) order[i]: i};
  order.sort((a, b) {
    final newest = _newestSavedAt(
      buckets[b]!,
    ).compareTo(_newestSavedAt(buckets[a]!));
    return newest != 0 ? newest : seen[a]!.compareTo(seen[b]!);
  });

  return [
    for (final key in order)
      DownloadGroup(
        key: key,
        album: buckets[key]!.first.album,
        artist: _sharedArtist(buckets[key]!),
        coverSha: buckets[key]!
            .map((t) => t.coverSha)
            .firstWhere((sha) => sha != null, orElse: () => null),
        tracks: _inAlbumOrder(buckets[key]!),
      ),
  ];
}

/// Disk taken by every downloaded file.
///
/// Summed over the rows on screen rather than read from `DownloadsDao.totalBytes`, so the figure
/// in the header can never disagree with the groups printed under it.
int totalDownloadBytes(List<DownloadedTrack> rows) =>
    rows.fold(0, (sum, row) => sum + row.sizeBytes);

/// A downloaded row as the catalog track it is a snapshot of, so the player can be handed a queue
/// from this screen without a network call.
///
/// Lossless for everything playback and the row need: the download index was designed to carry
/// exactly this, because a downloaded song has to render and play with the Hub unreachable. The
/// credited-artist list and the title markers stay in their JSON columns — both are display
/// extras a queue does not read, and decoding them here would put a parser in a mapper.
BrowseTrack browseTrackOf(DownloadedTrack row) => BrowseTrack(
  artist: row.artist,
  contentHash: row.contentHash,
  durationMs: row.durationMs,
  id: row.trackId,
  libraryId: row.libraryId,
  title: row.title,
  trackRef: row.trackRef,
  advisory: row.advisory,
  album: row.album,
  albumId: row.albumId,
  // Stored as the bare hash; every consumer of `cover_url` expects the Hub's path form.
  coverUrl: row.coverSha == null ? null : '/v1/images/${row.coverSha}',
  discNo: row.discNo,
  trackNo: row.trackNo,
);

int _newestSavedAt(List<DownloadedTrack> rows) =>
    rows.fold(0, (newest, row) => row.savedAt > newest ? row.savedAt : newest);

String? _sharedArtist(List<DownloadedTrack> rows) {
  final first = rows.first.artist;
  return rows.every((row) => row.artist == first) ? first : null;
}

List<DownloadedTrack> _inAlbumOrder(List<DownloadedTrack> rows) {
  final sorted = List<DownloadedTrack>.of(rows);
  sorted.sort((a, b) {
    // An untagged disc or track number sorts last rather than first: a single stray untagged file
    // pushed to the top would misrepresent the album's opening.
    final disc = (a.discNo ?? 1 << 30).compareTo(b.discNo ?? 1 << 30);
    if (disc != 0) return disc;
    final track = (a.trackNo ?? 1 << 30).compareTo(b.trackNo ?? 1 << 30);
    return track != 0 ? track : a.title.compareTo(b.title);
  });
  return sorted;
}
