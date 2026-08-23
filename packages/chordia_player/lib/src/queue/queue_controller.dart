/// The play queue and everything that decides what sounds next.
///
/// A port of the queue half of `frontend/src/lib/player/context.tsx`, and deliberately the only
/// half: no engine, no HTTP, no plugin. The rules that are easy to get wrong — what shuffle picks,
/// where an index lands after a queue edit, when a station is asked for more — are the ones worth
/// exhaustive tests, and none of them need an audio device to exercise. The engine subscribes to
/// [events] and does as it is told.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:math';

import 'package:chordia_sync/chordia_sync.dart';
import 'package:uuid/uuid.dart';

import 'continuation.dart';
import 'queue_events.dart';
import 'upcoming.dart';

/// How far past the start of a track "previous" restarts it instead of going back one.
const int kPrevRestartThresholdMs = 3000;

/// How many recently-played tracks to keep, most-recent first and distinct by track id.
const int kHistoryLimit = 50;

/// How many entries from the end of the queue to fetch the station's next page.
///
/// Three, to sit just outside the default prefetch window, so the appended tracks are cached
/// before they are needed rather than at the moment they are.
const int kContinuationLookahead = 3;

/// Creates the one-shot timer a minutes-based sleep timer runs on. Injected so a test can fire the
/// deadline by hand rather than waiting out an hour of wall clock.
typedef TimerFactory =
    Timer Function(Duration duration, void Function() onFire);

Timer _realTimer(Duration duration, void Function() onFire) =>
    Timer(duration, onFire);

const Uuid _uuid = Uuid();

/// The queue, its order, and the sleep timer — everything about playback except the audio.
class QueueController {
  QueueController({
    Random? random,
    Clock clock = systemClock,
    TimerFactory timerFactory = _realTimer,
    String Function()? newQid,
    this.lookahead = kContinuationLookahead,
    this.continuationFetcher,
    this.onSourceExhausted,
  }) : _random = random ?? Random(),
       _clock = clock,
       _timerFactory = timerFactory,
       _newQid = newQid ?? _uuid.v4;

  final Random _random;
  final Clock _clock;
  final TimerFactory _timerFactory;
  final String Function() _newQid;

  /// How far from the end of the queue a station is asked for its next page.
  final int lookahead;

  /// Fetches the next stretch of listening when the queue is running dry. Null disables autoplay
  /// continuation entirely, which is also the state before the app has wired up a Hub client.
  ///
  /// Mutable for the same reason the mesh's handlers are: the queue exists from bootstrap and the
  /// Hub client does not.
  ContinuationFetcher? continuationFetcher;

  /// Called with a smart playlist's id when its queue has been played to the end.
  ///
  /// That moment is knowable here and nowhere else — the Hub sees scrobbles, not that a queue ran
  /// out, and nothing but the queue knows which playlist it came from. What the app does with it
  /// (re-resolving a playlist that asked to renew itself) needs the network, so it is not done
  /// here.
  final void Function(String smartPlaylistId)? onSourceExhausted;

  /// Whether the listener has autoplay on. Read at the moment a continuation would fire, so a
  /// settings change takes effect on the next track boundary rather than the next queue.
  bool autoplay = true;

  /// The live playhead, for [prev]'s restart threshold. Installed by the handler once the engine
  /// exists; until then every "previous" goes back a track, which is the right answer for a queue
  /// that is not sounding yet.
  int Function() readPositionMs = _zero;

  static int _zero() => 0;

  final StreamController<QueueEvent> _events =
      StreamController<QueueEvent>.broadcast(sync: true);

  /// Every state change and every instruction to the engine, in order.
  ///
  /// Synchronous delivery: a command's effects must be complete before the next command is
  /// accepted, or a transport tap arriving during an await would act on a half-applied queue.
  Stream<QueueEvent> get events => _events.stream;

  final List<PlayerTrack> _queue = [];
  final List<PlayerTrack> _history = [];
  int _currentIndex = -1;
  PlayerTrack? _current;
  bool _shuffle = false;
  RepeatMode _repeat = RepeatMode.off;
  PlayContext? _context;
  SleepTimer? _sleepTimer;
  bool _sleepAtTrackEnd = false;
  Timer? _sleepTimeout;
  bool _continuationInFlight = false;
  bool _continuationExhausted = false;
  bool _closed = false;

  // Emission bookkeeping: a command mutates freely and the flush at its outermost boundary emits
  // one state change and at most one intent. Without it, `playNow` (which delegates to
  // `playQueue`) would announce itself twice and a subscriber would rebuild on a queue it had
  // already seen.
  int _depth = 0;
  bool _dirty = false;
  QueueEvent? _intent;

  List<PlayerTrack> get queue => UnmodifiableListView(_queue);

  /// Recently-played tracks, most-recent first and distinct by track id.
  List<PlayerTrack> get history => UnmodifiableListView(_history);

  /// Where playback sits in [queue], or -1 before anything has started.
  int get currentIndex => _currentIndex;

  /// The entry the engine was last told to play.
  ///
  /// NOT `queue[currentIndex]`, and the difference is load-bearing: removing the playing entry
  /// leaves the audio sounding while the index slides onto whatever took its place, so anything
  /// that describes what is audible — the now-playing bar, the scrobble, the cache pin — must read
  /// this one.
  PlayerTrack? get current => _current;

  bool get shuffle => _shuffle;

  RepeatMode get repeat => _repeat;

  /// Where the current queue was started from, for the "Playing from …" back-link.
  PlayContext? get context => _context;

  SleepTimer? get sleepTimer => _sleepTimer;

  /// The positions to preload after the current one, wrapping only under repeat-all.
  List<int> upcoming(int count) => upcomingIndices(
    _currentIndex,
    _queue.length,
    count,
    wrap: _repeat == RepeatMode.all,
  );

  /// Replace the queue and start at [startIndex].
  ///
  /// [context] is set on every call including the default null, so starting an album (or a bare
  /// [playNow]) after a playlist cannot inherit the playlist's id. Advancing WITHIN a queue never
  /// comes through here, so track two of a playlist keeps it.
  void playQueue(
    List<PlayerTrack> tracks, {
    int startIndex = 0,
    PlayContext? context,
  }) => _command(() {
    _queue
      ..clear()
      ..addAll([for (final track in tracks) track.copyWith(qid: _newQid())]);
    _context = context;
    // A different queue is a different question about what comes next, so a station that had
    // nothing left must not keep that verdict — otherwise autoplay stays dead for the rest of the
    // session after the first finite station ends.
    _continuationExhausted = false;
    _dirty = true;
    _activate(startIndex);
  });

  /// Play one track immediately, replacing the queue with just it.
  void playNow(PlayerTrack track) => playQueue([track]);

  /// Append to the end of the queue.
  void enqueue(PlayerTrack track) => _command(() {
    _queue.add(track.copyWith(qid: _newQid()));
    _dirty = true;
  });

  /// Insert right after the current entry.
  void playNext(PlayerTrack track) => _command(() {
    _queue.insert(
      (_currentIndex + 1).clamp(0, _queue.length),
      track.copyWith(qid: _newQid()),
    );
    _dirty = true;
  });

  /// Drop one entry. Removing the playing entry does not stop it: the audio plays on and the index
  /// now names whatever moved into its place, which is what makes "remove this from the queue"
  /// different from "skip".
  void removeFromQueue(int index) => _command(() {
    if (index < 0 || index >= _queue.length) return;
    _queue.removeAt(index);
    if (index < _currentIndex) _currentIndex -= 1;
    _dirty = true;
  });

  /// Move an entry, keeping the playing index pointed at the same entry across the move.
  void reorderQueue(int from, int to) => _command(() {
    if (from < 0 ||
        from >= _queue.length ||
        to < 0 ||
        to >= _queue.length ||
        from == to) {
      return;
    }
    _queue.insert(to, _queue.removeAt(from));
    _currentIndex = indexAfterMove(_currentIndex, from, to);
    _dirty = true;
  });

  /// Start the entry at [index] without disturbing the rest of the queue — a tap on an upcoming
  /// track in the queue panel.
  void jumpTo(int index) => _command(() {
    if (index < 0 || index >= _queue.length) return;
    _activate(index);
  });

  /// Advance to whatever comes next, extending the queue from the station if it has run out.
  void next() => _command(_advance);

  /// Restart the current track if it is past [kPrevRestartThresholdMs] or is the first entry,
  /// otherwise go back one.
  void prev() => _command(() {
    if (readPositionMs() > kPrevRestartThresholdMs || _currentIndex <= 0) {
      _intent = const RestartCurrentRequested();
      return;
    }
    _activate(_currentIndex - 1);
  });

  /// The engine reached the end of a track.
  ///
  /// "Stop after this track" is consumed here rather than by the sleep timer itself, because the
  /// end of the track is the only moment it means anything.
  void onTrackEnded() => _command(() {
    if (_sleepAtTrackEnd) {
      _sleepAtTrackEnd = false;
      _sleepTimer = null;
      _dirty = true;
      return;
    }
    _advance();
  });

  void toggleShuffle() => setShuffleMode(!_shuffle);

  /// Set shuffle to a value rather than flipping it — a collection carries its own shuffle
  /// preference, and starting one has to APPLY that preference, which a toggle cannot express.
  void setShuffleMode(bool on) => _command(() {
    if (_shuffle == on) return;
    _shuffle = on;
    _dirty = true;
  });

  void cycleRepeat() => setRepeatMode(switch (_repeat) {
    RepeatMode.off => RepeatMode.all,
    RepeatMode.all => RepeatMode.one,
    RepeatMode.one => RepeatMode.off,
  });

  void setRepeatMode(RepeatMode mode) => _command(() {
    if (_repeat == mode) return;
    _repeat = mode;
    _dirty = true;
  });

  /// Arm a sleep timer, or cancel the armed one with null.
  void setSleepTimer(SleepTimerOption? option) => _command(() {
    _sleepTimeout?.cancel();
    _sleepTimeout = null;
    _sleepAtTrackEnd = false;
    _dirty = true;
    switch (option) {
      case null:
        _sleepTimer = null;
      case SleepAfterCurrentTrack():
        _sleepAtTrackEnd = true;
        _sleepTimer = const SleepAtTrackEnd();
      case SleepAfterMinutes(:final minutes):
        final ms = (minutes * Duration.millisecondsPerMinute).round();
        _sleepTimeout = _timerFactory(
          Duration(milliseconds: ms),
          _onSleepElapsed,
        );
        _sleepTimer = SleepAtTime(endsAt: _clock() + ms);
    }
  });

  /// Forget everything about this listening session.
  ///
  /// Signing out must silence the player, and leaving the queue behind would show the next visitor
  /// what the last one was listening to. Shuffle and repeat survive: they are transport
  /// preferences, not somebody's data.
  void clear() => _command(() {
    _sleepTimeout?.cancel();
    _sleepTimeout = null;
    _sleepAtTrackEnd = false;
    _sleepTimer = null;
    _queue.clear();
    _history.clear();
    _currentIndex = -1;
    _current = null;
    _context = null;
    _continuationExhausted = false;
    _dirty = true;
  });

  Future<void> dispose() async {
    _closed = true;
    _sleepTimeout?.cancel();
    _sleepTimeout = null;
    await _events.close();
  }

  /// Make [i] the playing entry: record the one it replaces in history, move the index, warm the
  /// station, and ask the engine to start.
  void _activate(int i) {
    if (i < 0 || i >= _queue.length) return;
    final track = _queue[i];
    final leaving = _current;
    if (leaving != null && leaving.id != track.id) {
      _history
        ..removeWhere((entry) => entry.id == leaving.id)
        ..insert(0, leaving);
      if (_history.length > kHistoryLimit) {
        _history.removeRange(kHistoryLimit, _history.length);
      }
    }
    _currentIndex = i;
    _current = track;
    _dirty = true;
    // Fetch the next page BEFORE the queue runs dry, so the prefetch window can cover the handoff.
    // Waiting until the last track ends would put a round trip in the gap between two songs, which
    // is exactly where it is most audible.
    if (i >= _queue.length - lookahead) unawaited(_runContinuation());
    _intent = PlayEntryRequested(index: i, track: track);
  }

  void _advance() {
    final n = _computeNext();
    if (n != null) {
      _activate(n);
      return;
    }
    final source = _context;
    if (source is SmartPlaylistContext) onSourceExhausted?.call(source.id);
    // The queue is out. Ask the station for more instead of stopping — that is the whole of what
    // the autoplay setting means.
    final from = _currentIndex;
    unawaited(
      _runContinuation().then((appended) {
        // Only jump if the listener has not started something else in the meantime. An await spans
        // user input, and resuming into a queue they have replaced is worse than stopping.
        if (appended && _currentIndex == from) {
          _command(() => _activate(from + 1));
        }
      }),
    );
  }

  /// Which index plays after this one, or null when the queue is out.
  int? _computeNext() {
    if (_queue.isEmpty) return null;
    final i = _currentIndex;
    if (_repeat == RepeatMode.one) return i;
    if (_shuffle && _queue.length > 1) return _pickShuffled(i);
    if (i + 1 < _queue.length) return i + 1;
    if (_repeat == RepeatMode.all) return 0;
    return null;
  }

  /// A uniformly random entry other than the one playing.
  ///
  /// Shuffle is a flag consulted here, not a reordering of the queue, so a shuffled queue has no
  /// end to run out of — which is why nothing below ever returns null and why the continuation
  /// path is unreachable from a shuffled advance.
  ///
  /// Drawn from `length - 1` and shifted past the current index rather than by rejection sampling,
  /// which is the same distribution over the same set but always terminates. The web client's
  /// `while (r === i)` loop is fine against a real generator and hangs the player forever against
  /// a scripted one, and a test source is exactly what this has to be driven by.
  int _pickShuffled(int i) {
    if (i < 0 || i >= _queue.length) return _random.nextInt(_queue.length);
    final r = _random.nextInt(_queue.length - 1);
    return r >= i ? r + 1 : r;
  }

  /// Extend the queue with the next stretch of the station that fits what is playing. Resolves
  /// true only when tracks were actually appended.
  ///
  /// Silent and cheap when autoplay is off, when repeat is on (both repeat modes already answer
  /// "what comes next"), or when the station is spent. The two flags are both load-bearing:
  /// in-flight because a fast double-ended (a zero-length track, a decode error at the tail) would
  /// otherwise append the same page twice, and exhausted because a station with nothing left
  /// answers every request the same way.
  Future<bool> _runContinuation() async {
    final fetch = continuationFetcher;
    if (fetch == null) return false;
    if (!autoplay) return false;
    if (_repeat != RepeatMode.off) return false;
    if (_continuationInFlight || _continuationExhausted) return false;
    final last = _queue.isNotEmpty ? _queue.last : _current;
    final request = continuationRequestFor(_context, last?.id);
    if (request == null) {
      _continuationExhausted = true;
      return false;
    }
    _continuationInFlight = true;
    try {
      final page = await fetch(request);
      if (_closed) return false;
      if (page.tracks.isEmpty) {
        _continuationExhausted = true;
        return false;
      }
      _command(() {
        // Remember where this station resumes. Without it the next continuation rebuilds the
        // station from the top and replays the tracks that just finished.
        final source = _context;
        if (source is RadioContext) {
          _context = RadioContext(
            id: source.id,
            name: source.name,
            stationKind: source.stationKind,
            stationCursor: StationCursor(page.cursor),
          );
        }
        _queue.addAll([for (final track in page.tracks) _asAutoplay(track)]);
        _dirty = true;
      });
      return true;
    } on Object {
      // A failed fetch is not a finished station: leave the exhausted flag alone so the next track
      // boundary tries again.
      return false;
    } finally {
      _continuationInFlight = false;
    }
  }

  /// Stamp a station track as this queue's own: a fresh entry id, and the autoplay marker the
  /// queue panel uses to show where the listener's queue ended and the station took over.
  PlayerTrack _asAutoplay(PlayerTrack track) => PlayerTrack(
    qid: _newQid(),
    id: track.id,
    title: track.title,
    artist: track.artist,
    artistId: track.artistId,
    artists: track.artists,
    album: track.album,
    albumId: track.albumId,
    plays: track.plays,
    durationMs: track.durationMs,
    coverUrl: track.coverUrl,
    libraryId: track.libraryId,
    trackRef: track.trackRef,
    contentHash: track.contentHash,
    advisory: track.advisory,
    variants: track.variants,
    autoplay: true,
  );

  void _onSleepElapsed() => _command(() {
    _sleepTimeout = null;
    _sleepTimer = null;
    _dirty = true;
    _intent = const SleepTimerElapsed();
  });

  void _command(void Function() body) {
    _depth++;
    try {
      body();
    } finally {
      _depth--;
      if (_depth == 0) _flush();
    }
  }

  void _flush() {
    if (_closed) return;
    if (_dirty) {
      _dirty = false;
      _events.add(const QueueStateChanged());
    }
    final intent = _intent;
    _intent = null;
    if (intent != null) _events.add(intent);
  }
}
