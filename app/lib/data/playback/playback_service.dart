import 'dart:async';

import 'package:chordia_api/chordia_api.dart';
import 'package:chordia_player/chordia_player.dart';
import 'package:chordia_sync/chordia_sync.dart';
// Flutter has a `RepeatMode` of its own, for animations. The queue's is the one this file means.
import 'package:flutter/widgets.dart' hide RepeatMode;

import 'quality.dart';
import 'replay_gain.dart';
import 'source_resolver.dart';

/// Persists one counted play and does not return until it is durable.
///
/// A function rather than [ScrobbleService] itself, for the reason that class states about its own
/// sender: durability, batching and backoff are the service's business, while *whether this play is
/// worth recording at all* is the app's. Separating them is also what lets the wiring from a
/// playhead sample to a stored event be tested without a database.
typedef PlayRecorder =
    Future<void> Function(
      PlayerTrack track, {
      required int startedAt,
      required int msPlayed,
      PlayContext? context,
      PlaybackSource source,
    });

/// Asks the durable queue to try delivering whatever it holds.
typedef ScrobbleFlusher = Future<void> Function({bool force});

/// Tells the Hub what this device has just started. Presence, not history.
typedef NowPlayingReporter = void Function(PlayerTrack track);

/// Reads a track's measured loudness from the library that holds it.
///
/// Returns null when the library has no figure, or could not be asked. Both mean the same thing to
/// the caller — play at unity — which is why they are not distinguished.
typedef LoudnessReader = Future<AudioProperties?> Function(PlayerTrack track);

/// What the app did about a track it could not play.
enum PlaybackRecovery {
  /// Trying the same track once more. A dropped connection is usually over by the second attempt.
  retrying,

  /// Given up on this track; the next one is starting.
  skipped,

  /// Given up on playback. Either there is nowhere to skip to, or every track is failing the same
  /// way, which is what an unreachable library looks like from here.
  stopped,
}

/// A track that would not play, and what happened next.
///
/// Always published, even for the retry that then succeeds. Silence with no explanation is the
/// complaint this whole path exists to answer, and "trying again" is information — it tells the
/// listener the app noticed, which is the difference between a slow track and a broken app.
@immutable
class PlaybackFailure {
  const PlaybackFailure({
    required this.track,
    required this.recovery,
    required this.cause,
  });

  final PlayerTrack track;
  final PlaybackRecovery recovery;

  /// What the engine reported, kept whole so a debug view can say more than the sentence a
  /// listener is shown.
  final Object cause;
}

/// The listener preferences playback consults, defaulted for the cases where there are none.
///
/// A settled snapshot rather than a live `UserSettings?`, because every field here is read at a
/// track boundary and a half-loaded settings response must not be the difference between a play
/// being scrobbled and not.
@immutable
class PlaybackPreferences {
  const PlaybackPreferences({
    this.quality = QualityProfile.original,
    this.normalizeVolume = false,
    this.scrobble = true,
  });

  factory PlaybackPreferences.from(
    UserSettings? settings,
  ) => PlaybackPreferences(
    quality: settings?.streamingQuality ?? QualityProfile.original,
    normalizeVolume: settings?.normalizeVolume ?? false,
    // Defaulting on matches the Hub, and matters more than the other two: a play that is not
    // recorded is gone, while a play recorded against a listener who later turns scrobbling
    // off is one row they can delete.
    scrobble: settings?.scrobble ?? true,
  );

  final QualityProfile quality;
  final bool normalizeVolume;
  final bool scrobble;
}

/// Everything that has to happen around a track other than sounding it.
///
/// The handler owns the media session, the engine owns the audio and the queue owns the order;
/// this owns the decisions none of them can make — which bytes a track resolves to, how loud to
/// play it, when a play is durable, and when it is worth asking the Hub to take delivery.
///
/// It is a plain object rather than a widget or a notifier because Android can start the audio
/// service into a process with no UI: everything here has to work with no `BuildContext` in
/// existence.
class PlaybackService with WidgetsBindingObserver {
  PlaybackService({
    required this.handler,
    required this.engine,
    required this.queue,
    required SourceResolver resolver,
    required PlayRecorder recordPlay,
    required ScrobbleFlusher flush,
    required NowPlayingReporter reportNowPlaying,
    required LoudnessReader readLoudness,
    required PlaybackPreferences Function() preferences,
    required NetworkStatus Function() network,
    int Function()? clock,
  }) : _resolver = resolver,
       _recordPlay = recordPlay,
       _flush = flush,
       _reportNowPlaying = reportNowPlaying,
       _readLoudness = readLoudness,
       _preferences = preferences,
       _network = network,
       _clock = clock ?? _wallClock;

  final ChordiaAudioHandler handler;
  final PlaybackEngine engine;
  final QueueController queue;

  final SourceResolver _resolver;
  final PlayRecorder _recordPlay;
  final ScrobbleFlusher _flush;
  final NowPlayingReporter _reportNowPlaying;
  final LoudnessReader _readLoudness;
  final PlaybackPreferences Function() _preferences;
  final NetworkStatus Function() _network;
  final int Function() _clock;

  /// Where the current track's bytes came from, so its scrobble says so. Recorded at resolution
  /// because that is the only moment the answer is known.
  PlaybackSource _source = PlaybackSource.ownLibrary;

  /// Wall clock at which the current track started, which is what a listening event means by
  /// `started_at`. Not derived from `msPlayed` at scrobble time: that figure excludes pauses, so
  /// subtracting it would place a paused listen later than it happened.
  int _startedAt = 0;

  /// Bumped on every track start. A loudness read that lands after the queue has moved on belongs
  /// to a track nobody is hearing, and applying its gain would leave the wrong correction on the
  /// one that is.
  int _generation = 0;

  bool _online = true;
  bool _started = false;

  final _failures = StreamController<PlaybackFailure>.broadcast();
  final _subscriptions = <StreamSubscription<Object?>>[];

  /// The queue entry a retry has already been spent on, so a track gets exactly one second chance.
  ///
  /// Keyed by queue id rather than track id: the same track can legitimately sit in a queue twice,
  /// and the second copy deserves its own attempt.
  String? _retriedQid;

  /// Tracks that have failed in a row without one playing in between.
  ///
  /// A library that has gone away fails every track in the queue identically, and skipping through
  /// forty of them in a second — a notification each — is worse than stopping and saying so.
  int _consecutiveFailures = 0;

  /// How many tracks may fail in a row before playback stops rather than skipping on.
  static const maxConsecutiveFailures = 3;

  /// Tracks that would not play, and what was done about them.
  ///
  /// A stream rather than a state field because these are events: two failures in a row are two
  /// things the listener needs told, not one value that overwrote the other.
  Stream<PlaybackFailure> get failures => _failures.stream;

  /// Installs the hooks the handler leaves for the app, and starts watching the app's lifecycle.
  void start() {
    if (_started) return;
    _started = true;
    handler.resolveSource = resolveSource;
    _online = _network().online;
    _subscriptions
      ..add(engine.errors.listen((error) => unawaited(_onEngineError(error))))
      // A track that actually reaches the speakers clears the run of failures. Resetting on a
      // track START instead would defeat the cap entirely: every failing track starts.
      ..add(
        engine.states.listen((state) {
          if (state == EngineState.ready) _consecutiveFailures = 0;
        }),
      );
    WidgetsBinding.instance.addObserver(this);
  }

  Future<void> dispose() async {
    if (!_started) return;
    _started = false;
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    await _failures.close();
    WidgetsBinding.instance.removeObserver(this);
  }

  /// Resolves the bytes for a track, and remembers what kind of source they were.
  Future<EngineSource> resolveSource(PlayerTrack track) async {
    final source = await _resolver(track);
    _source = source is DownloadedSource
        ? PlaybackSource.local
        : PlaybackSource.ownLibrary;
    return source;
  }

  /// A track has begun. Called from the handler's now-playing hook, which fires before the engine
  /// is asked to load — early enough that the previous track's gain never reaches this one.
  void onTrackStarted(PlayerTrack track) {
    _startedAt = _clock();
    _generation++;
    // A new entry off the queue, so this one has its own retry to spend. A retry does not come
    // through here — it reloads the engine directly — which is what keeps it to one.
    _retriedQid = null;
    // Unity first, unconditionally. Whatever this track's correction turns out to be, the
    // preceding track's must not survive into it even for the moment the lookup takes.
    unawaited(engine.setPreampGain(1));

    _reportNowPlaying(track);

    // A track change is one of the three flush triggers. It is the cheapest of them: the network
    // is demonstrably in use, and anything queued has already waited at least a track.
    unawaited(_flush());

    if (_preferences().normalizeVolume && _network().online) {
      unawaited(_applyLoudness(track, _generation));
    }
  }

  /// A track has been heard for long enough to count.
  void onScrobble(PlayerTrack track, int msPlayed) {
    if (!_preferences().scrobble) return;
    unawaited(_record(track, msPlayed));
  }

  /// A track would not play.
  ///
  /// Three outcomes, in order of preference: try once more, move to the next track, or stop. The
  /// one thing never done is nothing — silence behind a play button that says it is playing is the
  /// state this exists to make impossible.
  Future<void> _onEngineError(EngineError error) async {
    final track = error.track ?? queue.current;
    if (track == null) return;
    final qid = track.qid ?? track.id;

    final worthRetrying =
        error.isTransient &&
        _retriedQid != qid &&
        _consecutiveFailures < maxConsecutiveFailures;
    if (worthRetrying) {
      _retriedQid = qid;
      _publish(track, error.cause, PlaybackRecovery.retrying);
      final EngineSource source;
      try {
        source = await resolveSource(track);
      } on Object catch (cause) {
        _giveUp(track, cause);
        return;
      }
      // Not awaited for a result: if this fails too it arrives back here as another error, with
      // the retry already spent, and takes the branch below.
      await engine.load(source, autoPlay: true);
      return;
    }

    _giveUp(track, error.cause);
  }

  /// Stops trying [track]: skip to the next one, or stop and say so.
  void _giveUp(PlayerTrack track, Object cause) {
    _consecutiveFailures++;
    final stop =
        _consecutiveFailures >= maxConsecutiveFailures ||
        // Repeat-one would hand the same unplayable track straight back.
        queue.repeat == RepeatMode.one ||
        !_hasSomewhereToGo;
    _publish(
      track,
      cause,
      stop ? PlaybackRecovery.stopped : PlaybackRecovery.skipped,
    );
    if (stop) {
      // The transport still reads as playing until something says otherwise, which is the stuck
      // play button over silence.
      unawaited(handler.pause());
      return;
    }
    queue.next();
  }

  /// Whether skipping would land on a different track rather than on this one again.
  bool get _hasSomewhereToGo {
    if (queue.queue.length < 2) return false;
    return queue.shuffle ||
        queue.repeat == RepeatMode.all ||
        queue.currentIndex + 1 < queue.queue.length;
  }

  void _publish(PlayerTrack track, Object cause, PlaybackRecovery recovery) {
    if (_failures.isClosed) return;
    _failures.add(
      PlaybackFailure(track: track, recovery: recovery, cause: cause),
    );
  }

  /// The network class changed.
  void onNetworkChanged(NetworkStatus status) {
    final regained = !_online && status.online;
    _online = status.online;
    // Forced, because connectivity returning is itself the evidence that the backoff window was
    // measuring an outage that has now ended.
    if (regained) unawaited(_flush(force: true));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Foregrounding commonly coincides with regaining a connection, and is the moment a user is
    // most likely to look at their listening history.
    if (state == AppLifecycleState.resumed) unawaited(_flush(force: true));
  }

  Future<void> _record(PlayerTrack track, int msPlayed) async {
    try {
      await _recordPlay(
        track,
        startedAt: _startedAt,
        msPlayed: msPlayed,
        context: queue.context,
        source: _source,
      );
    } on Object catch (error, stack) {
      // Losing a play is bad; taking playback down with it is worse.
      FlutterError.reportError(
        FlutterErrorDetails(exception: error, stack: stack, library: 'chordia'),
      );
      return;
    }
    await _flush();
  }

  Future<void> _applyLoudness(PlayerTrack track, int generation) async {
    final AudioProperties? audio;
    try {
      audio = await _readLoudness(track);
    } on Object {
      // The library not answering is not a reason to play at the wrong level: unity already
      // stands, and unity is the correct fallback.
      return;
    }
    if (generation != _generation || audio == null) return;
    await engine.setPreampGain(
      replayGainMultiplier(gainDb: audio.gainDb, peak: audio.peak),
    );
  }

  static int _wallClock() => DateTime.now().millisecondsSinceEpoch;
}
