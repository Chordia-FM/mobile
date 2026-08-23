import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'download_request.dart';

/// A partial download's description, kept beside its bytes.
///
/// The validator is the reason this file exists. Resuming means appending to bytes fetched
/// possibly days ago, and appending to a file the server has since replaced produces a track
/// stitched from two different encodings — which plays as a click, a burst of noise, or silence,
/// and looks like a corrupt download rather than a stale one. Recording the ETag next to the
/// partial is what makes the "has this changed?" question answerable at all.
@immutable
class DownloadManifest {
  const DownloadManifest({required this.request, this.etag, this.contentType});

  final DownloadRequest request;

  /// The library's ETag for these bytes — the file's SHA-256 for the original tier, and
  /// `{hash}.{tier}` for a transcode. Null until the first response has been seen.
  final String? etag;

  final String? contentType;

  DownloadManifest copyWith({String? etag, String? contentType}) =>
      DownloadManifest(
        request: request,
        etag: etag ?? this.etag,
        contentType: contentType ?? this.contentType,
      );

  Map<String, Object?> toJson() => {
    'request': request.toJson(),
    if (etag != null) 'etag': etag,
    if (contentType != null) 'content_type': contentType,
  };

  factory DownloadManifest.fromJson(Map<String, Object?> json) =>
      DownloadManifest(
        request: DownloadRequest.fromJson(
          (json['request']! as Map).cast<String, Object?>(),
        ),
        etag: json['etag'] as String?,
        contentType: json['content_type'] as String?,
      );
}

/// Where downloaded audio lives on this device, and the only thing that moves it.
///
/// The directory is a `Future` rather than a resolved `Directory` because the platform path is an
/// async call, and making every caller await a provider just to name a folder would push that
/// asynchrony into the widget tree. It is resolved once and reused.
///
/// Files live under application support, never the cache directory: a cache is by definition
/// something the OS may delete to reclaim space, and a download is the one audio artefact on the
/// device that no server can hand back on demand.
class DownloadStore {
  DownloadStore({required Future<Directory> directory})
    : _directory = directory;

  final Future<Directory> _directory;
  Directory? _resolved;

  Future<Directory> get directory async {
    final cached = _resolved;
    if (cached != null) return cached;
    final dir = await _directory;
    if (!dir.existsSync()) await dir.create(recursive: true);
    return _resolved = dir;
  }

  /// Bytes arriving for [trackId]. Becomes the finished file, under a new name, on completion.
  Future<File> partial(String trackId) async => File(
    '${(await directory).path}${Platform.pathSeparator}${_safe(trackId)}.part',
  );

  Future<File> _manifestFile(String trackId) async => File(
    '${(await directory).path}${Platform.pathSeparator}${_safe(trackId)}.json',
  );

  Future<void> writeManifest(DownloadManifest manifest) async {
    final file = await _manifestFile(manifest.request.trackId);
    await file.writeAsString(jsonEncode(manifest.toJson()), flush: true);
  }

  /// The manifest for [trackId], or null when there is none — or when what is there cannot be
  /// read as one.
  ///
  /// A corrupt manifest is treated as a missing one rather than an error: it can only be produced
  /// by a process killed mid-write, and the honest recovery from "we no longer know what these
  /// bytes are" is to start the download over, not to fail it permanently.
  Future<DownloadManifest?> readManifest(String trackId) async {
    final file = await _manifestFile(trackId);
    if (!file.existsSync()) return null;
    try {
      final json = jsonDecode(await file.readAsString());
      return DownloadManifest.fromJson((json as Map).cast<String, Object?>());
    } on Object {
      return null;
    }
  }

  /// How many bytes of [trackId] are already on disk.
  Future<int> bytesOnDisk(String trackId) async {
    final file = await partial(trackId);
    return file.existsSync() ? file.length() : 0;
  }

  /// Throws the partial bytes away, keeping the manifest.
  ///
  /// This is what a failed revalidation does: the description of *what we were downloading* is
  /// still correct, it is only the bytes that turned out to belong to a file that no longer
  /// exists upstream.
  Future<void> discardPartial(String trackId) async {
    final file = await partial(trackId);
    if (file.existsSync()) await file.delete();
  }

  /// Removes every trace of an in-flight download: the bytes and the manifest.
  Future<void> discard(String trackId) async {
    await discardPartial(trackId);
    final manifest = await _manifestFile(trackId);
    if (manifest.existsSync()) await manifest.delete();
  }

  /// Promotes the finished partial to its final name and drops the manifest.
  ///
  /// The rename is the commit point, and it is deliberately the last thing that happens before the
  /// database row is written: until the file has its real name nothing can mistake a half-fetched
  /// `.part` for a playable track, and the `downloads` row — the only index anything reads — is
  /// written only once the rename has returned.
  Future<File> publish(String trackId, {required String extension}) async {
    final source = await partial(trackId);
    final target = File(
      '${(await directory).path}${Platform.pathSeparator}${_safe(trackId)}.$extension',
    );
    // A leftover file under the target name is a previous copy of the same track — a re-download
    // at another tier. `rename` will not overwrite on every platform, so it goes first.
    if (target.existsSync()) await target.delete();
    final published = await source.rename(target.path);
    final manifest = await _manifestFile(trackId);
    if (manifest.existsSync()) await manifest.delete();
    return published;
  }

  /// Deletes a finished download's file. Silent when it is already gone, which an OS storage
  /// sweep or a restore-without-media can both cause.
  Future<void> deleteFile(String path) async {
    final file = File(path);
    if (file.existsSync()) await file.delete();
  }

  /// Track ids become file names, so anything a filesystem reserves has to go.
  ///
  /// Hub ids are opaque strings, not a format this app gets to assume; percent-encoding leaves
  /// ordinary ids untouched and cannot produce a separator, a colon or a wildcard.
  static String _safe(String trackId) => Uri.encodeComponent(trackId);
}

/// The file extension for a served content type.
///
/// Matched to what `ChordiaAudioSource` reads *back* out of a path when it plays a downloaded
/// file: it infers the content type from the extension, so an extension it does not recognise
/// makes every download claim to be an MP3. The two tables have to agree.
String extensionForContentType(String? contentType) {
  final type = contentType?.split(';').first.trim().toLowerCase();
  return switch (type) {
    'audio/flac' || 'audio/x-flac' => 'flac',
    'audio/mpeg' || 'audio/mp3' => 'mp3',
    'audio/mp4' || 'audio/aac' || 'audio/m4a' || 'audio/x-m4a' => 'm4a',
    'audio/opus' => 'opus',
    'audio/ogg' || 'application/ogg' => 'ogg',
    'audio/wav' || 'audio/x-wav' || 'audio/wave' => 'wav',
    _ => 'mp3',
  };
}
