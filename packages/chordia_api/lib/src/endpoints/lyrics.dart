import '../hub.dart';
import '../json.dart';
import '../models.g.dart';

/// Lyrics for a track, cached by the Hub.
///
/// A track with no lyrics answers **404**, not an empty document, so the absence arrives as an
/// `ApiException` the caller checks with `isNotFound` rather than an empty [Lyrics].
extension LyricsEndpoints on HubClient {
  Future<Lyrics> lyrics(String trackId) =>
      get('/v1/lyrics/$trackId', (json) => Lyrics.fromJson(asObject(json)));

  /// Sets lyrics by hand. The text is LRC when the input says it is synced.
  ///
  /// A manual edit pins the track: the auto-fetcher will not overwrite it afterwards, which is what
  /// [deleteLyrics] exists to undo.
  Future<Lyrics> putLyrics(String trackId, LyricsEditInput input) => put(
    '/v1/lyrics/$trackId',
    (json) => Lyrics.fromJson(asObject(json)),
    body: input.toJson(),
  );

  /// Forgets what is stored — a manual edit or a bad auto-match alike — so the next play fetches
  /// again from the provider.
  Future<void> deleteLyrics(String trackId) => delete('/v1/lyrics/$trackId');
}
