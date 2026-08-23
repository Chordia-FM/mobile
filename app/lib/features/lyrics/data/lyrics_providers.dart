import 'package:chordia_api/chordia_api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import 'lyrics_repository.dart';

/// The session's lyrics, cached — misses included.
///
/// Kept alive for the process rather than per screen: the point of the negative cache is that
/// closing and reopening the lyrics view, or shuffling back to a track, does not re-ask.
final lyricsRepositoryProvider = Provider<LyricsRepository>((ref) {
  final repository = LyricsRepository(
    fetch: (trackId) async {
      final hub = ref.read(hubClientProvider);
      if (hub == null) {
        // Status 0 is the transport-failure code the app treats as "ask again later", which is the
        // truth here: with no hub session there is nothing to ask, and remembering that as "this
        // song has no lyrics" would survive signing in.
        throw const ApiException(
          status: 0,
          title: 'No hub session to read lyrics from.',
          method: 'GET',
          path: '/v1/lyrics',
        );
      }
      return hub.lyrics(trackId);
    },
  );
  // A different hub is a different catalog; track ids do not carry across it.
  ref.listen(activeHubProvider, (_, _) => repository.clear());
  return repository;
});

/// One track's lyrics, or null when it has none.
///
/// Auto-disposed, unlike the repository behind it: this provider is a per-view read, and the memory
/// that has to outlive the view is the cache, not one screen's `AsyncValue`.
final trackLyricsProvider = FutureProvider.autoDispose.family<Lyrics?, String>(
  (ref, trackId) => ref.watch(lyricsRepositoryProvider).forTrack(trackId),
);
