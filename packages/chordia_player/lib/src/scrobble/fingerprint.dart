import 'package:chordia_api/chordia_api.dart';
import 'package:chordia_sync/chordia_sync.dart';

/// Runs of anything that is neither a letter nor a number, in any script.
final _separators = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

/// Mirror of the Hub's Rust normalizer for the fuzzy `(artist, title, album, duration)` tuple.
///
/// This has to agree character for character with the server and with the web client, because the
/// tuple is the weakest layer of track identity and the only one that resolves a play whose file
/// the Hub has never seen. A client that normalizes differently silently files its plays against a
/// track nobody else matches.
String normalizeMatchKey(String value) =>
    value.toLowerCase().replaceAll(_separators, ' ').trim();

/// The layered identity of what was played.
///
/// The content hash is the exact-file layer and is always sent; the normalized tuple is the
/// fallback the Hub uses when no library it knows holds that exact file. AcoustID and the
/// recording MBID are the stronger layers above both, and the mobile client does not compute
/// them — the library server that indexed the file does, and the Hub resolves them from the hash.
TrackFingerprint fingerprintOf(PlayerTrack track) {
  final album = track.album;
  return TrackFingerprint(
    contentHash: track.contentHash,
    artistNorm: normalizeMatchKey(track.artist),
    titleNorm: normalizeMatchKey(track.title),
    albumNorm: album == null ? null : normalizeMatchKey(album),
    durationMs: track.durationMs,
  );
}
