import 'package:chordia_player/chordia_player.dart';

import '../art/art_cache.dart';

/// Width, in pixels, to fetch cover art for the media notification at.
///
/// Sized for the lock screen and a car head unit rather than the notification shade, which is the
/// larger of the surfaces this one file has to serve. It is a fixed number rather than a
/// device-derived one because the resolver runs with no `BuildContext` — the media session outlives
/// every widget, and often starts before one exists.
const int kNotificationArtWidth = 512;

final RegExp _contentHash = RegExp(r'^[0-9a-f]{64}$');

/// The content hash inside a Hub `/v1/images/{hash}` path, or null if that is not what this is.
String? artHashOf(String? coverUrl) {
  if (coverUrl == null || coverUrl.isEmpty) return null;
  final segments = Uri.parse(coverUrl).pathSegments;
  if (segments.isEmpty) return null;
  final last = segments.last;
  return _contentHash.hasMatch(last) ? last : null;
}

/// Resolves the `file://` cover the operating system draws beside the transport controls.
///
/// It has to be a local file: `audio_service` hands `MediaItem.artUri` to platform code, which
/// fetches it with its own HTTP stack — one that knows nothing about the pinned client every other
/// request in this app goes through, and that would fail outright against a self-hosted Hub with a
/// certificate only we trust.
ArtResolver notificationArtResolver(ArtCache cache) => (track) async {
  final hash = artHashOf(track.coverUrl);
  if (hash == null) return null;
  final file = await cache.file(hash, width: kNotificationArtWidth);
  return file == null ? null : Uri.file(file.path);
};
