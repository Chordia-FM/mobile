import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:chordia_api/chordia_api.dart';

/// Downloads one derived artwork variant.
///
/// [width] has already been snapped to the Hub's ladder by [ArtCache], so an implementation must
/// pass it through rather than rounding it again.
typedef ArtFetcher = Future<Uint8List> Function(String sha256, int width);

/// The Hub has no image under this hash.
///
/// Distinct from a transport failure on purpose: "this album has no cover yet" is a stable answer
/// worth remembering for the session, while "the request failed" must stay retryable.
class ArtMissingException implements Exception {
  const ArtMissingException(this.sha256);

  final String sha256;

  @override
  String toString() => 'No image stored under $sha256.';
}

/// Artwork on disk, keyed by content hash and rendered width.
///
/// This exists instead of `cached_network_image` because the media notification and the lock
/// screen need a **`file://` URI**: `audio_service` hands `MediaItem.artUri` to platform code,
/// which loads it with its own HTTP stack — one that knows nothing about the pinned client in
/// `chordia_net` and would fail outright against a self-hosted host. So the bytes have to be on
/// disk, at a path we can name, before the media item is published.
///
/// **Layout.** One flat directory, one file per variant, named `{sha256}-w{width}` with no
/// extension. The name is the whole index: it is unique (the hash addresses the content, the width
/// the derivation), it needs no sidecar metadata, and it matches the key the Hub itself uses for
/// its derived blobs. Decoders sniff the magic bytes, so the missing extension costs nothing.
///
/// **Eviction.** Least-recently-used first. [_entries] is insertion-ordered — Dart map literals
/// are `LinkedHashMap` — so "used" is expressed by re-inserting a key at the end and the eviction
/// candidate is always `_entries.keys.first`. Ordering is seeded from file mtime on the first
/// sweep of an existing directory, which is why this is LRU-*ish* across restarts: within a
/// session it is exact, and after a restart it degrades to least-recently-*downloaded*. Tracking
/// true access times would mean either a sidecar index to keep in sync or `atime`, which most
/// mounts do not update.
class ArtCache {
  ArtCache({
    required Future<Directory> directory,
    required ArtFetcher fetch,
    this.maxBytes = defaultMaxBytes,
    void Function(Object error, StackTrace stack)? onError,
  }) : _directory = directory,
       _fetch = fetch,
       _onError = onError;

  /// Roughly a thousand 512px covers. Artwork is the one cache that grows with how much a user
  /// browses rather than with what they keep, so it needs a ceiling it will actually reach.
  static const defaultMaxBytes = 256 * 1024 * 1024;

  /// Written under this suffix and renamed into place, so a torn write is never mistaken for a
  /// complete file — and so a crash mid-write leaves debris the next sweep recognises and deletes.
  static const _partSuffix = '.part';

  static final _contentHash = RegExp(r'^[0-9a-f]{64}$');

  final int maxBytes;
  final Future<Directory> _directory;
  final ArtFetcher _fetch;
  final void Function(Object error, StackTrace stack)? _onError;

  /// Cache key to size in bytes, in least-recently-used-first order.
  final _entries = <String, int>{};

  /// Keys currently downloading. Several widgets mounting the same cover in one frame is the
  /// normal case, not the exception — a track list and its header ask for the same album art.
  final _inflight = <String, Future<File?>>{};

  /// Hashes the Hub answered 404 for. Keyed by hash rather than by key: an image the Hub does not
  /// have is absent at every width, and without this a grid of art-less albums re-asks on every
  /// scroll.
  final _missing = <String>{};

  Future<Directory>? _ready;
  Directory? _dir;

  /// True for a Hub content address: 64 lowercase hex characters.
  ///
  /// Checked before the value reaches a path, because these hashes arrive from the network and a
  /// `..` in one would escape the cache directory.
  static bool isContentHash(String value) => _contentHash.hasMatch(value);

  /// The file name a variant is stored under, with [width] snapped to the Hub's ladder.
  ///
  /// Snapping here rather than at the call site is what keeps the key honest: an off-ladder `?w=`
  /// is ignored by the Hub and it serves the **original**, so a file named `-w137` would hold
  /// multi-megabyte fanart.tv bytes while claiming to be a thumbnail.
  static String keyFor(String sha256, int width) =>
      '$sha256-w${snapImageWidth(width)}';

  /// The local file for a variant, downloading it once if it is not already there.
  ///
  /// Returns null rather than throwing for every failure mode — no such image, no network, no
  /// writable cache — because both callers (a widget and the media session) render the absence and
  /// neither can act on the reason.
  Future<File?> file(String sha256, {required int width}) {
    if (!isContentHash(sha256) || _missing.contains(sha256)) {
      return Future.value(null);
    }
    final snapped = snapImageWidth(width);
    final key = keyFor(sha256, snapped);
    final inflight = _inflight[key];
    if (inflight != null) return inflight;

    // `_resolve` suspends on its first await before it can reach the `finally` that clears this
    // entry, so registering the future after the call is still ordered correctly.
    final pending = _resolve(key, sha256, snapped);
    _inflight[key] = pending;
    return pending;
  }

  /// Bytes currently held on disk, for a storage row in settings.
  Future<int> totalBytes() async {
    await _ensureReady();
    return _entries.values.fold<int>(0, (sum, size) => sum + size);
  }

  /// Empties the cache, including the memory of which hashes had no image — a user clearing
  /// artwork is usually trying to make missing covers reappear after enrichment caught up.
  Future<void> clear() async {
    final dir = await _ensureReady();
    _entries.clear();
    _missing.clear();
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is File) await _deleteQuietly(entity);
    }
  }

  Future<File?> _resolve(String key, String sha256, int width) async {
    try {
      final dir = await _ensureReady();
      final file = File('${dir.path}/$key');

      final cached = _entries.remove(key);
      if (cached != null) {
        _entries[key] =
            cached; // Re-inserted at the end: this is the LRU touch.
        return file;
      }

      final bytes = await _fetch(sha256, width);
      await _write(file, bytes);
      _entries[key] = bytes.length;
      await _evict();
      return file;
    } on ArtMissingException {
      _missing.add(sha256);
      return null;
    } on Object catch (error, stack) {
      // Reported rather than swallowed: artwork silently vanishing hub-wide has looked like a UI
      // bug before, when it was the fetch failing for a nameable reason.
      _onError?.call(error, stack);
      return null;
    } finally {
      _inflight.remove(key);
    }
  }

  Future<void> _write(File file, Uint8List bytes) async {
    final partial = File('${file.path}$_partSuffix');
    try {
      await partial.writeAsBytes(bytes, flush: true);
      await partial.rename(file.path);
    } on Object {
      await _deleteQuietly(partial);
      rethrow;
    }
  }

  /// Drops least-recently-used entries until the cap is met.
  ///
  /// Stops at one entry: an image larger than the whole cap would otherwise delete itself the
  /// instant it landed, and re-download on the next frame forever.
  Future<void> _evict() async {
    var total = _entries.values.fold(0, (sum, size) => sum + size);
    while (total > maxBytes && _entries.length > 1) {
      final oldest = _entries.keys.first;
      total -= _entries.remove(oldest)!;
      await _deleteQuietly(File('${_dir!.path}/$oldest'));
    }
  }

  Future<Directory> _ensureReady() {
    final ready = _ready;
    if (ready != null) return ready;
    final started = _scan();
    _ready = started;
    // A cache directory can fail to open for reasons that pass — external storage still mounting
    // at boot, most often. Memoising that failure would leave the app with no artwork until the
    // next launch, so the attempt is forgotten and the next caller retries.
    unawaited(
      started.then<void>(
        (_) {},
        onError: (Object _) {
          if (identical(_ready, started)) _ready = null;
        },
      ),
    );
    return started;
  }

  Future<Directory> _scan() async {
    final dir = await _directory;
    await dir.create(recursive: true);
    _dir = dir;

    final found = <(String name, int modified, int size)>[];
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (name.endsWith(_partSuffix)) {
        // Debris from a write that never finished.
        await _deleteQuietly(entity);
        continue;
      }
      final stat = await entity.stat();
      found.add((name, stat.modified.millisecondsSinceEpoch, stat.size));
    }

    found.sort((a, b) => a.$2.compareTo(b.$2));
    for (final entry in found) {
      _entries[entry.$1] = entry.$3;
    }
    return dir;
  }

  static Future<void> _deleteQuietly(File file) async {
    try {
      await file.delete();
    } on FileSystemException {
      // Already gone, or held open by the platform image decoder. Either way there is nothing to
      // do about it and the entry is out of the index.
    }
  }
}

/// The content hash inside a Hub image reference, or null if there isn't one.
///
/// Browse DTOs carry `/v1/images/{hash}` paths — sometimes with a `?w=` the web client added, or a
/// `#fr=` framing fragment — rather than bare hashes, and some carry an external URL the Hub never
/// stored. Only the first kind can be cached, since the whole scheme is addressed by hash.
String? artHashOf(String? imageUrl) {
  if (imageUrl == null) return null;
  final parsed = Uri.tryParse(imageUrl);
  if (parsed == null) return null;
  final segments = parsed.pathSegments;
  if (segments.length < 2) return null;
  if (segments[segments.length - 2] != 'images') return null;
  final hash = segments.last;
  return ArtCache.isContentHash(hash) ? hash : null;
}
