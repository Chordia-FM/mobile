import 'dart:math';

import 'package:chordia_api/chordia_api.dart' show BrowseTrack;
import 'package:chordia_sync/chordia_sync.dart' show PlayContext;
import 'package:flutter/widgets.dart';

import '../../app/providers.dart' show PlayerActions;
import '../../features/catalog/catalog_routes.dart';
import '../../features/catalog/data/playback.dart' show toPlayerTrack;
import '../../features/home/data/discovery_nav.dart';
import '../../features/library/data/library_providers.dart' show LibraryHandoff;

/// The Library tab's [LibraryHandoff], answered by the app's real player and router.
///
/// The library feature states what it needs and something else supplies it, so that the feature
/// can be built and tested without a player. That "something else" is `bootstrap`, which overrides
/// `libraryHandoffProvider` with this — and until it did, every album, artist and radio pin on the
/// Library tab was a tile that highlighted under a finger and then did nothing.
///
/// This file sits at the composition seam and therefore depends on both sides of it, which nothing
/// else under `data/` is allowed to do.
class AppLibraryHandoff implements LibraryHandoff {
  const AppLibraryHandoff(this._player, {Random? random}) : _random = random;

  final PlayerActions _player;
  final Random? _random;

  @override
  Future<void> playTracks(
    List<BrowseTrack> tracks, {
    int startIndex = 0,
    bool shuffle = false,
    PlayContext? context,
  }) async {
    if (tracks.isEmpty) return;
    _player
      ..setShuffle(shuffle)
      ..playQueue(
        tracks.map(toPlayerTrack).toList(),
        startIndex: _startAt(tracks.length, startIndex, shuffle),
        context: context,
      );
  }

  /// Where a shuffled collection begins.
  ///
  /// The START is randomised too, but only when the caller did not name a row. Shuffle decides
  /// what plays *next*, so beginning at zero played track one first every single time and read as
  /// broken from the only side that matters — while a tapped row must still be the row that plays.
  int _startAt(int length, int startIndex, bool shuffle) {
    if (shuffle && startIndex == 0) {
      return (_random ?? Random()).nextInt(length);
    }
    return startIndex.clamp(0, length - 1);
  }

  @override
  void openAlbum(BuildContext context, String albumId) =>
      context.goToAlbum(albumId);

  @override
  void openArtist(BuildContext context, String artistId) =>
      context.goToArtist(artistId);

  /// A radio pin's id is the seed artist's, which is what `PinKind.radio` means on the wire.
  @override
  void openRadio(BuildContext context, String stationId) =>
      context.goToArtistRadio(stationId);
}
