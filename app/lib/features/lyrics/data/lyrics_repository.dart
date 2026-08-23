import 'package:chordia_api/chordia_api.dart';

/// Fetches one track's lyrics from the Hub.
typedef LyricsFetcher = Future<Lyrics> Function(String trackId);

/// Lyrics for the tracks played this session, including the ones that have none.
///
/// **The absence is the thing worth caching.** `GET /v1/lyrics/{trackId}` answers 404 for a track
/// with no lyrics, and most libraries have a long tail of tracks that will never have any — live
/// takes, interludes, anything the providers do not carry. Without a negative cache, opening the
/// lyrics view on shuffle re-asks the Hub for the same nothing on every play, and the Hub asks its
/// upstream provider. The miss is remembered for [missTtl] rather than forever because "no lyrics"
/// is a statement about the provider *today*: an auto-fetch or a hand-written edit can land at any
/// time, and a listener who adds lyrics on the desktop should not have to restart the phone app.
class LyricsRepository {
  LyricsRepository({
    required LyricsFetcher fetch,
    this.missTtl = const Duration(minutes: 5),
    this.capacity = 64,
    int Function()? clock,
  }) : _fetch = fetch,
       _clock = clock ?? _wallClock;

  final LyricsFetcher _fetch;

  /// How long a 404 is believed.
  final Duration missTtl;

  /// How many tracks are remembered before the oldest entry is dropped. A phone's worth of lyrics
  /// is small, but an all-night shuffle is not bounded by anything else.
  final int capacity;

  final int Function() _clock;

  /// Insertion-ordered, which is what makes the eviction below oldest-first.
  final _cache = <String, _Entry>{};

  /// In-flight requests, so a view rebuilding mid-fetch does not start a second one.
  final _inFlight = <String, Future<Lyrics?>>{};

  /// The lyrics for a track, or null when it has none.
  ///
  /// Anything other than a 404 propagates: a request that failed because the phone is in a tunnel
  /// is not evidence about the song, and caching it as "no lyrics" would outlive the tunnel.
  Future<Lyrics?> forTrack(String trackId) {
    final cached = _cache[trackId];
    if (cached != null && !cached.isExpired(_clock())) {
      return Future.value(cached.lyrics);
    }
    final pending = _inFlight[trackId];
    if (pending != null) return pending;

    final request = _load(trackId);
    _inFlight[trackId] = request;
    return request.whenComplete(() {
      _inFlight.remove(trackId);
    });
  }

  Future<Lyrics?> _load(String trackId) async {
    Lyrics? lyrics;
    try {
      lyrics = await _fetch(trackId);
    } on ApiException catch (e) {
      if (!e.isNotFound) rethrow;
      lyrics = null;
    }
    _store(trackId, lyrics);
    return lyrics;
  }

  void _store(String trackId, Lyrics? lyrics) {
    // Re-inserting moves the key to the back of the insertion order, so a track played twice is
    // not the next one evicted.
    _cache.remove(trackId);
    _cache[trackId] = _Entry(
      lyrics: lyrics,
      // A hit does not expire: lyrics that exist do not stop existing, and an edit made on this
      // device goes through [forget].
      expiresAt: lyrics == null ? _clock() + missTtl.inMilliseconds : null,
    );
    while (_cache.length > capacity) {
      _cache.remove(_cache.keys.first);
    }
  }

  /// Drops what is remembered for a track, so the next read asks again.
  void forget(String trackId) => _cache.remove(trackId);

  void clear() => _cache.clear();

  static int _wallClock() => DateTime.now().millisecondsSinceEpoch;
}

class _Entry {
  const _Entry({required this.lyrics, required this.expiresAt});

  final Lyrics? lyrics;

  /// Epoch milliseconds, or null for an entry that does not expire.
  final int? expiresAt;

  bool isExpired(int now) => expiresAt != null && now >= expiresAt!;
}

/// A start time no playhead reaches, for a line that cannot be placed.
const int _never = 0x7FFFFFFFFFFFFFFF;

/// The start offsets of [lines], as one non-decreasing array.
///
/// Built once per document, because [activeLyricLine] is a binary search and a binary search over
/// something not sorted returns confident nonsense. A LINE_SYNCED document is *supposed* to time
/// every line, but nothing in the contract enforces it, and one untimed line in the middle is
/// enough to make a raw `startMs` lookup non-monotonic.
///
/// An untimed line inherits the start of the *next* timed line, which — since the search takes the
/// last index at or before the playhead — means it is drawn in place but never highlighted. That is
/// the honest rendering: nothing is known about when it is sung, so nothing claims to know.
List<int> lyricStarts(List<LyricsLine> lines) {
  final starts = List<int>.filled(lines.length, _never);
  var next = _never;
  for (var i = lines.length - 1; i >= 0; i--) {
    final start = lines[i].startMs;
    if (start != null) next = start;
    starts[i] = start ?? next;
  }
  return starts;
}

/// The index into [starts] of the line sounding at [positionMs], or -1 before the first begins.
///
/// A binary search, not a scan. This is called on every playhead tick — twice a second, for the
/// whole time a track is playing — and a linear walk down a 120-line song does that work 120 times
/// over to answer a question the ordering already settles in seven comparisons.
///
/// A line stays current until the next one begins, even where the LRC gives it an `end_ms` that
/// falls earlier. Honouring the gap would drop the highlight to nothing during every instrumental
/// break, which reads as the view having lost its place rather than as the song having a rest.
int activeLyricLine(List<int> starts, int positionMs) {
  var lo = 0;
  var hi = starts.length - 1;
  var found = -1;
  while (lo <= hi) {
    final mid = (lo + hi) ~/ 2;
    if (starts[mid] > positionMs) {
      hi = mid - 1;
    } else {
      found = mid;
      lo = mid + 1;
    }
  }
  return found;
}

/// Whether a document carries per-line timing worth following.
bool isSynced(Lyrics lyrics) =>
    lyrics.syncType == LyricsSyncType.lineSYNCED &&
    lyrics.lines.any((line) => line.startMs != null);
