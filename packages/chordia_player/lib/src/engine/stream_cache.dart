import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';

/// A partially-downloaded track on disk, plus the index of which bytes it actually holds.
///
/// Audio is fetched in ranges — a seek jumps straight into the middle of a file — so a cache entry
/// is a sparse thing. Writing a naive "file exists, therefore complete" cache would serve silence
/// for the parts never fetched, and it is the kind of bug that only shows up on a long track after
/// a seek. The index makes the gaps explicit.
class StreamCacheEntry {
  StreamCacheEntry({
    required this.dataFile,
    required this.indexFile,
    required this.ranges,
    this.totalBytes,
    this.contentType,
    this.etag,
  });

  final File dataFile;
  final File indexFile;

  /// Half-open [start, end) byte ranges held, kept sorted and coalesced.
  final List<({int start, int end})> ranges;

  int? totalBytes;
  String? contentType;
  String? etag;

  bool get isComplete =>
      totalBytes != null &&
      ranges.length == 1 &&
      ranges.first.start == 0 &&
      ranges.first.end == totalBytes;

  /// How many contiguous bytes are available from [offset]. Zero means nothing cached there.
  int contiguousFrom(int offset) {
    for (final r in ranges) {
      if (offset >= r.start && offset < r.end) return r.end - offset;
    }
    return 0;
  }

  void record(int start, int length) {
    if (length <= 0) return;
    ranges.add((start: start, end: start + length));
    _coalesce();
  }

  void _coalesce() {
    ranges.sort((a, b) => a.start.compareTo(b.start));
    final merged = <({int start, int end})>[];
    for (final r in ranges) {
      if (merged.isEmpty || r.start > merged.last.end) {
        merged.add(r);
      } else if (r.end > merged.last.end) {
        merged[merged.length - 1] = (start: merged.last.start, end: r.end);
      }
    }
    ranges
      ..clear()
      ..addAll(merged);
  }

  Map<String, Object?> toJson() => {
    'total_bytes': totalBytes,
    'content_type': contentType,
    'etag': etag,
    'ranges': [
      for (final r in ranges) {'start': r.start, 'end': r.end},
    ],
  };

  static StreamCacheEntry fromJson(
    Map<String, Object?> json, {
    required File dataFile,
    required File indexFile,
  }) => StreamCacheEntry(
    dataFile: dataFile,
    indexFile: indexFile,
    totalBytes: json['total_bytes'] as int?,
    contentType: json['content_type'] as String?,
    etag: json['etag'] as String?,
    ranges: [
      for (final r in (json['ranges'] as List? ?? const []))
        (start: (r as Map)['start']! as int, end: r['end']! as int),
    ],
  );

  Future<void> persist() async {
    await indexFile.writeAsString(jsonEncode(toJson()), flush: true);
  }
}

/// Disk store for streamed audio, bounded by total size.
///
/// This is not merely an optimisation: replaying a track the listener just heard, or resuming after
/// a seek backwards, must not re-download from a server that might be a home connection on the
/// other side of the world.
class StreamCache {
  StreamCache({
    required this.directory,
    this.maxBytes = 1024 * 1024 * 1024,
    @visibleForTesting int Function()? clock,
  }) : _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch);

  final Directory directory;
  final int maxBytes;
  final int Function() _clock;

  final _entries = <String, StreamCacheEntry>{};

  /// Keys currently being played or faded out, which eviction must not touch.
  final _pinned = <String>{};

  String _safe(String key) =>
      base64Url.encode(utf8.encode(key)).replaceAll('=', '');

  Future<StreamCacheEntry> entryFor(String key) async {
    final existing = _entries[key];
    if (existing != null) return existing;

    await directory.create(recursive: true);
    final name = _safe(key);
    final dataFile = File(
      '${directory.path}${Platform.pathSeparator}$name.bin',
    );
    final indexFile = File(
      '${directory.path}${Platform.pathSeparator}$name.idx',
    );

    StreamCacheEntry entry;
    if (await indexFile.exists() && await dataFile.exists()) {
      try {
        entry = StreamCacheEntry.fromJson(
          jsonDecode(await indexFile.readAsString()) as Map<String, Object?>,
          dataFile: dataFile,
          indexFile: indexFile,
        );
      } on Object {
        // A truncated index would have us read bytes that were never written. Start over rather
        // than trust it — the cost is one re-download, the alternative is silent corruption.
        await _deleteQuietly(dataFile);
        await _deleteQuietly(indexFile);
        entry = StreamCacheEntry(
          dataFile: dataFile,
          indexFile: indexFile,
          ranges: [],
        );
      }
    } else {
      entry = StreamCacheEntry(
        dataFile: dataFile,
        indexFile: indexFile,
        ranges: [],
      );
    }
    _entries[key] = entry;
    return entry;
  }

  /// Keeps [key] from being evicted. The outgoing side of a crossfade is still being read from
  /// even though nothing is "playing" it any more.
  void pin(String key) => _pinned.add(key);
  void unpin(String key) => _pinned.remove(key);

  Future<void> writeAt(
    StreamCacheEntry entry,
    int offset,
    List<int> bytes,
  ) async {
    final handle = await entry.dataFile.open(mode: FileMode.writeOnlyAppend);
    try {
      await handle.setPosition(offset);
      await handle.writeFrom(bytes);
      await handle.flush();
    } finally {
      await handle.close();
    }
    entry.record(offset, bytes.length);
    await entry.persist();
  }

  Future<List<int>> readAt(
    StreamCacheEntry entry,
    int offset,
    int length,
  ) async {
    final handle = await entry.dataFile.open();
    try {
      await handle.setPosition(offset);
      return await handle.read(length);
    } finally {
      await handle.close();
    }
  }

  Future<int> totalBytes() async {
    if (!await directory.exists()) return 0;
    var sum = 0;
    await for (final f in directory.list()) {
      if (f is File) sum += await f.length();
    }
    return sum;
  }

  /// Drops least-recently-touched entries until the store fits, skipping anything pinned.
  Future<void> evictToFit() async {
    if (!await directory.exists()) return;
    var total = await totalBytes();
    if (total <= maxBytes) return;

    final files = <({File file, DateTime at, String stem})>[];
    await for (final f in directory.list()) {
      if (f is! File || !f.path.endsWith('.bin')) continue;
      final stat = await f.stat();
      final stem = f.uri.pathSegments.last.replaceAll('.bin', '');
      files.add((file: f, at: stat.accessed, stem: stem));
    }
    files.sort((a, b) => a.at.compareTo(b.at));

    final pinnedStems = _pinned.map(_safe).toSet();
    for (final f in files) {
      if (total <= maxBytes) break;
      if (pinnedStems.contains(f.stem)) continue;
      total -= await f.file.length();
      await _deleteQuietly(f.file);
      await _deleteQuietly(
        File('${directory.path}${Platform.pathSeparator}${f.stem}.idx'),
      );
      _entries.removeWhere((k, _) => _safe(k) == f.stem);
    }
  }

  Future<void> clear() async {
    _entries.clear();
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }

  int get lastTouched => _clock();

  static Future<void> _deleteQuietly(File f) async {
    try {
      if (await f.exists()) await f.delete();
    } on FileSystemException {
      // Another handle may still hold it on Windows; it will be swept on the next pass.
    }
  }
}
