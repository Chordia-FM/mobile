/// Which station carries on from what is playing, and the shape of one page of it.
///
/// A port of `frontend/src/lib/player/continuation.ts`, minus the fetching. The mapping from a
/// [PlayContext] to a station is a decision — it is why an album ends into that album's radio and a
/// smart playlist deliberately does not end into a playlist station — so it belongs here, tested.
/// The HTTP call does not: the queue must be drivable from a test with no Hub, and the Hub client
/// lives in a package this one only reaches through the app.
library;

import 'package:chordia_sync/chordia_sync.dart';
import 'package:meta/meta.dart';

/// What to ask a station for: its kind, its seed, and where to resume.
@immutable
class ContinuationRequest {
  const ContinuationRequest({
    required this.kind,
    required this.seed,
    this.cursor,
  });

  final StationKind kind;

  /// What the station is built from. Its meaning depends on [kind] — an artist id, a track id, an
  /// album id, a playlist id, or a genre slug.
  final String seed;

  /// The resume token, or null to build the station from the top.
  ///
  /// Note that an EXHAUSTED station arrives here as null, exactly as on the web: the caller's own
  /// exhausted flag is what stops a spent station being asked again, and it is reset whenever a new
  /// queue is started. Reading the cursor alone cannot tell the two apart, so it must not try.
  final String? cursor;

  @override
  bool operator ==(Object other) =>
      other is ContinuationRequest &&
      other.kind == kind &&
      other.seed == seed &&
      other.cursor == cursor;

  @override
  int get hashCode => Object.hash(kind, seed, cursor);

  @override
  String toString() => 'ContinuationRequest(${kind.wire}, $seed, $cursor)';
}

/// One page of a station: tracks to append, and where the next page starts.
@immutable
class ContinuationPage {
  const ContinuationPage({required this.tracks, this.cursor});

  /// Nothing more to play. The caller must treat this as "stop", never as "retry" — a finite
  /// station answers every later request the same way, and "empty means ask again" at the end of
  /// every queue is a fetch loop.
  const ContinuationPage.empty() : tracks = const [], cursor = null;

  final List<PlayerTrack> tracks;

  /// Where the page after this one starts. Null means the station is finished.
  final String? cursor;
}

/// Fetches one page of a station. Injected so a test can answer instantly, deterministically, and
/// without a network.
typedef ContinuationFetcher =
    Future<ContinuationPage> Function(ContinuationRequest request);

/// Which station should carry on from [context], seeding on [lastTrackId] when the context names
/// no entity of its own. Null when there is nothing to build a station from at all.
///
/// Every context can answer "what comes next": an album ends into that album's radio, an artist
/// page into that artist's, a station into its own next page. The contexts that name no entity —
/// liked, a search, a bare library browse, or nothing — fall back to the last track, which is
/// always a valid seed.
ContinuationRequest? continuationRequestFor(
  PlayContext? context,
  String? lastTrackId,
) {
  final request = switch (context) {
    // Keep the SAME station going rather than starting a fresh one from its seed. The cursor
    // carries the day and the offset, so the next page continues the exact weave the listener is
    // hearing instead of rebuilding today's station from the top and repeating its first tracks.
    RadioContext() => ContinuationRequest(
      kind: context.stationKind ?? StationKind.artist,
      seed: context.id,
      cursor: context.stationCursor?.value,
    ),
    AlbumContext() => ContinuationRequest(
      kind: StationKind.album,
      seed: context.id,
    ),
    ArtistContext() => ContinuationRequest(
      kind: StationKind.artist,
      seed: context.id,
    ),
    PlaylistContext() => ContinuationRequest(
      kind: StationKind.playlist,
      seed: context.id,
    ),
    // A smart playlist is deliberately absent from the station kinds: its id indexes
    // `smart_playlists`, a different table entirely, and handing it to the playlist station would
    // resolve a different playlist or none. Seeding on the last track is the honest answer, and it
    // is the same answer the id-less contexts get.
    SmartPlaylistContext() ||
    LibraryContext() ||
    LikedContext() ||
    SearchContext() ||
    null => ContinuationRequest(
      kind: StationKind.track,
      seed: lastTrackId ?? '',
    ),
  };
  return request.seed.isEmpty ? null : request;
}
