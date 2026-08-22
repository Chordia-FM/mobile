import 'dart:convert';

import 'package:chordia_api/chordia_api.dart';
import 'package:chordia_db/chordia_db.dart';
import 'package:flutter/foundation.dart';

/// Everything needed to fetch one track's audio and, when the last byte lands, to describe it
/// offline — without asking the Hub anything.
///
/// This is a *snapshot*, taken when the user tapped Download. It has to be, twice over. The bytes
/// may not finish arriving for hours, across app kills and network changes, so the catalog row
/// that started it is long gone by then; and a finished download has to render on a phone with the
/// radio off, where there is no catalog to join against. Both facts point at the same design: copy
/// the display fields in at request time and carry them all the way through.
///
/// It round-trips through JSON because it outlives the process. `DownloadTasks` holds the volatile
/// half of a queued download (how far it got, whether it failed); this immutable half rides in a
/// manifest file beside the partial bytes, so deleting the partial deletes its description too and
/// the two can never disagree.
@immutable
class DownloadRequest {
  const DownloadRequest({
    required this.trackId,
    required this.libraryId,
    required this.trackRef,
    required this.contentHash,
    required this.profile,
    required this.title,
    required this.artist,
    required this.durationMs,
    this.artistsJson,
    this.album,
    this.albumId,
    this.coverSha,
    this.advisory,
    this.variantsJson,
    this.trackNo,
    this.discNo,
  });

  /// The Hub's catalog id — the id every other surface keys on, and this download's identity.
  final String trackId;

  final String libraryId;

  /// The library's own id for the track, which is what the stream URL is built from.
  final String trackRef;

  /// SHA-256 of the source file. The library serves the same value as the ETag, so this is also
  /// the expected validator for the *original* tier.
  final String contentHash;

  /// The tier these bytes are fetched at, and the tier they stay at forever.
  ///
  /// A download is never adaptively swapped: the whole point of keeping a copy is that it plays
  /// identically on a plane and on Wi-Fi, and re-fetching a 40 MB FLAC as a 5 MB Opus because the
  /// phone wandered onto cellular would spend the user's data to make their music worse.
  final QualityProfile profile;

  final String title;
  final String artist;
  final int durationMs;

  /// Credited artists as a JSON array of `ArtistRef`, for per-artist navigation offline.
  final String? artistsJson;

  final String? album;
  final String? albumId;

  /// Hash half of the Hub's `/v1/images/{hash}` cover URL.
  final String? coverSha;

  final String? advisory;

  /// Title markers (`live`, `remaster`, …) as a JSON array, so an offline row badges the recording
  /// exactly as the online one does.
  final String? variantsJson;

  final int? trackNo;
  final int? discNo;

  /// Takes the snapshot from the catalog row the user acted on.
  factory DownloadRequest.of(BrowseTrack track, QualityProfile profile) =>
      DownloadRequest(
        trackId: track.id,
        libraryId: track.libraryId,
        trackRef: track.trackRef,
        contentHash: track.contentHash,
        profile: profile,
        title: track.title,
        artist: track.artist,
        durationMs: track.durationMs,
        artistsJson: track.artists == null
            ? null
            : jsonEncode([for (final a in track.artists!) a.toJson()]),
        album: track.album,
        albumId: track.albumId,
        coverSha: _artHashOf(track.coverUrl),
        advisory: track.advisory,
        variantsJson: track.variants == null
            ? null
            : jsonEncode([for (final v in track.variants!) v.wire]),
        trackNo: track.trackNo,
        discNo: track.discNo,
      );

  /// The finished-download row, once the bytes are on disk at [filePath].
  DownloadsCompanion toRow({
    required String filePath,
    required int sizeBytes,
    required int savedAt,
  }) => DownloadsCompanion.insert(
    trackId: trackId,
    libraryId: libraryId,
    trackRef: trackRef,
    contentHash: contentHash,
    // The wire string, not the enum: the column is deliberately independent of the generated API
    // models so an unknown future profile round-trips instead of throwing.
    profile: profile.wire,
    filePath: filePath,
    sizeBytes: sizeBytes,
    savedAt: savedAt,
    title: title,
    artist: artist,
    durationMs: durationMs,
    artistsJson: Value(artistsJson),
    album: Value(album),
    albumId: Value(albumId),
    coverSha: Value(coverSha),
    advisory: Value(advisory),
    variantsJson: Value(variantsJson),
    trackNo: Value(trackNo),
    discNo: Value(discNo),
  );

  Map<String, Object?> toJson() => {
    'track_id': trackId,
    'library_id': libraryId,
    'track_ref': trackRef,
    'content_hash': contentHash,
    'profile': profile.wire,
    'title': title,
    'artist': artist,
    'duration_ms': durationMs,
    if (artistsJson != null) 'artists_json': artistsJson,
    if (album != null) 'album': album,
    if (albumId != null) 'album_id': albumId,
    if (coverSha != null) 'cover_sha': coverSha,
    if (advisory != null) 'advisory': advisory,
    if (variantsJson != null) 'variants_json': variantsJson,
    if (trackNo != null) 'track_no': trackNo,
    if (discNo != null) 'disc_no': discNo,
  };

  factory DownloadRequest.fromJson(Map<String, Object?> json) =>
      DownloadRequest(
        trackId: json['track_id']! as String,
        libraryId: json['library_id']! as String,
        trackRef: json['track_ref']! as String,
        contentHash: json['content_hash']! as String,
        profile: QualityProfile.fromWire(json['profile']! as String),
        title: json['title']! as String,
        artist: json['artist']! as String,
        durationMs: json['duration_ms']! as int,
        artistsJson: json['artists_json'] as String?,
        album: json['album'] as String?,
        albumId: json['album_id'] as String?,
        coverSha: json['cover_sha'] as String?,
        advisory: json['advisory'] as String?,
        variantsJson: json['variants_json'] as String?,
        trackNo: json['track_no'] as int?,
        discNo: json['disc_no'] as int?,
      );
}

/// `/v1/images/{hash}` -> `hash`.
///
/// A local copy of the catalog's `artHashOf` minus the content-hash validation, because this file
/// is on the download path and must not depend on the art cache to describe a row it is saving.
String? _artHashOf(String? coverUrl) {
  if (coverUrl == null) return null;
  final segments = Uri.tryParse(coverUrl)?.pathSegments;
  if (segments == null || segments.length < 2) return null;
  return segments[segments.length - 2] == 'images' ? segments.last : null;
}
