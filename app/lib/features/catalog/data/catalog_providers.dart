import 'package:chordia_api/chordia_api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'catalog_api.dart';

/// Riverpod 3 retries an errored provider on its own, with a backoff.
///
/// Switched off for every read here. These screens already show a failure with a Retry button, and
/// a silent background retry both contradicts that button (the page heals while the user is
/// looking at "try again") and leaves a pending timer behind in widget tests, where it surfaces as
/// an unrelated teardown failure.
Duration? _noAutoRetry(int attempt, Object error) => null;

final artistDetailProvider = FutureProvider.autoDispose
    .family<ArtistDetail, String>(
      (ref, artistId) => ref.watch(catalogApiProvider).artist(artistId),
      retry: _noAutoRetry,
    );

/// Co-listen similarity, fetched separately so a slow similarity scan never delays the header.
final similarArtistsProvider = FutureProvider.autoDispose
    .family<List<BrowseArtist>, String>(
      (ref, artistId) => ref.watch(catalogApiProvider).similarArtists(artistId),
      retry: _noAutoRetry,
    );

final albumDetailProvider = FutureProvider.autoDispose
    .family<AlbumDetail, String>(
      (ref, albumId) => ref.watch(catalogApiProvider).album(albumId),
      retry: _noAutoRetry,
    );

/// One track with a freshly counted play total.
final trackDetailProvider = FutureProvider.autoDispose
    .family<BrowseTrack, String>(
      (ref, trackId) => ref.watch(catalogApiProvider).track(trackId),
      retry: _noAutoRetry,
    );

/// The viewer's own numbers for one track. Separate from [trackDetailProvider] so the details
/// above the fold render before the stats scan lands.
final trackStatsProvider = FutureProvider.autoDispose
    .family<EntityStats, String>(
      (ref, trackId) =>
          ref.watch(catalogApiProvider).entityStats(EntityKind.track, trackId),
      retry: _noAutoRetry,
    );

final genresProvider = FutureProvider.autoDispose<List<GenreSummary>>(
  (ref) => ref.watch(catalogApiProvider).genres(),
  retry: _noAutoRetry,
);

final genreDetailProvider = FutureProvider.autoDispose
    .family<GenreDetail, String>(
      (ref, slug) => ref.watch(catalogApiProvider).genre(slug),
      retry: _noAutoRetry,
    );

final labelsProvider = FutureProvider.autoDispose<List<LabelSummary>>(
  (ref) => ref.watch(catalogApiProvider).labels(),
  retry: _noAutoRetry,
);

final labelDetailProvider = FutureProvider.autoDispose
    .family<LabelDetail, String>(
      (ref, labelId) => ref.watch(catalogApiProvider).label(labelId),
      retry: _noAutoRetry,
    );

/// The caller's playlists, for the "Add to playlist" sheet.
final playlistsProvider = FutureProvider.autoDispose<List<Playlist>>(
  (ref) => ref.watch(catalogApiProvider).playlists(),
  retry: _noAutoRetry,
);

/// Which tracks the viewer has liked.
///
/// One set for the whole app rather than a per-row query: a heart appears on every visible row, and
/// asking the Hub per row would be a request per track. Deliberately NOT auto-disposed — the set
/// outlives any one screen, and re-fetching every liked track on each navigation is the cost this
/// avoids.
final likedTrackIdsProvider =
    AsyncNotifierProvider<LikedTracksController, Set<String>>(
      LikedTracksController.new,
    );

class LikedTracksController extends AsyncNotifier<Set<String>> {
  @override
  Future<Set<String>> build() async {
    final tracks = await ref.watch(catalogApiProvider).likedTracks();
    return {for (final track in tracks) track.id};
  }

  bool isLiked(String trackId) => state.value?.contains(trackId) ?? false;

  /// Flips one track's liked state, showing the new state before the Hub has confirmed it.
  ///
  /// Reverts on failure and rethrows so the caller can say what went wrong. A heart that stays
  /// filled after a failed write is worse than a brief flicker: it is a lie the next launch
  /// silently corrects.
  Future<void> toggle(String trackId) async {
    final before = state.value;
    // Nothing loaded yet means nothing to be optimistic about; let the fetch settle first.
    if (before == null) return;

    final liked = before.contains(trackId);
    final after = {...before};
    if (liked) {
      after.remove(trackId);
    } else {
      after.add(trackId);
    }
    state = AsyncData(after);

    try {
      final api = ref.read(catalogApiProvider);
      await (liked ? api.unlikeTrack(trackId) : api.likeTrack(trackId));
    } on Object {
      state = AsyncData(before);
      rethrow;
    }
  }
}
