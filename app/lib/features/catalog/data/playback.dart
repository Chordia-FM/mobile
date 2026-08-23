import 'dart:math';

import 'package:chordia_api/chordia_api.dart' show ArtistRef, BrowseTrack;
import 'package:chordia_sync/chordia_sync.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart' show PlayerActions;

/// The slice of the player the catalog screens drive.
///
/// Deliberately three verbs wide. The catalog starts playback and adds to the queue; it never
/// pauses, seeks, or reads position, so widening this would only couple these screens to a
/// transport they have no business knowing about.
abstract interface class CatalogPlayerActions {
  /// Replace the queue with [tracks] and start at [startIndex], attributing the session to
  /// [context] — the "Playing from …" line, and what scrobbles are credited to.
  void playQueue(
    List<PlayerTrack> tracks, {
    int startIndex = 0,
    PlayContext? context,
  });

  /// Insert directly after whatever is playing.
  void playNext(PlayerTrack track);

  /// Append to the end of the queue.
  void enqueue(PlayerTrack track);

  /// Shuffle applies to the transport, so starting a collection shuffled is two statements: this
  /// one, then a [playQueue] whose start index is already random.
  void setShuffle(bool shuffle);
}

/// The player, once something has installed one.
///
/// Null is the pre-wiring state, not an error: this feature is built alongside the player and must
/// compile and render without it. Every catalog control that needs playback is disabled while this
/// is null, so nothing appears tappable and then does nothing.
///
/// WIRING (one line, once the app exposes its `PlayerActions`):
///
/// ```dart
/// catalogPlayerActionsProvider.overrideWith(
///   (ref) => PlayerActionsAdapter(ref.watch(playerActionsProvider)),
/// )
/// ```
final catalogPlayerActionsProvider = Provider<CatalogPlayerActions?>(
  (ref) => null,
);

/// The app's full player, narrowed to what the catalog drives.
///
/// An adapter rather than making `PlayerActions` implement the interface directly, because the
/// dependency has to point this way: the player knows nothing about the catalog, and the catalog
/// depends on three of its verbs.
class PlayerActionsAdapter implements CatalogPlayerActions {
  const PlayerActionsAdapter(this._player);

  final PlayerActions _player;

  @override
  void playQueue(
    List<PlayerTrack> tracks, {
    int startIndex = 0,
    PlayContext? context,
  }) => _player.playQueue(tracks, startIndex: startIndex, context: context);

  @override
  void playNext(PlayerTrack track) => _player.playNext(track);

  @override
  void enqueue(PlayerTrack track) => _player.enqueue(track);

  @override
  void setShuffle(bool shuffle) => _player.setShuffle(shuffle);
}

/// A catalog row as the queue understands it.
///
/// One conversion in one place: the queue's [PlayerTrack] and the catalog's [BrowseTrack] carry the
/// same facts under different names, and a per-screen copy of this mapping is how a queue entry
/// ends up missing the library id it needs to obtain a streaming grant.
PlayerTrack toPlayerTrack(BrowseTrack track) => PlayerTrack(
  id: track.id,
  title: track.title,
  artist: track.artist,
  artistId: track.artistId,
  artists: track.artists?.map(_toTrackArtist).toList(),
  album: track.album,
  albumId: track.albumId,
  plays: track.plays,
  durationMs: track.durationMs,
  coverUrl: track.coverUrl,
  libraryId: track.libraryId,
  trackRef: track.trackRef,
  contentHash: track.contentHash,
  advisory: track.advisory,
  // Both enums mirror the same contract, but they are separate Dart types — the sync package
  // cannot depend on the API package. Matched on the wire value, which is the definition of both.
  variants: track.variants
      ?.map((v) => TrackVariant.tryParse(v.wire))
      .nonNulls
      .toList(),
);

TrackArtist _toTrackArtist(ArtistRef artist) =>
    TrackArtist(id: artist.id, name: artist.name, imageUrl: artist.imageUrl);

/// Play [tracks] from [index], keeping the whole list as the queue.
///
/// The whole list, never just the tapped row: a track opened from an album has to be followed by
/// the rest of that album, and [context] is what makes the player say where it came from and what
/// the scrobbles are credited to.
void playTracksFrom(
  WidgetRef ref, {
  required List<BrowseTrack> tracks,
  required int index,
  required PlayContext? playContext,
}) {
  final player = ref.read(catalogPlayerActionsProvider);
  if (player == null || tracks.isEmpty) return;
  player.playQueue(
    tracks.map(toPlayerTrack).toList(),
    startIndex: index.clamp(0, tracks.length - 1),
    context: playContext,
  );
}

/// Start a whole collection, shuffled or in order.
///
/// The START index is randomised too when shuffling. The transport's shuffle only decides what
/// plays *next*, so beginning at zero played track one first every time and shuffle read as broken
/// from the only side that matters.
void playCollection(
  WidgetRef ref, {
  required List<BrowseTrack> tracks,
  required PlayContext? playContext,
  bool shuffle = false,
  Random? random,
}) {
  final player = ref.read(catalogPlayerActionsProvider);
  if (player == null || tracks.isEmpty) return;
  player.setShuffle(shuffle);
  playTracksFrom(
    ref,
    tracks: tracks,
    index: shuffle ? (random ?? Random()).nextInt(tracks.length) : 0,
    playContext: playContext,
  );
}
